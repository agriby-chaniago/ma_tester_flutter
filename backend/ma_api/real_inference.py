from __future__ import annotations

import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Callable

import numpy as np

REAL_PIPELINE_NAME = "real-inference-adapter"
REAL_PIPELINE_VERSION = "0.2.0"
REAL_PIPELINE_READY = False
REAL_PIPELINE_ERROR = "REAL_IMPL_MODULE is empty"

_REAL_PREDICT_FN: Callable[..., Any] | None = None
_REAL_IMPL_MODULE_NAME: str = ""
_REAL_IMPL_CALLABLE_NAME: str = "predict"
_REAL_IMPL_ISOLATED: bool = True
_REAL_IMPL_TIMEOUT_S: int = 180


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except Exception:
        return default
    return max(10, value)


def _normalize_timing(timing: dict[str, Any]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key in ("pre_ms", "infer_ms", "post_ms"):
        value = timing.get(key, 0.0)
        out[key] = round(float(value), 3)
    return out


def _predict_in_subprocess(
    module_name: str,
    callable_name: str,
    rgb_u8: np.ndarray,
    threshold: float,
) -> tuple[np.ndarray, np.ndarray, dict[str, Any], dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="ma-real-") as tmpdir:
        input_path = Path(tmpdir) / "input.npz"
        output_path = Path(tmpdir) / "output.npz"

        np.savez_compressed(
            input_path,
            rgb_u8=rgb_u8.astype(np.uint8, copy=False),
            threshold=np.asarray([float(threshold)], dtype=np.float32),
        )

        cmd = [
            sys.executable,
            "-m",
            "ma_api.real_worker_runner",
            "--module",
            module_name,
            "--callable",
            callable_name,
            "--input",
            str(input_path),
            "--output",
            str(output_path),
        ]

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=_REAL_IMPL_TIMEOUT_S,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                f"Isolated delegate timed out after {_REAL_IMPL_TIMEOUT_S}s"
            ) from exc

        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or f"exit={proc.returncode}").strip()
            raise RuntimeError(
                f"Isolated delegate failed (exit={proc.returncode}): {err[:500]}"
            )

        if not output_path.exists():
            raise RuntimeError("Isolated delegate completed without output artifact")

        data = np.load(output_path, allow_pickle=False)
        proba_map = data["proba_map"]
        mask_u8 = data["mask_u8"]
        stats = json.loads(str(data["stats_json"].item()))
        timing = json.loads(str(data["timing_json"].item()))
        return proba_map, mask_u8, stats, timing


def _load_delegate() -> tuple[Callable[..., Any] | None, str | None]:
    module_name = os.getenv("REAL_IMPL_MODULE", "").strip()
    callable_name = os.getenv("REAL_IMPL_CALLABLE", "predict").strip() or "predict"

    global _REAL_IMPL_MODULE_NAME, _REAL_IMPL_CALLABLE_NAME, _REAL_IMPL_ISOLATED, _REAL_IMPL_TIMEOUT_S
    _REAL_IMPL_MODULE_NAME = module_name
    _REAL_IMPL_CALLABLE_NAME = callable_name
    _REAL_IMPL_ISOLATED = _bool_env("REAL_IMPL_ISOLATED", True)
    _REAL_IMPL_TIMEOUT_S = _int_env("REAL_IMPL_TIMEOUT_S", 180)

    if not module_name:
        return None, "REAL_IMPL_MODULE is empty"

    try:
        module = importlib.import_module(module_name)
    except Exception as exc:
        return None, f"Failed importing REAL_IMPL_MODULE '{module_name}': {exc}"

    ready = bool(getattr(module, "REAL_PIPELINE_READY", True))
    if not ready:
        err = str(getattr(module, "REAL_PIPELINE_ERROR", "Delegate module reports not ready"))
        return None, err

    fn = getattr(module, callable_name, None)
    if fn is None or not callable(fn):
        return None, f"Callable not found: {module_name}.{callable_name}"

    global REAL_PIPELINE_NAME, REAL_PIPELINE_VERSION
    REAL_PIPELINE_NAME = str(getattr(module, "REAL_PIPELINE_NAME", module_name))
    REAL_PIPELINE_VERSION = str(getattr(module, "REAL_PIPELINE_VERSION", "unknown"))

    if _REAL_IMPL_ISOLATED:
        def _isolated_predict(rgb_u8: np.ndarray, threshold: float):
            return _predict_in_subprocess(module_name, callable_name, rgb_u8, threshold)

        return _isolated_predict, None

    return fn, None


def _ensure_loaded() -> None:
    global _REAL_PREDICT_FN, REAL_PIPELINE_READY, REAL_PIPELINE_ERROR

    if _REAL_PREDICT_FN is not None:
        return

    fn, err = _load_delegate()
    if fn is None:
        REAL_PIPELINE_READY = False
        REAL_PIPELINE_ERROR = err or "Unknown delegate loading error"
        return

    _REAL_PREDICT_FN = fn
    REAL_PIPELINE_READY = True
    REAL_PIPELINE_ERROR = ""


# Load at import time so readiness can be exposed by backend metadata endpoints.
_ensure_loaded()


def predict(
    rgb_u8: np.ndarray,
    threshold: float,
) -> tuple[np.ndarray, np.ndarray, dict[str, Any], dict[str, float]]:
    """Delegate real prediction to user module.

    Delegate contract:
    - Input: rgb_u8 (H, W, 3) uint8, threshold float
    - Return: (proba_map, mask_u8, stats_dict, timing_dict)
    """
    _ensure_loaded()

    if _REAL_PREDICT_FN is None:
        raise RuntimeError(REAL_PIPELINE_ERROR or "Real delegate is not ready")

    try:
        try:
            out = _REAL_PREDICT_FN(rgb_u8=rgb_u8, threshold=threshold)
        except TypeError:
            out = _REAL_PREDICT_FN(rgb_u8, threshold)
    except Exception as exc:
        raise RuntimeError(f"Delegate predict failed: {exc}") from exc

    if not isinstance(out, tuple) or len(out) != 4:
        raise RuntimeError("Delegate must return tuple: (proba_map, mask_u8, stats, timing)")

    proba_map, mask_u8, stats, timing = out

    if not isinstance(proba_map, np.ndarray):
        raise RuntimeError("Delegate proba_map must be numpy.ndarray")
    if not isinstance(mask_u8, np.ndarray):
        raise RuntimeError("Delegate mask_u8 must be numpy.ndarray")
    if not isinstance(stats, dict):
        raise RuntimeError("Delegate stats must be dict")
    if not isinstance(timing, dict):
        raise RuntimeError("Delegate timing must be dict")

    if mask_u8.dtype != np.uint8:
        mask_u8 = np.clip(mask_u8, 0, 255).astype(np.uint8)

    return proba_map, mask_u8, stats, _normalize_timing(timing)

from __future__ import annotations

import argparse
import importlib
import json
import traceback
from typing import Any

import numpy as np


def _to_jsonable(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): _to_jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_jsonable(v) for v in value]
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        return float(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    return value


def _normalize_timing(timing: dict[str, Any]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key in ("pre_ms", "infer_ms", "post_ms"):
        value = timing.get(key, 0.0)
        out[key] = round(float(value), 3)
    return out


def _load_input(path: str) -> tuple[np.ndarray, float]:
    data = np.load(path, allow_pickle=False)
    rgb_u8 = data["rgb_u8"]
    threshold_arr = np.asarray(data["threshold"]).reshape(-1)
    threshold = float(threshold_arr[0]) if threshold_arr.size else 0.75
    return rgb_u8, threshold


def _save_output(
    path: str,
    proba_map: np.ndarray,
    mask_u8: np.ndarray,
    stats: dict[str, Any],
    timing: dict[str, Any],
) -> None:
    np.savez_compressed(
        path,
        proba_map=proba_map.astype(np.float32, copy=False),
        mask_u8=np.clip(mask_u8, 0, 255).astype(np.uint8, copy=False),
        stats_json=np.asarray(json.dumps(_to_jsonable(stats), ensure_ascii=True)),
        timing_json=np.asarray(json.dumps(_normalize_timing(timing), ensure_ascii=True)),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--module", required=True)
    parser.add_argument("--callable", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    try:
        module = importlib.import_module(args.module)
        fn = getattr(module, args.callable, None)
        if fn is None or not callable(fn):
            raise RuntimeError(f"Callable not found: {args.module}.{args.callable}")

        rgb_u8, threshold = _load_input(args.input)

        try:
            out = fn(rgb_u8=rgb_u8, threshold=threshold)
        except TypeError:
            out = fn(rgb_u8, threshold)

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

        _save_output(args.output, proba_map, mask_u8, stats, timing)
        return 0
    except Exception as exc:
        print(f"real_worker_runner failed: {exc}", flush=True)
        print(traceback.format_exc(), flush=True)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

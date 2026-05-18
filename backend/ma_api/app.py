from __future__ import annotations

import base64
import importlib
import inspect
import logging
import time
from io import BytesIO
from typing import Any, Callable
from uuid import uuid4

logger = logging.getLogger(__name__)

import numpy as np
from fastapi import FastAPI, File, HTTPException, Query, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError

from .config import settings
from .metrics import RollingStats
from .segmentation import (
    compute_statistics,
    create_overlay,
    image_to_png_bytes,
    npy_b64,
    png_data_url,
    preprocess_probability,
    remove_small_components,
)

app = FastAPI(title="MA Segmentation API", version=settings.api_version)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

STARTED_AT = time.time()
READY = True
WARMUP_MS = 0.0
STATS = RollingStats(maxlen=256)

ALLOWED_MIME = {"image/jpeg", "image/jpg", "image/png"}
MODE_AUTO = "auto"
MODE_SIM = "sim"
MODE_REAL = "real"
ALLOWED_MODES = {MODE_AUTO, MODE_SIM, MODE_REAL}

REAL_PIPELINE_FN: Callable[..., Any] | None = None
REAL_PIPELINE_ERROR: str | None = None
REAL_PIPELINE_META: dict[str, Any] = {}


def _load_real_pipeline() -> tuple[Callable[..., Any] | None, str | None, dict[str, Any]]:
    meta: dict[str, Any] = {
        "module": settings.real_pipeline_module or None,
        "callable": settings.real_pipeline_callable,
        "module_ready_flag": None,
        "pipeline_name": None,
        "pipeline_version": None,
    }

    if not settings.enable_real_mode:
        return None, "Real mode disabled (ENABLE_REAL_MODE=false)", meta

    if not settings.real_pipeline_module:
        return None, "REAL_PIPELINE_MODULE is empty", meta

    try:
        module = importlib.import_module(settings.real_pipeline_module)
    except Exception as exc:
        return None, f"Failed to import module '{settings.real_pipeline_module}': {exc}", meta

    meta["pipeline_name"] = getattr(module, "REAL_PIPELINE_NAME", None)
    meta["pipeline_version"] = getattr(module, "REAL_PIPELINE_VERSION", None)

    module_ready_flag = bool(getattr(module, "REAL_PIPELINE_READY", True))
    meta["module_ready_flag"] = module_ready_flag
    if not module_ready_flag:
        module_error = str(getattr(module, "REAL_PIPELINE_ERROR", "Real pipeline module reports not ready"))
        return None, module_error, meta

    fn = getattr(module, settings.real_pipeline_callable, None)
    if fn is None or not callable(fn):
        return (
            None,
            (
                "Callable not found: "
                f"{settings.real_pipeline_module}.{settings.real_pipeline_callable}"
            ),
            meta,
        )

    return fn, None, meta


REAL_PIPELINE_FN, REAL_PIPELINE_ERROR, REAL_PIPELINE_META = _load_real_pipeline()
REAL_PIPELINE_IMPLEMENTED = REAL_PIPELINE_FN is not None

# Cache call strategy at startup — avoid per-request exception-driven dispatch.
# Contract: REAL_PIPELINE_FN must accept (rgb_u8, threshold) positionally
# or (rgb_u8=..., threshold=...) as keyword args.
_pipeline_use_kwargs: bool = False
if REAL_PIPELINE_FN is not None:
    try:
        sig = inspect.signature(REAL_PIPELINE_FN)
        sig.bind(rgb_u8=None, threshold=0.5)
        _pipeline_use_kwargs = True
        logger.info("[init] REAL_PIPELINE_FN: using keyword call strategy")
    except (TypeError, ValueError):
        # ValueError: inspect.signature() fails for some C-extension / torch.compile objects
        _pipeline_use_kwargs = False
        logger.info("[init] REAL_PIPELINE_FN: using positional call strategy")


def _is_allowed_magic(raw: bytes) -> bool:
    if raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return True
    if raw.startswith(b"\xff\xd8\xff"):
        return True
    return False


def _validate_file(upload: UploadFile, raw: bytes) -> None:
    size_mb = len(raw) / (1024 * 1024)
    if size_mb > settings.max_file_mb:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({size_mb:.2f} MB). Max {settings.max_file_mb} MB",
        )

    if upload.content_type not in ALLOWED_MIME:
        raise HTTPException(
            status_code=415,
            detail=(
                f"Unsupported Media Type: {upload.content_type}. "
                "Use image/jpeg, image/jpg, or image/png"
            ),
        )

    if not _is_allowed_magic(raw):
        raise HTTPException(
            status_code=415,
            detail="Invalid image magic bytes. File content is not a valid PNG/JPEG.",
        )


def _decode_image(raw: bytes) -> np.ndarray:
    try:
        img = Image.open(BytesIO(raw)).convert("RGB")
    except UnidentifiedImageError as exc:
        raise HTTPException(status_code=415, detail="Cannot decode image file") from exc

    arr = np.array(img, dtype=np.uint8)
    h, w, _ = arr.shape
    mp = (h * w) / 1_000_000
    if mp > settings.max_megapixels:
        raise HTTPException(
            status_code=413,
            detail=(
                f"Image too large ({mp:.2f} MP). "
                f"Max allowed is {settings.max_megapixels:.1f} MP"
            ),
        )
    return arr


def _is_real_mode_ready() -> bool:
    return settings.enable_real_mode and REAL_PIPELINE_IMPLEMENTED


def _model_arch_label() -> str:
    if _is_real_mode_ready() and REAL_PIPELINE_META.get("pipeline_name"):
        return str(REAL_PIPELINE_META["pipeline_name"])
    return "UNetLinformerMamba-SIM"


def _normalize_mode(mode: str | None) -> str:
    resolved = (mode or settings.default_inference_mode).strip().lower()
    if resolved not in ALLOWED_MODES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode '{resolved}'. Allowed: auto, sim, real",
        )
    return resolved


def _resolve_inference_mode(
    mode: str | None,
    allow_fallback: bool,
) -> tuple[str, str, str | None, dict[str, str]]:
    requested = _normalize_mode(mode)
    fallback: str | None = None

    if requested == MODE_AUTO:
        if _is_real_mode_ready():
            used = MODE_REAL
        else:
            used = MODE_SIM
            fallback = "auto->sim"
    elif requested == MODE_REAL:
        if _is_real_mode_ready():
            used = MODE_REAL
        elif allow_fallback:
            used = MODE_SIM
            fallback = "real->sim"
        else:
            raise HTTPException(
                status_code=503,
                detail="Real model is not ready and fallback is disabled",
            )
    else:
        used = MODE_SIM

    headers = {
        "x-model-mode-requested": requested,
        "x-model-mode-used": used,
    }
    if fallback is not None:
        headers["x-model-fallback"] = fallback

    return requested, used, fallback, headers


def _timed_predict_sim(rgb_u8: np.ndarray, threshold: float) -> tuple[np.ndarray, np.ndarray, dict, dict]:
    t0 = time.perf_counter()
    proba = preprocess_probability(rgb_u8)
    t1 = time.perf_counter()

    mask_u8 = (proba >= threshold).astype(np.uint8) * 255
    mask_u8 = remove_small_components(mask_u8, min_area=settings.min_component_area)
    stats = compute_statistics(mask_u8)
    t2 = time.perf_counter()

    timing = {
        "pre_ms": round((t1 - t0) * 1000.0, 3),
        "infer_ms": 0.0,
        "post_ms": round((t2 - t1) * 1000.0, 3),
    }
    return proba, mask_u8, stats, timing


def _timed_predict_real(rgb_u8: np.ndarray, threshold: float) -> tuple[np.ndarray, np.ndarray, dict, dict]:
    if REAL_PIPELINE_FN is None:
        detail = REAL_PIPELINE_ERROR or "Real model pipeline is not ready"
        raise HTTPException(status_code=503, detail=detail)

    try:
        if _pipeline_use_kwargs:
            out = REAL_PIPELINE_FN(rgb_u8=rgb_u8, threshold=threshold)
        else:
            out = REAL_PIPELINE_FN(rgb_u8, threshold)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Real mode inference failed: {exc}") from exc

    if out is None:
        raise HTTPException(status_code=500, detail="REAL_PIPELINE_FN returned None")
    if not isinstance(out, tuple):
        raise HTTPException(
            status_code=500,
            detail=f"REAL_PIPELINE_FN must return tuple, got {type(out).__name__}",
        )
    if len(out) != 4:
        raise HTTPException(
            status_code=500,
            detail=f"REAL_PIPELINE_FN must return 4-tuple, got len={len(out)}",
        )

    proba_map, mask_u8, stats, timing = out

    if not isinstance(proba_map, np.ndarray):
        raise HTTPException(status_code=500, detail="Real pipeline output proba_map must be numpy.ndarray")
    if not isinstance(mask_u8, np.ndarray):
        raise HTTPException(status_code=500, detail="Real pipeline output mask_u8 must be numpy.ndarray")
    if not isinstance(stats, dict):
        raise HTTPException(status_code=500, detail="Real pipeline output stats must be dict")
    if not isinstance(timing, dict):
        raise HTTPException(status_code=500, detail="Real pipeline output timing must be dict")

    if proba_map.ndim < 2 or mask_u8.ndim < 2:
        raise HTTPException(
            status_code=500,
            detail=f"Pipeline output unexpected ndim: proba={proba_map.ndim}, mask={mask_u8.ndim}",
        )
    if proba_map.size == 0 or mask_u8.size == 0:
        raise HTTPException(status_code=500, detail="Pipeline returned empty array")
    if proba_map.shape[:2] != mask_u8.shape[:2]:
        raise HTTPException(
            status_code=500,
            detail=f"Shape mismatch: proba={proba_map.shape}, mask={mask_u8.shape}",
        )
    if not np.issubdtype(proba_map.dtype, np.number):
        raise HTTPException(
            status_code=500,
            detail=f"proba_map dtype must be numeric, got {proba_map.dtype}",
        )

    if mask_u8.dtype != np.uint8:
        mask_u8 = np.clip(mask_u8, 0, 255).astype(np.uint8)

    for key in ("pre_ms", "infer_ms", "post_ms"):
        value = timing.get(key, 0.0)
        try:
            timing[key] = round(float(value), 3)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Invalid real timing field '{key}': {exc}") from exc

    return proba_map, mask_u8, stats, timing


def _timed_predict(rgb_u8: np.ndarray, threshold: float, mode_used: str) -> tuple[np.ndarray, np.ndarray, dict, dict]:
    if mode_used == MODE_REAL:
        return _timed_predict_real(rgb_u8, threshold)
    return _timed_predict_sim(rgb_u8, threshold)


def _predict_with_runtime_fallback(
    rgb_u8: np.ndarray,
    threshold: float,
    requested_mode: str,
    mode_used: str,
    mode_fallback: str | None,
    allow_fallback: bool,
    mode_headers: dict[str, str],
) -> tuple[np.ndarray, np.ndarray, dict, dict, str, str | None, dict[str, str]]:
    try:
        proba_map, mask_u8, stats, timing = _timed_predict(rgb_u8, threshold, mode_used)
        return proba_map, mask_u8, stats, timing, mode_used, mode_fallback, mode_headers
    except HTTPException as exc:
        if mode_used == MODE_REAL and allow_fallback and requested_mode in {MODE_AUTO, MODE_REAL}:
            logger.warning("[predict] real-mode failed (%r) — falling back to sim", exc.detail)
            proba_map, mask_u8, stats, timing = _timed_predict_sim(rgb_u8, threshold)
            mode_used = MODE_SIM
            mode_fallback = mode_fallback or "real-runtime->sim"
            mode_headers = dict(mode_headers)
            mode_headers["x-model-mode-used"] = MODE_SIM
            mode_headers["x-model-fallback"] = mode_fallback
            return proba_map, mask_u8, stats, timing, mode_used, mode_fallback, mode_headers
        raise


def _response_headers(
    request_id: str,
    timing: dict,
    output_type: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, str]:
    headers = {
        "x-request-id": request_id,
        "x-pre-ms": str(timing["pre_ms"]),
        "x-infer-ms": str(timing["infer_ms"]),
        "x-post-ms": str(timing["post_ms"]),
    }
    if output_type is not None:
        headers["x-output"] = output_type
    if extra_headers:
        headers.update(extra_headers)
    return headers


@app.get("/")
def root() -> dict:
    uptime = time.time() - STARTED_AT
    return {
        "status": "ok",
        "ready": READY,
        "api_version": settings.api_version,
        "model_version": settings.model_version,
        "device": settings.device,
        "checkpoint_sha256": settings.checkpoint_sha256,
        "uptime_s": round(uptime, 3),
        "warmup_ms": WARMUP_MS,
        "default_inference_mode": settings.default_inference_mode,
        "real_mode_enabled": settings.enable_real_mode,
        "real_mode_ready": _is_real_mode_ready(),
        "allow_real_fallback": settings.allow_real_fallback,
        "real_pipeline_module": settings.real_pipeline_module or None,
        "real_pipeline_callable": settings.real_pipeline_callable,
        "real_pipeline_name": REAL_PIPELINE_META.get("pipeline_name"),
        "real_pipeline_version": REAL_PIPELINE_META.get("pipeline_version"),
        "real_pipeline_module_ready": REAL_PIPELINE_META.get("module_ready_flag"),
        "real_pipeline_error": REAL_PIPELINE_ERROR,
    }


@app.get("/healthz")
def healthz() -> dict:
    uptime = time.time() - STARTED_AT
    return {
        "status": "ok",
        "ready": READY,
        "model_loaded": READY,
        "api_version": settings.api_version,
        "model_version": settings.model_version,
        "device": settings.device,
        "checkpoint_sha256": settings.checkpoint_sha256,
        "uptime_s": round(uptime, 3),
        "warmup_ms": WARMUP_MS,
        "default_inference_mode": settings.default_inference_mode,
        "real_mode_enabled": settings.enable_real_mode,
        "real_mode_ready": _is_real_mode_ready(),
        "allow_real_fallback": settings.allow_real_fallback,
        "real_pipeline_module_ready": REAL_PIPELINE_META.get("module_ready_flag"),
        "real_pipeline_error": REAL_PIPELINE_ERROR,
    }


@app.get("/model_info")
def model_info() -> dict:
    return {
        "task": "Microaneurysm Segmentation",
        "arch": _model_arch_label(),
        "in_channels": 1,
        "classes": "Binary",
        "model_version": settings.model_version,
        "api_version": settings.api_version,
        "device": settings.device,
        "checkpoint_sha256": settings.checkpoint_sha256,
        "deterministic": True,
        "available_modes": [MODE_AUTO, MODE_SIM, MODE_REAL],
        "default_mode": settings.default_inference_mode,
        "real_mode_enabled": settings.enable_real_mode,
        "real_mode_ready": _is_real_mode_ready(),
        "allow_real_fallback": settings.allow_real_fallback,
        "real_pipeline_module": settings.real_pipeline_module or None,
        "real_pipeline_callable": settings.real_pipeline_callable,
        "real_pipeline_name": REAL_PIPELINE_META.get("pipeline_name"),
        "real_pipeline_version": REAL_PIPELINE_META.get("pipeline_version"),
        "real_pipeline_module_ready": REAL_PIPELINE_META.get("module_ready_flag"),
        "real_pipeline_error": REAL_PIPELINE_ERROR,
    }


@app.get("/metrics_basic")
def metrics_basic() -> dict:
    return STATS.as_dict()


@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    fmt: str = Query(default="json", pattern="^(png|proba|compact|json)$"),
    threshold: float = Query(default=0.75, ge=0.0, le=1.0),
    return_overlay: bool = Query(default=True),
    proba: bool = Query(default=False),
    mode: str = Query(default=settings.default_inference_mode, pattern="^(auto|sim|real)$"),
    allow_fallback: bool = Query(default=settings.allow_real_fallback),
):
    if not READY:
        raise HTTPException(status_code=503, detail="Model not ready")

    req_id = str(uuid4())
    raw = await file.read()
    _validate_file(file, raw)
    rgb_u8 = _decode_image(raw)

    requested_mode, mode_used, mode_fallback, mode_headers = _resolve_inference_mode(
        mode,
        allow_fallback,
    )

    (
        proba_map,
        mask_u8,
        stats,
        timing,
        mode_used,
        mode_fallback,
        mode_headers,
    ) = _predict_with_runtime_fallback(
        rgb_u8,
        threshold,
        requested_mode,
        mode_used,
        mode_fallback,
        allow_fallback,
        mode_headers,
    )
    STATS.add(timing["pre_ms"], timing["infer_ms"], timing["post_ms"])

    if fmt == "png":
        png = image_to_png_bytes(mask_u8)
        return Response(
            content=png,
            media_type="image/png",
            headers=_response_headers(
                req_id,
                timing,
                output_type="mask",
                extra_headers=mode_headers,
            ),
        )

    if fmt == "proba":
        finite_mask = np.isfinite(proba_map)
        if not finite_mask.all():
            non_finite_count = int(finite_mask.size - finite_mask.sum())
            logger.warning("[predict] proba_map contains %d non-finite values — sanitizing", non_finite_count)
        proba_map = np.nan_to_num(proba_map, nan=0.0, posinf=1.0, neginf=0.0)
        proba_u8 = np.clip(proba_map * 255.0, 0, 255).astype(np.uint8)
        png = image_to_png_bytes(proba_u8)
        return Response(
            content=png,
            media_type="image/png",
            headers=_response_headers(
                req_id,
                timing,
                output_type="probability_u8",
                extra_headers=mode_headers,
            ),
        )

    mask_png_b64 = base64.b64encode(image_to_png_bytes(mask_u8)).decode("ascii")

    if fmt == "compact":
        payload = {
            "status": "success",
            "filename": file.filename,
            "mask_png_b64": mask_png_b64,
            "timing_ms": timing,
            "request_id": req_id,
            "requested_mode": requested_mode,
            "mode_used": mode_used,
            "mode_fallback": mode_fallback,
        }
        import json

        return Response(
            content=json.dumps(payload),
            media_type="application/json",
            headers=_response_headers(req_id, timing, extra_headers=mode_headers),
        )

    overlay_url = None
    original_url = None
    if return_overlay:
        overlay_u8 = create_overlay(rgb_u8, mask_u8)
        overlay_url = png_data_url(overlay_u8)
        original_url = png_data_url(rgb_u8)

    payload = {
        "status": "success",
        "filename": file.filename,
        "image_size": {"width": int(rgb_u8.shape[1]), "height": int(rgb_u8.shape[0])},
        "threshold": threshold,
        "segmentation_mask": "data:image/png;base64," + mask_png_b64,
        "overlay_image": overlay_url,
        "original_image": original_url,
        "statistics": stats,
        "timing_ms": timing,
        "api_version": settings.api_version,
        "model_version": settings.model_version,
        "checkpoint_sha256": settings.checkpoint_sha256,
        "requested_mode": requested_mode,
        "mode_used": mode_used,
        "mode_fallback": mode_fallback,
    }

    if proba:
        payload["proba_npy_b64"] = npy_b64(proba_map.astype(np.float32))

    import json

    return Response(
        content=json.dumps(payload),
        media_type="application/json",
        headers=_response_headers(req_id, timing, extra_headers=mode_headers),
    )


@app.post("/predict_batch")
async def predict_batch(
    files: list[UploadFile] = File(...),
    fmt: str = Query(default="compact", pattern="^(compact|stats)$"),
    threshold: float = Query(default=0.75, ge=0.0, le=1.0),
    mode: str = Query(default=settings.default_inference_mode, pattern="^(auto|sim|real)$"),
    allow_fallback: bool = Query(default=settings.allow_real_fallback),
):
    if not READY:
        raise HTTPException(status_code=503, detail="Model not ready")

    if len(files) == 0:
        raise HTTPException(status_code=400, detail="No files uploaded")
    if len(files) == 1:
        logger.warning("[batch] single file submitted — consider /predict for single images")
    if len(files) > settings.max_batch_files:
        raise HTTPException(
            status_code=400,
            detail=f"Too many files. Max allowed is {settings.max_batch_files}",
        )

    req_id = str(uuid4())
    results = []
    requested_mode, mode_used, mode_fallback, mode_headers = _resolve_inference_mode(
        mode,
        allow_fallback,
    )
    batch_mode_used = mode_used
    batch_mode_fallback = mode_fallback

    for file in files:
        try:
            raw = await file.read()
            _validate_file(file, raw)
            rgb_u8 = _decode_image(raw)
            (
                proba_map,
                mask_u8,
                stats,
                timing,
                item_mode_used,
                item_mode_fallback,
                _,
            ) = _predict_with_runtime_fallback(
                rgb_u8,
                threshold,
                requested_mode,
                mode_used,
                mode_fallback,
                allow_fallback,
                mode_headers,
            )
            STATS.add(timing["pre_ms"], timing["infer_ms"], timing["post_ms"])

            item = {
                "filename": file.filename,
                "status": "success",
                "mode_used": item_mode_used,
                "mode_fallback": item_mode_fallback,
            }
            if item_mode_used == MODE_SIM:
                batch_mode_used = MODE_SIM
            if item_mode_fallback:
                batch_mode_fallback = item_mode_fallback

            if fmt == "compact":
                try:
                    item["mask_png_b64"] = base64.b64encode(image_to_png_bytes(mask_u8)).decode("ascii")
                except Exception as enc_exc:
                    item["mask_png_b64"] = None
                    item["overlay_png_b64"] = None
                    item["error"] = f"Encoding failed: {enc_exc}"
                item["timing_ms"] = timing
            else:
                item["num_components"] = stats["num_microaneurysms"]
                item["coverage_pct"] = stats["coverage_percentage"]

            results.append(item)
        except HTTPException as exc:
            results.append(
                {
                    "filename": file.filename,
                    "status": "error",
                    "error": exc.detail,
                }
            )

    payload = {
        "status": "completed",
        "count": len(results),
        "results": results,
        "request_id": req_id,
        "requested_mode": requested_mode,
        "mode_used": batch_mode_used,
        "mode_fallback": batch_mode_fallback,
    }

    mode_headers = dict(mode_headers)
    mode_headers["x-model-mode-used"] = batch_mode_used
    if batch_mode_fallback:
        mode_headers["x-model-fallback"] = batch_mode_fallback

    import json

    return Response(
        content=json.dumps(payload),
        media_type="application/json",
        headers={"x-request-id": req_id, **mode_headers},
    )

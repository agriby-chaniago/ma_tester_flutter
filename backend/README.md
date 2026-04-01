# Backend MA API (Modular)

This backend replaces notebook runtime for local development stability.

## Setup

1. Create and activate virtual environment

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
```

1. Install dependencies

```bash
pip install -r requirements.txt
```

For real model path (PyTorch + notebook-port architecture):

```bash
pip install -r requirements-real.txt
```

Optional full parity (Mamba):

```bash
pip install -r requirements-real-mamba.txt
```

1. Run API server

```bash
python run.py
```

Server runs at `http://127.0.0.1:8000`.

## Smoke Test

Without image:

```bash
python tests/smoke_test.py --base http://127.0.0.1:8000
```

With image:

```bash
python tests/smoke_test.py --base http://127.0.0.1:8000 --image /path/to/retina.jpg
```

## Endpoints

- `GET /`
- `GET /healthz`
- `GET /model_info`
- `GET /metrics_basic`
- `POST /predict`
- `POST /predict_batch`

The API includes request-id headers and timing headers for client observability.

## Hybrid Inference Mode

`/predict` and `/predict_batch` now support:

- `mode=auto|sim|real`
- `allow_fallback=true|false`

Behavior:

- `auto`: use real mode when available, otherwise simulator.
- `sim`: force simulator mode.
- `real`: request real mode; if unavailable and `allow_fallback=true`, API falls back to simulator.
- If real mode fails at runtime and fallback is enabled, request is retried in simulator mode (`real-runtime->sim`).

Response metadata is returned via headers:

- `x-model-mode-requested`
- `x-model-mode-used`
- `x-model-fallback` (only when fallback happens)

Optional env flags:

- `DEFAULT_INFERENCE_MODE` (default `auto`)
- `ALLOW_REAL_FALLBACK` (default `true`)
- `ENABLE_REAL_MODE` (default `false`)
- `REAL_PIPELINE_MODULE` (default empty)
- `REAL_PIPELINE_CALLABLE` (default `predict`)
- `MAX_FILE_MB` (default `20`)
- `MAX_MEGAPIXELS` (default `16.0`)

Notes for dataset usage:

- IDRID images are often around 12 MP, so default `MAX_MEGAPIXELS=16.0` allows them.
- If needed, increase limits via env before starting backend, for example:

```bash
export MAX_MEGAPIXELS=20
export MAX_FILE_MB=30
```

If real mode is enabled, backend will try loading:

`<REAL_PIPELINE_MODULE>.<REAL_PIPELINE_CALLABLE>`

Expected callable contract:

```python
def predict(rgb_u8: np.ndarray, threshold: float):
    # return (proba_map, mask_u8, stats_dict, timing_dict)
    return proba_map, mask_u8, stats, {"pre_ms": 0.0, "infer_ms": 0.0, "post_ms": 0.0}
```

If module/callable is missing, real mode is marked not ready and fallback behavior applies.

### Quick Start Template

A template real pipeline is available at:

- `ma_api.real_pipeline_template.predict`

To test real-mode wiring flow (still expected not-ready status):

```bash
export ENABLE_REAL_MODE=true
export REAL_PIPELINE_MODULE=ma_api.real_pipeline_template
export REAL_PIPELINE_CALLABLE=predict
python run.py
```

Then replace template implementation and set `REAL_PIPELINE_READY=True` in the module.

### Adapter Mode (Recommended)

Use adapter module so backend contract stays stable while you iterate model code:

```bash
export ENABLE_REAL_MODE=true
export REAL_PIPELINE_MODULE=ma_api.real_inference
export REAL_PIPELINE_CALLABLE=predict

export REAL_IMPL_MODULE=ma_api.real_pipeline_template
export REAL_IMPL_CALLABLE=predict
```

Later, swap `REAL_IMPL_MODULE` to your actual model module without changing API app wiring.

## Always-On Local Run (No Connection Refused)

If you often get `Connection refused` during testing, use the safe runner scripts.

Start with auto-restart in background:

```bash
cd backend
VENV_DIR="$PWD/.venv" ./start_safe.sh
./wait_health.sh
```

Do not use `sudo` for these scripts. Running as root can create duplicate instances and port conflicts.

Tail logs:

```bash
tail -f .runtime/backend_safe.log
```

Stop safely:

```bash
./stop_safe.sh
```

`stop_safe.sh` also attempts to clean orphan backend listeners on port `8000` when pid files are stale.

If you see `ModuleNotFoundError: No module named 'fastapi'`, re-install deps into the canonical backend env:

```bash
cd backend
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/python -m pip install -r requirements.txt
./.venv/bin/python -c "import fastapi, uvicorn; print('deps_ok')"
```

Notes:

- `run_safe.sh` restarts backend automatically if process exits.
- `run.py` reads `HOST` and `PORT` env vars.
- `run_safe.sh` now exits immediately when port is already in use (no infinite restart loop).

### Real Notebook Port (Implemented)

Real implementation module is available at:

- `ma_api.real_impl_notebook_port.predict`

Minimal env for real path:

```bash
export ENABLE_REAL_MODE=true
export REAL_PIPELINE_MODULE=ma_api.real_inference
export REAL_PIPELINE_CALLABLE=predict

export REAL_IMPL_MODULE=ma_api.real_impl_notebook_port
export REAL_IMPL_CALLABLE=predict
export CKPT_PATH=/absolute/path/to/best_state_dict.pt
export REAL_DEVICE=auto
export REAL_UNSAFE_LOAD=false
export REAL_USE_LINFORMER=true
export REAL_USE_MAMBA=true
export REAL_IMPL_ISOLATED=true
export REAL_IMPL_TIMEOUT_S=180
```

Notes:

- If `CKPT_PATH` is missing, real mode will report not-ready and fallback to simulator (if enabled).
- `REAL_UNSAFE_LOAD=true` allows fallback to `weights_only=False` for trusted checkpoints only.
- Default real path expects Mamba ON (`REAL_USE_MAMBA=true`) for closer architecture parity.
- If Mamba installation/import is stuck, temporarily set `REAL_USE_MAMBA=false` and run without mamba-ssm.
- Enable Mamba only when environment is stable: `REAL_USE_MAMBA=true` and install `requirements-real-mamba.txt`.
- `REAL_IMPL_ISOLATED=true` runs real inference in a subprocess worker per request to prevent API process force-close on native crashes.
- If subprocess worker hangs, request is aborted after `REAL_IMPL_TIMEOUT_S` seconds.

# Backend — MA API

FastAPI backend for microaneurysm segmentation. Supports simulator mode (no GPU) and real model inference.

## Setup

```bash
cd backend
python3 -m venv .venv

# Base (simulator only)
.venv/bin/pip install -r requirements.txt

# Real model (PyTorch + notebook-port architecture)
.venv/bin/pip install -r requirements-real.txt

# Mamba SSM (optional, for full architecture parity)
.venv/bin/pip install -r requirements-real-mamba.txt
```

## Run

```bash
./run.sh start      # start in background (auto-restart on crash)
./run.sh stop       # stop
./run.sh restart    # restart
./run.sh status     # check if running
./run.sh logs       # tail log output
```

Server at `http://127.0.0.1:8000`.

Defaults baked in:
- `CKPT_PATH` → `ckpts_ma/best_state_dict.pt`
- `REAL_PIPELINE_MODULE` → `ma_api.real_impl_notebook_port`

Override any env var before calling `./run.sh start`:

```bash
PORT=9000 ./run.sh start
CKPT_PATH=/other/path.pt ./run.sh start
```

## Smoke Test

```bash
# Without image
.venv/bin/python tests/smoke_test.py --base http://127.0.0.1:8000

# With image
.venv/bin/python tests/smoke_test.py --base http://127.0.0.1:8000 --image /path/to/retina.jpg
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Health + real mode status |
| GET | `/model_info` | Architecture + mode info |
| GET | `/metrics_basic` | Basic metrics |
| POST | `/predict` | Single image inference |
| POST | `/predict_batch` | Batch inference |

## Inference Modes

`mode=auto|sim|real` on `/predict` and `/predict_batch`:

| Mode | Behavior |
|------|----------|
| `auto` | Real if ready, else sim |
| `sim` | Force simulator |
| `real` | Force real; falls back to sim if `allow_fallback=true` |

Response headers: `x-model-mode-requested`, `x-model-mode-used`, `x-model-fallback`.

## Env Vars

| Var | Default | Description |
|-----|---------|-------------|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8000` | Bind port |
| `CKPT_PATH` | `ckpts_ma/best_state_dict.pt` | Checkpoint path |
| `REAL_PIPELINE_MODULE` | `ma_api.real_impl_notebook_port` | Inference module |
| `REAL_PIPELINE_CALLABLE` | `predict` | Callable in module |
| `ENABLE_REAL_MODE` | `true` | Enable real inference |
| `ALLOW_REAL_FALLBACK` | `true` | Fallback to sim on real failure |
| `DEFAULT_INFERENCE_MODE` | `auto` | Default mode |
| `REAL_DEVICE` | `auto` | `cpu`, `cuda`, or `auto` |
| `REAL_USE_MAMBA` | `true` | Use mamba_ssm decoder |
| `REAL_MAMBA_STRICT` | `false` | Fail if mamba unavailable |
| `REAL_UNSAFE_LOAD` | `false` | Allow `weights_only=False` |
| `REAL_IMPL_ISOLATED` | `true` | Run inference in subprocess |
| `REAL_IMPL_TIMEOUT_S` | `180` | Subprocess timeout |
| `MAX_FILE_MB` | `20` | Max upload size |
| `MAX_MEGAPIXELS` | `16.0` | Max image resolution |

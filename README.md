# MA Segmentation Tester

Flutter app for retinal microaneurysm segmentation — web simulator + full tester.

## Requirements

- Flutter SDK
- Python 3.11+ (for backend)

## Quick Start

### 1. Backend

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-real.txt -r requirements-real-mamba.txt

./run.sh start       # start in background
./run.sh status      # check running
./run.sh logs        # tail logs
./run.sh stop        # stop
```

Backend runs at `http://127.0.0.1:8000`.

### 2. Frontend

```bash
# Web (Chrome) — simulator UI
flutter pub get
flutter run -d chrome

# Desktop/device — full tester (API, batch, metrics, performance)
flutter run
```

### 3. Configure API URL

Edit `.env` in project root:

```
API_BASE=http://127.0.0.1:8000
TIMEOUT_MS=90000
```

> If `.env` fails to load in browser, enter API URL manually in the app bar.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Health check |
| GET | `/model_info` | Model metadata |
| GET | `/metrics_basic` | Basic metrics |
| POST | `/predict` | Single image inference |
| POST | `/predict_batch` | Batch inference |

## Inference Modes

`/predict` and `/predict_batch` accept `mode=auto|sim|real`:

- `auto` — use real model if ready, else simulator
- `sim` — force simulator
- `real` — force real model (falls back to sim if `allow_fallback=true`)

## Web Simulator Features

- Upload retinal image → run segmentation
- View: original / mask / overlay / compare
- Overlay opacity control
- Timing + statistics panel
- Session history

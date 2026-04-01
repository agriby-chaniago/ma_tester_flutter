# MA Segmentation Tester

Flutter application for retinal microaneurysm segmentation testing and simulation.

## App Modes

- Web mode opens an interactive simulator focused on upload and segmentation visualization.
- Non-web mode opens the full multi-tab tester for API testing, batch, metrics, and performance.

## Requirements

- Flutter SDK installed and available in PATH.
- A running backend API with these endpoints:
  - GET /healthz
  - GET /model_info
  - GET /metrics_basic
  - POST /predict
  - POST /predict_batch
- Configure API URL in .env:
  - API_BASE=https://your-server-url
  - TIMEOUT_MS=90000

## Run Local Web Simulator

1. Install dependencies

flutter pub get

2. Run web app

flutter run -d chrome

3. Open simulator and verify connection

- Click health check in app bar.
- Upload retinal image.
- Run simulation and inspect mask or overlay output.

## Run Non-Web App

flutter run

This opens the full tester interface (API tests, batch, single prediction, metrics, performance).

## Key Web Simulator Features

- Upload retinal image and run segmentation.
- Interactive viewer with zoom and pan.
- View modes: original, mask, overlay, compare.
- Overlay opacity control.
- Timing and segmentation statistics panel.
- Session history panel for recent runs.

## Notes

- If .env fails to load in some web environments, you can still enter API URL manually in the simulator.
- For stable local demos, ensure backend is ready before running inference.

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

---

## Docker Deployment (Zero-Config, GPU)

Jalankan full stack (Flutter web + FastAPI backend + GPU inference) di workstation mana pun tanpa install Flutter, Python, atau CUDA secara manual.

### Prasyarat

Install di workstation target sebelum mulai:

**1. Docker Engine (v24+)**
```bash
# Cek versi
docker --version
docker compose version
```
Install: https://docs.docker.com/engine/install/

**2. NVIDIA Driver (≥ 530.30.02 untuk CUDA 12.1)**
```bash
nvidia-smi
# Pastikan Driver Version ≥ 530.30.02
```

**3. NVIDIA Container Toolkit**
```bash
# Install
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verifikasi
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

---

### Step 1 — Clone Repository

```bash
git clone https://github.com/agriby-chaniago/ma_tester_flutter.git
cd ma_tester_flutter
```

---

### Step 2 — Copy Model Weights dari USB

Model weights tidak disimpan di git karena ukurannya besar. Copy dari flash drive ke folder berikut:

```
ma_tester_flutter/
└── backend/
    └── ckpts_ma/          ← paste semua file weights ke sini
        ├── best_state_dict.pt
        ├── best.ckpt
        ├── last.ckpt
        ├── ma_best_*.ckpt
        └── .gitkeep       ← file ini sudah ada, jangan dihapus
```

Setelah copy, verifikasi:
```bash
ls backend/ckpts_ma/
# Harus terlihat: best_state_dict.pt, best.ckpt, dll.
```

---

### Step 3 — Build Docker Images

```bash
docker compose build
```

Proses pertama kali memakan waktu ~10-20 menit (download PyTorch CUDA base image ~5GB + Flutter SDK). Build selanjutnya jauh lebih cepat karena layer cache.

---

### Step 4 — Jalankan

```bash
docker compose up
```

Tunggu hingga backend healthy (model PyTorch load ~60-90 detik). Log yang menandakan siap:
```
backend-1  | INFO:     Application startup complete.
```

---

### Step 5 — Buka Aplikasi

Buka browser di workstation **mana pun** yang bisa reach server:

```
http://<IP-workstation>
```

Contoh:
- Di server sendiri: `http://localhost`
- Dari laptop lain di LAN: `http://192.168.1.100`

`API_BASE` otomatis menyesuaikan hostname — tidak perlu konfigurasi manual.

---

### Verifikasi

```bash
# GPU terdeteksi di container
docker compose exec backend nvidia-smi

# Dynamic .env berjalan benar
curl http://localhost/assets/.env
# Output: API_BASE=http://localhost/api

# Backend healthy
curl http://localhost/api/healthz
```

---

### Perintah Berguna

```bash
docker compose up -d          # jalankan di background
docker compose logs -f        # lihat log realtime
docker compose logs backend   # log backend saja
docker compose down           # stop + hapus container
docker compose build --no-cache  # rebuild dari awal (jika ada masalah)
```

---

### Troubleshooting

**Frontend 502 Bad Gateway saat pertama buka**
Backend masih loading model PyTorch. Tunggu 60-90 detik, refresh browser.

**`curl http://localhost/assets/.env` → 404**
Flutter web asset path berbeda di versi Flutter ini. Cek path aktual:
```bash
docker compose exec frontend ls /usr/share/nginx/html/
```
Sesuaikan `location` di `docker/nginx.conf` jika path berbeda.

**`docker: unknown flag: --gpus`**
NVIDIA Container Toolkit belum terinstall atau Docker belum direstart setelah install. Ulangi Step prasyarat nomor 3.

**`CUDA driver version is insufficient`**
NVIDIA driver di host terlalu lama. Update driver ke ≥ 530.30.02.

**Inference lambat / fallback ke sim mode**
Real model gagal load. Cek apakah weights ada di `backend/ckpts_ma/`:
```bash
ls backend/ckpts_ma/*.ckpt
```
Jika kosong, ulangi Step 2.

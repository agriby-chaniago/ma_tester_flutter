# Retinexa

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

Install di workstation Windows 11 target sebelum mulai. **Urutan penting.**

**1. Git for Windows**

Download dan install: https://git-scm.com/download/win

Pilih opsi default saat wizard install. Setelah selesai, gunakan **Windows Terminal** atau **PowerShell** untuk semua perintah selanjutnya.

---

**2. NVIDIA Driver for Windows (≥ 530.30.02 untuk CUDA 12.1)**

Download driver terbaru untuk GPU kamu: https://www.nvidia.com/Download/index.aspx

Install driver, restart Windows, lalu verifikasi:
```powershell
nvidia-smi
# Pastikan Driver Version ≥ 530.30.02
```

> Install driver **sebelum** Docker Desktop agar GPU terdeteksi dengan benar saat konfigurasi WSL2.

---

**3. Docker Desktop for Windows**

Download: https://docs.docker.com/desktop/install/windows-install/

Jalankan installer, ikuti wizard. Docker Desktop akan otomatis menginstall dan mengaktifkan **WSL2** jika belum ada — restart Windows jika diminta.

Setelah install, verifikasi:
```powershell
docker --version
docker compose version
```

> Pastikan WSL2 backend aktif: Docker Desktop → Settings → General → "Use the WSL 2 based engine" ✓ (default di Windows 11).

---

**4. Verifikasi GPU ke Docker**

```powershell
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

Output harus menampilkan info GPU. Jika berhasil, setup selesai.

> Di Windows 11 + Docker Desktop, NVIDIA Container Toolkit **tidak perlu diinstall manual**. Docker Desktop otomatis enable GPU passthrough via WSL2 backend.

---

### Step 1 — Clone Repository

```bash
git clone https://github.com/agriby-chaniago/retinexa.git
cd retinexa
```

---

### Step 2 — Copy Model Weights dari USB

Model weights tidak disimpan di git karena ukurannya besar. Copy dari flash drive ke folder berikut:

```
retinexa/
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
Docker Desktop belum enable GPU support. Pastikan: Settings → General → "Use the WSL 2 based engine" aktif, lalu restart Docker Desktop.

**`CUDA driver version is insufficient`**
NVIDIA driver di host terlalu lama. Update driver ke ≥ 530.30.02.

**Inference lambat / fallback ke sim mode**
Real model gagal load. Cek apakah weights ada di `backend/ckpts_ma/`:
```bash
ls backend/ckpts_ma/*.ckpt
```
Jika kosong, ulangi Step 2.

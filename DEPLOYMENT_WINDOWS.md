# Deployment Guide — Windows 11 + NVIDIA GPU

Panduan A–Z untuk menjalankan MA Segmentation Tester di PC pameran berbasis Windows 11.

---

## Hardware Requirements

| Komponen | Minimum |
|----------|---------|
| RAM | 16 GB |
| VRAM | 6 GB |
| Disk | 40 GB free (Docker image CUDA ~5GB + build cache + WSL virtual disk) |
| GPU | NVIDIA dengan driver ≥ 530.30.02 |
| OS | Windows 11 |

---

## Section 1 — Install Prasyarat (sekali saja)

### A. Aktifkan WSL2

Buka PowerShell **sebagai Administrator**, jalankan:

```powershell
wsl --install
```

Restart PC, lalu:

```powershell
wsl --set-default-version 2
```

### B. Install NVIDIA Driver Terbaru

- Download dari: https://www.nvidia.com/Download/index.aspx
- CUDA on WSL2 otomatis tersedia dengan driver ≥ 527.41 — tidak perlu install CUDA toolkit terpisah

### C. Install Docker Desktop

- Download dari: https://www.docker.com/products/docker-desktop/
- Saat install: centang **"Use WSL 2 based engine"**
- Setelah install, buka Docker Desktop:
  - Settings → General → aktifkan **"Use WSL 2 based engine"**
  - Settings → Resources → WSL Integration → aktifkan distro default

### D. Install Git

- Download dari: https://git-scm.com/download/win
- Pilih opsi: **"Git from the command line and also from 3rd-party software"**

### E. Verifikasi GPU di Docker

Buka PowerShell, jalankan:

```powershell
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

Output harus menampilkan info GPU. Jika error, selesaikan dulu sebelum lanjut.

---

## Section 2 — Windows Power Settings (WAJIB untuk pameran)

Cegah PC tidur/sleep saat demo berlangsung.

Via PowerShell as Administrator:

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

Atau manual:

```
Control Panel → Power Options → High Performance
System Settings → Sleep → Never
Windows Update → Advanced Options → uncheck "Automatically restart this device when needed"
```

---

## Section 3 — Setup Project (sekali saja)

### A. Pre-pull base images *(opsional, mempercepat build)*

```powershell
docker pull pytorch/pytorch:2.3.1-cuda12.1-cudnn8-runtime
docker pull ghcr.io/cirruslabs/flutter:stable
```

### B. Clone repository

```powershell
git clone https://github.com/agriby-chaniago/retinexa.git
cd retinexa
```

### C. Copy model weights dari USB

Salin isi folder `ckpts_ma` dari USB ke `backend\ckpts_ma\`:

```powershell
# Ganti D: dengan drive letter USB Anda
xcopy D:\ckpts_ma\* backend\ckpts_ma\ /Y
```

Verifikasi:

```powershell
dir backend\ckpts_ma\
# Harus ada: best_state_dict.pt, best.ckpt, dll.
```

### D. Build Docker images

> **Direkomendasikan:** Build di PC development, transfer via `docker save/load` (lihat Section 6).
> Build onsite hanya jika tidak ada image yang sudah disimpan.

Build memerlukan internet stabil dan memakan waktu **15–20 menit** pertama kali:

```powershell
docker compose build
```

Verifikasi setelah build:

```powershell
docker images
# Harus ada: ma_tester_backend:latest dan ma_tester_frontend:latest
```

---

## Section 4 — Menjalankan Setiap Pameran

**Cara 1 — Script (disarankan):**

Double-click `start.bat` — akan menunggu backend siap lalu otomatis buka browser.

**Cara 2 — Manual:**

```powershell
docker compose up -d
# Tunggu ~90 detik (PyTorch loading), lalu buka browser ke:
start http://localhost
```

Monitor log jika perlu:

```powershell
docker compose logs -f
```

Log yang menandakan siap: `INFO:     Application startup complete.`

---

## Section 5 — Stop

Double-click `stop.bat`, atau:

```powershell
# Temporary stop (container tetap ada, restart lebih cepat):
docker compose stop

# Full shutdown + hapus container:
docker compose down
```

---

## Section 6 — Offline Backup Strategy (SANGAT DISARANKAN)

Setelah build berhasil, simpan image ke SSD/USB eksternal agar bisa deploy tanpa internet.

**Simpan image (di PC dev atau PC pameran setelah build):**

```powershell
docker save -o ma_backend.tar ma_tester_backend:latest
docker save -o ma_frontend.tar ma_tester_frontend:latest
```

Simpan `ma_backend.tar` + `ma_frontend.tar` + seluruh folder project ke SSD.

**Load image di PC lain (tidak perlu internet, tidak perlu rebuild):**

```powershell
docker load -i ma_backend.tar
docker load -i ma_frontend.tar
docker compose up -d
```

---

## Section 7 — Verifikasi

Setelah `docker compose up -d` dan tunggu ~90 detik:

```
Buka browser → http://localhost/api/healthz
Expected: {"status":"ok"}

Buka browser → http://localhost/assets/.env
Expected: API_BASE=http://localhost/api

Buka browser → http://localhost
Expected: App load, upload retina image → inference sukses
```

Via PowerShell:

```powershell
# GPU terdeteksi di container
docker compose exec backend nvidia-smi

# Status services
docker compose ps
# backend: healthy, frontend: running
```

---

## Section 8 — DO NOT (Saat Pameran Berlangsung)

```
❌ Jangan restart Windows
❌ Jangan jalankan Windows Update
❌ Jangan buka aplikasi GPU berat lain (game, render, streaming)
❌ Jangan tutup Docker Desktop dari system tray
❌ Jangan delete container/volume saat app running
❌ Jangan cabut internet jika belum ada offline backup (Section 6)
```

---

## Section 9 — Troubleshooting

**Docker Desktop tidak mau start**

```powershell
wsl --status   # pastikan WSL2 aktif
```

Pastikan virtualization (Intel VT-x / AMD-V) enabled di BIOS.

---

**GPU tidak terdeteksi di container**

- Update NVIDIA driver ke versi terbaru
- Docker Desktop: Settings → Resources → WSL Integration → aktifkan distro default
- Restart Docker Desktop setelah perubahan

---

**Port 80 sudah dipakai** (IIS, Apache, Skype, lainnya)

```powershell
netstat -ano | findstr :80
```

Ubah di `docker-compose.yml`:

```yaml
ports:
  - "8080:80"   # ganti 80 dengan port bebas
```

Akses via `http://localhost:8080`.

---

**Frontend 502 Bad Gateway saat pertama buka**

Backend masih loading model PyTorch (~90 detik). Tunggu dan refresh browser.

---

**Build gagal: flutter pub get / network error**

Docker Desktop tidak bisa akses internet. Proxy atau firewall kantor kadang memblokir. Gunakan offline strategy (Section 6) sebagai alternatif.

---

**Debug: backend tidak healthy / inference gagal**

```powershell
docker compose logs backend --tail 50
# Cari error: missing weights, CUDA failure, model load issue
```

Pastikan weights ada:

```powershell
dir backend\ckpts_ma\
# Harus ada .pt dan .ckpt files
```

---

**Build sangat lambat / Docker Desktop lag**

Windows Defender scan WSL filesystem memperlambat drastis. Tambahkan exclusion:

```
Windows Security → Virus & threat protection → Manage settings → Exclusions → Add a folder:
- C:\Users\<user>\AppData\Local\Docker
- C:\Users\<user>\.docker
- <lokasi folder project retinexa>
```

---

**WSL disk penuh**

```powershell
wsl -e df -h
# Bersihkan build cache (aman, tidak hapus image):
docker builder prune -f
```

---

**Emergency Recovery (Demo Tiba-Tiba Tidak Jalan)**

```powershell
# Step 1: restart services
docker compose restart

# Step 2: jika masih gagal
docker compose down
docker compose up -d

# Step 3: jika masih gagal → restart Docker Desktop dari system tray, lalu start.bat

# Step 4: Docker Desktop corrupt total
# 1. Quit Docker Desktop dari system tray
# 2. Di PowerShell as Admin: wsl --shutdown
# 3. Buka kembali Docker Desktop
# 4. Jika masih gagal: uninstall → reboot → install ulang Docker Desktop
#    (image yang sudah di-save via docker save TIDAK hilang)
```

---

**Inference pertama sangat lambat**

Normal. CUDA kernel compilation terjadi saat inference pertama setelah startup.
**Lakukan 1x test inference sebelum booth dibuka** — inference berikutnya jauh lebih cepat.

---

## Pre-Exhibition Checklist

Lakukan ini sebelum booth dibuka:

```
☐ Docker Desktop running — icon muncul di system tray
☐ Settings → General → "Start Docker Desktop when you log in" aktif
☐ docker compose ps → backend = "healthy", frontend = "running"
☐ docker compose exec backend nvidia-smi → GPU terdeteksi
☐ Buka http://localhost → app load
☐ Lakukan 1x test inference (CUDA warmup)
☐ Charger / power terhubung
☐ Windows sleep disabled (Section 2)
☐ Browser fullscreen aktif (gunakan start_kiosk.bat)
☐ Backup SSD dengan docker save tersedia (Section 6)
☐ Model weights ada di backend\ckpts_ma\
```

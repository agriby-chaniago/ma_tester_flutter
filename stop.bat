@echo off
echo Choose stop mode:
echo   1. Temporary stop  — containers preserved, restart lebih cepat (docker compose stop)
echo   2. Full shutdown   — hapus containers, next start lebih lambat (docker compose down)
echo.
echo Note: Kedua pilihan TIDAK menghapus Docker images.
echo       Jalankan start.bat untuk start ulang.
echo.
set /p choice="Enter 1 or 2: "
if "%choice%"=="1" (
    docker compose stop
    echo Containers stopped. Run start.bat to restart.
)
if "%choice%"=="2" (
    docker compose down
    echo Containers removed. Run start.bat to restart.
)
pause

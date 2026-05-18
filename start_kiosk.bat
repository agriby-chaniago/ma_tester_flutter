@echo off
echo Starting MA Segmentation Tester (Kiosk Mode)...
docker compose up -d

echo Waiting for backend to be ready (up to 3 minutes)...
:waitloop
powershell -Command "try { Invoke-WebRequest http://localhost/api/healthz -UseBasicParsing | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
    timeout /t 5 /nobreak > nul
    goto waitloop
)

if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" (
    start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --kiosk http://localhost --edge-kiosk-type=fullscreen
) else (
    start chrome --kiosk http://localhost
)
echo Done. Kiosk mode active at http://localhost

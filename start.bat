@echo off
echo Starting MA Segmentation Tester...
docker compose up -d

echo Waiting for backend to be ready (up to 3 minutes)...
:waitloop
powershell -Command "try { Invoke-WebRequest http://localhost/api/healthz -UseBasicParsing | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
    timeout /t 5 /nobreak > nul
    goto waitloop
)

start http://localhost
echo Done. App is running at http://localhost

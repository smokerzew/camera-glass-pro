@echo off
rem Double-click (or run) on Windows: builds dist\CameraGlassPro.ipa inside WSL Ubuntu.
rem Pass --sign or --install to forward to scripts/build-ipa.sh.
cd /d "%~dp0"
wsl.exe -d Ubuntu-24.04 --cd "%~dp0" -- bash -lc "./scripts/build-ipa.sh %*"
pause

@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0grok_regkit_service_manager.ps1" Restart
pause

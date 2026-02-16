@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0destroy-cluster.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-vagrant.ps1"
pause

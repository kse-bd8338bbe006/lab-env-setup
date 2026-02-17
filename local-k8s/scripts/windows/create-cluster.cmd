@echo off
cd /d "%~dp0"

multipass set local.driver=hyperv
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-network.ps1"
terraform init
terraform apply

pause

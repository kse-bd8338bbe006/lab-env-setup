@echo off
cd /d "%~dp0"

terraform destroy -auto-approve

multipass delete --all
multipass purge

del "%USERPROFILE%\.kube\config-multipass" 2>nul

pause

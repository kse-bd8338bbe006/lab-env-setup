@echo off
cd /d "%~dp0"

terraform destroy -auto-approve

multipass delete --all
multipass purge

pause

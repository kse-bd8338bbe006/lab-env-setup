@echo off
cd /d "%~dp0"

del "%TEMP%\hosts_ip.txt" 2>nul
multipass set local.driver=hyperv
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-network.ps1"

terraform init

REM First apply: creates VMs, cluster, and kubeconfig file
REM Second apply: kubernetes/helm providers detect kubeconfig and deploy resources
terraform apply -auto-approve
terraform apply -auto-approve

copy "%USERPROFILE%\.kube\config-multipass" "%USERPROFILE%\.kube\config"

pause

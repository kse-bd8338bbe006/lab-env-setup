# Reset script for Windows (Hyper-V / Multipass)
# Deletes all Multipass VMs and cleans up generated files

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "Deleting all Multipass VMs..." -ForegroundColor Yellow
multipass delete --all
multipass purge

Write-Host "Cleaning up generated files..." -ForegroundColor Yellow

# Remove infra generated files
Remove-Item -Path "infra\cloud-init-*.yaml" -ErrorAction SilentlyContinue
Remove-Item -Path "infra\haproxy_*.cfg" -ErrorAction SilentlyContinue
Remove-Item -Path "infra\terraform.tfstate*" -ErrorAction SilentlyContinue
Remove-Item -Path "infra\.terraform" -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "infra\.terraform.lock.hcl" -ErrorAction SilentlyContinue

# Remove apps generated files
Remove-Item -Path "apps\haproxy_ingress.cfg" -ErrorAction SilentlyContinue
Remove-Item -Path "apps\terraform.tfstate*" -ErrorAction SilentlyContinue
Remove-Item -Path "apps\.terraform" -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "apps\.terraform.lock.hcl" -ErrorAction SilentlyContinue

# Remove temporary files
Remove-Item -Path "$env:TEMP\hosts_ip.txt" -ErrorAction SilentlyContinue

# Remove kubeconfig
Remove-Item -Path "$env:USERPROFILE\.kube\config-multipass" -ErrorAction SilentlyContinue

Write-Host "Cleanup complete!" -ForegroundColor Green

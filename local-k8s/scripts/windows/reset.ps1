# Reset script for Windows
# Deletes all Multipass VMs and cleans up generated files

Write-Host "Deleting all Multipass VMs..." -ForegroundColor Yellow
multipass delete --all
multipass purge

Write-Host "Cleaning up generated files..." -ForegroundColor Yellow

# Remove cloud-init files
Remove-Item -Path "cloud-init-*.yaml" -ErrorAction SilentlyContinue
Remove-Item -Path "haproxy_*.cfg" -ErrorAction SilentlyContinue

# Remove Terraform state
Remove-Item -Path "terraform.tfstate*" -ErrorAction SilentlyContinue

# Remove temporary files
Remove-Item -Path "$env:TEMP\hosts_ip.txt" -ErrorAction SilentlyContinue

# Remove kubeconfig
Remove-Item -Path "$env:USERPROFILE\.kube\config-multipass" -ErrorAction SilentlyContinue

Write-Host "Cleanup complete!" -ForegroundColor Green

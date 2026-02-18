# Reset script for Windows (VirtualBox)
# Deletes all Vagrant VMs and cleans up generated files

Write-Host "Destroying Vagrant VMs..." -ForegroundColor Yellow
vagrant destroy -f

Write-Host "Cleaning up generated files..." -ForegroundColor Yellow

# Remove cloud-init files
Remove-Item -Path "infra\cloud-init-*.yaml" -ErrorAction SilentlyContinue
Remove-Item -Path "infra\haproxy_*.cfg" -ErrorAction SilentlyContinue
Remove-Item -Path "apps\haproxy_*.cfg" -ErrorAction SilentlyContinue

# Remove Terraform state
Remove-Item -Path "infra\terraform.tfstate*" -ErrorAction SilentlyContinue
Remove-Item -Path "apps\terraform.tfstate*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Path "infra\.terraform" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Path "apps\.terraform" -ErrorAction SilentlyContinue
Remove-Item -Path "infra\.terraform.lock.hcl" -ErrorAction SilentlyContinue
Remove-Item -Path "apps\.terraform.lock.hcl" -ErrorAction SilentlyContinue

# Remove temporary files
Remove-Item -Path "$env:TEMP\hosts_ip.txt" -ErrorAction SilentlyContinue

# Remove kubeconfig
Remove-Item -Path "$env:USERPROFILE\.kube\config-virtualbox" -ErrorAction SilentlyContinue

Write-Host "Cleanup complete!" -ForegroundColor Green

# Reset script for Windows (root level)
# Deletes all Multipass VMs and cleans up generated files

Write-Host "Deleting all Multipass VMs..." -ForegroundColor Yellow

# todo: delete only create vm for this k8s
multipass delete --all
multipass purge

Write-Host "Cleaning up generated files in windows directory..." -ForegroundColor Yellow

# Navigate to windows directory and clean up
if (Test-Path ".\windows") {
    Push-Location ".\windows"
    
    # Remove cloud-init files
    Remove-Item -Path "cloud-init-*.yaml" -ErrorAction SilentlyContinue
    Remove-Item -Path "haproxy_*.cfg" -ErrorAction SilentlyContinue
    
    # Remove Terraform state
    Remove-Item -Path "terraform.tfstate*" -ErrorAction SilentlyContinue
    
    Pop-Location
}

# Clean up root Terraform state
Remove-Item -Path "terraform.tfstate*" -ErrorAction SilentlyContinue

# Remove temporary files
Remove-Item -Path "$env:TEMP\hosts_ip.txt" -ErrorAction SilentlyContinue

# Remove kubeconfig
Remove-Item -Path "$env:USERPROFILE\.kube\config-multipass" -ErrorAction SilentlyContinue

Write-Host "Cleanup complete!" -ForegroundColor Green

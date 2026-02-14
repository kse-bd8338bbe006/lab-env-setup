#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up VirtualBox Host-Only Network for Kubernetes cluster VMs.

.DESCRIPTION
    Creates a VirtualBox Host-Only adapter for static IP communication between
    the host and K8s cluster VMs. Internet access is provided separately by
    Multipass default NAT network.

    This script is for Windows Home edition users who cannot use Hyper-V.

.NOTES
    Prerequisites:
    - VirtualBox 7.0+ installed
    - Run this script once as Administrator before running terraform apply
    - Multipass must be configured to use VirtualBox backend:
      multipass set local.driver=virtualbox

    Network architecture (dual-adapter VMs):
    - eth0: Multipass NAT (internet access, dynamic IP)
    - k8snet: Host-Only Adapter (cluster communication, static IP)

    Host-Only network configuration:
    - Adapter: VirtualBox Host-Only Ethernet Adapter
    - Subnet: 192.168.56.0/24
    - Host IP: 192.168.56.1
#>

param(
    [string]$GatewayIP = "192.168.56.1",
    [string]$Netmask = "255.255.255.0",
    [string]$Subnet = "192.168.56.0/24"
)

Write-Host "Setting up VirtualBox network for Kubernetes cluster..." -ForegroundColor Cyan

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Find VBoxManage
$vboxManagePaths = @(
    "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
    "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe"
)

$vboxManage = $null
foreach ($path in $vboxManagePaths) {
    if (Test-Path $path) {
        $vboxManage = $path
        break
    }
}

if (-not $vboxManage) {
    Write-Error "VBoxManage.exe not found. Please install VirtualBox first."
    Write-Host "Download from: https://www.virtualbox.org/wiki/Downloads" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Found VBoxManage: $vboxManage" -ForegroundColor Gray

# Check existing Host-Only adapters
Write-Host "Checking Host-Only adapters..." -ForegroundColor Yellow
$existingAdapters = & $vboxManage list hostonlyifs 2>&1

$adapterExists = $false
$adapterConfigured = $false
$adapterName = $null

if ($existingAdapters -match "Name:\s+(.+)") {
    # Parse existing adapters to find one with our IP or any existing adapter
    $lines = $existingAdapters -split "`n"
    $currentAdapter = $null
    $currentIP = $null

    foreach ($line in $lines) {
        if ($line -match "^Name:\s+(.+)$") {
            # Save previous adapter if it had our IP
            if ($currentAdapter -and $currentIP -eq $GatewayIP) {
                $adapterConfigured = $true
                $adapterName = $currentAdapter.Trim()
            }
            $currentAdapter = $Matches[1]
            $adapterExists = $true
            # Keep first adapter as fallback
            if (-not $adapterName) {
                $adapterName = $currentAdapter.Trim()
            }
        }
        if ($line -match "^IPAddress:\s+(.+)$") {
            $currentIP = $Matches[1].Trim()
        }
    }
    # Check last adapter
    if ($currentAdapter -and $currentIP -eq $GatewayIP) {
        $adapterConfigured = $true
        $adapterName = $currentAdapter.Trim()
    }
}

if ($adapterConfigured) {
    Write-Host "  Host-Only adapter '$adapterName' already configured with IP $GatewayIP" -ForegroundColor Gray
} elseif ($adapterExists) {
    # Configure existing adapter
    Write-Host "  Configuring existing Host-Only adapter: $adapterName" -ForegroundColor Green

    & $vboxManage hostonlyif ipconfig "$adapterName" --ip $GatewayIP --netmask $Netmask
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure Host-Only adapter IP"
        exit 1
    }
    Write-Host "  Configured IP: $GatewayIP/$Netmask" -ForegroundColor Green
} else {
    # Create new adapter
    Write-Host "  Creating new Host-Only adapter..." -ForegroundColor Green
    $createResult = & $vboxManage hostonlyif create 2>&1

    if ($createResult -match "Interface '(.+)' was successfully created") {
        $adapterName = $Matches[1]
        Write-Host "  Created adapter: $adapterName" -ForegroundColor Green
    } else {
        Write-Error "Failed to create Host-Only adapter: $createResult"
        exit 1
    }

    # Configure IP
    & $vboxManage hostonlyif ipconfig "$adapterName" --ip $GatewayIP --netmask $Netmask
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure Host-Only adapter IP"
        exit 1
    }
    Write-Host "  Configured IP: $GatewayIP/$Netmask" -ForegroundColor Green
}

# Verify multipass driver
Write-Host ""
Write-Host "Checking Multipass driver..." -ForegroundColor Yellow
try {
    $driver = multipass get local.driver 2>&1
    if ($driver -eq "virtualbox") {
        Write-Host "  Multipass is using VirtualBox driver [OK]" -ForegroundColor Green
    } else {
        Write-Host "  Multipass is using '$driver' driver" -ForegroundColor Red
        Write-Host ""
        Write-Host "  To switch to VirtualBox, run these commands:" -ForegroundColor Yellow
        Write-Host "    Stop-Service -Name 'Multipass'" -ForegroundColor Cyan
        Write-Host "    multipass set local.driver=virtualbox" -ForegroundColor Cyan
        Write-Host "    Start-Service -Name 'Multipass'" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  Could not check Multipass driver (is Multipass installed?)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Network setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Host-Only Adapter: $adapterName"
Write-Host "  Host IP:           $GatewayIP"
Write-Host "  Subnet:            $Subnet"
Write-Host ""
Write-Host "VM Network Architecture:" -ForegroundColor Cyan
Write-Host "  eth0   - Multipass NAT (internet access)"
Write-Host "  k8snet - Host-Only Adapter (static IPs for cluster)"
Write-Host ""
Write-Host "Static IP allocations:" -ForegroundColor Gray
Write-Host "  haproxy:  192.168.56.10"
Write-Host "  master-0: 192.168.56.11"
Write-Host "  worker-0: 192.168.56.21"
Write-Host "  worker-1: 192.168.56.22"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Ensure Multipass uses VirtualBox driver (see above)"
Write-Host "  2. Run: terraform init"
Write-Host "  3. Run: terraform apply"

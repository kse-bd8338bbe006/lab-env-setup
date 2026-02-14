#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up Hyper-V Internal Switch with NAT for Kubernetes cluster VMs.

.DESCRIPTION
    Creates a dedicated Hyper-V Internal Switch (K8sSwitch) with NAT configuration
    to provide stable static IP addresses for the K8s cluster while maintaining
    internet connectivity through NAT.

.NOTES
    Run this script once as Administrator before running terraform apply.

    Network configuration:
    - Switch: K8sSwitch (Internal)
    - Subnet: 192.168.50.0/24
    - Gateway: 192.168.50.1 (Windows host)
    - NAT: K8sNAT
#>

param(
    [string]$SwitchName = "K8sSwitch",
    [string]$NatName = "K8sNAT",
    [string]$GatewayIP = "192.168.50.1",
    [int]$PrefixLength = 24,
    [string]$Subnet = "192.168.50.0/24"
)

Write-Host "Setting up Hyper-V network for Kubernetes cluster..." -ForegroundColor Cyan

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Create Internal Switch
Write-Host "Checking VMSwitch '$SwitchName'..." -ForegroundColor Yellow
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    Write-Host "  Creating Internal VMSwitch: $SwitchName" -ForegroundColor Green
    New-VMSwitch -SwitchName $SwitchName -SwitchType Internal | Out-Null
} else {
    Write-Host "  VMSwitch '$SwitchName' already exists" -ForegroundColor Gray
}

# Get the interface for the switch
Start-Sleep -Seconds 2  # Wait for interface to be ready
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
if (-not $adapter) {
    Write-Error "Could not find network adapter for switch '$SwitchName'"
    exit 1
}
$IfIndex = $adapter.ifIndex
Write-Host "  Found adapter: $($adapter.Name) (Index: $IfIndex)" -ForegroundColor Gray

# Assign gateway IP to switch interface
Write-Host "Checking IP configuration..." -ForegroundColor Yellow
$existingIP = Get-NetIPAddress -InterfaceIndex $IfIndex -IPAddress $GatewayIP -ErrorAction SilentlyContinue
if (-not $existingIP) {
    Write-Host "  Assigning IP $GatewayIP/$PrefixLength to interface" -ForegroundColor Green
    New-NetIPAddress -IPAddress $GatewayIP -PrefixLength $PrefixLength -InterfaceIndex $IfIndex | Out-Null
} else {
    Write-Host "  IP $GatewayIP already assigned" -ForegroundColor Gray
}

# Create NAT for internet access
Write-Host "Checking NAT configuration..." -ForegroundColor Yellow
if (-not (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue)) {
    Write-Host "  Creating NAT: $NatName for subnet $Subnet" -ForegroundColor Green
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $Subnet | Out-Null
} else {
    Write-Host "  NAT '$NatName' already exists" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Network setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration summary:" -ForegroundColor Cyan
Write-Host "  Switch:  $SwitchName"
Write-Host "  Gateway: $GatewayIP"
Write-Host "  Subnet:  $Subnet"
Write-Host "  NAT:     $NatName"
Write-Host ""
Write-Host "VMs can now use static IPs in the 192.168.50.x range." -ForegroundColor Cyan
Write-Host "Example allocations:" -ForegroundColor Gray
Write-Host "  haproxy:  192.168.50.10"
Write-Host "  master-0: 192.168.50.11"
Write-Host "  worker-0: 192.168.50.21"
Write-Host "  worker-1: 192.168.50.22"

#Requires -Version 5.1
<#
.SYNOPSIS
    Destroys the Hyper-V K8s cluster, cleaning up all resources.
.DESCRIPTION
    Performs a thorough cleanup: Terraform state (apps then infra), Multipass VMs,
    and state files.

    All output is logged to destroy-cluster_<timestamp>.log for troubleshooting.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# -- Configuration ------------------------------------------------------------

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir     = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile    = Join-Path $LogDir "destroy-cluster_$Timestamp.log"

# -- Logging helpers -----------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] [$Level] $Message"
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "`n[$Step] $Message" -ForegroundColor Cyan
    Write-Log "STEP $Step - $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
    Write-Log $Message "OK"
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
    Write-Log $Message
}

function Invoke-LoggedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $cmdLine = "$Command $($Arguments -join ' ')"
    Write-Log "Executing: $cmdLine"
    $output = & $Command @Arguments 2>&1 | Out-String
    if ($output) { Add-Content -Path $LogFile -Value $output }
    Write-Log "Exit code: $LASTEXITCODE"
}

# -- Main ----------------------------------------------------------------------

Set-Location $ScriptDir

Set-Content -Path $LogFile -Value "=== destroy-cluster started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host "============================================" -ForegroundColor White
Write-Host " Destroy Hyper-V K8s Cluster"                 -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host "  Log file: $LogFile" -ForegroundColor Gray
Write-Host ""
Write-Host "This will destroy ALL VMs and clean up state files." -ForegroundColor Yellow

$confirm = Read-Host "Are you sure? (y/N)"
if ($confirm -ne "y") {
    Write-Host "Cancelled."
    exit 0
}

# Step 1: Terraform destroy applications
Write-Step "1/5" "Destroying Terraform applications..."
Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=apps", "destroy", "-auto-approve")
Write-Ok "Applications Terraform destroy complete."

# Step 2: Terraform destroy infrastructure
Write-Step "2/5" "Destroying Terraform infrastructure..."
Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=infra", "destroy", "-auto-approve")
Write-Ok "Infrastructure Terraform destroy complete."

# Step 3: Delete Multipass VMs
Write-Step "3/5" "Deleting Multipass VMs..."
Invoke-LoggedCommand -Command "multipass" -Arguments @("delete", "--all")
Invoke-LoggedCommand -Command "multipass" -Arguments @("purge")
Write-Ok "Multipass VMs deleted."

# Step 4: Clean up state files
Write-Step "4/5" "Cleaning up state files..."
$cleanupPaths = @(
    "infra\terraform.tfstate",
    "infra\terraform.tfstate.backup",
    "infra\.terraform.tfstate.lock.info",
    "infra\.terraform",
    "infra\cloud-init-*.yaml",
    "infra\haproxy_*.cfg",
    "apps\terraform.tfstate",
    "apps\terraform.tfstate.backup",
    "apps\.terraform.tfstate.lock.info",
    "apps\.terraform",
    "apps\haproxy_ingress.cfg",
    "$env:USERPROFILE\.kube\config-multipass"
)
foreach ($path in $cleanupPaths) {
    $fullPath = Join-Path $ScriptDir $path
    # Handle glob patterns
    $items = Get-Item $fullPath -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        try {
            Remove-Item -Recurse -Force $item.FullName -ErrorAction Stop
        } catch {
            Start-Sleep -Seconds 2
            Remove-Item -Recurse -Force $item.FullName -ErrorAction SilentlyContinue
        }
        Write-Info "Removed: $($item.FullName)"
    }
}

# Remove temp hosts file
$hostsIpFile = Join-Path $env:TEMP "hosts_ip.txt"
if (Test-Path $hostsIpFile) { Remove-Item $hostsIpFile -Force }

Write-Ok "State files cleaned."

# Step 5: Verify
Write-Step "5/5" "Verifying cleanup..."
$remaining = & multipass list 2>&1 | Out-String
Write-Log "Remaining VMs: $remaining"
Write-Info "Multipass status:"
Write-Host $remaining

# Final status
Write-Log "=== destroy-cluster completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cluster destroyed."                          -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Log: $LogFile" -ForegroundColor Gray
Write-Host ""

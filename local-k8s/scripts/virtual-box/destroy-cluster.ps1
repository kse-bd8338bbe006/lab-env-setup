#Requires -Version 5.1
<#
.SYNOPSIS
    Destroys the VirtualBox K8s cluster, cleaning up all resources.
.DESCRIPTION
    Performs a thorough cleanup: Vagrant VMs, orphaned VirtualBox VMs, stale
    processes, and state files. Terraform resources are destroyed implicitly
    when the VMs are removed.

    All output is logged to destroy-cluster_<timestamp>.log for troubleshooting.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Configuration ──────────────────────────────────────────────────────────────

$VMNames    = @("haproxy", "master-0", "worker-0", "worker-1")
$VBoxManage = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $ScriptDir "destroy-cluster_$Timestamp.log"

# ── Logging helpers ────────────────────────────────────────────────────────────

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

# ── Main ───────────────────────────────────────────────────────────────────────

Set-Location $ScriptDir

Set-Content -Path $LogFile -Value "=== destroy-cluster started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host "============================================" -ForegroundColor White
Write-Host " Destroy VirtualBox K8s Cluster"              -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host "  Log file: $LogFile" -ForegroundColor Gray
Write-Host ""
Write-Host "This will destroy ALL VMs and clean up state files." -ForegroundColor Yellow

$confirm = Read-Host "Are you sure? (y/N)"
if ($confirm -ne "y") {
    Write-Host "Cancelled."
    exit 0
}

# Step 1: Kill stale vagrant/ruby processes
Write-Step "1/4" "Stopping stale vagrant processes..."
$procs = Get-Process -Name ruby, vagrant -ErrorAction SilentlyContinue
if ($procs) {
    foreach ($p in $procs) {
        Write-Log "Killing $($p.ProcessName).exe PID $($p.Id)"
    }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Info "Killed $($procs.Count) process(es)."
    Start-Sleep -Seconds 2
} else {
    Write-Info "No stale processes found."
}

# Step 2: Vagrant destroy
Write-Step "2/4" "Destroying Vagrant VMs..."
Invoke-LoggedCommand -Command "vagrant" -Arguments @("destroy", "-f")
Write-Ok "Vagrant destroy complete."

# Step 3: Clean up orphaned VirtualBox VMs
Write-Step "3/4" "Removing orphaned VirtualBox VMs..."
if (Test-Path $VBoxManage) {
    $vboxList = & $VBoxManage list vms 2>&1 | Out-String
    Write-Log "VBoxManage list vms:`n$vboxList"
    foreach ($name in $VMNames) {
        if ($vboxList -match "`"$name`"\s+\{([a-f0-9-]+)\}") {
            $uuid = $Matches[1]
            Write-Info "Removing orphan: $name {$uuid}"
            Write-Log "Removing orphan VM: $name {$uuid}"
            & $VBoxManage controlvm $uuid poweroff 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            & $VBoxManage unregistervm $uuid --delete 2>&1 | Out-Null
        }
    }
    Write-Ok "Orphan cleanup complete."
} else {
    Write-Info "VBoxManage not found, skipping orphan cleanup."
    Write-Log "VBoxManage not found at $VBoxManage" "WARN"
}

# Step 4: Clean up state files
Write-Step "4/4" "Cleaning up state files..."
$cleanupPaths = @(
    ".vagrant\machines",
    ".join-command",
    "terraform.tfstate",
    "terraform.tfstate.backup",
    ".terraform.tfstate.lock.info"
)
foreach ($path in $cleanupPaths) {
    $fullPath = Join-Path $ScriptDir $path
    if (Test-Path $fullPath) {
        try {
            Remove-Item -Recurse -Force $fullPath -ErrorAction Stop
        } catch {
            Start-Sleep -Seconds 2
            Remove-Item -Recurse -Force $fullPath -ErrorAction SilentlyContinue
        }
        Write-Info "Removed: $path"
    }
}
Write-Ok "State files cleaned."

# Final status
Write-Log "=== destroy-cluster completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cluster destroyed."                          -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Log: $LogFile" -ForegroundColor Gray
Write-Host ""
& vagrant status 2>&1 | Write-Host

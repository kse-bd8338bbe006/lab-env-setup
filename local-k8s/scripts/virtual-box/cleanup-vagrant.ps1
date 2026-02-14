#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans up stale Vagrant state without destroying VMs.
.DESCRIPTION
    Kills orphaned vagrant/ruby processes, removes stale lock files, and
    reconciles Vagrant machine state with VirtualBox. Use this when vagrant
    commands fail with "another process is already executing an action".
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$VMNames    = @("haproxy", "master-0", "worker-0", "worker-1")
$VBoxManage = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "`n[$Step] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

# ── Main ───────────────────────────────────────────────────────────────────────

Set-Location $ScriptDir

Write-Host "============================================" -ForegroundColor White
Write-Host " Vagrant State Cleanup"                       -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

# Step 1: Kill stale processes
Write-Step "1/3" "Killing stale vagrant/ruby processes..."
$procs = Get-Process -Name ruby, vagrant -ErrorAction SilentlyContinue
if ($procs) {
    foreach ($p in $procs) {
        Write-Info "Killing $($p.ProcessName).exe (PID $($p.Id))"
    }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Ok "Killed $($procs.Count) process(es)."
} else {
    Write-Info "No stale processes found."
}

# Step 2: Reconcile Vagrant state with VirtualBox
Write-Step "2/3" "Reconciling Vagrant state with VirtualBox..."
$machinesDir = Join-Path $ScriptDir ".vagrant\machines"

if (Test-Path $VBoxManage) {
    $vboxList = & $VBoxManage list vms 2>&1 | Out-String

    foreach ($name in $VMNames) {
        $idFile = Join-Path $machinesDir "$name\virtualbox\id"
        $hasVagrantId = Test-Path $idFile
        $vboxHasVM = $vboxList -match "`"$name`"\s+\{([a-f0-9-]+)\}"
        $vboxUuid = if ($vboxHasVM) { $Matches[1] } else { $null }

        if ($hasVagrantId -and -not $vboxHasVM) {
            # Vagrant thinks VM exists but VirtualBox doesn't have it
            $staleId = Get-Content $idFile
            Write-Warn "$name : Vagrant has ID $staleId but VM not in VirtualBox. Removing stale ID."
            Remove-Item $idFile -Force
        }
        elseif (-not $hasVagrantId -and $vboxHasVM) {
            # VirtualBox has the VM but Vagrant lost track of it
            Write-Warn "$name : Orphaned VM in VirtualBox {$vboxUuid}. Vagrant has no record."
            Write-Info "  Run 'destroy-cluster.ps1' to remove orphans, or manually:"
            Write-Info "  VBoxManage unregistervm $vboxUuid --delete"
        }
        elseif ($hasVagrantId -and $vboxHasVM) {
            $vagrantId = (Get-Content $idFile).Trim()
            if ($vagrantId -ne $vboxUuid) {
                Write-Warn "$name : Vagrant ID ($vagrantId) doesn't match VirtualBox UUID ($vboxUuid). Fixing..."
                Set-Content -Path $idFile -Value $vboxUuid -NoNewline
            } else {
                Write-Ok "$name : Vagrant and VirtualBox in sync."
            }
        }
        else {
            Write-Info "$name : Not created (clean)."
        }
    }
} else {
    Write-Warn "VBoxManage not found at $VBoxManage, skipping reconciliation."
}

# Step 3: Remove stale lock artifacts
Write-Step "3/3" "Checking for stale lock artifacts..."
$lockFiles = Get-ChildItem -Path $machinesDir -Recurse -Filter "*.lock" -ErrorAction SilentlyContinue
if ($lockFiles) {
    foreach ($lock in $lockFiles) {
        Write-Info "Removing lock: $($lock.FullName)"
        Remove-Item $lock.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Ok "Removed $($lockFiles.Count) lock file(s)."
} else {
    Write-Info "No stale lock files found."
}

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cleanup complete."                           -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
& vagrant status 2>&1 | Write-Host

#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a VirtualBox K8s cluster using Vagrant and deploys applications with Terraform.
.DESCRIPTION
    Handles the known issue where vagrant.exe on Windows detaches from its ruby.exe
    child process, causing premature exit codes. The script waits for the actual
    provisioning to complete and validates each VM before proceeding.

    All output is logged to create-cluster_<timestamp>.log for troubleshooting.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Configuration ──────────────────────────────────────────────────────────────

$VMs = [ordered]@{
    "haproxy"  = @{ IP = "192.168.56.10"; Role = "haproxy" }
    "master-0" = @{ IP = "192.168.56.11"; Role = "master" }
    "worker-0" = @{ IP = "192.168.56.21"; Role = "worker" }
    "worker-1" = @{ IP = "192.168.56.22"; Role = "worker" }
}

$VBoxManage = Join-Path $env:ProgramFiles "Oracle\VirtualBox\VBoxManage.exe"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir     = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile    = Join-Path $LogDir "create-cluster_$Timestamp.log"

# ── Logging helpers ────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
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

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    Write-Log $Message "FAIL"
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
    Write-Log $Message
}

function Invoke-LoggedCommand {
    <#
    .SYNOPSIS
        Runs an external command, streams output to the log file, and returns the exit code.
        Shows a spinner on screen so the user knows it's working.
    #>
    param(
        [string]$Command,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 600,
        [string]$WorkingDirectory = $ScriptDir
    )

    Write-Log "Executing: $Command $($Arguments -join ' ')"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Command
    $psi.Arguments = $Arguments -join " "
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    # Show spinner while waiting
    $spinChars = @("|", "/", "-", "\")
    $i = 0
    while (-not $proc.WaitForExit(500)) {
        if ($TimeoutSeconds -gt 0 -and (New-TimeSpan -Start $proc.StartTime).TotalSeconds -gt $TimeoutSeconds) {
            $proc.Kill()
            Write-Log "Process killed: exceeded ${TimeoutSeconds}s timeout" "ERROR"
            break
        }
        Write-Host -NoNewline "`r  $($spinChars[$i % 4]) Working... " -ForegroundColor Gray
        $i++
    }
    Write-Host -NoNewline "`r                `r"

    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    if ($stdout) { Add-Content -Path $LogFile -Value $stdout }
    if ($stderr) { Add-Content -Path $LogFile -Value "[STDERR] $stderr" }
    Write-Log "Exit code: $exitCode"

    return $exitCode
}

# ── Vagrant helpers ────────────────────────────────────────────────────────────

function Stop-StaleVagrant {
    $procs = Get-Process -Name ruby, vagrant -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Info "Killing $($procs.Count) stale vagrant/ruby process(es)..."
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Wait-RubyProcess {
    param([int]$TimeoutSeconds = 600)

    $ruby = Get-Process -Name ruby -ErrorAction SilentlyContinue
    if (-not $ruby) { return }

    Write-Info "Vagrant provisioning running in background (ruby.exe PID $($ruby.Id)), waiting..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $spinChars = @("|", "/", "-", "\")
    $i = 0
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $ruby = Get-Process -Name ruby -ErrorAction SilentlyContinue
        if (-not $ruby) {
            Write-Host -NoNewline "`r                `r"
            Write-Info "Background provisioning completed after $([math]::Round($sw.Elapsed.TotalSeconds))s."
            return
        }
        Write-Host -NoNewline "`r  $($spinChars[$i % 4]) Provisioning... $([math]::Round($sw.Elapsed.TotalSeconds))s " -ForegroundColor Gray
        $i++
        Start-Sleep -Seconds 2
    }
    Write-Host ""
    throw "Timed out waiting for ruby.exe after ${TimeoutSeconds}s."
}

function Invoke-Vagrant {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 600
    )

    $exitCode = Invoke-LoggedCommand -Command "vagrant" -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds

    if ($exitCode -eq 0) { return }

    # Exit code 127: vagrant detached from ruby.exe - wait for background provisioning
    if ($exitCode -eq 127) {
        Write-Info "Vagrant exited early (code 127), checking for background provisioning..."
        Wait-RubyProcess -TimeoutSeconds $TimeoutSeconds
        return
    }

    # Other non-zero exit: check if ruby is still running (same detach issue)
    $ruby = Get-Process -Name ruby -ErrorAction SilentlyContinue
    if ($ruby) {
        Write-Info "Vagrant exited (code $exitCode) but provisioning still running..."
        Wait-RubyProcess -TimeoutSeconds $TimeoutSeconds
        return
    }

    throw "vagrant $($Arguments -join ' ') failed with exit code $exitCode"
}

function Test-VMProvisioned {
    param(
        [string]$Name,
        [string]$Role
    )

    $checkCommand = switch ($Role) {
        "haproxy" { "systemctl is-active haproxy nfs-kernel-server postgresql" }
        "master"  { "kubectl get nodes --no-headers 2>/dev/null | head -1 || echo FAIL" }
        "worker"  { "which kubeadm > /dev/null 2>&1 && echo OK || echo FAIL" }
    }

    Write-Log "Validating $Name ($Role): $checkCommand"

    try {
        $result = & vagrant ssh $Name -c $checkCommand 2>&1 | Out-String
        Write-Log "Validation result for $Name : $result"
        switch ($Role) {
            "haproxy" {
                if ($result -match "inactive|failed") { return $false }
                return $true
            }
            "master" {
                if ($result -match "FAIL" -or [string]::IsNullOrWhiteSpace($result)) { return $false }
                return $true
            }
            "worker" {
                return $result -match "OK"
            }
        }
    } catch {
        Write-Log "Validation failed for $Name : $_" "ERROR"
        return $false
    }
    return $false
}

function Invoke-VagrantUp {
    param(
        [string]$Name,
        [string]$Role,
        [int]$MaxAttempts = 2
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Info "Retry attempt $attempt/$MaxAttempts..."
            Stop-StaleVagrant
        }

        try {
            Invoke-Vagrant -Arguments @("up", $Name)
        } catch {
            Write-Info "vagrant up failed: $_"
        }

        if (Test-VMProvisioned -Name $Name -Role $Role) {
            return $true
        }

        # VM might be running but unprovisioned - try explicit provision
        $status = & vagrant status $Name --machine-readable 2>&1 | Out-String
        Write-Log "Status for $Name after vagrant up: $status"
        if ($status -match "state,running") {
            Write-Info "VM is running but not provisioned. Running vagrant provision..."
            Stop-StaleVagrant
            try {
                Invoke-Vagrant -Arguments @("provision", $Name)
            } catch {
                Write-Info "vagrant provision failed: $_"
            }
            if (Test-VMProvisioned -Name $Name -Role $Role) {
                return $true
            }
        }
    }

    return $false
}

# ── Main ───────────────────────────────────────────────────────────────────────

Set-Location $ScriptDir

# Initialize log
Set-Content -Path $LogFile -Value "=== create-cluster started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Write-Log "PowerShell $($PSVersionTable.PSVersion)"
Write-Log "Working directory: $ScriptDir"

Write-Host "============================================" -ForegroundColor White
Write-Host " VirtualBox K8s Cluster Setup (Vagrant)"     -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host "  Log file: $LogFile" -ForegroundColor Gray

# Pre-flight checks
Write-Log "Running pre-flight checks..."
$ErrorActionPreference = "Continue"
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
    Write-Fail "vagrant not found in PATH"; exit 1
}
Write-Log "vagrant: $(& vagrant --version 2>$null)"

if (-not (Test-Path $VBoxManage)) {
    Write-Fail "VBoxManage not found at $VBoxManage"; exit 1
}
Write-Log "VBoxManage: $(& $VBoxManage --version 2>$null)"

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Fail "terraform not found in PATH"; exit 1
}
Write-Log "terraform: $(& terraform --version 2>$null | Select-Object -First 1)"
$ErrorActionPreference = "Stop"

$sshKeyPath = Join-Path $env:USERPROFILE ".ssh\kse_ci_cd_sec_id_rsa.pub"
if (-not (Test-Path $sshKeyPath)) {
    Write-Fail "SSH public key not found: $sshKeyPath"
    Write-Info "Generate it with: ssh-keygen -t rsa -f ~/.ssh/kse_ci_cd_sec_id_rsa"
    exit 1
}
Write-Log "SSH key found: $sshKeyPath"

# Clean up stale files from previous runs
$hostsIpFile = Join-Path $env:TEMP "hosts_ip.txt"
if (Test-Path $hostsIpFile) { Remove-Item $hostsIpFile -Force }
$staleKubeConfig = Join-Path $env:USERPROFILE ".kube\config-virtualbox"
if (Test-Path $staleKubeConfig) { Remove-Item $staleKubeConfig -Force }

# Kill stale processes from previous failed runs
Stop-StaleVagrant

# Create VMs sequentially (order matters: haproxy -> master -> workers)
$totalVMs = $VMs.Count
$current = 0
$failed = @()

foreach ($entry in $VMs.GetEnumerator()) {
    $current++
    $name = $entry.Key
    $role = $entry.Value.Role
    $ip   = $entry.Value.IP

    Write-Step "$current/$totalVMs" "Creating $name ($role, $ip)..."

    if (Invoke-VagrantUp -Name $name -Role $role) {
        Write-Ok "$name is provisioned and running."
    } else {
        Write-Fail "$name failed to provision. See log: $LogFile"
        $failed += $name
        if ($role -in @("haproxy", "master")) {
            Write-Fail "Cannot continue without $name."
            Write-Host "`nTo debug: vagrant ssh $name" -ForegroundColor Yellow
            Write-Log "ABORTING: required VM $name failed" "FATAL"
            exit 1
        }
    }
}

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host " VM Creation Summary"                         -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

Write-Host ""
Write-Host "  IP Addresses:" -ForegroundColor White
foreach ($entry in $VMs.GetEnumerator()) {
    $indicator = if ($entry.Key -in $failed) { "[FAIL]" } else { "  [OK]" }
    $color     = if ($entry.Key -in $failed) { "Red" } else { "Green" }
    Write-Host "  $indicator $($entry.Key): $($entry.Value.IP)" -ForegroundColor $color
}

if ($failed.Count -gt 0) {
    Write-Host "`nWARNING: $($failed.Count) VM(s) failed. Continuing with Terraform..." -ForegroundColor Yellow
}

# Terraform deployment - infra/ creates cluster and kubeconfig, apps/ deploys helm charts
$ErrorActionPreference = "Continue"

Write-Step "5/8" "Initializing infrastructure Terraform..."
$tfInitCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=infra", "init")
if ($tfInitCode -ne 0) {
    Write-Fail "terraform init (infra) failed (exit code $tfInitCode). See log: $LogFile"
    exit 1
}
Write-Ok "Infrastructure Terraform initialized."

Write-Step "6/8" "Deploying infrastructure with Terraform..."
$tfApplyCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=infra", "apply", "-auto-approve") -TimeoutSeconds 1200
if ($tfApplyCode -ne 0) {
    Write-Fail "terraform apply (infra) failed (exit code $tfApplyCode). See log: $LogFile"
    exit 1
}
Write-Ok "Infrastructure deployed (cluster ready, kubeconfig available)."

Write-Step "7/8" "Initializing applications Terraform..."
$tfInitCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=apps", "init")
if ($tfInitCode -ne 0) {
    Write-Fail "terraform init (apps) failed (exit code $tfInitCode). See log: $LogFile"
    exit 1
}
Write-Ok "Applications Terraform initialized."

Write-Step "8/8" "Deploying applications with Terraform..."
$tfApplyCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=apps", "apply", "-auto-approve") -TimeoutSeconds 1200
if ($tfApplyCode -ne 0) {
    Write-Fail "terraform apply (apps) failed (exit code $tfApplyCode). See log: $LogFile"
    exit 1
}
Write-Ok "Applications deployed."

# Copy kubeconfig to default location
$kubeConfig = Join-Path $env:USERPROFILE ".kube\config-virtualbox"
$kubeDefault = Join-Path $env:USERPROFILE ".kube\config"
if (Test-Path $kubeConfig) {
    Copy-Item $kubeConfig $kubeDefault -Force
    Write-Ok "Kubeconfig copied to $kubeDefault"
}

$ErrorActionPreference = "Stop"

# Final status
Write-Log "=== create-cluster completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cluster deployed successfully!"              -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  To SSH:  vagrant ssh <vm-name>" -ForegroundColor White
Write-Host "  Status:  vagrant ssh master-0 -c 'kubectl get nodes'" -ForegroundColor White
Write-Host "  Log:     $LogFile" -ForegroundColor Gray
Write-Host ""

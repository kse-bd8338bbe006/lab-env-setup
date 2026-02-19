#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a Hyper-V K8s cluster using Multipass and deploys applications with Terraform.
.DESCRIPTION
    Orchestrates the full cluster lifecycle:
    1. Pre-flight checks (multipass, terraform, SSH key)
    2. Hyper-V network setup (K8sSwitch + NAT)
    3. Infrastructure deployment (VMs, K8s bootstrap, kubeconfig)
    4. Application deployment (ingress, monitoring, ArgoCD, Vault, Harbor)

    All output is logged to create-cluster_<timestamp>.log for troubleshooting.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Configuration ------------------------------------------------------------

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir     = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile    = Join-Path $LogDir "create-cluster_$Timestamp.log"

# -- Logging helpers -----------------------------------------------------------

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

# -- Main ----------------------------------------------------------------------

Set-Location $ScriptDir

# Initialize log
Set-Content -Path $LogFile -Value "=== create-cluster started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Write-Log "PowerShell $($PSVersionTable.PSVersion)"
Write-Log "Working directory: $ScriptDir"

Write-Host "============================================" -ForegroundColor White
Write-Host " Hyper-V K8s Cluster Setup (Multipass)"      -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host "  Log file: $LogFile" -ForegroundColor Gray

# Step 1: Pre-flight checks
Write-Step "1/7" "Running pre-flight checks..."
$ErrorActionPreference = "Continue"

if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    Write-Fail "multipass not found in PATH"; exit 1
}
Write-Log "multipass: $(& multipass version 2>$null | Select-Object -First 1)"
Write-Ok "multipass found."

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Fail "terraform not found in PATH"; exit 1
}
Write-Log "terraform: $(& terraform --version 2>$null | Select-Object -First 1)"
Write-Ok "terraform found."

$sshKeyPath = Join-Path $env:USERPROFILE ".ssh\kse_ci_cd_sec_id_rsa.pub"
if (-not (Test-Path $sshKeyPath)) {
    Write-Fail "SSH public key not found: $sshKeyPath"
    Write-Info "Generate it with: ssh-keygen -t rsa -f ~/.ssh/kse_ci_cd_sec_id_rsa"
    exit 1
}
Write-Ok "SSH key found."
$ErrorActionPreference = "Stop"

# Step 2: Network setup
Write-Step "2/7" "Setting up Hyper-V network..."
Write-Info "Setting Multipass driver to Hyper-V..."
& multipass set local.driver=hyperv 2>&1 | Out-Null

$setupNetwork = Join-Path $ScriptDir "setup-network.ps1"
if (Test-Path $setupNetwork) {
    $netCode = Invoke-LoggedCommand -Command "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setupNetwork)
    if ($netCode -ne 0) {
        Write-Fail "Network setup failed (exit code $netCode). See log: $LogFile"
        exit 1
    }
    Write-Ok "Hyper-V network configured."
} else {
    Write-Info "setup-network.ps1 not found, assuming network already configured."
}

# Clean stale files from previous runs
$hostsIpFile = Join-Path $env:TEMP "hosts_ip.txt"
if (Test-Path $hostsIpFile) { Remove-Item $hostsIpFile -Force }
$staleKubeConfig = Join-Path $env:USERPROFILE ".kube\config-multipass"
if (Test-Path $staleKubeConfig) { Remove-Item $staleKubeConfig -Force }

# Step 3: Initialize infrastructure Terraform
Write-Step "3/7" "Initializing infrastructure Terraform..."
$tfInitCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=infra", "init")
if ($tfInitCode -ne 0) {
    Write-Fail "terraform init (infra) failed (exit code $tfInitCode). See log: $LogFile"
    exit 1
}
Write-Ok "Infrastructure Terraform initialized."

# Step 4: Deploy infrastructure
Write-Step "4/7" "Deploying infrastructure with Terraform (VMs, K8s cluster, kubeconfig)..."
$tfApplyCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=infra", "apply", "-auto-approve") -TimeoutSeconds 1800
if ($tfApplyCode -ne 0) {
    Write-Fail "terraform apply (infra) failed (exit code $tfApplyCode). See log: $LogFile"
    exit 1
}
Write-Ok "Infrastructure deployed (cluster ready, kubeconfig available)."

# Step 5: Initialize applications Terraform
Write-Step "5/7" "Initializing applications Terraform..."
$tfInitCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=apps", "init")
if ($tfInitCode -ne 0) {
    Write-Fail "terraform init (apps) failed (exit code $tfInitCode). See log: $LogFile"
    exit 1
}
Write-Ok "Applications Terraform initialized."

# Step 6: Deploy applications
Write-Step "6/7" "Deploying applications with Terraform (ingress, monitoring, ArgoCD, Vault, Harbor)..."
$tfApplyCode = Invoke-LoggedCommand -Command "terraform" -Arguments @("-chdir=apps", "apply", "-auto-approve") -TimeoutSeconds 1800
if ($tfApplyCode -ne 0) {
    Write-Fail "terraform apply (apps) failed (exit code $tfApplyCode). See log: $LogFile"
    exit 1
}
Write-Ok "Applications deployed."

# Step 7: Final setup
Write-Step "7/7" "Finalizing cluster setup..."
$kubeConfig = Join-Path $env:USERPROFILE ".kube\config-multipass"
$kubeDefault = Join-Path $env:USERPROFILE ".kube\config"
if (Test-Path $kubeConfig) {
    Copy-Item $kubeConfig $kubeDefault -Force
    Write-Ok "Kubeconfig copied to $kubeDefault"
}

# Final status
Write-Log "=== create-cluster completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cluster deployed successfully!"              -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Cluster:     kubectl get nodes" -ForegroundColor White
Write-Host "  ArgoCD:      http://argocd.192.168.50.10.nip.io" -ForegroundColor White
Write-Host "  Grafana:     http://grafana.192.168.50.10.nip.io" -ForegroundColor White
Write-Host "  Vault:       http://vault.192.168.50.10.nip.io" -ForegroundColor White
Write-Host "  Harbor:      http://harbor.192.168.50.10.nip.io" -ForegroundColor White
Write-Host "  Prometheus:  http://prometheus.192.168.50.10.nip.io" -ForegroundColor White
Write-Host ""
Write-Host "  SSH:         multipass shell <vm-name>" -ForegroundColor White
Write-Host "  Log:         $LogFile" -ForegroundColor Gray
Write-Host ""

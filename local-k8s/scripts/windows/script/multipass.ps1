param()

# Read JSON input from stdin
$input_json = [Console]::In.ReadToEnd()
$input_data = $input_json | ConvertFrom-Json

$name = $input_data.name
$mem = $input_data.mem
$disk = $input_data.disk
$cpu = $input_data.cpu
$image = $input_data.image
$init_data = $input_data.init
$network_switch = $input_data.network_switch
$mac_address = $input_data.mac_address

$ScriptDir = Split-Path -Parent $PSScriptRoot  # parent of script/ = windows/
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "multipass.log"

function Write-Log {
    param($Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$ts] $Message"
}

function Find-VM {
    param($VMName)
    
    try {
        $output = multipass list --format=json | ConvertFrom-Json
        
        foreach ($vm in $output.list) {
            if ($vm.name -eq $VMName) {
                return @{
                    name = $VMName
                    ip = $vm.ipv4[0]
                    release = $vm.release
                    state = $vm.state
                }
            }
        }
    }
    catch {
        Write-Log "Error finding VM: $_"
    }
    
    return $null
}

function New-VM {
    param(
        $VMName,
        $CPUCount,
        $Memory,
        $DiskSize,
        $CloudInitData
    )

    # Create temporary file for cloud-init data
    $tempFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempFile -Value $CloudInitData

    try {
        # Build argument list properly (avoid Invoke-Expression parsing issues)
        $launchArgs = @("launch", $image, "--name", $VMName, "--cpus", $CPUCount,
                  "--disk", $DiskSize, "--memory", $Memory, "--timeout", "600",
                  "--cloud-init", $tempFile)
        if ($network_switch -and $mac_address) {
            $launchArgs += @("--network", "name=$network_switch,mode=manual,mac=$mac_address")
        } elseif ($network_switch) {
            $launchArgs += @("--network", "name=$network_switch,mode=manual")
        }

        Write-Log "Executing: multipass $($launchArgs -join ' ')"

        $output = & multipass @launchArgs 2>&1
        $exitCode = $LASTEXITCODE
        Write-Log "Exit code: $exitCode"
        Write-Log "Output: $output"

        if ($exitCode -ne 0) {
            $errMsg = ($output | Out-String).Trim()
            Write-Log "ERROR: multipass launch failed: $errMsg"
            throw "multipass launch failed (exit code $exitCode): $errMsg"
        }

        Remove-Item -Path $tempFile -Force

        return Find-VM -VMName $VMName
    }
    catch {
        Write-Log "Error creating VM: $_"
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        throw
    }
}

# Main logic
$result = Find-VM -VMName $name

if ($null -eq $result) {
    # Add random sleep to avoid race conditions
    Start-Sleep -Seconds (Get-Random -Minimum 1 -Maximum 10)
    $result = New-VM -VMName $name -CPUCount $cpu -Memory $mem -DiskSize $disk -CloudInitData $init_data
}

# Output result as JSON
$result | ConvertTo-Json -Compress

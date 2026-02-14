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

function Write-Log {
    param($Message)
    Add-Content -Path "multipass.log" -Value $Message
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
        $networkArg = if ($network_switch -and $mac_address) {
            "--network name=$network_switch,mode=manual,mac=$mac_address"
        } elseif ($network_switch) {
            "--network name=$network_switch,mode=manual"
        } else { "" }
        $imageArg = if ($image) { $image } else { "" }
        $cmd = "multipass launch $imageArg --name $VMName --cpus $CPUCount --disk $DiskSize --memory $Memory --timeout 600 $networkArg --cloud-init `"$tempFile`""
        Write-Log "Executing: $cmd"
        
        $result = Invoke-Expression $cmd 2>&1
        Write-Log "Result: $result"
        
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

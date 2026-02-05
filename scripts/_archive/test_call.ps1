# Test calling another script with parameters
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetScript = Join-Path $scriptDir "debug_param.ps1"

Write-Host "Testing parameter passing..."
Write-Host "Target: $targetScript"
Write-Host ""

# Method 1: Direct
Write-Host "Method 1: Direct parameters"
& $targetScript -InputPath "input1" -OutputDir "output1"
Write-Host ""

# Method 2: Splatting
Write-Host "Method 2: Splatting"
$params = @{
    InputPath = "input2"
    OutputDir = "output2"
}
& $targetScript @params

# Test OutputDir parameter
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pipelineScript = Join-Path $scriptDir "run_pipeline_exhaustive.ps1"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[0]

Write-Host "Testing with OutputDir parameter..."
Write-Host "Scene: $($scene.FullName)"
Write-Host "Pipeline: $pipelineScript"
Write-Host ""

# Test 1: Direct parameter
Write-Host "Test 1: Direct parameter"
& $pipelineScript -InputPath $scene.FullName -OutputDir "output_simple_radial" 2>&1 | Select-Object -First 15

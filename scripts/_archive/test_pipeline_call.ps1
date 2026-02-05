# Test calling pipeline with OutputDir
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pipelineScript = Join-Path $scriptDir "run_pipeline_exhaustive.ps1"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[0]

Write-Host "Scene: $($scene.FullName)"
Write-Host "Pipeline: $pipelineScript"
Write-Host ""
Write-Host "Calling with OutputDir=output_simple_radial"
Write-Host ""

# Call with explicit parameter - capture just first few lines
$output = & $pipelineScript -InputPath $scene.FullName -OutputDir "output_simple_radial" 2>&1 | Select-Object -First 15
$output | ForEach-Object { Write-Host $_ }

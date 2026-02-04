# Clear output and run Scene 1 with custom matching at 0.5 fps
$scenes = Get-ChildItem 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]

Write-Host "Scene 1: $($scene1.FullName)"

# Clear output directory
$outputDir = Join-Path $scene1.FullName 'output'
if (Test-Path $outputDir) {
    Write-Host "Clearing output directory: $outputDir"
    Remove-Item -LiteralPath $outputDir -Recurse -Force
}

Write-Host "Running pipeline..."
& "$PSScriptRoot\run_pipeline_dual_camera.ps1" -InputPath $scene1.FullName

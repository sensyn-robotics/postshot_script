# Run Scene 1 with exhaustive matching at 0.5 fps (reuse existing frames)
$scenes = Get-ChildItem 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]

Write-Host "Scene 1: $($scene1.FullName)"

# Clear only COLMAP output (keep extracted frames)
$colmapDir = Join-Path $scene1.FullName 'output\colmap_output'
if (Test-Path $colmapDir) {
    Write-Host "Clearing COLMAP output: $colmapDir"
    Remove-Item -LiteralPath $colmapDir -Recurse -Force
}

Write-Host "Running exhaustive matching pipeline..."
& "$PSScriptRoot\run_pipeline_exhaustive.ps1" -InputPath $scene1.FullName -VisualizationIntervalMinutes 10

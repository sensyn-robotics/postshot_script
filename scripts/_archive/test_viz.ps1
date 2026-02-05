# Temporary test script for visualization
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName
$sparsePath = Join-Path $scene1 'output\colmap_output\sparse\0'

Write-Host "Scene1: $scene1"
Write-Host "SparsePath: $sparsePath"

# Copy to temp
$tempDir = Join-Path $env:TEMP 'viz_test'
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
Copy-Item -LiteralPath $sparsePath -Destination $tempDir -Recurse

Write-Host "Copied sparse to: $tempDir"
Write-Host "Contents:"
Get-ChildItem $tempDir

# Run Python
$outputPng = Join-Path $env:TEMP 'test_viz.png'
Write-Host ""
Write-Host "Running render_pointcloud.py..."
python C:\postshot_script\scripts\render_pointcloud.py $tempDir $outputPng --title "Test" 2>&1

Write-Host "Exit code: $LASTEXITCODE"
if (Test-Path $outputPng) {
    $size = (Get-Item $outputPng).Length
    Write-Host "SUCCESS: Output created at $outputPng ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "FAILED: No output created" -ForegroundColor Red
}

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

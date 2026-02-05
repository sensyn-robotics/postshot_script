# Test visualization scripts with Python 3.11
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get Python path
$pythonPathFile = Join-Path $scriptDir "python_path.txt"
$pythonExe = (Get-Content $pythonPathFile -First 1).Trim()

Write-Host "=== Testing Visualization ===" -ForegroundColor Cyan
Write-Host "Python: $pythonExe"

# Find scene1
$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

# Test 1: COLMAP point cloud visualization
Write-Host ""
Write-Host "--- Test 1: COLMAP Point Cloud ---" -ForegroundColor Yellow

$sparsePath = Join-Path $scene1 "output\colmap_output\sparse\0"
$tempSparse = "C:\postshot_temp_viz\sparse"
$outputImage = "C:\postshot_temp_viz\colmap_test.png"

# Create temp dir and copy sparse
if (Test-Path "C:\postshot_temp_viz") { Remove-Item "C:\postshot_temp_viz" -Recurse -Force }
New-Item -ItemType Directory -Path "C:\postshot_temp_viz" -Force | Out-Null
Copy-Item -LiteralPath $sparsePath -Destination $tempSparse -Recurse

Write-Host "Sparse path: $tempSparse"
Write-Host "Output: $outputImage"

$renderScript = Join-Path $scriptDir "scripts\render_pointcloud.py"
& $pythonExe $renderScript $tempSparse $outputImage --title "COLMAP Test" 2>&1

if (Test-Path $outputImage) {
    $size = (Get-Item $outputImage).Length
    Write-Host "SUCCESS: Created $outputImage ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "FAILED: No output created" -ForegroundColor Red
}

# Test 2: PLY visualization
Write-Host ""
Write-Host "--- Test 2: PLY Point Cloud ---" -ForegroundColor Yellow

$plyPath = Join-Path $scene1 "output\scene.ply"
$tempPly = "C:\postshot_temp_viz\scene.ply"
$outputImage2 = "C:\postshot_temp_viz\ply_test.png"

Copy-Item -LiteralPath $plyPath -Destination $tempPly

Write-Host "PLY path: $tempPly"
Write-Host "Output: $outputImage2"

& $pythonExe $renderScript $tempPly $outputImage2 --title "3DGS PLY Test" 2>&1

if (Test-Path $outputImage2) {
    $size = (Get-Item $outputImage2).Length
    Write-Host "SUCCESS: Created $outputImage2 ($size bytes)" -ForegroundColor Green
} else {
    Write-Host "FAILED: No output created" -ForegroundColor Red
}

# Copy results to scene output
Write-Host ""
Write-Host "--- Copying results ---" -ForegroundColor Yellow
$vizDir = Join-Path $scene1 "output\visualizations"
if (-not (Test-Path $vizDir)) { New-Item -ItemType Directory -Path $vizDir -Force | Out-Null }

if (Test-Path $outputImage) {
    Copy-Item $outputImage -Destination (Join-Path $vizDir "colmap_visualization.png") -Force
    Write-Host "Copied COLMAP visualization to: $vizDir"
}
if (Test-Path $outputImage2) {
    Copy-Item $outputImage2 -Destination (Join-Path $vizDir "3dgs_visualization.png") -Force
    Write-Host "Copied 3DGS visualization to: $vizDir"
}

# List visualization directory
Write-Host ""
Write-Host "Visualization directory contents:"
Get-ChildItem -LiteralPath $vizDir -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  $($_.Name) ($($_.Length) bytes)"
}

# Cleanup
Remove-Item "C:\postshot_temp_viz" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done."

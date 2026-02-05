# Debug script to check COLMAP sparse reconstruction
# Uses path discovery to avoid hardcoded Unicode paths

$colmapExe = "C:\COLMAP\bin\colmap.exe"

Write-Host "=== Checking sparse reconstructions ===" -ForegroundColor Cyan

# Find Scene 1 directory by pattern (first one starting with ①)
$testDataPath = "C:\postshot_test_data"
$scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Where-Object { $_.Name -match "^①" } | Select-Object -First 1

if (-not $scene1Dir) {
    # Fallback: get first directory
    $scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Select-Object -First 1
}

if (-not $scene1Dir) {
    Write-Host "ERROR: Scene 1 directory not found" -ForegroundColor Red
    exit 1
}

Write-Host "Scene 1: $($scene1Dir.FullName)" -ForegroundColor Cyan
$sparsePath = Join-Path $scene1Dir.FullName "output\colmap_output\sparse"

if (-not (Test-Path -LiteralPath $sparsePath)) {
    Write-Host "ERROR: Sparse path not found: $sparsePath" -ForegroundColor Red
    exit 1
}

# List all reconstruction folders
$recons = Get-ChildItem -LiteralPath $sparsePath -Directory | Sort-Object Name
Write-Host "Found $($recons.Count) reconstruction(s):" -ForegroundColor Yellow
foreach ($r in $recons) {
    $camerasFile = Join-Path $r.FullName "cameras.bin"
    $imagesFile = Join-Path $r.FullName "images.bin"
    $pointsFile = Join-Path $r.FullName "points3D.bin"

    $camSize = if (Test-Path -LiteralPath $camerasFile) { (Get-Item -LiteralPath $camerasFile).Length } else { 0 }
    $imgSize = if (Test-Path -LiteralPath $imagesFile) { (Get-Item -LiteralPath $imagesFile).Length } else { 0 }
    $ptsSize = if (Test-Path -LiteralPath $pointsFile) { (Get-Item -LiteralPath $pointsFile).Length } else { 0 }

    Write-Host "  $($r.Name): cameras=$camSize bytes, images=$imgSize bytes, points3D=$ptsSize bytes"
}

# Analyze largest reconstruction (by images.bin size)
$largest = $recons | Sort-Object {
    $f = Join-Path $_.FullName "images.bin"
    if (Test-Path -LiteralPath $f) { (Get-Item -LiteralPath $f).Length } else { 0 }
} -Descending | Select-Object -First 1

Write-Host ""
Write-Host "=== Analyzing largest reconstruction: $($largest.Name) ===" -ForegroundColor Cyan

# Use temporary ASCII path to avoid Unicode issues with COLMAP
$tempPath = "C:\Postshot_Temp\sparse_check"
if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Recurse -Force }
Copy-Item -LiteralPath $largest.FullName -Destination $tempPath -Recurse

Write-Host "Running COLMAP model_analyzer..." -ForegroundColor Yellow
& $colmapExe model_analyzer --path $tempPath

# Clean up
Remove-Item -Path $tempPath -Recurse -Force

# Count total input images
Write-Host ""
Write-Host "=== Input image counts ===" -ForegroundColor Cyan
$imagesPath = Join-Path $scene1Dir.FullName "output\images"
$videoW = Join-Path $imagesPath "video_W"
$videoZ = Join-Path $imagesPath "video_Z"

if (Test-Path -LiteralPath $videoW) {
    $wideCount = (Get-ChildItem -LiteralPath $videoW -File).Count
    Write-Host "  video_W: $wideCount images"
} else {
    Write-Host "  video_W: NOT FOUND"
}

if (Test-Path -LiteralPath $videoZ) {
    $zoomCount = (Get-ChildItem -LiteralPath $videoZ -File).Count
    Write-Host "  video_Z: $zoomCount images"
} else {
    Write-Host "  video_Z: NOT FOUND"
}

# Check which sparse reconstruction was actually used for Postshot
Write-Host ""
Write-Host "=== Checking which reconstruction Postshot used ===" -ForegroundColor Cyan
$outputSparsePath = Join-Path $scene1Dir.FullName "output\sparse"
if (Test-Path -LiteralPath $outputSparsePath) {
    Write-Host "output\sparse exists - checking contents..."
    Get-ChildItem -LiteralPath $outputSparsePath -Recurse | ForEach-Object {
        Write-Host "  $($_.FullName.Replace($scene1Dir.FullName, ''))"
    }
} else {
    Write-Host "output\sparse does NOT exist"
    Write-Host "Postshot likely used colmap_output\sparse instead"
}

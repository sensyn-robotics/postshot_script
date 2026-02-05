# Check Scene 4 output_simple_radial state
$testData = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testData -Directory | Sort-Object Name
$scene4 = $scenes[3]  # 0-indexed

$outputDir = Join-Path $scene4.FullName "output_simple_radial"

Write-Host "=== Scene 4: $($scene4.Name) ===" -ForegroundColor Cyan
Write-Host "Output dir: $outputDir"
Write-Host ""

if (-not (Test-Path -LiteralPath $outputDir)) {
    Write-Host "output_simple_radial does not exist" -ForegroundColor Red
    exit 0
}

# Check each stage output
Write-Host "Stage outputs:" -ForegroundColor Yellow

# Stage 1: images
$imagesDir = Join-Path $outputDir "images"
$wImages = if (Test-Path "$imagesDir\video_W") { (Get-ChildItem "$imagesDir\video_W" -File).Count } else { 0 }
$zImages = if (Test-Path "$imagesDir\video_Z") { (Get-ChildItem "$imagesDir\video_Z" -File).Count } else { 0 }
Write-Host "  Stage 1 (frames): W=$wImages, Z=$zImages"

# Stage 3: database
$dbPath = Join-Path $outputDir "colmap\database.db"
$dbExists = Test-Path -LiteralPath $dbPath
Write-Host "  Stage 3 (features): database.db = $dbExists"

# Stage 5: sparse
$sparseDir = Join-Path $outputDir "sparse\0"
$sparseExists = Test-Path -LiteralPath (Join-Path $sparseDir "images.bin")
Write-Host "  Stage 5 (mapper): sparse/0 = $sparseExists"

if ($sparseExists) {
    $pointsSize = [math]::Round((Get-Item (Join-Path $sparseDir "points3D.bin")).Length / 1MB, 2)
    Write-Host "    points3D.bin: $pointsSize MB"
}

# Stage 6: psht
$pshtPath = Join-Path $outputDir "scene.psht"
$pshtExists = Test-Path -LiteralPath $pshtPath
Write-Host "  Stage 6 (train): scene.psht = $pshtExists"

# Stage 7: ply
$plyPath = Join-Path $outputDir "scene.ply"
$plyExists = Test-Path -LiteralPath $plyPath
Write-Host "  Stage 7 (export): scene.ply = $plyExists"

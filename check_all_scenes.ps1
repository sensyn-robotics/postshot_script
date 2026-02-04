# Check status of all scenes
$testDataPath = "C:\postshot_test_data"
$sceneDirectories = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name

Write-Host "=== Scene Status Check ===" -ForegroundColor Cyan
Write-Host ""

$sceneNum = 1
foreach ($dir in $sceneDirectories) {
    $scenePath = $dir.FullName
    $outputDir = Join-Path $scenePath "output"

    Write-Host "Scene $sceneNum : $($dir.Name)" -ForegroundColor Yellow

    # Check for key files
    $pshtPath = Join-Path $outputDir "scene.psht"
    $plyPath = Join-Path $outputDir "scene.ply"
    $imagesDir = Join-Path $outputDir "images"
    $colmapDir = Join-Path $outputDir "colmap_output"

    $hasPsht = Test-Path $pshtPath
    $hasPly = Test-Path $plyPath
    $hasImages = Test-Path $imagesDir
    $hasColmap = Test-Path $colmapDir

    if ($hasPsht) {
        $pshtSize = [math]::Round((Get-Item $pshtPath).Length / 1MB, 2)
        Write-Host "  scene.psht: YES ($pshtSize MB)" -ForegroundColor Green
    } else {
        Write-Host "  scene.psht: NO" -ForegroundColor Red
    }

    if ($hasPly) {
        $plySize = [math]::Round((Get-Item $plyPath).Length / 1MB, 2)
        Write-Host "  scene.ply:  YES ($plySize MB)" -ForegroundColor Green
    } else {
        Write-Host "  scene.ply:  NO" -ForegroundColor Red
    }

    if ($hasImages) {
        $wCount = (Get-ChildItem -LiteralPath (Join-Path $imagesDir "video_W") -File -ErrorAction SilentlyContinue).Count
        $zCount = (Get-ChildItem -LiteralPath (Join-Path $imagesDir "video_Z") -File -ErrorAction SilentlyContinue).Count
        Write-Host "  images:     YES (W: $wCount, Z: $zCount)" -ForegroundColor Green
    } else {
        Write-Host "  images:     NO" -ForegroundColor Red
    }

    if ($hasColmap) {
        $sparseCount = (Get-ChildItem -LiteralPath (Join-Path $colmapDir "sparse") -Directory -ErrorAction SilentlyContinue).Count
        Write-Host "  colmap:     YES ($sparseCount reconstructions)" -ForegroundColor Green
    } else {
        Write-Host "  colmap:     NO" -ForegroundColor Red
    }

    Write-Host ""
    $sceneNum++
}

# Debug script to check extracted images from input videos
# Usage: .\debug_check_images.ps1 [-DataPath <path>]

param(
    [string]$DataPath = "C:\postshot_test_data"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Image Extraction Status Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Data Path: $DataPath"
Write-Host ""

if (-not (Test-Path $DataPath)) {
    Write-Host "ERROR: Data path not found: $DataPath" -ForegroundColor Red
    exit 1
}

$scenes = Get-ChildItem $DataPath -Directory
$totalScenes = $scenes.Count
$scenesWithImages = 0

foreach ($scene in $scenes) {
    Write-Host "----------------------------------------"
    Write-Host "Scene: $($scene.Name)" -ForegroundColor Yellow

    $imagesPath = Join-Path $scene.FullName 'output\images'

    if (-not (Test-Path $imagesPath)) {
        Write-Host "  [X] No images folder found" -ForegroundColor Red
        continue
    }

    # Check for video_W and video_Z folders (dual camera setup)
    $videoW = Join-Path $imagesPath 'video_W'
    $videoZ = Join-Path $imagesPath 'video_Z'

    # Also check for Wide and Zoom folders (alternative naming)
    $wide = Join-Path $imagesPath 'Wide'
    $zoom = Join-Path $imagesPath 'Zoom'

    $hasImages = $false

    # Check video_W
    if (Test-Path $videoW) {
        $wCount = (Get-ChildItem $videoW -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($wCount -gt 0) {
            Write-Host "  [OK] video_W: $wCount images" -ForegroundColor Green
            $hasImages = $true
        } else {
            Write-Host "  [X] video_W: 0 images (folder exists but empty)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [ ] video_W: folder not found" -ForegroundColor Gray
    }

    # Check video_Z
    if (Test-Path $videoZ) {
        $zCount = (Get-ChildItem $videoZ -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($zCount -gt 0) {
            Write-Host "  [OK] video_Z: $zCount images" -ForegroundColor Green
            $hasImages = $true
        } else {
            Write-Host "  [X] video_Z: 0 images (folder exists but empty)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [ ] video_Z: folder not found" -ForegroundColor Gray
    }

    # Check Wide
    if (Test-Path $wide) {
        $wideCount = (Get-ChildItem $wide -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($wideCount -gt 0) {
            Write-Host "  [OK] Wide: $wideCount images" -ForegroundColor Green
            $hasImages = $true
        } else {
            Write-Host "  [X] Wide: 0 images (folder exists but empty)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [ ] Wide: folder not found" -ForegroundColor Gray
    }

    # Check Zoom
    if (Test-Path $zoom) {
        $zoomCount = (Get-ChildItem $zoom -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($zoomCount -gt 0) {
            Write-Host "  [OK] Zoom: $zoomCount images" -ForegroundColor Green
            $hasImages = $true
        } else {
            Write-Host "  [X] Zoom: 0 images (folder exists but empty)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [ ] Zoom: folder not found" -ForegroundColor Gray
    }

    # Check for any other image folders
    $otherFolders = Get-ChildItem $imagesPath -Directory | Where-Object {
        $_.Name -notin @('video_W', 'video_Z', 'Wide', 'Zoom')
    }
    foreach ($folder in $otherFolders) {
        $count = (Get-ChildItem $folder.FullName -Filter *.png -ErrorAction SilentlyContinue).Count
        if ($count -gt 0) {
            Write-Host "  [?] $($folder.Name): $count images" -ForegroundColor Cyan
            $hasImages = $true
        }
    }

    if ($hasImages) {
        $scenesWithImages++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total scenes: $totalScenes"
Write-Host "Scenes with images: $scenesWithImages"
Write-Host "Scenes without images: $($totalScenes - $scenesWithImages)"

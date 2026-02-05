# Analyze factors affecting 3DGS quality
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExe = (Get-Content (Join-Path $scriptDir "python_path.txt") -First 1).Trim()

$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

Write-Host "=== Quality Analysis for Scene 1 ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check COLMAP reconstruction quality
Write-Host "--- COLMAP Reconstruction ---" -ForegroundColor Yellow
$sparsePath = Join-Path $scene1 "output\colmap_output\sparse\0"

# Count registered images
$imagesBin = Join-Path $sparsePath "images.bin"
if (Test-Path $imagesBin) {
    $size = (Get-Item $imagesBin).Length
    Write-Host "  images.bin size: $([math]::Round($size/1KB, 2)) KB"
}

$points3DBin = Join-Path $sparsePath "points3D.bin"
if (Test-Path $points3DBin) {
    $size = (Get-Item $points3DBin).Length
    Write-Host "  points3D.bin size: $([math]::Round($size/1KB, 2)) KB"
}

# 2. Check image resolution
Write-Host ""
Write-Host "--- Image Quality ---" -ForegroundColor Yellow
$imagesDir = Join-Path $scene1 "output\images"
$sampleImage = Get-ChildItem -LiteralPath (Join-Path $imagesDir "video_W") -File | Select-Object -First 1

if ($sampleImage) {
    # Copy to temp for analysis
    $tempImg = "C:\postshot_temp_analysis.png"
    Copy-Item -LiteralPath $sampleImage.FullName -Destination $tempImg

    $pythonCode = @"
import cv2
import numpy as np
img = cv2.imread(r'$tempImg')
if img is not None:
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
    print(f'Resolution: {w}x{h}')
    print(f'Megapixels: {(w*h)/1000000:.2f} MP')
    print(f'Sharpness (Laplacian var): {laplacian_var:.2f}')
    if laplacian_var < 100:
        print('WARNING: Image appears blurry (variance < 100)')
    elif laplacian_var < 500:
        print('Note: Image sharpness is moderate')
    else:
        print('Image sharpness is good')
"@
    & $pythonExe -c $pythonCode 2>&1 | ForEach-Object { Write-Host "  $_" }
    Remove-Item $tempImg -ErrorAction SilentlyContinue
}

# 3. Analyze blur distribution
Write-Host ""
Write-Host "--- Blur Analysis (sample of 20 frames) ---" -ForegroundColor Yellow

$wImages = Get-ChildItem -LiteralPath (Join-Path $imagesDir "video_W") -File | Select-Object -First 20
$tempDir = "C:\postshot_temp_blur"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

foreach ($img in $wImages) {
    Copy-Item -LiteralPath $img.FullName -Destination (Join-Path $tempDir $img.Name)
}

$pythonCode = @"
import cv2
import os
import numpy as np

img_dir = r'$tempDir'
scores = []
for f in sorted(os.listdir(img_dir)):
    if f.endswith('.png') or f.endswith('.jpg'):
        img = cv2.imread(os.path.join(img_dir, f), cv2.IMREAD_GRAYSCALE)
        if img is not None:
            var = cv2.Laplacian(img, cv2.CV_64F).var()
            scores.append(var)

if scores:
    print(f'Frames analyzed: {len(scores)}')
    print(f'Mean sharpness: {np.mean(scores):.2f}')
    print(f'Min sharpness: {np.min(scores):.2f}')
    print(f'Max sharpness: {np.max(scores):.2f}')
    blurry_count = sum(1 for s in scores if s < 100)
    print(f'Blurry frames (var < 100): {blurry_count}/{len(scores)}')
"@
& $pythonExe -c $pythonCode 2>&1 | ForEach-Object { Write-Host "  $_" }
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# 4. Suggestions
Write-Host ""
Write-Host "=== Recommendations to Improve Quality ===" -ForegroundColor Green
Write-Host ""
Write-Host "1. INCREASE TRAINING STEPS" -ForegroundColor Cyan
Write-Host "   Current: 30,000 steps"
Write-Host "   Try: 50,000-100,000 steps for sharper results"
Write-Host "   Edit: config/default_config.json -> postshot.training_steps"
Write-Host ""
Write-Host "2. REMOVE BLURRY FRAMES" -ForegroundColor Cyan
Write-Host "   Run blur detection before COLMAP:"
Write-Host "   python scripts/blur_detector.py output/images --remove"
Write-Host ""
Write-Host "3. INCREASE IMAGE COUNT (if under 200)" -ForegroundColor Cyan
Write-Host "   Extract at higher FPS: config/config_2fps.json"
Write-Host "   Then use frame_selector.py to keep best frames"
Write-Host ""
Write-Host "4. CHECK COLMAP QUALITY" -ForegroundColor Cyan
Write-Host "   Low point count may indicate:"
Write-Host "   - Poor feature matching between W and Z cameras"
Write-Host "   - Insufficient overlap between frames"
Write-Host "   - Scene with few distinct features"
Write-Host ""

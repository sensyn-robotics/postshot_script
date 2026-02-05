# Alternative approach: Crop W images to match Z FOV for better registration
# Then run COLMAP on cropped W + original Z images
param(
    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [double]$CropRatio = 0.35,  # 35% center crop (Z FOV is roughly 35% of W)

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "output_cropped_colmap"
)

$ErrorActionPreference = 'Stop'

# Get scene path
if (-not $ScenePath) {
    $scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
    $ScenePath = $scenes[0].FullName
}

Write-Host "=== Cropped W + Original Z COLMAP Registration ===" -ForegroundColor Cyan
Write-Host "Scene: $ScenePath" -ForegroundColor Yellow
Write-Host "Crop ratio: $CropRatio (keeping center $([int]($CropRatio*100))%)" -ForegroundColor Yellow

$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
$colmapExe = "C:\COLMAP\bin\colmap.exe"

$originalImagesPath = Join-Path $ScenePath "output\images"
$outputPath = Join-Path $ScenePath $OutputDir
$croppedImagesPath = Join-Path $outputPath "images"
$databasePath = Join-Path $outputPath "database.db"
$sparsePath = Join-Path $outputPath "sparse"

# Clean output directory
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
New-Item -ItemType Directory -Path $croppedImagesPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $croppedImagesPath "video_W") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $croppedImagesPath "video_Z") -Force | Out-Null
New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

# ============================================
# Step 1: Crop W images
# ============================================
Write-Host ""
Write-Host "=== Step 1: Crop W images (center $([int]($CropRatio*100))%) ===" -ForegroundColor Cyan

$wInputDir = Join-Path $originalImagesPath "video_W"
$wOutputDir = Join-Path $croppedImagesPath "video_W"

& $pythonPath "C:\postshot_script\scripts\crop_wide_images.py" `
    $wInputDir $wOutputDir `
    --crop_ratio $CropRatio

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to crop W images" -ForegroundColor Red
    exit 1
}

# ============================================
# Step 2: Copy Z images unchanged
# ============================================
Write-Host ""
Write-Host "=== Step 2: Copy Z images ===" -ForegroundColor Cyan

$zInputDir = Join-Path $originalImagesPath "video_Z"
$zOutputDir = Join-Path $croppedImagesPath "video_Z"

$zImages = Get-ChildItem -LiteralPath $zInputDir -Filter "*.png"
Write-Host "Copying $($zImages.Count) Z images..." -ForegroundColor Gray

foreach ($img in $zImages) {
    Copy-Item -LiteralPath $img.FullName -Destination $zOutputDir
}

# ============================================
# Step 3: Run COLMAP feature extraction
# ============================================
Write-Host ""
Write-Host "=== Step 3: Feature Extraction ===" -ForegroundColor Cyan

$extractArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $croppedImagesPath,
    "--ImageReader.single_camera_per_folder", "1",
    "--ImageReader.camera_model", "OPENCV",
    "--SiftExtraction.max_num_features", "16384",
    "--SiftExtraction.first_octave", "-1"
)

Write-Host "Running feature extraction..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $extractArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature extraction failed" -ForegroundColor Red
    exit 1
}

# ============================================
# Step 4: Run exhaustive matching
# ============================================
Write-Host ""
Write-Host "=== Step 4: Exhaustive Matching ===" -ForegroundColor Cyan

$matchArgs = @(
    "exhaustive_matcher",
    "--database_path", $databasePath
)

Write-Host "Running exhaustive matching..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $matchArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Matching failed" -ForegroundColor Red
    exit 1
}

# ============================================
# Step 5: Run mapper with relaxed settings
# ============================================
Write-Host ""
Write-Host "=== Step 5: Mapper ===" -ForegroundColor Cyan

$mapperArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $croppedImagesPath,
    "--output_path", $sparsePath,
    "--Mapper.init_min_num_inliers", "15",
    "--Mapper.abs_pose_min_num_inliers", "5",
    "--Mapper.abs_pose_min_inlier_ratio", "0.05",
    "--Mapper.init_max_error", "8",
    "--Mapper.ba_global_max_num_iterations", "50"
)

Write-Host "Running mapper..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $mapperArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "WARNING: Mapper returned non-zero" -ForegroundColor Yellow
}

# ============================================
# Analyze results
# ============================================
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan

$models = Get-ChildItem -LiteralPath $sparsePath -Directory | Sort-Object Name
foreach ($model in $models) {
    Write-Host ""
    Write-Host "Model: $($model.Name)" -ForegroundColor Yellow
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $model.FullName
}

Write-Host ""
Write-Host "Output: $sparsePath" -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: These results are on CROPPED images." -ForegroundColor Yellow
Write-Host "If registration is good, need to transfer poses to original W images." -ForegroundColor Yellow

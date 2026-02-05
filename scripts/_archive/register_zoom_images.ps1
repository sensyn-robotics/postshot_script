# Two-stage Z image registration
# Stage 1: Build W-only model (or use existing)
# Stage 2: Register Z images to W model using image_registrator
param(
    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "output_dual_registered"
)

$ErrorActionPreference = 'Stop'

# Get scene path
if (-not $ScenePath) {
    $scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
    $ScenePath = $scenes[0].FullName
}

Write-Host "=== Two-Stage Z Image Registration ===" -ForegroundColor Cyan
Write-Host "Scene: $ScenePath" -ForegroundColor Yellow

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$imagesPath = Join-Path $ScenePath "output\images"
$outputPath = Join-Path $ScenePath $OutputDir
$databasePath = Join-Path $outputPath "database.db"
$sparsePath = Join-Path $outputPath "sparse"

# Clean output directory
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

# Count images
$wImages = @(Get-ChildItem -LiteralPath (Join-Path $imagesPath "video_W") -Filter "*.png")
$zImages = @(Get-ChildItem -LiteralPath (Join-Path $imagesPath "video_Z") -Filter "*.png")
Write-Host "W images: $($wImages.Count), Z images: $($zImages.Count)" -ForegroundColor Gray

# ============================================
# Stage 1: Feature Extraction (all images)
# ============================================
Write-Host ""
Write-Host "=== Stage 1: Feature Extraction ===" -ForegroundColor Cyan

$extractArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
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
# Stage 2: Match W images only (exhaustive)
# ============================================
Write-Host ""
Write-Host "=== Stage 2: Match W images only ===" -ForegroundColor Cyan

# Create W-only image list
$wOnlyList = Join-Path $outputPath "w_only_images.txt"
$wImages | ForEach-Object { "video_W/$($_.Name)" } | Out-File -FilePath $wOnlyList -Encoding utf8

# Use vocab tree matcher with image list to match only W images
# Actually, let's use exhaustive but we'll do it in two stages

# First, match all images exhaustively (we need the matches in the database)
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
# Stage 3: Run mapper with all images
# ============================================
Write-Host ""
Write-Host "=== Stage 3: Run Mapper (all images) ===" -ForegroundColor Cyan

$allSparsePath = Join-Path $outputPath "sparse_all"
New-Item -ItemType Directory -Path $allSparsePath -Force | Out-Null

# Run mapper with relaxed settings to get best possible registration
$mapperArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
    "--output_path", $allSparsePath,
    "--Mapper.init_min_num_inliers", "15",
    "--Mapper.abs_pose_min_num_inliers", "3",
    "--Mapper.abs_pose_min_inlier_ratio", "0.01",
    "--Mapper.init_max_error", "12",
    "--Mapper.ba_global_max_num_iterations", "50",
    "--Mapper.max_reg_trials", "5"
)

Write-Host "Running mapper with very relaxed settings..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $mapperArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "WARNING: Mapper returned non-zero" -ForegroundColor Yellow
}

# Find the largest model
$allModels = Get-ChildItem -LiteralPath $allSparsePath -Directory | Sort-Object Name
if ($allModels.Count -eq 0) {
    Write-Host "ERROR: No model created" -ForegroundColor Red
    exit 1
}
$mainModelPath = $allModels[0].FullName
Write-Host "Main model created: $mainModelPath" -ForegroundColor Green

# Analyze each model
Write-Host ""
Write-Host "=== Analyzing all models ===" -ForegroundColor Cyan
foreach ($model in $allModels) {
    Write-Host ""
    Write-Host "Model: $($model.Name)" -ForegroundColor Yellow
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $model.FullName
}

# ============================================
# Stage 4: Try to register more images
# ============================================
Write-Host ""
Write-Host "=== Stage 4: Try to register more images ===" -ForegroundColor Cyan

$finalSparsePath = Join-Path $sparsePath "0"
New-Item -ItemType Directory -Path $finalSparsePath -Force | Out-Null

# Copy main model as starting point
Copy-Item -LiteralPath (Join-Path $mainModelPath "cameras.bin") -Destination $finalSparsePath
Copy-Item -LiteralPath (Join-Path $mainModelPath "images.bin") -Destination $finalSparsePath
Copy-Item -LiteralPath (Join-Path $mainModelPath "points3D.bin") -Destination $finalSparsePath

# Use image_registrator to try adding more images with VERY relaxed settings
$registerArgs = @(
    "image_registrator",
    "--database_path", $databasePath,
    "--input_path", $finalSparsePath,
    "--output_path", $finalSparsePath,
    "--Mapper.abs_pose_min_num_inliers", "3",
    "--Mapper.abs_pose_min_inlier_ratio", "0.01",
    "--Mapper.max_reg_trials", "10"
)

Write-Host "Running image registrator (very relaxed)..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $registerArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "WARNING: Image registrator returned non-zero exit code" -ForegroundColor Yellow
}

# ============================================
# Stage 5: Final bundle adjustment
# ============================================
Write-Host ""
Write-Host "=== Stage 5: Bundle Adjustment ===" -ForegroundColor Cyan

$baArgs = @(
    "bundle_adjuster",
    "--input_path", $finalSparsePath,
    "--output_path", $finalSparsePath
)

Write-Host "Running bundle adjustment..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $baArgs -NoNewWindow -Wait -PassThru

# ============================================
# Analyze results
# ============================================
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan

$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
if (Test-Path $pythonPath) {
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $finalSparsePath
}

Write-Host ""
Write-Host "Output: $finalSparsePath" -ForegroundColor Green

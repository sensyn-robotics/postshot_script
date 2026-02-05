<#
.SYNOPSIS
Test COLMAP registration with various settings.

.DESCRIPTION
Run COLMAP feature extraction, matching, and mapping with configurable settings
to diagnose and fix image registration issues.

.PARAMETER ImageDir
Path to images directory

.PARAMETER OutputDir
Path to output directory for COLMAP results

.PARAMETER TestName
Name for this test (used in output reporting)

.PARAMETER CameraModel
Camera model to use: OPENCV, SIMPLE_RADIAL, PINHOLE (default: OPENCV)

.PARAMETER InitMinNumInliers
Mapper.init_min_num_inliers setting (default: 50)

.PARAMETER AbsPoseMinNumInliers
Mapper.abs_pose_min_num_inliers setting (default: 15)

.PARAMETER AbsPoseMinInlierRatio
Mapper.abs_pose_min_inlier_ratio setting (default: 0.15)

.PARAMETER InitMaxError
Mapper.init_max_error setting (default: 4)

.PARAMETER MultipleModels
Allow multiple models: 0 or 1 (default: 1)

.PARAMETER SingleCameraPerFolder
Treat each subfolder as a separate camera: 0 or 1 (default: 1)
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$ImageDir,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [string]$TestName = "default",

    [Parameter(Mandatory=$false)]
    [ValidateSet("OPENCV", "SIMPLE_RADIAL", "PINHOLE", "SIMPLE_PINHOLE")]
    [string]$CameraModel = "OPENCV",

    [Parameter(Mandatory=$false)]
    [int]$InitMinNumInliers = 50,

    [Parameter(Mandatory=$false)]
    [int]$AbsPoseMinNumInliers = 15,

    [Parameter(Mandatory=$false)]
    [double]$AbsPoseMinInlierRatio = 0.15,

    [Parameter(Mandatory=$false)]
    [double]$InitMaxError = 4,

    [Parameter(Mandatory=$false)]
    [int]$MultipleModels = 1,

    [Parameter(Mandatory=$false)]
    [int]$SingleCameraPerFolder = 1
)

$ErrorActionPreference = 'Stop'

# COLMAP executable
$colmapExe = "C:\COLMAP\bin\colmap.exe"
if (-not (Test-Path $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at $colmapExe" -ForegroundColor Red
    exit 1
}

# Python for analyzing results
$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
if (-not (Test-Path $pythonPath)) {
    $pythonPath = "python"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  COLMAP Registration Test: $TestName" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
Write-Host "  Camera model: $CameraModel" -ForegroundColor Yellow
Write-Host "  SingleCameraPerFolder: $SingleCameraPerFolder" -ForegroundColor Yellow
Write-Host "  init_min_num_inliers: $InitMinNumInliers" -ForegroundColor Yellow
Write-Host "  abs_pose_min_num_inliers: $AbsPoseMinNumInliers" -ForegroundColor Yellow
Write-Host "  abs_pose_min_inlier_ratio: $AbsPoseMinInlierRatio" -ForegroundColor Yellow
Write-Host "  init_max_error: $InitMaxError" -ForegroundColor Yellow
Write-Host "  multiple_models: $MultipleModels" -ForegroundColor Yellow
Write-Host ""
Write-Host "Directories:" -ForegroundColor Cyan
Write-Host "  Images: $ImageDir" -ForegroundColor Gray
Write-Host "  Output: $OutputDir" -ForegroundColor Gray
Write-Host ""

# Validate image directory
if (-not (Test-Path -LiteralPath $ImageDir)) {
    Write-Host "ERROR: Image directory not found: $ImageDir" -ForegroundColor Red
    exit 1
}

# Count images
$imageCount = (Get-ChildItem -LiteralPath $ImageDir -Recurse -Include @("*.jpg", "*.jpeg", "*.png") -File).Count
Write-Host "Total images: $imageCount" -ForegroundColor Yellow

# Create/clean output directory
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$databasePath = Join-Path $OutputDir "database.db"
$sparsePath = Join-Path $OutputDir "sparse"

# Measure time
$startTime = Get-Date

# === Step 1: Feature Extraction ===
Write-Host ""
Write-Host "=== Step 1: Feature Extraction ===" -ForegroundColor Cyan

$featureArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $ImageDir,
    "--ImageReader.single_camera_per_folder=$SingleCameraPerFolder",
    "--ImageReader.camera_model=$CameraModel",
    "--SiftExtraction.max_num_features=8192"
)

Write-Host "Running: colmap $($featureArgs -join ' ')" -ForegroundColor DarkGray

$process = Start-Process -FilePath $colmapExe -ArgumentList $featureArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature extraction failed" -ForegroundColor Red
    exit 1
}
Write-Host "Feature extraction complete" -ForegroundColor Green

# === Step 2: Exhaustive Matching ===
Write-Host ""
Write-Host "=== Step 2: Exhaustive Matching ===" -ForegroundColor Cyan

$matchArgs = @(
    "exhaustive_matcher",
    "--database_path", $databasePath
)

Write-Host "Running: colmap $($matchArgs -join ' ')" -ForegroundColor DarkGray

$process = Start-Process -FilePath $colmapExe -ArgumentList $matchArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Matching failed" -ForegroundColor Red
    exit 1
}
Write-Host "Matching complete" -ForegroundColor Green

# === Step 3: Mapper ===
Write-Host ""
Write-Host "=== Step 3: Mapping ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

$mapperArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $ImageDir,
    "--output_path", $sparsePath,
    "--Mapper.init_min_num_inliers=$InitMinNumInliers",
    "--Mapper.abs_pose_min_num_inliers=$AbsPoseMinNumInliers",
    "--Mapper.abs_pose_min_inlier_ratio=$AbsPoseMinInlierRatio",
    "--Mapper.init_max_error=$InitMaxError",
    "--Mapper.multiple_models=$MultipleModels",
    "--Mapper.ba_global_max_num_iterations=50"
)

Write-Host "Running: colmap $($mapperArgs -join ' ')" -ForegroundColor DarkGray

$process = Start-Process -FilePath $colmapExe -ArgumentList $mapperArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Mapping failed" -ForegroundColor Red
    exit 1
}
Write-Host "Mapping complete" -ForegroundColor Green

# Calculate elapsed time
$endTime = Get-Date
$elapsed = $endTime - $startTime

# === Step 4: Analyze Results ===
Write-Host ""
Write-Host "=== Step 4: Results Analysis ===" -ForegroundColor Cyan

$reconFolders = @(Get-ChildItem -LiteralPath $sparsePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' })

if ($reconFolders.Count -eq 0) {
    Write-Host "ERROR: No reconstructions created" -ForegroundColor Red
    Write-Host ""
    Write-Host "=== TEST FAILED: $TestName ===" -ForegroundColor Red
    exit 1
}

Write-Host "Created $($reconFolders.Count) reconstruction(s)" -ForegroundColor Yellow
Write-Host ""

# Analyze each reconstruction with Python
$totalRegistered = 0
$totalW = 0
$totalZ = 0

foreach ($recon in $reconFolders) {
    $output = & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $recon.FullName 2>&1
    Write-Host $output

    # Parse output to extract counts
    $regMatch = $output | Select-String -Pattern 'Registered images: (\d+)'
    $wMatch = $output | Select-String -Pattern 'W images: (\d+)'
    $zMatch = $output | Select-String -Pattern 'Z images: (\d+)'

    if ($regMatch) {
        $registered = [int]$regMatch.Matches[0].Groups[1].Value
        $totalRegistered += $registered
    }
    if ($wMatch) {
        $w = [int]$wMatch.Matches[0].Groups[1].Value
        $totalW += $w
    }
    if ($zMatch) {
        $z = [int]$zMatch.Matches[0].Groups[1].Value
        $totalZ += $z
    }
}

# === Final Summary ===
Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  TEST RESULTS: $TestName" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-Host "Time: $($elapsed.TotalSeconds.ToString('F1')) seconds" -ForegroundColor Cyan
Write-Host "Input images: $imageCount" -ForegroundColor Cyan
Write-Host "Registered: $totalRegistered / $imageCount ($([math]::Round($totalRegistered * 100 / $imageCount, 1))%)" -ForegroundColor $(if ($totalRegistered -ge $imageCount * 0.8) { 'Green' } else { 'Yellow' })
Write-Host "  W: $totalW" -ForegroundColor Yellow
Write-Host "  Z: $totalZ" -ForegroundColor Yellow
Write-Host ""

$success = $totalRegistered -ge ($imageCount * 0.8)
if ($success) {
    Write-Host "SUCCESS: Registered 80%+ images!" -ForegroundColor Green
} else {
    Write-Host "NEEDS IMPROVEMENT: Less than 80% registered" -ForegroundColor Yellow
}

# Return result object for scripting
return @{
    TestName = $TestName
    TotalImages = $imageCount
    RegisteredImages = $totalRegistered
    WImages = $totalW
    ZImages = $totalZ
    ElapsedSeconds = $elapsed.TotalSeconds
    Success = $success
}

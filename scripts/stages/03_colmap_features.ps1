# 03_colmap_features.ps1
# Stage 3: COLMAP feature extraction
#
# Input: output/images/
# Output: output/colmap/database.db

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath
)

$ErrorActionPreference = 'Stop'

# Load configuration
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Use ScenePath if provided, otherwise use config
if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    $ScenePath = $config.input.scene_path
}

if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    Write-Host "ERROR: ScenePath is required (via parameter or config)" -ForegroundColor Red
    exit 1
}

# Resolve paths
$outputDir = Join-Path $ScenePath $config.output.dir_name
$imagesDir = Join-Path $outputDir $config.output.images_subdir
$colmapDir = Join-Path $outputDir $config.output.colmap_subdir
$databasePath = Join-Path $colmapDir "database.db"
$colmapExe = $config.paths.colmap

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 3: COLMAP Feature Extraction" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Images: $imagesDir" -ForegroundColor White
Write-Host "  Database: $databasePath" -ForegroundColor White
Write-Host "  Camera model: $($config.stage_03_features.camera_model)" -ForegroundColor White
Write-Host "  Single camera: $(if ($config.stage_03_features.PSObject.Properties['single_camera'] -and $config.stage_03_features.single_camera) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Max features: $($config.stage_03_features.max_features)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate COLMAP
if (-not (Test-Path -LiteralPath $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
    exit 1
}

# Validate images directory
if (-not (Test-Path -LiteralPath $imagesDir)) {
    Write-Host "ERROR: Images directory not found: $imagesDir" -ForegroundColor Red
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check if database already exists with features
if (Test-Path -LiteralPath $databasePath) {
    if ($overwrite) {
        Write-Host "  Deleting existing database (overwrite_result=true)..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $databasePath -Force
    } else {
        Write-Host "  Database already exists: $databasePath" -ForegroundColor Yellow
        Write-Host "  Skipping feature extraction (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Stage 3 Complete (skipped - database exists)" -ForegroundColor Green
        exit 0
    }
}

# Create COLMAP output directory
if (-not (Test-Path -LiteralPath $colmapDir)) {
    New-Item -ItemType Directory -Path $colmapDir -Force | Out-Null
}

# Get COLMAP binary path
$colmapBin = if ($colmapExe -like "*.bat") {
    $colmapBinDir = Split-Path -Parent $colmapExe
    Join-Path $colmapBinDir "bin\colmap.exe"
} else {
    $colmapExe
}

# Set up COLMAP environment
$colmapRootDir = if ($colmapExe -like "*.bat") {
    Split-Path -Parent $colmapExe
} else {
    Split-Path -Parent (Split-Path -Parent $colmapExe)
}

$env:PATH = "$(Join-Path $colmapRootDir 'bin');$env:PATH"
$env:QT_PLUGIN_PATH = Join-Path $colmapRootDir "plugins"

# Build feature extraction arguments
$singleCameraPerFolder = if ($config.stage_03_features.single_camera_per_folder) { 1 } else { 0 }
$singleCamera = 0
if ($config.stage_03_features.PSObject.Properties['single_camera'] -and $config.stage_03_features.single_camera) {
    $singleCamera = 1
}

$colmapArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $imagesDir,
    "--ImageReader.single_camera=$singleCamera",
    "--ImageReader.single_camera_per_folder=$singleCameraPerFolder",
    "--ImageReader.camera_model=$($config.stage_03_features.camera_model)",
    "--SiftExtraction.max_num_features=$($config.stage_03_features.max_features)"
)

Write-Host ""
Write-Host "  Running feature extraction..." -ForegroundColor Cyan
Write-Host "  Command: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

$process = Start-Process -FilePath $colmapBin `
    -ArgumentList $colmapArgs `
    -NoNewWindow -Wait -PassThru

if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature extraction failed with exit code $($process.ExitCode)" -ForegroundColor Red
    exit 1
}

# Verify database was created
if (-not (Test-Path -LiteralPath $databasePath)) {
    Write-Host "ERROR: Database was not created" -ForegroundColor Red
    exit 1
}

$dbSize = (Get-Item -LiteralPath $databasePath).Length / 1MB

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 3 Complete" -ForegroundColor Green
Write-Host "  Database: $databasePath" -ForegroundColor White
Write-Host "  Size: $('{0:N2}' -f $dbSize) MB" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

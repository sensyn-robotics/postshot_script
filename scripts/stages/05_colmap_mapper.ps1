# 05_colmap_mapper.ps1
# Stage 5: COLMAP sparse reconstruction (mapper)
#
# Input: output/colmap/database.db + output/images/
# Output: output/colmap/sparse/0/

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
$sparseDir = Join-Path $colmapDir "sparse"
$vizDir = Join-Path $outputDir $config.output.visualizations_subdir
$colmapExe = $config.paths.colmap

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 5: COLMAP Mapper" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Database: $databasePath" -ForegroundColor White
Write-Host "  Images: $imagesDir" -ForegroundColor White
Write-Host "  Output: $sparseDir" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate COLMAP
if (-not (Test-Path -LiteralPath $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
    exit 1
}

# Validate database
if (-not (Test-Path -LiteralPath $databasePath)) {
    Write-Host "ERROR: Database not found: $databasePath" -ForegroundColor Red
    Write-Host "  Run stages 03-04 first" -ForegroundColor Yellow
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check for existing reconstruction
if ((Test-Path -LiteralPath $sparseDir) -and -not $overwrite) {
    $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
    if ($reconFolders.Count -gt 0) {
        # Verify at least one has required files
        $validRecon = $false
        foreach ($recon in $reconFolders) {
            $imagesFile = Join-Path $recon.FullName "images.bin"
            if (Test-Path -LiteralPath $imagesFile) {
                $validRecon = $true
                Write-Host "  Found existing reconstruction: $($recon.Name)" -ForegroundColor Yellow
                break
            }
        }
        if ($validRecon) {
            Write-Host "  Skipping mapper (overwrite_result=false)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Stage 5 Complete (skipped - reconstruction exists)" -ForegroundColor Green
            exit 0
        }
    }
}

# Create sparse output directory
if (-not (Test-Path -LiteralPath $sparseDir)) {
    New-Item -ItemType Directory -Path $sparseDir -Force | Out-Null
}

# Create visualizations directory
if (-not (Test-Path -LiteralPath $vizDir)) {
    New-Item -ItemType Directory -Path $vizDir -Force | Out-Null
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

# Build mapper arguments
$multipleModels = if ($config.stage_05_mapper.multiple_models) { 1 } else { 0 }

$colmapArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $imagesDir,
    "--output_path", $sparseDir,
    "--Mapper.multiple_models=$multipleModels",
    "--Mapper.min_model_size=$($config.stage_05_mapper.min_model_size)",
    "--Mapper.ba_global_max_num_iterations=$($config.stage_05_mapper.ba_global_max_iterations)",
    "--Mapper.ba_local_max_num_iterations=$($config.stage_05_mapper.ba_local_max_iterations)",
    "--Mapper.init_min_num_inliers=$($config.stage_05_mapper.init_min_num_inliers)",
    "--Mapper.abs_pose_min_num_inliers=$($config.stage_05_mapper.abs_pose_min_num_inliers)",
    "--Mapper.abs_pose_min_inlier_ratio=$($config.stage_05_mapper.abs_pose_min_inlier_ratio)"
)

Write-Host ""
Write-Host "  Running mapper..." -ForegroundColor Cyan
Write-Host "  Command: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

# Log file for visualization monitor
$vizLog = Join-Path $vizDir "mapper_progress.log"
Add-Content -Path $vizLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting COLMAP mapper"

$startTime = Get-Date

$process = Start-Process -FilePath $colmapBin `
    -ArgumentList $colmapArgs `
    -NoNewWindow -Wait -PassThru

$duration = (Get-Date) - $startTime

Add-Content -Path $vizLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Mapper completed with exit code $($process.ExitCode)"

if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Mapper failed with exit code $($process.ExitCode)" -ForegroundColor Red
    exit 1
}

# Find reconstructions
$reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }

if ($reconFolders.Count -eq 0) {
    Write-Host "ERROR: No reconstruction created" -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($reconFolders.Count) reconstruction(s)" -ForegroundColor Cyan

# Find largest reconstruction
$largestRecon = $null
$largestSize = 0

foreach ($recon in $reconFolders) {
    $imagesBin = Join-Path $recon.FullName "images.bin"
    if (Test-Path -LiteralPath $imagesBin) {
        $size = (Get-Item -LiteralPath $imagesBin).Length
        Write-Host "    Reconstruction $($recon.Name): images.bin = $size bytes" -ForegroundColor Gray
        if ($size -gt $largestSize) {
            $largestSize = $size
            $largestRecon = $recon
        }
    }
}

if (-not $largestRecon) {
    Write-Host "ERROR: No valid reconstruction found" -ForegroundColor Red
    exit 1
}

Write-Host "  Selected reconstruction: $($largestRecon.Name)" -ForegroundColor Green

# Save visualization (simple point cloud stats for now)
$vizInfoFile = Join-Path $vizDir "reconstruction_info.txt"
$points3dBin = Join-Path $largestRecon.FullName "points3D.bin"
$points3dSize = if (Test-Path -LiteralPath $points3dBin) { (Get-Item -LiteralPath $points3dBin).Length } else { 0 }

$vizInfo = @"
COLMAP Reconstruction Summary
=============================
Reconstruction folder: $($largestRecon.Name)
images.bin size: $largestSize bytes
points3D.bin size: $points3dSize bytes
Duration: $($duration.ToString('hh\:mm\:ss'))
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

Set-Content -Path $vizInfoFile -Value $vizInfo

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 5 Complete" -ForegroundColor Green
Write-Host "  Reconstruction: $($largestRecon.FullName)" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

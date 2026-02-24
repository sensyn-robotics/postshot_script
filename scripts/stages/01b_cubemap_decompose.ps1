# 01b_cubemap_decompose.ps1
# Stage 1b: Decompose equirectangular frames into cubemap face images
#
# Input: output/images/video_single/ (equirectangular frames from stage 01)
# Output: output/images/cubemap/ (5 face subdirectories with perspective images)
#
# After successful decomposition, moves video_single/ to output/equirect_originals/
# so that COLMAP only sees the cubemap perspective images.

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

if (-not (Test-Path -LiteralPath $ScenePath)) {
    Write-Host "ERROR: Scene path not found: $ScenePath" -ForegroundColor Red
    exit 1
}

# Resolve paths
$outputDir = Join-Path $ScenePath $config.output.dir_name
$imagesDir = Join-Path $outputDir $config.output.images_subdir
$singleImagesDir = Join-Path $imagesDir "video_single"
$cubemapDir = Join-Path $imagesDir "cubemap"
$equirectBackupDir = Join-Path $outputDir "equirect_originals"
$ffmpegExe = $config.paths.ffmpeg
$pythonExe = $config.paths.python
$scriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Read cubemap config
$fov = 110
$outputSize = 0
$faces = "front,right,back,left,top"

if ($config.PSObject.Properties['stage_01b_cubemap']) {
    $cubemapConfig = $config.stage_01b_cubemap

    if ($cubemapConfig.PSObject.Properties['fov']) {
        $fov = $cubemapConfig.fov
    }
    if ($cubemapConfig.PSObject.Properties['output_size']) {
        $outputSize = $cubemapConfig.output_size
    }
    if ($cubemapConfig.PSObject.Properties['faces']) {
        $faces = ($cubemapConfig.faces -join ",")
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 1b: Cubemap Decomposition" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scene: $ScenePath" -ForegroundColor White
Write-Host "  Input: $singleImagesDir" -ForegroundColor White
Write-Host "  Output: $cubemapDir" -ForegroundColor White
Write-Host "  FOV: $fov degrees" -ForegroundColor White
Write-Host "  Faces: $faces" -ForegroundColor White
if ($outputSize -gt 0) {
    Write-Host "  Output size: ${outputSize}px" -ForegroundColor White
} else {
    Write-Host "  Output size: auto (from input height)" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Cyan

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check if cubemap output already exists
if (Test-Path -LiteralPath $cubemapDir) {
    $existingCount = (Get-ChildItem -LiteralPath $cubemapDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count

    if ($existingCount -gt 0 -and -not $overwrite) {
        Write-Host "  Found $existingCount existing cubemap images" -ForegroundColor Yellow
        Write-Host "  Skipping decomposition (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Stage 1b Complete (skipped - cubemap exists)" -ForegroundColor Green
        exit 0
    }

    if ($overwrite -and $existingCount -gt 0) {
        Write-Host "  Deleting existing cubemap output (overwrite_result=true)..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $cubemapDir -Recurse -Force
    }
}

# Validate equirectangular source images
# Check video_single first, then fall back to equirect_originals (in case of re-run)
$sourceDir = $null

if (Test-Path -LiteralPath $singleImagesDir) {
    $sourceCount = (Get-ChildItem -LiteralPath $singleImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
    if ($sourceCount -gt 0) {
        $sourceDir = $singleImagesDir
        Write-Host "  Source: video_single/ ($sourceCount frames)" -ForegroundColor Cyan
    }
}

if (-not $sourceDir) {
    # Check if equirect_originals exists (previous run moved files there)
    $equirectSingleDir = Join-Path $equirectBackupDir "video_single"
    if (Test-Path -LiteralPath $equirectSingleDir) {
        $sourceCount = (Get-ChildItem -LiteralPath $equirectSingleDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
        if ($sourceCount -gt 0) {
            $sourceDir = $equirectSingleDir
            Write-Host "  Source: equirect_originals/video_single/ ($sourceCount frames)" -ForegroundColor Cyan
        }
    }
}

if (-not $sourceDir) {
    Write-Host "ERROR: No equirectangular frames found in video_single/ or equirect_originals/" -ForegroundColor Red
    Write-Host "  Run stage 01 (frame extraction) first" -ForegroundColor Yellow
    exit 1
}

# Validate Python
if (-not (Test-Path -LiteralPath $pythonExe)) {
    $resolved = (Get-Command $pythonExe -ErrorAction SilentlyContinue).Source
    if ($resolved) {
        $pythonExe = $resolved
    } else {
        Write-Host "ERROR: Python not found at: $pythonExe" -ForegroundColor Red
        exit 1
    }
}

# Validate FFmpeg
if (-not (Test-Path -LiteralPath $ffmpegExe)) {
    Write-Host "ERROR: FFmpeg not found at: $ffmpegExe" -ForegroundColor Red
    exit 1
}

# Locate cubemap_decompose.py
$cubemapScript = Join-Path $scriptDir "cubemap_decompose.py"
if (-not (Test-Path -LiteralPath $cubemapScript)) {
    Write-Host "ERROR: cubemap_decompose.py not found at: $cubemapScript" -ForegroundColor Red
    exit 1
}

# Run cubemap decomposition
Write-Host ""
Write-Host "  Running cubemap decomposition..." -ForegroundColor Cyan

$pythonArgs = @(
    $cubemapScript,
    "--input_dir", $sourceDir,
    "--output_dir", $cubemapDir,
    "--fov", $fov,
    "--ffmpeg", $ffmpegExe,
    "--faces", $faces
)

if ($outputSize -gt 0) {
    $pythonArgs += @("--output_size", $outputSize)
}

$startTime = Get-Date

& $pythonExe $pythonArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Cubemap decomposition failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

$duration = (Get-Date) - $startTime

# Verify output
$totalCubemapImages = 0
if (Test-Path -LiteralPath $cubemapDir) {
    $totalCubemapImages = (Get-ChildItem -LiteralPath $cubemapDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

if ($totalCubemapImages -eq 0) {
    Write-Host "ERROR: No cubemap images were generated" -ForegroundColor Red
    exit 1
}

# Move video_single/ to equirect_originals/ so COLMAP only sees cubemap faces
if ($sourceDir -eq $singleImagesDir) {
    Write-Host ""
    Write-Host "  Moving equirectangular originals to backup..." -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $equirectBackupDir)) {
        New-Item -ItemType Directory -Path $equirectBackupDir -Force | Out-Null
    }

    $equirectTarget = Join-Path $equirectBackupDir "video_single"
    if (Test-Path -LiteralPath $equirectTarget) {
        Remove-Item -LiteralPath $equirectTarget -Recurse -Force
    }

    Move-Item -LiteralPath $singleImagesDir -Destination $equirectTarget
    Write-Host "  Moved: video_single/ -> equirect_originals/video_single/" -ForegroundColor Green
}

# Count faces per directory
$faceList = $faces -split ","
$faceNames = @{
    "front" = "1_front"
    "right" = "2_right"
    "back"  = "3_back"
    "left"  = "4_left"
    "top"   = "5_top"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 1b Complete" -ForegroundColor Green
Write-Host "  Total cubemap images: $totalCubemapImages" -ForegroundColor White
foreach ($face in $faceList) {
    $faceDirName = $faceNames[$face.Trim()]
    if ($faceDirName) {
        $faceDir = Join-Path $cubemapDir $faceDirName
        if (Test-Path -LiteralPath $faceDir) {
            $faceCount = (Get-ChildItem -LiteralPath $faceDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
            Write-Host "  ${faceDirName}/: $faceCount images" -ForegroundColor White
        }
    }
}
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

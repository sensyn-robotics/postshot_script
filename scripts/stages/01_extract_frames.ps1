# 01_extract_frames.ps1
# Stage 1: Extract frames from video files using FFmpeg
#
# Input: Video files (video_W.mp4, video_Z.mp4)
# Output: output/images/video_W/, output/images/video_Z/

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
$wImagesDir = Join-Path $imagesDir "video_W"
$zImagesDir = Join-Path $imagesDir "video_Z"
$ffmpegExe = $config.paths.ffmpeg

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 1: Frame Extraction" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scene: $ScenePath" -ForegroundColor White
Write-Host "  Output: $imagesDir" -ForegroundColor White
Write-Host "  FPS: $($config.stage_01_extract.fps)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate FFmpeg
if (-not (Test-Path -LiteralPath $ffmpegExe)) {
    Write-Host "ERROR: FFmpeg not found at: $ffmpegExe" -ForegroundColor Red
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check for existing frames
$existingWCount = 0
$existingZCount = 0
if (Test-Path -LiteralPath $wImagesDir) {
    $existingWCount = (Get-ChildItem -LiteralPath $wImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $zImagesDir) {
    $existingZCount = (Get-ChildItem -LiteralPath $zImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

if (($existingWCount -gt 0 -or $existingZCount -gt 0) -and -not $overwrite) {
    Write-Host "  Found existing frames: W=$existingWCount, Z=$existingZCount" -ForegroundColor Yellow
    Write-Host "  Skipping extraction (overwrite_result=false)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Stage 1 Complete (skipped - frames exist)" -ForegroundColor Green
    exit 0
}

# Find video files
$videos = Get-ChildItem -LiteralPath $ScenePath -File | Where-Object {
    $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV", ".avi", ".AVI")
}

$wVideos = $videos | Where-Object { $_.Name -match "_W[-.]" }
$zVideos = $videos | Where-Object { $_.Name -match "_Z[-.]" }

Write-Host "  Found videos: W=$($wVideos.Count), Z=$($zVideos.Count)" -ForegroundColor Cyan

if ($wVideos.Count -eq 0 -and $zVideos.Count -eq 0) {
    Write-Host "ERROR: No video files found" -ForegroundColor Red
    exit 1
}

# Create output directories
foreach ($dir in @($imagesDir, $wImagesDir, $zImagesDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Extract frames function
function Extract-Frames {
    param(
        [string]$VideoPath,
        [string]$OutputDir,
        [double]$Fps,
        [string]$Format,
        [int]$Quality
    )

    $outputPattern = Join-Path $OutputDir "frame_%05d.$Format"

    Write-Host "  Extracting: $(Split-Path -Leaf $VideoPath)" -ForegroundColor Cyan

    $process = Start-Process -FilePath $ffmpegExe `
        -ArgumentList @("-i", $VideoPath, "-vf", "fps=$Fps", "-q:v", $Quality, "-start_number", "1", $outputPattern) `
        -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: FFmpeg failed with exit code $($process.ExitCode)" -ForegroundColor Red
        return $false
    }

    $frameCount = (Get-ChildItem -LiteralPath $OutputDir -File |
        Where-Object { $_.Extension -eq ".$Format" }).Count
    Write-Host "    Extracted $frameCount frames" -ForegroundColor Green

    return $true
}

# Extract W video frames
$fps = $config.stage_01_extract.fps
$format = $config.stage_01_extract.format
$quality = $config.stage_01_extract.quality

foreach ($video in $wVideos) {
    $result = Extract-Frames -VideoPath $video.FullName -OutputDir $wImagesDir -Fps $fps -Format $format -Quality $quality
    if (-not $result) {
        Write-Host "ERROR: Failed to extract W frames" -ForegroundColor Red
        exit 1
    }
}

# Extract Z video frames
foreach ($video in $zVideos) {
    $result = Extract-Frames -VideoPath $video.FullName -OutputDir $zImagesDir -Fps $fps -Format $format -Quality $quality
    if (-not $result) {
        Write-Host "ERROR: Failed to extract Z frames" -ForegroundColor Red
        exit 1
    }
}

# Count final frames
$wCount = (Get-ChildItem -LiteralPath $wImagesDir -File -ErrorAction SilentlyContinue).Count
$zCount = (Get-ChildItem -LiteralPath $zImagesDir -File -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 1 Complete" -ForegroundColor Green
Write-Host "  W frames: $wCount" -ForegroundColor White
Write-Host "  Z frames: $zCount" -ForegroundColor White
Write-Host "  Total: $($wCount + $zCount)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

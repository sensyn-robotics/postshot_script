# 01_extract_frames.ps1
# Stage 1: Extract frames from video files using FFmpeg
#
# Input: Video files (video_W.mp4, video_Z.mp4 or any single video)
# Output: output/images/video_W/, output/images/video_Z/ or output/images/video_single/

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [double]$FpsOverride = 0,

    [Parameter(Mandatory=$false)]
    [double]$ScaleOverride = 0
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
$singleImagesDir = Join-Path $imagesDir "video_single"
$ffmpegExe = $config.paths.ffmpeg

# Determine effective fps and scale
$fps = if ($FpsOverride -gt 0) { $FpsOverride } else { $config.stage_01_extract.fps }
$scale = if ($ScaleOverride -gt 0) { $ScaleOverride } else { 1.0 }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 1: Frame Extraction" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scene: $ScenePath" -ForegroundColor White
Write-Host "  Output: $imagesDir" -ForegroundColor White
Write-Host "  FPS: $fps$(if ($FpsOverride -gt 0) { ' (override)' })" -ForegroundColor White
if ($scale -ne 1.0) {
    Write-Host "  Scale: ${scale}x (override)" -ForegroundColor White
}
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

# Check for existing frames (W/Z or single)
$existingWCount = 0
$existingZCount = 0
$existingSingleCount = 0
if (Test-Path -LiteralPath $wImagesDir) {
    $existingWCount = (Get-ChildItem -LiteralPath $wImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $zImagesDir) {
    $existingZCount = (Get-ChildItem -LiteralPath $zImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $singleImagesDir) {
    $existingSingleCount = (Get-ChildItem -LiteralPath $singleImagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

if (($existingWCount -gt 0 -or $existingZCount -gt 0 -or $existingSingleCount -gt 0) -and -not $overwrite) {
    Write-Host "  Found existing frames: W=$existingWCount, Z=$existingZCount, Single=$existingSingleCount" -ForegroundColor Yellow
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

# Auto-detect single video mode
$singleVideoMode = ($wVideos.Count -eq 0 -and $zVideos.Count -eq 0 -and $videos.Count -gt 0)

if ($singleVideoMode) {
    Write-Host "  Single video mode: found $($videos.Count) video(s) (no W/Z pattern)" -ForegroundColor Yellow
} else {
    Write-Host "  Found videos: W=$($wVideos.Count), Z=$($zVideos.Count)" -ForegroundColor Cyan
}

if ($wVideos.Count -eq 0 -and $zVideos.Count -eq 0 -and $videos.Count -eq 0) {
    Write-Host "ERROR: No video files found" -ForegroundColor Red
    exit 1
}

# Create output directories
if ($singleVideoMode) {
    foreach ($dir in @($imagesDir, $singleImagesDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
} else {
    foreach ($dir in @($imagesDir, $wImagesDir, $zImagesDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

# Extract frames function
function Extract-Frames {
    param(
        [string]$VideoPath,
        [string]$OutputDir,
        [double]$Fps,
        [string]$Format,
        [int]$Quality,
        [double]$Scale = 1.0
    )

    $outputPattern = Join-Path $OutputDir "frame_%05d.$Format"

    Write-Host "  Extracting: $(Split-Path -Leaf $VideoPath)" -ForegroundColor Cyan

    # Build video filter string
    $vf = "fps=$Fps"
    if ($Scale -ne 1.0 -and $Scale -gt 0) {
        $vf += ",scale=iw*${Scale}:ih*${Scale}"
    }

    $process = Start-Process -FilePath $ffmpegExe `
        -ArgumentList @("-i", $VideoPath, "-vf", $vf, "-q:v", $Quality, "-start_number", "1", $outputPattern) `
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

# Common extraction parameters
$format = $config.stage_01_extract.format
$quality = $config.stage_01_extract.quality

if ($singleVideoMode) {
    # Single video mode: extract all videos into video_single/
    foreach ($video in $videos) {
        $result = Extract-Frames -VideoPath $video.FullName -OutputDir $singleImagesDir -Fps $fps -Format $format -Quality $quality -Scale $scale
        if (-not $result) {
            Write-Host "ERROR: Failed to extract frames from $($video.Name)" -ForegroundColor Red
            exit 1
        }
    }

    # Count final frames
    $singleCount = (Get-ChildItem -LiteralPath $singleImagesDir -File -ErrorAction SilentlyContinue).Count

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Stage 1 Complete (single video mode)" -ForegroundColor Green
    Write-Host "  Frames: $singleCount" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Green
} else {
    # Dual camera mode (W/Z)
    foreach ($video in $wVideos) {
        $result = Extract-Frames -VideoPath $video.FullName -OutputDir $wImagesDir -Fps $fps -Format $format -Quality $quality -Scale $scale
        if (-not $result) {
            Write-Host "ERROR: Failed to extract W frames" -ForegroundColor Red
            exit 1
        }
    }

    foreach ($video in $zVideos) {
        $result = Extract-Frames -VideoPath $video.FullName -OutputDir $zImagesDir -Fps $fps -Format $format -Quality $quality -Scale $scale
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
}

exit 0

# 02_filter_frames.ps1
# Stage 2: Filter frames (blur detection + keyframe selection)
#
# Input: output/images/video_W/, output/images/video_Z/
# Output: Filtered frames (blurred/skipped moved to subfolders)

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
$pythonExe = $config.paths.python
$scriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 2: Frame Filtering" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Images: $imagesDir" -ForegroundColor White

# Check if filtering is enabled
if (-not $config.stage_02_filter.enabled) {
    Write-Host "  Filtering DISABLED in config" -ForegroundColor Yellow
    Write-Host "Stage 2 Complete (skipped - disabled)" -ForegroundColor Green
    exit 0
}

Write-Host "  Blur threshold: $($config.stage_02_filter.blur_threshold)" -ForegroundColor White
Write-Host "  Target overlap: $($config.stage_02_filter.target_overlap * 100)%" -ForegroundColor White
Write-Host "  Max frames: $($config.stage_02_filter.max_frames)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate Python (resolve bare command name from PATH if needed)
if (-not (Test-Path -LiteralPath $pythonExe)) {
    $resolved = (Get-Command $pythonExe -ErrorAction SilentlyContinue).Source
    if ($resolved) {
        $pythonExe = $resolved
    } else {
        Write-Host "ERROR: Python not found at: $pythonExe" -ForegroundColor Red
        exit 1
    }
}

# Validate images directory
if (-not (Test-Path -LiteralPath $imagesDir)) {
    Write-Host "ERROR: Images directory not found: $imagesDir" -ForegroundColor Red
    exit 1
}

# Count current frames
$wImagesDir = Join-Path $imagesDir "video_W"
$zImagesDir = Join-Path $imagesDir "video_Z"
$singleImagesDir = Join-Path $imagesDir "video_single"
$wCount = 0
$zCount = 0
$singleCount = 0
if (Test-Path -LiteralPath $wImagesDir) {
    $wCount = (Get-ChildItem -LiteralPath $wImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $zImagesDir) {
    $zCount = (Get-ChildItem -LiteralPath $zImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $singleImagesDir) {
    $singleCount = (Get-ChildItem -LiteralPath $singleImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

# Detect single video mode
$singleVideoMode = ($wCount -eq 0 -and $zCount -eq 0 -and $singleCount -gt 0)

if ($singleVideoMode) {
    Write-Host "  Current frame count: Single=$singleCount" -ForegroundColor Cyan
} else {
    Write-Host "  Current frame count: W=$wCount, Z=$zCount, Total=$($wCount + $zCount)" -ForegroundColor Cyan
}

# Step 1: Blur Detection
Write-Host ""
Write-Host "--- Step 2a: Blur Detection ---" -ForegroundColor Yellow

$blurScript = Join-Path $scriptDir "util/blur_detector.py"
if (-not (Test-Path -LiteralPath $blurScript)) {
    Write-Host "ERROR: blur_detector.py not found at: $blurScript" -ForegroundColor Red
    exit 1
}

$blurArgs = @(
    $blurScript,
    $imagesDir
)

if ($config.stage_02_filter.blur_threshold -eq "auto") {
    $blurArgs += "--auto-threshold"
} else {
    $blurArgs += "--threshold"
    $blurArgs += $config.stage_02_filter.blur_threshold
}
$blurArgs += "--remove"

Write-Host "  Running blur detection..." -ForegroundColor Cyan
& $pythonExe $blurArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Blur detection failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

# Step 2: Keyframe Selection (optical flow based)
Write-Host ""
Write-Host "--- Step 2b: Keyframe Selection ---" -ForegroundColor Yellow

$flowScript = Join-Path $scriptDir "util\optical_flow_analyzer.py"
if (-not (Test-Path -LiteralPath $flowScript)) {
    Write-Host "WARNING: optical_flow_analyzer.py not found, skipping keyframe selection" -ForegroundColor Yellow
} else {
    $targetOverlap = $config.stage_02_filter.target_overlap * 100

    $flowArgs = @(
        $flowScript,
        $imagesDir,
        "--select-keyframes",
        "--target-overlap", $targetOverlap,
        "--remove-non-keyframes"
    )

    Write-Host "  Running keyframe selection (target overlap: $targetOverlap%)..." -ForegroundColor Cyan
    & $pythonExe $flowArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Keyframe selection failed, continuing with all frames" -ForegroundColor Yellow
    }
}

# Step 3: Limit frame count
Write-Host ""
Write-Host "--- Step 2c: Frame Limit Check ---" -ForegroundColor Yellow

# Recount frames after filtering
$wCount = 0
$zCount = 0
$singleCount = 0
if (Test-Path -LiteralPath $wImagesDir) {
    $wCount = (Get-ChildItem -LiteralPath $wImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $zImagesDir) {
    $zCount = (Get-ChildItem -LiteralPath $zImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if ($singleVideoMode -and (Test-Path -LiteralPath $singleImagesDir)) {
    $singleCount = (Get-ChildItem -LiteralPath $singleImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

$totalFrames = if ($singleVideoMode) { $singleCount } else { $wCount + $zCount }
$maxFrames = $config.stage_02_filter.max_frames

if ($singleVideoMode) {
    Write-Host "  Frames after filtering: Single=$singleCount" -ForegroundColor Cyan
} else {
    Write-Host "  Frames after filtering: W=$wCount, Z=$zCount, Total=$totalFrames" -ForegroundColor Cyan
}

if ($totalFrames -gt $maxFrames) {
    Write-Host "  Frame count ($totalFrames) exceeds max ($maxFrames)" -ForegroundColor Yellow

    # Use blur_detector.py's limit function
    $limitArgs = @(
        $blurScript,
        $imagesDir,
        "--analyze",
        "--limit-frames",
        "--max-frames", $maxFrames
    )

    Write-Host "  Limiting frames to $maxFrames..." -ForegroundColor Cyan
    & $pythonExe $limitArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Frame limiting failed" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Frame count within limit ($totalFrames <= $maxFrames)" -ForegroundColor Green
}

# Final count
$wCount = 0
$zCount = 0
$singleCount = 0
if (Test-Path -LiteralPath $wImagesDir) {
    $wCount = (Get-ChildItem -LiteralPath $wImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if (Test-Path -LiteralPath $zImagesDir) {
    $zCount = (Get-ChildItem -LiteralPath $zImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}
if ($singleVideoMode -and (Test-Path -LiteralPath $singleImagesDir)) {
    $singleCount = (Get-ChildItem -LiteralPath $singleImagesDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") }).Count
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 2 Complete" -ForegroundColor Green
if ($singleVideoMode) {
    Write-Host "  Final frame count: Single=$singleCount" -ForegroundColor White
} else {
    Write-Host "  Final frame count: W=$wCount, Z=$zCount" -ForegroundColor White
    Write-Host "  Total: $($wCount + $zCount)" -ForegroundColor White
}
Write-Host "========================================" -ForegroundColor Green

exit 0

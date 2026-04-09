# create_test_dataset.ps1
# Create a small test dataset (30 images) for quick pipeline testing
#
# Extracts 15 evenly-spaced frames from video_W and 15 from video_Z
#
# Usage:
#   .\create_test_dataset.ps1 -SourceScene "C:\postshot_test_data\scene1" -OutputPath "C:\test_data_small"

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceScene,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\test_data_small",

    [Parameter(Mandatory=$false)]
    [int]$FramesPerCamera = 15
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Create Test Dataset" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Source: $SourceScene" -ForegroundColor White
Write-Host "  Output: $OutputPath" -ForegroundColor White
Write-Host "  Frames per camera: $FramesPerCamera" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate source
if (-not (Test-Path -LiteralPath $SourceScene)) {
    Write-Host "ERROR: Source scene not found: $SourceScene" -ForegroundColor Red
    exit 1
}

# Look for images in the output folder of the source scene
$sourceOutputDir = Join-Path $SourceScene "output"
$sourceImagesDir = Join-Path $sourceOutputDir "images"

if (-not (Test-Path -LiteralPath $sourceImagesDir)) {
    Write-Host "ERROR: Source images not found at: $sourceImagesDir" -ForegroundColor Red
    Write-Host "  Run the pipeline on the source scene first, or provide a scene with extracted images" -ForegroundColor Yellow
    exit 1
}

# Find W and Z image directories
$wSourceDir = Join-Path $sourceImagesDir "video_W"
$zSourceDir = Join-Path $sourceImagesDir "video_Z"

$hasW = Test-Path -LiteralPath $wSourceDir
$hasZ = Test-Path -LiteralPath $zSourceDir

if (-not $hasW -and -not $hasZ) {
    Write-Host "ERROR: No video_W or video_Z directories found in: $sourceImagesDir" -ForegroundColor Red
    exit 1
}

# Create output directories
$outputImagesDir = Join-Path $OutputPath "output\images"
$wOutputDir = Join-Path $outputImagesDir "video_W"
$zOutputDir = Join-Path $outputImagesDir "video_Z"

foreach ($dir in @($OutputPath, $outputImagesDir, $wOutputDir, $zOutputDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Copy-UniformSample {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [int]$Count,
        [string]$CameraName
    )

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        Write-Host "  $CameraName : Source not found, skipping" -ForegroundColor Yellow
        return 0
    }

    $images = Get-ChildItem -LiteralPath $SourceDir -File |
        Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG") } |
        Sort-Object Name

    if ($images.Count -eq 0) {
        Write-Host "  $CameraName : No images found, skipping" -ForegroundColor Yellow
        return 0
    }

    Write-Host "  $CameraName : Found $($images.Count) images, selecting $Count..." -ForegroundColor Cyan

    # Calculate indices for uniform sampling
    if ($images.Count -le $Count) {
        $selectedIndices = 0..($images.Count - 1)
    } else {
        $selectedIndices = @()
        for ($i = 0; $i -lt $Count; $i++) {
            $idx = [math]::Floor($i * ($images.Count - 1) / ($Count - 1))
            $selectedIndices += $idx
        }
        $selectedIndices = $selectedIndices | Select-Object -Unique
    }

    # Copy selected images
    $copied = 0
    foreach ($idx in $selectedIndices) {
        $src = $images[$idx]
        $dst = Join-Path $DestDir $src.Name

        Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
        $copied++
    }

    Write-Host "    Copied $copied images" -ForegroundColor Green
    return $copied
}

# Copy uniform samples from each camera
Write-Host ""
Write-Host "--- Copying frames ---" -ForegroundColor Yellow

$wCopied = Copy-UniformSample -SourceDir $wSourceDir -DestDir $wOutputDir -Count $FramesPerCamera -CameraName "video_W"
$zCopied = Copy-UniformSample -SourceDir $zSourceDir -DestDir $zOutputDir -Count $FramesPerCamera -CameraName "video_Z"

$totalCopied = $wCopied + $zCopied

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Test Dataset Created" -ForegroundColor Green
Write-Host "  Location: $OutputPath" -ForegroundColor White
Write-Host "  Total frames: $totalCopied (W=$wCopied, Z=$zCopied)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To test the pipeline, run:" -ForegroundColor Cyan
Write-Host "  .\scripts\run_pipeline.ps1 -ConfigPath config\pipeline.json -ScenePath `"$OutputPath`"" -ForegroundColor White
Write-Host ""

exit 0

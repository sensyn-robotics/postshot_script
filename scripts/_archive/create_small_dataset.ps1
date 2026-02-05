<#
.SYNOPSIS
Create a small dataset (15 W + 15 Z images) for quick COLMAP testing.

.DESCRIPTION
Extracts evenly spaced frames from the full dataset to create a smaller
test set that can be processed quickly (~30 seconds vs minutes).

.PARAMETER ScenePath
Path to the scene folder (contains output/images)

.PARAMETER OutputDir
Output directory for small dataset (default: output_test_small)

.PARAMETER ImagesPerCamera
Number of images to extract per camera (default: 15)
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "output_test_small",

    [Parameter(Mandatory=$false)]
    [int]$ImagesPerCamera = 15
)

# If no scene path provided, use scene1
if (-not $ScenePath) {
    $scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
    $ScenePath = $scenes[0].FullName
}

Write-Host "=== Create Small Dataset ===" -ForegroundColor Cyan
Write-Host "Scene: $ScenePath" -ForegroundColor Yellow
Write-Host "Output: $OutputDir" -ForegroundColor Yellow
Write-Host "Images per camera: $ImagesPerCamera" -ForegroundColor Yellow
Write-Host ""

# Source images directory
$sourceImagesDir = Join-Path $ScenePath 'output\images'
if (-not (Test-Path -LiteralPath $sourceImagesDir)) {
    Write-Host "ERROR: Source images directory not found: $sourceImagesDir" -ForegroundColor Red
    exit 1
}

# Get W and Z images
$wImagesDir = Join-Path $sourceImagesDir 'video_W'
$zImagesDir = Join-Path $sourceImagesDir 'video_Z'

if (-not (Test-Path -LiteralPath $wImagesDir) -or -not (Test-Path -LiteralPath $zImagesDir)) {
    Write-Host "ERROR: video_W or video_Z subdirectory not found" -ForegroundColor Red
    exit 1
}

$wImages = @(Get-ChildItem -LiteralPath $wImagesDir -Filter '*.png' | Sort-Object Name)
$zImages = @(Get-ChildItem -LiteralPath $zImagesDir -Filter '*.png' | Sort-Object Name)

Write-Host "Found $($wImages.Count) W images and $($zImages.Count) Z images" -ForegroundColor Gray

if ($wImages.Count -lt $ImagesPerCamera -or $zImages.Count -lt $ImagesPerCamera) {
    Write-Host "ERROR: Not enough images (need at least $ImagesPerCamera per camera)" -ForegroundColor Red
    exit 1
}

# Calculate step size for even spacing
$wStep = [math]::Floor($wImages.Count / $ImagesPerCamera)
$zStep = [math]::Floor($zImages.Count / $ImagesPerCamera)

Write-Host "W step: every $wStep images" -ForegroundColor Gray
Write-Host "Z step: every $zStep images" -ForegroundColor Gray

# Create output directory structure
$outputPath = Join-Path $ScenePath $OutputDir
$outputImagesPath = Join-Path $outputPath 'images'
$outputWPath = Join-Path $outputImagesPath 'video_W'
$outputZPath = Join-Path $outputImagesPath 'video_Z'

# Clean and create directories
if (Test-Path -LiteralPath $outputPath) {
    Write-Host "Removing existing output directory..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

New-Item -ItemType Directory -Path $outputWPath -Force | Out-Null
New-Item -ItemType Directory -Path $outputZPath -Force | Out-Null

# Copy selected W images
Write-Host ""
Write-Host "Copying W images..." -ForegroundColor Cyan
$copiedW = @()
for ($i = 0; $i -lt $ImagesPerCamera; $i++) {
    $idx = $i * $wStep
    if ($idx -lt $wImages.Count) {
        $src = $wImages[$idx]
        $dst = Join-Path $outputWPath $src.Name
        Copy-Item -LiteralPath $src.FullName -Destination $dst
        $copiedW += $src.Name
        Write-Host "  $($src.Name)" -ForegroundColor Gray
    }
}

# Copy selected Z images
Write-Host ""
Write-Host "Copying Z images..." -ForegroundColor Cyan
$copiedZ = @()
for ($i = 0; $i -lt $ImagesPerCamera; $i++) {
    $idx = $i * $zStep
    if ($idx -lt $zImages.Count) {
        $src = $zImages[$idx]
        $dst = Join-Path $outputZPath $src.Name
        Copy-Item -LiteralPath $src.FullName -Destination $dst
        $copiedZ += $src.Name
        Write-Host "  $($src.Name)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Green
Write-Host "Created small dataset at: $outputPath" -ForegroundColor Green
Write-Host "W images: $($copiedW.Count)" -ForegroundColor Yellow
Write-Host "Z images: $($copiedZ.Count)" -ForegroundColor Yellow
Write-Host "Total: $($copiedW.Count + $copiedZ.Count) images" -ForegroundColor Yellow
Write-Host ""
Write-Host "Images directory: $outputImagesPath" -ForegroundColor Cyan

# Return path for use in other scripts
return $outputImagesPath

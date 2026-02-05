<#
.SYNOPSIS
Run a series of COLMAP registration tests with different settings.

.DESCRIPTION
Creates a small dataset and tests various COLMAP configurations to find
settings that register all images (both W and Z cameras).

.PARAMETER ScenePath
Path to scene folder (optional, defaults to scene1)

.PARAMETER SkipDatasetCreation
Skip creating small dataset (use existing)
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDatasetCreation
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get scene path
if (-not $ScenePath) {
    $scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
    $ScenePath = $scenes[0].FullName
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  COLMAP Registration Test Suite" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scene: $ScenePath" -ForegroundColor Yellow
Write-Host ""

# Step 1: Create small dataset
$smallDatasetPath = Join-Path $ScenePath "output_test_small"
$imagesPath = Join-Path $smallDatasetPath "images"

if (-not $SkipDatasetCreation) {
    Write-Host "=== Creating Small Dataset (15 W + 15 Z) ===" -ForegroundColor Cyan
    & "$scriptDir\create_small_dataset.ps1" -ScenePath $ScenePath -OutputDir "output_test_small" -ImagesPerCamera 15
    Write-Host ""
}

if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "ERROR: Small dataset not found at $imagesPath" -ForegroundColor Red
    Write-Host "Run without -SkipDatasetCreation to create it" -ForegroundColor Yellow
    exit 1
}

# Results collection
$results = @()

# Define test configurations
$tests = @(
    # Test 1: Baseline (current settings)
    @{
        Name = "baseline"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 50
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    },

    # Test 2: Relaxed init_min_num_inliers
    @{
        Name = "relaxed_init_30"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    },

    # Test 3: More relaxed init (15)
    @{
        Name = "relaxed_init_15"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 15
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    },

    # Test 4: Very relaxed all thresholds
    @{
        Name = "very_relaxed"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 10
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.05
        InitMaxError = 8
        MultipleModels = 1
    },

    # Test 5: SIMPLE_RADIAL camera model
    @{
        Name = "simple_radial"
        CameraModel = "SIMPLE_RADIAL"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 50
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    },

    # Test 6: SIMPLE_RADIAL with relaxed settings
    @{
        Name = "simple_radial_relaxed"
        CameraModel = "SIMPLE_RADIAL"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 15
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.05
        InitMaxError = 8
        MultipleModels = 1
    },

    # Test 7: Force single model
    @{
        Name = "single_model"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 10
        AbsPoseMinInlierRatio = 0.1
        InitMaxError = 8
        MultipleModels = 0
    },

    # Test 8: Single camera for all images (not per folder)
    @{
        Name = "single_camera_all"
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 0
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 10
        AbsPoseMinInlierRatio = 0.1
        InitMaxError = 8
        MultipleModels = 1
    }
)

# Run each test
foreach ($test in $tests) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Magenta
    Write-Host "  Running Test: $($test.Name)" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta

    $outputDir = Join-Path $smallDatasetPath "colmap_$($test.Name)"

    try {
        $result = & "$scriptDir\test_colmap_registration.ps1" `
            -ImageDir $imagesPath `
            -OutputDir $outputDir `
            -TestName $test.Name `
            -CameraModel $test.CameraModel `
            -SingleCameraPerFolder $test.SingleCameraPerFolder `
            -InitMinNumInliers $test.InitMinNumInliers `
            -AbsPoseMinNumInliers $test.AbsPoseMinNumInliers `
            -AbsPoseMinInlierRatio $test.AbsPoseMinInlierRatio `
            -InitMaxError $test.InitMaxError `
            -MultipleModels $test.MultipleModels

        $results += $result
    }
    catch {
        Write-Host "ERROR in test $($test.Name): $_" -ForegroundColor Red
        $results += @{
            TestName = $test.Name
            TotalImages = 0
            RegisteredImages = 0
            WImages = 0
            ZImages = 0
            ElapsedSeconds = 0
            Success = $false
            Error = $_.ToString()
        }
    }
}

# === Final Summary ===
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  FINAL RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Print table header
$header = "{0,-25} {1,8} {2,8} {3,8} {4,8} {5,8}" -f "Test", "Total", "Reg", "W", "Z", "Time(s)"
Write-Host $header -ForegroundColor White
Write-Host ("-" * 75) -ForegroundColor Gray

foreach ($r in $results) {
    $color = if ($r.Success) { 'Green' } elseif ($r.ZImages -gt 0) { 'Yellow' } else { 'Red' }
    $row = "{0,-25} {1,8} {2,8} {3,8} {4,8} {5,8:F1}" -f $r.TestName, $r.TotalImages, $r.RegisteredImages, $r.WImages, $r.ZImages, $r.ElapsedSeconds
    Write-Host $row -ForegroundColor $color
}

Write-Host ""

# Find best result
$bestResult = $results | Sort-Object -Property @{Expression={$_.ZImages}; Descending=$true}, @{Expression={$_.RegisteredImages}; Descending=$true} | Select-Object -First 1

if ($bestResult.ZImages -gt 0) {
    Write-Host "BEST RESULT: $($bestResult.TestName)" -ForegroundColor Green
    Write-Host "  Registered $($bestResult.RegisteredImages) images ($($bestResult.WImages) W, $($bestResult.ZImages) Z)" -ForegroundColor Green
} else {
    Write-Host "NO TEST REGISTERED Z IMAGES" -ForegroundColor Red
    Write-Host "Consider trying:" -ForegroundColor Yellow
    Write-Host "  1. Different camera models" -ForegroundColor Yellow
    Write-Host "  2. Lower resolution images" -ForegroundColor Yellow
    Write-Host "  3. Manual feature matching inspection" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Test outputs saved to: $smallDatasetPath" -ForegroundColor Cyan

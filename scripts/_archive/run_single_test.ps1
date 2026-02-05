# Run a single COLMAP registration test
param(
    [Parameter(Mandatory=$false)]
    [string]$TestName = "baseline"
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get scene path
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$ScenePath = $scenes[0].FullName

$smallDatasetPath = Join-Path $ScenePath "output_test_small"
$imagesPath = Join-Path $smallDatasetPath "images"

# Define test configurations
$tests = @{
    "baseline" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 50
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    }
    "relaxed_init_30" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    }
    "very_relaxed" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 10
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.05
        InitMaxError = 8
        MultipleModels = 1
    }
    "simple_radial" = @{
        CameraModel = "SIMPLE_RADIAL"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 50
        AbsPoseMinNumInliers = 15
        AbsPoseMinInlierRatio = 0.15
        InitMaxError = 4
        MultipleModels = 1
    }
    "simple_radial_relaxed" = @{
        CameraModel = "SIMPLE_RADIAL"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 15
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.05
        InitMaxError = 8
        MultipleModels = 1
    }
    "single_model" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 10
        AbsPoseMinInlierRatio = 0.1
        InitMaxError = 8
        MultipleModels = 0
    }
    "single_camera_all" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 0
        InitMinNumInliers = 30
        AbsPoseMinNumInliers = 10
        AbsPoseMinInlierRatio = 0.1
        InitMaxError = 8
        MultipleModels = 1
    }
    # New tests for cross-camera registration
    "cross_camera_focus" = @{
        CameraModel = "OPENCV"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 15  # Very low to allow W-Z initial pairs
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.02  # Very low ratio
        InitMaxError = 16  # Higher error tolerance
        MultipleModels = 0  # Force single model
    }
    "pinhole_relaxed" = @{
        CameraModel = "PINHOLE"
        SingleCameraPerFolder = 1
        InitMinNumInliers = 15
        AbsPoseMinNumInliers = 5
        AbsPoseMinInlierRatio = 0.05
        InitMaxError = 12
        MultipleModels = 0
    }
}

if (-not $tests.ContainsKey($TestName)) {
    Write-Host "Available tests:" -ForegroundColor Yellow
    $tests.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$test = $tests[$TestName]
$outputDir = Join-Path $smallDatasetPath "colmap_$TestName"

& "$scriptDir\test_colmap_registration.ps1" `
    -ImageDir $imagesPath `
    -OutputDir $outputDir `
    -TestName $TestName `
    -CameraModel $test.CameraModel `
    -SingleCameraPerFolder $test.SingleCameraPerFolder `
    -InitMinNumInliers $test.InitMinNumInliers `
    -AbsPoseMinNumInliers $test.AbsPoseMinNumInliers `
    -AbsPoseMinInlierRatio $test.AbsPoseMinInlierRatio `
    -InitMaxError $test.InitMaxError `
    -MultipleModels $test.MultipleModels

<#
.SYNOPSIS
Test improved COLMAP settings on the full dataset.

.DESCRIPTION
Runs COLMAP with relaxed settings on all 254 images to verify improved registration.
#>
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get scene path
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$ScenePath = $scenes[0].FullName

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Full Dataset Registration Test (Improved Settings)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scene: $ScenePath" -ForegroundColor Yellow

$imagesPath = Join-Path $ScenePath 'output\images'
$outputPath = Join-Path $ScenePath 'output_improved_registration'

# Clean previous output
if (Test-Path -LiteralPath $outputPath) {
    Write-Host "Removing previous output..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

# Run test with relaxed settings
& "$scriptDir\test_colmap_registration.ps1" `
    -ImageDir $imagesPath `
    -OutputDir $outputPath `
    -TestName "improved_full" `
    -CameraModel "OPENCV" `
    -SingleCameraPerFolder 1 `
    -InitMinNumInliers 15 `
    -AbsPoseMinNumInliers 5 `
    -AbsPoseMinInlierRatio 0.05 `
    -InitMaxError 8 `
    -MultipleModels 1

Write-Host ""
Write-Host "Output saved to: $outputPath" -ForegroundColor Cyan

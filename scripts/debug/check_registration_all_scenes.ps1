<#
.SYNOPSIS
    Check COLMAP registration counts for all scenes.

.DESCRIPTION
    Analyzes all scenes in test_data_path to check:
    - Total images (W + Z)
    - Registered images in COLMAP sparse model
    - W vs Z camera registration breakdown
    - Registration percentage

.PARAMETER ConfigPath
    Path to pipeline config JSON (default: config/pipeline.json)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "config\pipeline.json"
)

$ErrorActionPreference = "Stop"

# Get script root (go up from scripts/debug to project root)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptDir
$scriptRoot = Split-Path -Parent $scriptsDir
Set-Location $scriptRoot

# Load config
$configFullPath = Join-Path $scriptRoot $ConfigPath
if (-not (Test-Path -LiteralPath $configFullPath)) {
    Write-Host "ERROR: Config not found: $configFullPath" -ForegroundColor Red
    exit 1
}
$config = Get-Content -LiteralPath $configFullPath -Raw | ConvertFrom-Json
$testDataPath = $config.pipeline.test_data_path

# Use Python from PATH (more reliable than hardcoded path with Japanese chars)
$pythonPath = "python"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "COLMAP Registration Analysis" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get all scene directories
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name

$results = @()

foreach ($scene in $scenes) {
    $scenePath = $scene.FullName
    $sceneName = $scene.Name
    $outputDir = Join-Path $scenePath "output"
    $imagesDir = Join-Path $outputDir "images"
    $colmapDir = Join-Path $outputDir "colmap"
    $sparseDir = Join-Path $colmapDir "sparse"

    Write-Host "Checking: $sceneName" -ForegroundColor Yellow

    # Count total images
    $wImagesDir = Join-Path $imagesDir "video_W"
    $zImagesDir = Join-Path $imagesDir "video_Z"

    $wTotal = 0
    $zTotal = 0

    if (Test-Path -LiteralPath $wImagesDir) {
        $wTotal = (Get-ChildItem -LiteralPath $wImagesDir -Filter "*.png" | Measure-Object).Count
    }
    if (Test-Path -LiteralPath $zImagesDir) {
        $zTotal = (Get-ChildItem -LiteralPath $zImagesDir -Filter "*.png" | Measure-Object).Count
    }

    $totalImages = $wTotal + $zTotal

    # Check for sparse reconstructions
    $wRegistered = 0
    $zRegistered = 0
    $totalRegistered = 0
    $points3D = 0
    $numCameras = 0
    $reconstructionInfo = "N/A"

    if (Test-Path -LiteralPath $sparseDir) {
        # Find all reconstruction folders (0, 1, 2, etc.)
        $recons = Get-ChildItem -LiteralPath $sparseDir -Directory | Sort-Object { [int]$_.Name }

        if ($recons.Count -gt 0) {
            # Use largest reconstruction (most images)
            $bestRecon = $null
            $bestCount = 0

            foreach ($recon in $recons) {
                $imagesPath = Join-Path $recon.FullName "images.bin"
                if (Test-Path -LiteralPath $imagesPath) {
                    # Quick check - use Python to get counts
                    $tempOutput = & $pythonPath -c @"
import sys
sys.path.insert(0, r'$scriptRoot\scripts')
from read_colmap_model import read_images_binary, read_points3D_binary, read_cameras_binary
import os

sparse_path = r'$($recon.FullName)'
images_path = os.path.join(sparse_path, 'images.bin')
points_path = os.path.join(sparse_path, 'points3D.bin')
cameras_path = os.path.join(sparse_path, 'cameras.bin')

images = read_images_binary(images_path)
points = read_points3D_binary(points_path)
cameras = read_cameras_binary(cameras_path)

w_count = len([i for i in images.values() if 'video_W' in i['name']])
z_count = len([i for i in images.values() if 'video_Z' in i['name']])

print(f'{len(images)}|{w_count}|{z_count}|{len(points)}|{len(cameras)}')
"@ 2>&1

                    if ($LASTEXITCODE -eq 0 -and $tempOutput -match '^\d+\|') {
                        $parts = $tempOutput.Split('|')
                        $count = [int]$parts[0]
                        if ($count -gt $bestCount) {
                            $bestCount = $count
                            $bestRecon = $recon
                            $totalRegistered = $count
                            $wRegistered = [int]$parts[1]
                            $zRegistered = [int]$parts[2]
                            $points3D = [int]$parts[3]
                            $numCameras = [int]$parts[4]
                        }
                    }
                }
            }

            if ($recons.Count -gt 1) {
                $reconstructionInfo = "$($recons.Count) models (using largest)"
            } else {
                $reconstructionInfo = "1 model"
            }
        }
    }

    # Calculate percentages
    $wPct = if ($wTotal -gt 0) { [math]::Round(($wRegistered / $wTotal) * 100, 1) } else { 0 }
    $zPct = if ($zTotal -gt 0) { [math]::Round(($zRegistered / $zTotal) * 100, 1) } else { 0 }
    $totalPct = if ($totalImages -gt 0) { [math]::Round(($totalRegistered / $totalImages) * 100, 1) } else { 0 }

    $result = [PSCustomObject]@{
        Scene = $sceneName.Substring(0, [Math]::Min(20, $sceneName.Length))
        TotalImages = $totalImages
        Registered = $totalRegistered
        "Reg%" = "$totalPct%"
        WTotal = $wTotal
        WReg = $wRegistered
        "W%" = "$wPct%"
        ZTotal = $zTotal
        ZReg = $zRegistered
        "Z%" = "$zPct%"
        Points3D = $points3D
        Cameras = $numCameras
    }

    $results += $result
}

# Display results as table
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Registration Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results | Format-Table -AutoSize

# Detailed analysis
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Detailed Analysis" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

foreach ($r in $results) {
    $status = if ([double]($r."Z%" -replace '%','') -lt 10) {
        "Z NOT REGISTERED"
    } elseif ([double]($r."Z%" -replace '%','') -lt 50) {
        "Z PARTIALLY REGISTERED"
    } else {
        "OK"
    }

    $statusColor = switch ($status) {
        "Z NOT REGISTERED" { "Red" }
        "Z PARTIALLY REGISTERED" { "Yellow" }
        "OK" { "Green" }
    }

    Write-Host "$($r.Scene): " -NoNewline
    Write-Host $status -ForegroundColor $statusColor
    Write-Host "  Total: $($r.Registered)/$($r.TotalImages) ($($r."Reg%"))"
    Write-Host "  W camera: $($r.WReg)/$($r.WTotal) ($($r."W%"))"
    Write-Host "  Z camera: $($r.ZReg)/$($r.ZTotal) ($($r."Z%"))"
    Write-Host "  3D points: $($r.Points3D)"
    Write-Host ""
}

# Overall summary
$totalW = ($results | Measure-Object -Property WReg -Sum).Sum
$totalZ = ($results | Measure-Object -Property ZReg -Sum).Sum
$totalAll = ($results | Measure-Object -Property Registered -Sum).Sum
$totalImages = ($results | Measure-Object -Property TotalImages -Sum).Sum

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Overall Statistics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total images across all scenes: $totalImages"
Write-Host "Total registered: $totalAll ($([math]::Round($totalAll / $totalImages * 100, 1))%)"
Write-Host "Total W registered: $totalW"
Write-Host "Total Z registered: $totalZ"

if ($totalZ -eq 0) {
    Write-Host "`nDIAGNOSIS: Z camera is NOT being registered at all!" -ForegroundColor Red
    Write-Host "This explains the poor 3DGS quality - only W camera data is being used." -ForegroundColor Red
} elseif ($totalZ -lt $totalW * 0.5) {
    Write-Host "`nDIAGNOSIS: Z camera registration is very low!" -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Generate COLMAP and PLY visualizations for all scenes.

.DESCRIPTION
    Creates visualization images for each scene:
    - COLMAP sparse point cloud (4-view composite)
    - Postshot PLY (4 separate view images)

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
Write-Host "Visualization Generation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get all scene directories
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name

foreach ($scene in $scenes) {
    $scenePath = $scene.FullName
    $sceneName = $scene.Name
    $outputDir = Join-Path $scenePath "output"
    $colmapDir = Join-Path $outputDir "colmap"
    $sparseDir = Join-Path $colmapDir "sparse"
    $postshotDir = Join-Path $outputDir "postshot"
    $vizDir = Join-Path $outputDir "visualizations"

    Write-Host "Processing: $sceneName" -ForegroundColor Yellow

    # Create visualizations directory
    if (-not (Test-Path -LiteralPath $vizDir)) {
        New-Item -ItemType Directory -Path $vizDir -Force | Out-Null
    }

    # 1. COLMAP sparse visualization
    if (Test-Path -LiteralPath $sparseDir) {
        # Find best reconstruction (most images)
        $recons = Get-ChildItem -LiteralPath $sparseDir -Directory | Sort-Object { [int]$_.Name }

        if ($recons.Count -gt 0) {
            # Use reconstruction 0 (usually the largest)
            $bestRecon = $recons[0].FullName
            $colmapOutput = Join-Path $vizDir "colmap_sparse.png"

            # Truncate scene name for title
            $shortName = $sceneName.Substring(0, [Math]::Min(25, $sceneName.Length))

            Write-Host "  Rendering COLMAP sparse..." -ForegroundColor Gray
            $result = & $pythonPath "$scriptRoot\scripts\render_pointcloud.py" `
                $bestRecon `
                $colmapOutput `
                --title "COLMAP: $shortName" 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "    Created: colmap_sparse.png" -ForegroundColor Green
            } else {
                Write-Host "    Failed to render COLMAP" -ForegroundColor Red
                Write-Host "    $result" -ForegroundColor Red
            }
        } else {
            Write-Host "  No COLMAP reconstruction found" -ForegroundColor Red
        }
    } else {
        Write-Host "  No sparse directory found" -ForegroundColor Red
    }

    # 2. Postshot PLY visualization
    $plyPath = Join-Path $postshotDir "scene.ply"
    if (Test-Path -LiteralPath $plyPath) {
        Write-Host "  Rendering Postshot PLY..." -ForegroundColor Gray
        $result = & $pythonPath "$scriptRoot\scripts\render_checkpoint.py" `
            $plyPath `
            $vizDir `
            "final" 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Created: checkpoint_final_view1-4.png" -ForegroundColor Green
        } else {
            Write-Host "    Failed to render PLY" -ForegroundColor Red
            Write-Host "    $result" -ForegroundColor Red
        }
    } else {
        Write-Host "  No scene.ply found at: $plyPath" -ForegroundColor Red
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Visualization Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# List all generated visualizations
Write-Host "Generated files:" -ForegroundColor Green
foreach ($scene in $scenes) {
    $vizDir = Join-Path $scene.FullName "output\visualizations"
    if (Test-Path -LiteralPath $vizDir) {
        $files = Get-ChildItem -LiteralPath $vizDir -Filter "*.png" | Select-Object -ExpandProperty Name
        if ($files) {
            Write-Host "  $($scene.Name):" -ForegroundColor Cyan
            foreach ($f in $files) {
                Write-Host "    - $f"
            }
        }
    }
}

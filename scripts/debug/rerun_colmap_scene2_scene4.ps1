<#
.SYNOPSIS
    Re-run COLMAP stages 3-5 for Scene 2 and Scene 4 with overwrite enabled.
#>

$ErrorActionPreference = "Stop"

# Get script root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptDir
$scriptRoot = Split-Path -Parent $scriptsDir
Set-Location $scriptRoot

$configPath = "config\pipeline_overwrite.json"
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$testDataPath = $config.pipeline.test_data_path

# Get all scenes
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name

# Scene 2 (index 1) and Scene 4 (index 3)
$scenesToProcess = @($scenes[1], $scenes[3])

foreach ($scene in $scenesToProcess) {
    $scenePath = $scene.FullName
    $sceneName = $scene.Name

    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  Processing: $sceneName" -ForegroundColor Magenta
    Write-Host "  Path: $scenePath" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    # Run stages 3-5
    Write-Host "`nRunning Stage 3: Feature Extraction..." -ForegroundColor Cyan
    & "$scriptRoot\scripts\stages\03_colmap_features.ps1" -ConfigPath $configPath -ScenePath $scenePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Stage 3 failed for $sceneName" -ForegroundColor Red
        continue
    }

    Write-Host "`nRunning Stage 4: Feature Matching..." -ForegroundColor Cyan
    & "$scriptRoot\scripts\stages\04_colmap_matching.ps1" -ConfigPath $configPath -ScenePath $scenePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Stage 4 failed for $sceneName" -ForegroundColor Red
        continue
    }

    Write-Host "`nRunning Stage 5: Mapper..." -ForegroundColor Cyan
    & "$scriptRoot\scripts\stages\05_colmap_mapper.ps1" -ConfigPath $configPath -ScenePath $scenePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Stage 5 failed for $sceneName" -ForegroundColor Red
        continue
    }

    Write-Host "`n$sceneName completed successfully!" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  All scenes processed" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

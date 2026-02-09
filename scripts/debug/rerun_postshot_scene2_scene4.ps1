<#
.SYNOPSIS
    Re-run Postshot stages 6-7 for Scene 2 and Scene 4.
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

    # Run stages 6-7
    Write-Host "`nRunning Stage 6: Postshot Training..." -ForegroundColor Cyan
    & "$scriptRoot\scripts\stages\06_postshot_train.ps1" -ConfigPath $configPath -ScenePath $scenePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Stage 6 failed for $sceneName" -ForegroundColor Red
        continue
    }

    Write-Host "`nRunning Stage 7: Postshot Export..." -ForegroundColor Cyan
    & "$scriptRoot\scripts\stages\07_postshot_export.ps1" -ConfigPath $configPath -ScenePath $scenePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Stage 7 failed for $sceneName" -ForegroundColor Red
        continue
    }

    Write-Host "`n$sceneName completed successfully!" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  All scenes processed" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

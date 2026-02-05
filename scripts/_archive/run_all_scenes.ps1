# run_all_scenes.ps1
# Run all scenes with 0.5fps configuration (proven working settings)
#
# This script runs the pipeline on all scenes in the test data directory
# using the default 0.5fps extraction rate which produces good results.

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDataPath = "C:\postshot_test_data",

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "output",

    [Parameter(Mandatory=$false)]
    [int[]]$SceneNumbers,

    [Parameter(Mandatory=$false)]
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$configDir = Join-Path $repoRoot "config"

# Dynamically discover scenes
$sceneDirectories = @()
if (Test-Path -LiteralPath $TestDataPath) {
    $sceneDirectories = Get-ChildItem -LiteralPath $TestDataPath -Directory | Sort-Object Name
}

$scenes = @()
$sceneNum = 1
foreach ($dir in $sceneDirectories) {
    $scenes += @{
        Number = $sceneNum
        Name = $dir.Name
        FullPath = $dir.FullName
    }
    $sceneNum++
}

# Filter scenes if specific numbers requested
if ($SceneNumbers) {
    $scenes = $scenes | Where-Object { $_.Number -in $SceneNumbers }
}

Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "#   Run All Scenes - 0.5fps Pipeline                   #" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
Write-Host "  Test data path:   $TestDataPath" -ForegroundColor Gray
Write-Host "  Output directory: $OutputDir" -ForegroundColor Gray
Write-Host "  Scenes to run:    $($scenes.Count)" -ForegroundColor Gray
if ($SkipExisting) {
    Write-Host "  Skip existing:    Yes" -ForegroundColor Yellow
}
Write-Host ""

# Check test data path
if (-not (Test-Path -LiteralPath $TestDataPath)) {
    Write-Host "ERROR: Test data path not found: $TestDataPath" -ForegroundColor Red
    exit 1
}

if ($scenes.Count -eq 0) {
    Write-Host "ERROR: No scenes found in $TestDataPath" -ForegroundColor Red
    exit 1
}

# List scenes
Write-Host "Scenes:" -ForegroundColor Cyan
foreach ($scene in $scenes) {
    Write-Host "  $($scene.Number). $($scene.Name)" -ForegroundColor Gray
}
Write-Host ""

# Results tracking
$results = @()
$startTimeTotal = Get-Date

foreach ($scene in $scenes) {
    $scenePath = $scene.FullPath
    $sceneOutputPath = Join-Path $scenePath $OutputDir

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  Scene $($scene.Number): $($scene.Name)" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # Check if we should skip
    if ($SkipExisting) {
        $pshtPath = Join-Path $sceneOutputPath "scene.psht"
        if (Test-Path $pshtPath) {
            Write-Host "  Skipping - output already exists" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Scene = $scene.Number
                Name = $scene.Name
                Status = "SKIPPED"
                Reason = "Output exists"
                Duration = "00:00:00"
            }
            continue
        }
    }

    $sceneStartTime = Get-Date

    try {
        # Run the pipeline
        Write-Host "  Running pipeline..." -ForegroundColor Gray

        & "$scriptDir\run_pipeline_exhaustive.ps1" `
            -InputPath $scenePath `
            -OutputDir $OutputDir

        $exitCode = $LASTEXITCODE
        $sceneEndTime = Get-Date
        $sceneDuration = $sceneEndTime - $sceneStartTime

        # Check results
        $pshtPath = Join-Path $sceneOutputPath "scene.psht"
        $plyPath = Join-Path $sceneOutputPath "scene.ply"

        if ($exitCode -eq 0 -and (Test-Path $pshtPath)) {
            $status = "SUCCESS"
            Write-Host "  SUCCESS ($($sceneDuration.ToString('hh\:mm\:ss')))" -ForegroundColor Green
        } else {
            $status = "FAILED"
            Write-Host "  FAILED (exit code: $exitCode)" -ForegroundColor Red
        }

        $results += [PSCustomObject]@{
            Scene = $scene.Number
            Name = $scene.Name
            Status = $status
            Reason = if ($status -eq "FAILED") { "Exit code $exitCode" } else { $null }
            Duration = $sceneDuration.ToString('hh\:mm\:ss')
            PshtExists = (Test-Path $pshtPath)
            PlyExists = (Test-Path $plyPath)
        }
    }
    catch {
        $sceneEndTime = Get-Date
        $sceneDuration = $sceneEndTime - $sceneStartTime

        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red

        $results += [PSCustomObject]@{
            Scene = $scene.Number
            Name = $scene.Name
            Status = "FAILED"
            Reason = $_.Exception.Message
            Duration = $sceneDuration.ToString('hh\:mm\:ss')
        }
    }
}

$endTimeTotal = Get-Date
$totalDuration = $endTimeTotal - $startTimeTotal

# Summary
Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host "#                    Summary                           #" -ForegroundColor Magenta
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host ""

$results | Format-Table -Property Scene, Name, Status, Duration -AutoSize

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  Total scenes:  $($results.Count)" -ForegroundColor Gray
Write-Host "  Successful:    $successCount" -ForegroundColor Green
Write-Host "  Failed:        $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped:       $skippedCount" -ForegroundColor $(if ($skippedCount -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""
Write-Host "Total duration: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta

# Export results
$resultsPath = Join-Path $TestDataPath "pipeline_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $resultsPath -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $resultsPath" -ForegroundColor Gray

if ($failedCount -gt 0) {
    exit 1
} else {
    exit 0
}

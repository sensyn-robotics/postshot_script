# Run remaining scenes (2, 3, 4) with 0.5fps configuration
# Scene 1 is already complete in output/ directory
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "#   Run Remaining Scenes (2, 3, 4) - 0.5fps            #" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host ""

# Find all scenes
$testDataPath = "C:\postshot_test_data"
$sceneDirectories = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name

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

Write-Host "Found $($scenes.Count) scenes:" -ForegroundColor Cyan
foreach ($scene in $scenes) {
    $outputDir = Join-Path $scene.FullPath "output"
    $pshtPath = Join-Path $outputDir "scene.psht"
    $status = if (Test-Path $pshtPath) { "[COMPLETE]" } else { "[PENDING]" }
    Write-Host "  $($scene.Number). $($scene.Name) $status"
}
Write-Host ""

# Results tracking
$results = @()
$startTimeTotal = Get-Date

# Process scenes 2, 3, 4 (skip scene 1 which is complete)
foreach ($scene in $scenes) {
    if ($scene.Number -eq 1) {
        Write-Host "Skipping Scene 1 (already complete)" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Scene = 1
            Name = $scene.Name
            Status = "SKIPPED"
            Reason = "Already complete"
            Duration = "00:00:00"
        }
        continue
    }

    $scenePath = $scene.FullPath
    $outputDir = Join-Path $scenePath "output"
    $pshtPath = Join-Path $outputDir "scene.psht"

    # Check if already complete
    if (Test-Path $pshtPath) {
        Write-Host ""
        Write-Host "Scene $($scene.Number): Already complete, skipping" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Scene = $scene.Number
            Name = $scene.Name
            Status = "SKIPPED"
            Reason = "Already complete"
            Duration = "00:00:00"
        }
        continue
    }

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  Scene $($scene.Number): $($scene.Name)" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    $sceneStartTime = Get-Date

    try {
        # Run the pipeline
        Write-Host "  Running pipeline..." -ForegroundColor Gray

        & "$scriptDir\scripts\run_pipeline_exhaustive.ps1" `
            -InputPath $scenePath `
            -OutputDir "output"

        $exitCode = $LASTEXITCODE
        $sceneEndTime = Get-Date
        $sceneDuration = $sceneEndTime - $sceneStartTime

        # Check results
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
$resultsPath = Join-Path $testDataPath "pipeline_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $resultsPath -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $resultsPath" -ForegroundColor Gray

if ($failedCount -gt 0) {
    exit 1
} else {
    exit 0
}

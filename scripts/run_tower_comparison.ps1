# run_tower_comparison.ps1
# Runs sequential (all scenes) then exhaustive (all scenes) for comparison
# Results are saved to separate output dirs (output_sequential, output_exhaustive)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $PSScriptRoot "run_pipeline_single.ps1"
$seqConfig = Join-Path $projectRoot "config\pipeline_tower_sequential.json"
$exhConfig = Join-Path $projectRoot "config\pipeline_tower_exhaustive.json"
$towerDataPath = "C:\postshot_script\data\tower"

Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host "#  Tower Comparison: Sequential vs Exhaustive           #" -ForegroundColor Magenta
Write-Host "#  All 3 scenes with both matchers                     #" -ForegroundColor Magenta
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Sequential config: $seqConfig (output_sequential/)" -ForegroundColor White
Write-Host "  Exhaustive config: $exhConfig (output_exhaustive/)" -ForegroundColor White
Write-Host ""

$totalStart = Get-Date

# --- Run 1: Sequential on All Scenes (faster) ---
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  RUN 1: Sequential Matcher - All 3 Scenes" -ForegroundColor Cyan
Write-Host "  (loop_detection + guided_matching enabled)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$seqStart = Get-Date
& $runner -ConfigPath $seqConfig
$seqDuration = (Get-Date) - $seqStart

Write-Host ""
Write-Host "  Sequential run completed in $($seqDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host ""

# --- Run 2: Exhaustive on All Scenes ---
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  RUN 2: Exhaustive Matcher - All 3 Scenes" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$exhStart = Get-Date
& $runner -ConfigPath $exhConfig
$exhDuration = (Get-Date) - $exhStart

Write-Host ""
Write-Host "  Exhaustive run completed in $($exhDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

# --- Summary ---
$totalDuration = (Get-Date) - $totalStart

Write-Host ""
Write-Host "########################################################" -ForegroundColor Green
Write-Host "#  ALL RUNS COMPLETE" -ForegroundColor Green
Write-Host "#  Sequential (3 scenes): $($seqDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "#  Exhaustive (3 scenes): $($exhDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "#  Total: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host "########################################################" -ForegroundColor Green

# Print timing log comparison
Write-Host ""
Write-Host "  Timing logs:" -ForegroundColor White
$scenes = Get-ChildItem -LiteralPath $towerDataPath -Directory | Sort-Object Name
foreach ($scene in $scenes) {
    Write-Host "  $($scene.Name):" -ForegroundColor White
    $seqTiming = Join-Path $scene.FullName "output_sequential\timing.json"
    $exhTiming = Join-Path $scene.FullName "output_exhaustive\timing.json"
    if (Test-Path -LiteralPath $seqTiming) {
        Write-Host "    [SEQ] $seqTiming" -ForegroundColor Cyan
    }
    if (Test-Path -LiteralPath $exhTiming) {
        Write-Host "    [EXH] $exhTiming" -ForegroundColor Yellow
    }
}

# Run pipeline for all scenes with SIMPLE_RADIAL
param([int]$StartScene = 0)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pipelineScript = Join-Path $scriptDir "run_pipeline_exhaustive.ps1"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name

Write-Host "=== Running SIMPLE_RADIAL Pipeline for All Scenes ===" -ForegroundColor Cyan
Write-Host "Total scenes: $($scenes.Count)" -ForegroundColor Gray
Write-Host ""

for ($i = $StartScene; $i -lt $scenes.Count; $i++) {
    $scene = $scenes[$i]
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Scene $($i + 1) of $($scenes.Count): $($scene.Name)" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    $params = @{
        InputPath = $scene.FullName
        OutputDir = "output_simple_radial"
    }
    & $pipelineScript @params

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Scene $($i + 1) failed" -ForegroundColor Yellow
    } else {
        Write-Host "Scene $($i + 1) completed successfully" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== All Scenes Complete ===" -ForegroundColor Green

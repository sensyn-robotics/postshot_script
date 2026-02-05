# run_scene1_02fps.ps1
# Test 0.2 FPS extraction on scene1 with separate output directory
#
# This script runs the pipeline on scene1 with 0.2fps to compare with 0.5fps results.
# Results are stored in output_0.2fps to avoid overwriting existing 0.5fps results.

param(
    [Parameter(Mandatory=$false)]
    [string]$ScenePath
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$configDir = Join-Path $repoRoot "config"

# Scene 1 path - use parameter or find first directory in test data
if (-not $ScenePath) {
    $testDataPath = "C:\postshot_test_data"
    if (Test-Path $testDataPath) {
        # Get first scene directory (scene 1)
        $scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
        if ($scenes.Count -gt 0) {
            $ScenePath = $scenes[0].FullName
        }
    }
}

$scene1Path = $ScenePath

# Check if scene exists
if (-not $scene1Path -or -not (Test-Path -LiteralPath $scene1Path)) {
    Write-Host "ERROR: Scene 1 not found. Please provide -ScenePath parameter." -ForegroundColor Red
    Write-Host "Usage: .\run_scene1_02fps.ps1 -ScenePath 'C:\path\to\scene'" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Scene 1 - 0.2 FPS Test" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Input: $scene1Path" -ForegroundColor Cyan
Write-Host "  Config: config_0.2fps.json" -ForegroundColor Cyan
Write-Host "  Output: output_0.2fps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Run the pipeline with 0.2fps config and separate output directory
& "$scriptDir\run_pipeline_exhaustive.ps1" `
    -InputPath $scene1Path `
    -ConfigPath "$configDir\config_0.2fps.json" `
    -OutputDir "output_0.2fps"

$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: 0.2fps test completed" -ForegroundColor Green
    Write-Host "  Results in: $scene1Path\output_0.2fps" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "FAILED: 0.2fps test failed with exit code $exitCode" -ForegroundColor Red
}

exit $exitCode

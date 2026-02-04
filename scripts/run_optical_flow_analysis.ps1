# run_optical_flow_analysis.ps1
# PowerShell wrapper for optical flow analysis and keyframe selection
#
# This script runs the Python optical flow analyzer on extracted frames.

param(
    [Parameter(Mandatory=$true)]
    [string]$ImagesDir,

    [Parameter(Mandatory=$false)]
    [switch]$Analyze,

    [Parameter(Mandatory=$false)]
    [switch]$SelectKeyframes,

    [Parameter(Mandatory=$false)]
    [double]$TargetOverlap = 99.0,  # Based on 0.5fps analysis: 98.8% overlap

    [Parameter(Mandatory=$false)]
    [switch]$RemoveNonKeyframes,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [string]$Camera
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Optical Flow Analysis" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Images: $ImagesDir" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if images directory exists
if (-not (Test-Path -LiteralPath $ImagesDir)) {
    Write-Host "ERROR: Images directory not found: $ImagesDir" -ForegroundColor Red
    exit 1
}

# Build Python arguments
$pythonScript = Join-Path $scriptDir "optical_flow_analyzer.py"
$pythonArgs = @($pythonScript, $ImagesDir)

if ($Analyze) {
    $pythonArgs += "--analyze"
}

if ($SelectKeyframes) {
    $pythonArgs += "--select-keyframes"
    $pythonArgs += "--target-overlap"
    $pythonArgs += $TargetOverlap.ToString()
}

if ($RemoveNonKeyframes) {
    $pythonArgs += "--remove-non-keyframes"
}

if ($DryRun) {
    $pythonArgs += "--dry-run"
}

if ($Camera) {
    $pythonArgs += "--camera"
    $pythonArgs += $Camera
}

# Run Python script
Write-Host "Running: python $($pythonArgs -join ' ')" -ForegroundColor Gray
$output = & python @pythonArgs 2>&1
$exitCode = $LASTEXITCODE

# Output results
foreach ($line in $output) {
    Write-Host $line
}

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Optical flow analysis failed with exit code $exitCode" -ForegroundColor Red
    exit $exitCode
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Analysis complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

exit 0

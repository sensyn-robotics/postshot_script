# Debug: Test single scene to verify Unicode path handling fix
# Usage: .\debug_test_single_scene.ps1

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug: Single Scene Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get first scene
$scenes = @(Get-ChildItem "C:\postshot_test_data" -Directory | Sort-Object Name)
$scene = $scenes[0].FullName
$sceneName = $scenes[0].Name

Write-Host ""
Write-Host "Testing scene: $sceneName" -ForegroundColor Yellow
Write-Host "Full path: $scene" -ForegroundColor Gray

# Check if images exist
$imagesPath = Join-Path $scene "output\images"
$videoW = Join-Path $imagesPath "video_W"
$videoZ = Join-Path $imagesPath "video_Z"

Write-Host ""
Write-Host "Checking existing images..." -ForegroundColor Yellow
Write-Host "  Images path exists: $(Test-Path $imagesPath)" -ForegroundColor Gray
if (Test-Path $videoW) {
    $wCount = (Get-ChildItem -LiteralPath $videoW -Filter "*.png").Count
    Write-Host "  video_W images: $wCount" -ForegroundColor Gray
}
if (Test-Path $videoZ) {
    $zCount = (Get-ChildItem -LiteralPath $videoZ -Filter "*.png").Count
    Write-Host "  video_Z images: $zCount" -ForegroundColor Gray
}

# Test calling generate_match_pairs.ps1 directly
Write-Host ""
Write-Host "Testing generate_match_pairs.ps1..." -ForegroundColor Yellow

$generateScript = Join-Path $scriptDir "generate_match_pairs.ps1"
$matchPairsOutput = Join-Path $scene "output\colmap_output\match_pairs_test.txt"

# Ensure colmap_output directory exists
$colmapOutputDir = Join-Path $scene "output\colmap_output"
if (-not (Test-Path $colmapOutputDir)) {
    New-Item -ItemType Directory -Path $colmapOutputDir -Force | Out-Null
}

Write-Host "  Images dir: $imagesPath" -ForegroundColor Gray
Write-Host "  Output: $matchPairsOutput" -ForegroundColor Gray

# Call the script
& $generateScript -ImagesDir $imagesPath -OutputPath $matchPairsOutput -TemporalOverlap 5 -CrossCameraSameTimestamp

$exitCode = $LASTEXITCODE
Write-Host ""
Write-Host "Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

if (Test-Path $matchPairsOutput) {
    $lineCount = (Get-Content $matchPairsOutput).Count
    Write-Host "Match pairs file created with $lineCount pairs" -ForegroundColor Green
} else {
    Write-Host "Match pairs file NOT created" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

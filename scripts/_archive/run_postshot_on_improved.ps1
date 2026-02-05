# Run Postshot on the improved COLMAP reconstruction
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import postshot_runner and config_loader
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")
. (Join-Path $scriptDir "postshot_runner.ps1")

# Load config
$Config = Load-Config

# Paths
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

$imagesPath = Join-Path $scene1 "output\images"
$sparsePath = Join-Path $scene1 "output_improved_registration\sparse\0"
$outputPath = Join-Path $scene1 "output_improved_registration"
$pshtFile = Join-Path $outputPath "scene.psht"

Write-Host "=== Running Postshot on Improved Reconstruction ===" -ForegroundColor Cyan
Write-Host "Images: $imagesPath" -ForegroundColor Yellow
Write-Host "Sparse: $sparsePath" -ForegroundColor Yellow
Write-Host "Output: $pshtFile" -ForegroundColor Yellow
Write-Host ""

# Check paths exist
if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "ERROR: Images path not found: $imagesPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $sparsePath)) {
    Write-Host "ERROR: Sparse path not found: $sparsePath" -ForegroundColor Red
    exit 1
}

# Run Postshot pipeline
$result = Run-PostshotPipeline `
    -InputPath $imagesPath `
    -OutputPath $pshtFile `
    -Config $Config `
    -ExportPly $true `
    -ColmapSparsePath $sparsePath

if ($result.Success) {
    Write-Host ""
    Write-Host "=== Complete ===" -ForegroundColor Green
    Write-Host "PSHT: $($result.PshtPath)" -ForegroundColor Cyan
    Write-Host "PLY: $($result.PlyPath)" -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Postshot pipeline failed" -ForegroundColor Red
    exit 1
}

# Run pipeline with W camera only (to test if W↔Z matching is the problem)
param(
    [Parameter(Mandatory=$false)]
    [int]$SceneNumber = 1
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  W Camera Only Test" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Find scene
$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene = $scenes[$SceneNumber - 1]
$scenePath = $scene.FullName

Write-Host "Scene: $($scene.Name)"
Write-Host "Testing W camera only to diagnose W+Z matching issues"
Write-Host ""

# Setup paths
$outputDir = "output_W_only"
$outputPath = Join-Path $scenePath $outputDir
$imagesPath = Join-Path $outputPath "images"
$wImagesPath = Join-Path $imagesPath "video_W"

# Check if already done
$pshtPath = Join-Path $outputPath "scene.psht"
if (Test-Path $pshtPath) {
    Write-Host "Output already exists: $pshtPath" -ForegroundColor Yellow
    Write-Host "Delete $outputPath to re-run" -ForegroundColor Yellow
    exit 0
}

# Create output structure
Write-Host "Creating output directory structure..."
if (-not (Test-Path $imagesPath)) {
    New-Item -ItemType Directory -Path $imagesPath -Force | Out-Null
}

# Copy only W images
$sourceWImages = Join-Path $scenePath "output\images\video_W"
if (-not (Test-Path $sourceWImages)) {
    Write-Host "ERROR: Source W images not found: $sourceWImages" -ForegroundColor Red
    exit 1
}

Write-Host "Copying W images only..."
if (-not (Test-Path $wImagesPath)) {
    Copy-Item -LiteralPath $sourceWImages -Destination $wImagesPath -Recurse
}
$wCount = (Get-ChildItem -LiteralPath $wImagesPath -File).Count
Write-Host "  Copied $wCount W images"

# Run pipeline on W only
Write-Host ""
Write-Host "Running COLMAP + Postshot on W camera only..."
Write-Host ""

& "$scriptDir\scripts\run_pipeline_exhaustive.ps1" `
    -InputPath $scenePath `
    -OutputDir $outputDir

$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: W-only pipeline completed" -ForegroundColor Green

    # Check COLMAP registration
    $sparsePath = Join-Path $outputPath "colmap_output\sparse\0\images.bin"
    if (Test-Path $sparsePath) {
        $size = (Get-Item $sparsePath).Length
        Write-Host "  images.bin: $([math]::Round($size/1KB, 2)) KB"
    }

    Write-Host ""
    Write-Host "Compare quality:"
    Write-Host "  Original (W+Z): $scenePath\output\scene.psht"
    Write-Host "  W-only: $outputPath\scene.psht"
} else {
    Write-Host ""
    Write-Host "FAILED with exit code $exitCode" -ForegroundColor Red
}

exit $exitCode

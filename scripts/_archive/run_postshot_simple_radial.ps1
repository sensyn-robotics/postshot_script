# Run Postshot on SIMPLE_RADIAL model for scene 1
param(
    [int]$SceneIndex = 0
)

$postshotCli = "C:\Program Files\Jawset Postshot\bin\postshot-cli.exe"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[$SceneIndex].FullName
$sceneName = $scenes[$SceneIndex].Name

Write-Host "=== Running Postshot for Scene $($SceneIndex + 1) ===" -ForegroundColor Cyan
Write-Host "Scene: $sceneName" -ForegroundColor Gray

$sparsePath = Join-Path $scene "output_simple_radial\sparse\0"
$imagesPath = Join-Path $scene "output\images"
$outputPath = Join-Path $scene "output_simple_radial"

# Verify paths exist
if (-not (Test-Path -LiteralPath $sparsePath)) {
    Write-Host "ERROR: Sparse model not found at $sparsePath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "ERROR: Images not found at $imagesPath" -ForegroundColor Red
    exit 1
}

$pshtFile = Join-Path $outputPath "scene.psht"
$plyFile = Join-Path $outputPath "scene.ply"

Write-Host ""
Write-Host "Sparse: $sparsePath" -ForegroundColor Gray
Write-Host "Images: $imagesPath" -ForegroundColor Gray
Write-Host "Output: $pshtFile" -ForegroundColor Gray

# Run Postshot training
Write-Host ""
Write-Host "=== Starting Postshot Training ===" -ForegroundColor Cyan

$postshotArgs = @(
    "train",
    "-i", $imagesPath,
    "-i", $sparsePath,
    "-o", $pshtFile,
    "-s", "30"
)

Write-Host "Running: postshot-cli $($postshotArgs -join ' ')" -ForegroundColor DarkGray
& $postshotCli @postshotArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Postshot training failed" -ForegroundColor Red
    exit 1
}

# Export PLY
Write-Host ""
Write-Host "=== Exporting PLY ===" -ForegroundColor Cyan
$exportArgs = @(
    "export",
    "-i", $pshtFile,
    "--splat", $plyFile
)

& $postshotCli @exportArgs

Write-Host ""
Write-Host "=== Complete ===" -ForegroundColor Green
Write-Host "PSHT: $pshtFile"
Write-Host "PLY: $plyFile"

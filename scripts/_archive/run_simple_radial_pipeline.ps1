# Run SIMPLE_RADIAL COLMAP + Postshot pipeline for a scene
param(
    [Parameter(Mandatory=$true)]
    [int]$SceneIndex
)

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$postshotCli = "C:\Program Files\Jawset Postshot\bin\postshot-cli.exe"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[$SceneIndex].FullName
$sceneName = $scenes[$SceneIndex].Name

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Scene $($SceneIndex + 1): $sceneName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$imagesPath = Join-Path $scene "output\images"
$outputPath = Join-Path $scene "output_simple_radial"
$databasePath = Join-Path $outputPath "database.db"
$sparsePath = Join-Path $outputPath "sparse"

# Check if images exist
if (-not (Test-Path -LiteralPath $imagesPath)) {
    Write-Host "ERROR: Images not found at $imagesPath" -ForegroundColor Red
    exit 1
}

# Clean and create output directory
if (Test-Path -LiteralPath $outputPath) {
    Write-Host "Cleaning existing output..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

# Feature extraction with SIMPLE_RADIAL
Write-Host ""
Write-Host "=== Feature Extraction (SIMPLE_RADIAL) ===" -ForegroundColor Cyan
$extractArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
    "--ImageReader.single_camera_per_folder", "1",
    "--ImageReader.camera_model", "SIMPLE_RADIAL"
)
$process = Start-Process -FilePath $colmapExe -ArgumentList $extractArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature extraction failed" -ForegroundColor Red
    exit 1
}

# Exhaustive matching
Write-Host ""
Write-Host "=== Exhaustive Matching ===" -ForegroundColor Cyan
$matchArgs = @(
    "exhaustive_matcher",
    "--database_path", $databasePath
)
$process = Start-Process -FilePath $colmapExe -ArgumentList $matchArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Matching failed" -ForegroundColor Red
    exit 1
}

# Mapper
Write-Host ""
Write-Host "=== Mapper ===" -ForegroundColor Cyan
$mapperArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
    "--output_path", $sparsePath
)
$process = Start-Process -FilePath $colmapExe -ArgumentList $mapperArgs -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
    Write-Host "WARNING: Mapper returned non-zero" -ForegroundColor Yellow
}

# Check results
$models = Get-ChildItem -LiteralPath $sparsePath -Directory | Sort-Object Name
if ($models.Count -eq 0) {
    Write-Host "ERROR: No models created" -ForegroundColor Red
    exit 1
}

$bestModel = $models[0].FullName
Write-Host ""
Write-Host "Using model: $($models[0].Name)" -ForegroundColor Green

# Run Postshot
Write-Host ""
Write-Host "=== Postshot Training ===" -ForegroundColor Cyan
$pshtFile = Join-Path $outputPath "scene.psht"
$plyFile = Join-Path $outputPath "scene.ply"

$postshotArgs = @(
    "train",
    "-i", $imagesPath,
    "-i", $bestModel,
    "-o", $pshtFile,
    "-s", "30"
)

Write-Host "Running: postshot-cli train..." -ForegroundColor DarkGray
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
Write-Host "========================================" -ForegroundColor Green
Write-Host "Scene $($SceneIndex + 1) COMPLETE" -ForegroundColor Green
Write-Host "PSHT: $pshtFile" -ForegroundColor Green
Write-Host "PLY: $plyFile" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Test COLMAP with SIMPLE_RADIAL camera model (same as colmap_batch)
param()

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName
$imagesPath = Join-Path $scene1 "output\images"
$outputPath = Join-Path $scene1 "output_simple_radial"
$databasePath = Join-Path $outputPath "database.db"
$sparsePath = Join-Path $outputPath "sparse"

Write-Host "=== Testing SIMPLE_RADIAL (same as colmap_batch) ===" -ForegroundColor Cyan
Write-Host "Images: $imagesPath" -ForegroundColor Gray

# Clean and create output directory
if (Test-Path -LiteralPath $outputPath) {
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

# Mapper with DEFAULT settings (same as colmap_batch)
Write-Host ""
Write-Host "=== Mapper (DEFAULT settings) ===" -ForegroundColor Cyan
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

# Analyze results
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan

$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
$models = Get-ChildItem -LiteralPath $sparsePath -Directory | Sort-Object Name

if ($models.Count -eq 0) {
    Write-Host "ERROR: No models created" -ForegroundColor Red
    exit 1
}

foreach ($model in $models) {
    Write-Host ""
    Write-Host "Model: $($model.Name)" -ForegroundColor Yellow
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $model.FullName
}

Write-Host ""
Write-Host "Output: $sparsePath" -ForegroundColor Green

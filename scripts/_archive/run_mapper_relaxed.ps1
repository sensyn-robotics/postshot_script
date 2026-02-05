# Run COLMAP mapper with very relaxed settings on existing database
param()

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName
$outputPath = Join-Path $scene1 "output_dual_registered"
$databasePath = Join-Path $outputPath "database.db"
$imagesPath = Join-Path $scene1 "output\images"
$sparsePath = Join-Path $outputPath "sparse"

Write-Host "=== Running Mapper with Very Relaxed Settings ===" -ForegroundColor Cyan
Write-Host "Database: $databasePath" -ForegroundColor Gray
Write-Host "Images: $imagesPath" -ForegroundColor Gray

# Clean and create sparse directory
if (Test-Path -LiteralPath $sparsePath) {
    Remove-Item -LiteralPath $sparsePath -Recurse -Force
}
New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

$mapperArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
    "--output_path", $sparsePath,
    "--Mapper.init_min_num_inliers", "10",
    "--Mapper.abs_pose_min_num_inliers", "3",
    "--Mapper.abs_pose_min_inlier_ratio", "0.01",
    "--Mapper.init_max_error", "16",
    "--Mapper.max_reg_trials", "10"
)

Write-Host "Running: colmap mapper ..." -ForegroundColor DarkGray
$process = Start-Process -FilePath $colmapExe -ArgumentList $mapperArgs -NoNewWindow -Wait -PassThru

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

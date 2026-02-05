# Test Z-only COLMAP with OPENCV camera model
# This tests if Z images can register well when W images are not present

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[0].FullName
$sceneName = $scenes[0].Name

Write-Host "=== Testing Z-only COLMAP with OPENCV ===" -ForegroundColor Cyan
Write-Host "Scene: $sceneName" -ForegroundColor Gray

$imagesPath = Join-Path $scene "output\images\video_Z"
$outputPath = Join-Path $scene "output_z_only_opencv"
$databasePath = Join-Path $outputPath "database.db"
$sparsePath = Join-Path $outputPath "sparse"

Write-Host "Z Images: $imagesPath" -ForegroundColor Gray
Write-Host "Output: $outputPath" -ForegroundColor Gray

# Count Z images
$zCount = (Get-ChildItem -LiteralPath $imagesPath -File -ErrorAction SilentlyContinue).Count
Write-Host "Z image count: $zCount" -ForegroundColor Gray

# Clean and create output directory
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
New-Item -ItemType Directory -Path $sparsePath -Force | Out-Null

# Feature extraction with OPENCV
Write-Host ""
Write-Host "=== Feature Extraction (OPENCV) ===" -ForegroundColor Cyan
$extractArgs = @(
    "feature_extractor",
    "--database_path", $databasePath,
    "--image_path", $imagesPath,
    "--ImageReader.single_camera", "1",
    "--ImageReader.camera_model", "OPENCV"
)
Write-Host "Running: colmap $($extractArgs -join ' ')" -ForegroundColor DarkGray
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

# Analyze results
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan

$models = Get-ChildItem -LiteralPath $sparsePath -Directory | Sort-Object Name
if ($models.Count -eq 0) {
    Write-Host "ERROR: No models created" -ForegroundColor Red
    exit 1
}

# Use Python to read model
$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"

foreach ($model in $models) {
    Write-Host ""
    Write-Host "Model: $($model.Name)" -ForegroundColor Yellow

    $pythonCode = @"
import struct
from pathlib import Path

model_path = Path(r'$($model.FullName)')
images_file = model_path / 'images.bin'

if not images_file.exists():
    print('No images.bin found')
    exit(1)

with open(images_file, 'rb') as f:
    num_images = struct.unpack('Q', f.read(8))[0]

print(f'Registered images: {num_images} / $zCount')
print(f'Registration rate: {num_images/$zCount*100:.1f}%')
"@

    & $pythonPath -c $pythonCode
}

Write-Host ""
Write-Host "=== Z-only OPENCV Test Complete ===" -ForegroundColor Green

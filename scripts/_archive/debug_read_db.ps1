# Read COLMAP database using sqlite3 via COLMAP

$testDataPath = "C:\postshot_test_data"
$scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Select-Object -First 1
$dbPath = Join-Path $scene1Dir.FullName "output\colmap_output\database.db"

Write-Host "=== Reading COLMAP Database ===" -ForegroundColor Cyan
Write-Host "Database: $dbPath"

# Copy to temp location
$tempDb = "C:\Postshot_Temp\scene1_db.db"
Copy-Item -LiteralPath $dbPath -Destination $tempDb -Force

# Use COLMAP database management to export info
$colmapExe = "C:\COLMAP\bin\colmap.exe"

# Export cameras to text
Write-Host ""
Write-Host "=== Exporting database info ===" -ForegroundColor Yellow

# Try to use colmap's database tools - but they don't exist for direct inspection
# Instead, let's use the model_converter on the sparse reconstruction

# Check all sparse reconstructions
$sparseDir = Join-Path $scene1Dir.FullName "output\colmap_output\sparse"
$tempSparseText = "C:\Postshot_Temp\sparse_text"

if (Test-Path $tempSparseText) {
    Remove-Item $tempSparseText -Recurse -Force
}

$reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory | Sort-Object Name
Write-Host "Found $($reconFolders.Count) reconstruction(s)"

foreach ($recon in $reconFolders) {
    Write-Host ""
    Write-Host "=== Reconstruction $($recon.Name) ===" -ForegroundColor Cyan

    # Copy to temp location
    $tempRecon = "C:\Postshot_Temp\recon_$($recon.Name)"
    if (Test-Path $tempRecon) {
        Remove-Item $tempRecon -Recurse -Force
    }
    Copy-Item -LiteralPath $recon.FullName -Destination $tempRecon -Recurse

    # Convert to text format
    $textOutput = "C:\Postshot_Temp\text_$($recon.Name)"
    if (Test-Path $textOutput) {
        Remove-Item $textOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Path $textOutput -Force | Out-Null

    & $colmapExe model_converter --input_path $tempRecon --output_path $textOutput --output_type TXT 2>&1 | Out-Null

    # Read cameras.txt
    $camerasFile = Join-Path $textOutput "cameras.txt"
    if (Test-Path $camerasFile) {
        Write-Host "--- cameras.txt ---" -ForegroundColor Yellow
        Get-Content $camerasFile | ForEach-Object {
            if ($_ -notmatch "^#") {
                Write-Host $_
            }
        }
    }

    # Count images per folder
    $imagesFile = Join-Path $textOutput "images.txt"
    if (Test-Path $imagesFile) {
        $wideCount = (Get-Content $imagesFile | Where-Object { $_ -match "video_W" }).Count
        $zoomCount = (Get-Content $imagesFile | Where-Object { $_ -match "video_Z" }).Count
        Write-Host ""
        Write-Host "Images: video_W=$wideCount, video_Z=$zoomCount" -ForegroundColor Green
    }

    # Cleanup
    Remove-Item $tempRecon -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $textOutput -Recurse -Force -ErrorAction SilentlyContinue
}

# Cleanup
Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

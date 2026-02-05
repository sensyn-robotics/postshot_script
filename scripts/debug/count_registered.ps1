# Count registered images using COLMAP model_converter
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$colmap = "C:\Program Files\COLMAP\bin\colmap.bat"

Write-Host "=== Registered Image Counts ==="

$outputs = @("output_improved_registration", "output_simple_radial", "output_z_only_opencv")
foreach ($outName in $outputs) {
    $sparseDir = "$scene1\$outName\sparse\0"
    if (Test-Path $sparseDir) {
        Write-Host ""
        Write-Host "${outName}:"
        $txtDir = "$scene1\$outName\sparse_txt"
        if (-not (Test-Path $txtDir)) { New-Item -ItemType Directory -Path $txtDir -Force | Out-Null }

        # Convert to text to count images
        & $colmap model_converter --input_path $sparseDir --output_path $txtDir --output_type TXT 2>$null

        if (Test-Path "$txtDir\images.txt") {
            $lines = Get-Content "$txtDir\images.txt"
            $imageLines = $lines | Where-Object { $_ -match "^[0-9]+" -and $_ -notmatch "^#" }
            $imageCount = ($imageLines | Measure-Object).Count / 2
            Write-Host "  Registered images: $imageCount"
        }

        if (Test-Path "$txtDir\points3D.txt") {
            $pointLines = Get-Content "$txtDir\points3D.txt" | Where-Object { $_ -match "^[0-9]+" }
            $pointCount = ($pointLines | Measure-Object).Count
            Write-Host "  3D points: $pointCount"
        }
    }
}

# Also show total available images
Write-Host ""
Write-Host "=== Total Available Images ==="
$imagesDir = "$scene1\output_simple_radial\images"
if (Test-Path $imagesDir) {
    $totalImages = (Get-ChildItem $imagesDir -Recurse -File -Filter "*.jpg").Count +
                   (Get-ChildItem $imagesDir -Recurse -File -Filter "*.png").Count
    Write-Host "Total images in images folder: $totalImages"
}

# Check reconstruction state for scene 1
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$colmap = "C:\COLMAP\COLMAP.bat"

Write-Host "Scene 1: $scene1"
Write-Host ""

# Check output_simple_radial (best reconstruction based on file sizes)
$outputDir = "$scene1\output_simple_radial"
$sparseDir = "$outputDir\sparse\0"
$imagesDir = "$outputDir\images"

if (Test-Path $sparseDir) {
    Write-Host "=== output_simple_radial ==="

    # Count total images
    $wImages = Get-ChildItem "$imagesDir\video_W" -File -ErrorAction SilentlyContinue | Measure-Object
    $zImages = Get-ChildItem "$imagesDir\video_Z" -File -ErrorAction SilentlyContinue | Measure-Object
    Write-Host "W camera images: $($wImages.Count)"
    Write-Host "Z camera images: $($zImages.Count)"
    Write-Host "Total images: $($wImages.Count + $zImages.Count)"

    # Check sparse reconstruction
    Write-Host ""
    Write-Host "Sparse model files:"
    Get-ChildItem $sparseDir -File | ForEach-Object {
        $sizeKB = [math]::Round($_.Length / 1KB, 1)
        Write-Host "  $($_.Name): $sizeKB KB"
    }
}

# List all output directories
Write-Host ""
Write-Host "=== All output directories ==="
Get-ChildItem $scene1 -Directory | Where-Object { $_.Name -like "output*" } | ForEach-Object {
    Write-Host "  $($_.Name)"
}

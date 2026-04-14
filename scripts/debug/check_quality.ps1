# Check output quality for output_simple_radial
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$outputDir = "$scene1\output_simple_radial"

Write-Host "=== Output Quality Review: output_simple_radial ==="
Write-Host "Path: $outputDir"
Write-Host ""

# Check directory structure
Write-Host "=== Directory Structure ==="
Get-ChildItem $outputDir -Directory | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host ""

# Check for rendered videos
Write-Host "=== Video/Image Outputs ==="
$videos = Get-ChildItem $outputDir -Recurse -Include "*.mp4","*.avi" -ErrorAction SilentlyContinue
if ($videos) {
    foreach ($v in $videos) {
        $sizeMB = [math]::Round($v.Length / 1MB, 1)
        Write-Host "  $($v.Name) ($sizeMB MB)"
    }
} else {
    Write-Host "  No video files found"
}
Write-Host ""

# Check visualizations folder
$vizDir = "$outputDir\visualizations"
if (Test-Path $vizDir) {
    Write-Host "=== Visualizations ==="
    $vizFiles = Get-ChildItem $vizDir -File
    Write-Host "  Files: $($vizFiles.Count)"
    $vizFiles | Select-Object -First 5 | ForEach-Object {
        $sizeKB = [math]::Round($_.Length / 1KB, 1)
        Write-Host "    $($_.Name) ($sizeKB KB)"
    }
    if ($vizFiles.Count -gt 5) { Write-Host "    ... and $($vizFiles.Count - 5) more" }
}
Write-Host ""

# Check postshot directory
$postshotDir = "$outputDir\postshot"
if (Test-Path $postshotDir) {
    Write-Host "=== Postshot Directory ==="
    Get-ChildItem $postshotDir -File | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host "  $($_.Name) ($sizeMB MB)"
    }
}
Write-Host ""

# COLMAP sparse quality
Write-Host "=== COLMAP Sparse Reconstruction ==="
$sparseDir = "$outputDir\sparse\0"
if (Test-Path $sparseDir) {
    $cameras = Get-ChildItem $sparseDir -Filter "cameras.bin" | Select-Object -First 1
    $images = Get-ChildItem $sparseDir -Filter "images.bin" | Select-Object -First 1
    $points = Get-ChildItem $sparseDir -Filter "points3D.bin" | Select-Object -First 1

    if ($cameras) { Write-Host "  cameras.bin: $([math]::Round($cameras.Length / 1KB, 1)) KB" }
    if ($images) { Write-Host "  images.bin: $([math]::Round($images.Length / 1MB, 1)) MB" }
    if ($points) { Write-Host "  points3D.bin: $([math]::Round($points.Length / 1MB, 1)) MB" }
}

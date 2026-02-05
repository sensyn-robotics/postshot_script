# Convert sparse model to text and count registered images
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$colmap = "C:\COLMAP\COLMAP.bat"

$sparseDir = "$scene1\output_simple_radial\sparse\0"
$txtDir = "$scene1\output_simple_radial\sparse_txt"

if (-not (Test-Path $txtDir)) {
    New-Item -ItemType Directory -Path $txtDir -Force | Out-Null
}

Write-Host "Converting binary to text..."
& $colmap model_converter --input_path $sparseDir --output_path $txtDir --output_type TXT

if (Test-Path "$txtDir\images.txt") {
    Write-Host ""
    Write-Host "=== images.txt header ==="
    Get-Content "$txtDir\images.txt" -Head 10

    Write-Host ""
    $content = Get-Content "$txtDir\images.txt"
    # Count lines that start with a number (image entries)
    $imageEntries = ($content | Where-Object { $_ -match '^\d+\s' }).Count
    Write-Host "Registered images: $imageEntries"

    # Count W vs Z
    $wCount = ($content | Where-Object { $_ -match 'video_W' }).Count
    $zCount = ($content | Where-Object { $_ -match 'video_Z' }).Count
    Write-Host "W camera registered: $wCount"
    Write-Host "Z camera registered: $zCount"
}

if (Test-Path "$txtDir\points3D.txt") {
    $points = (Get-Content "$txtDir\points3D.txt" | Where-Object { $_ -match '^\d+\s' }).Count
    Write-Host "3D points: $points"
}

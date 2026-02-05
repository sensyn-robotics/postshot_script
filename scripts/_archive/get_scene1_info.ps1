# Get scene1 info
param()

$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]
Write-Host "Scene1: $($scene1.FullName)"

$imagesDir = Join-Path $scene1.FullName 'output\images'
Write-Host "Images dir: $imagesDir"
Write-Host "Images dir exists: $(Test-Path -LiteralPath $imagesDir)"

if (Test-Path -LiteralPath $imagesDir) {
    # Try different methods
    Write-Host ""
    Write-Host "Checking images subdirectories..."
    Get-ChildItem -LiteralPath $imagesDir -Directory | ForEach-Object {
        $subImages = @(Get-ChildItem -LiteralPath $_.FullName -File)
        Write-Host "  $($_.Name): $($subImages.Count) files"
        if ($subImages.Count -gt 0) {
            $subImages | Select-Object -First 3 | ForEach-Object { Write-Host "    $($_.Name)" }
        }
    }

    # Also check for direct images
    $directImages = @(Get-ChildItem -LiteralPath $imagesDir -File)
    Write-Host ""
    Write-Host "Direct files in images folder: $($directImages.Count)"
}

$sparseDir = Join-Path $scene1.FullName 'output\colmap_output\sparse'
if (Test-Path -LiteralPath $sparseDir) {
    Write-Host ""
    Write-Host "Sparse reconstructions:"
    Get-ChildItem -LiteralPath $sparseDir -Directory | ForEach-Object {
        $imagesFile = Join-Path $_.FullName 'images.bin'
        $pointsFile = Join-Path $_.FullName 'points3D.bin'
        $imagesSize = if (Test-Path -LiteralPath $imagesFile) { (Get-Item -LiteralPath $imagesFile).Length } else { 0 }
        $pointsSize = if (Test-Path -LiteralPath $pointsFile) { (Get-Item -LiteralPath $pointsFile).Length } else { 0 }
        Write-Host "  Reconstruction $($_.Name): images.bin=$imagesSize bytes, points3D.bin=$pointsSize bytes"
    }
}

# Return scene path for use in other scripts
return $scene1.FullName

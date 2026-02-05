# Move latest output to output_0.2fps and analyze 0.5fps overlap
$ErrorActionPreference = 'Stop'

$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

Write-Host "=== Moving Output to output_0.2fps ===" -ForegroundColor Cyan
Write-Host "Scene: $scene1"

# Create output_0.2fps directory
$output02Dir = Join-Path $scene1 'output_0.2fps'
if (-not (Test-Path $output02Dir)) {
    New-Item -ItemType Directory -Path $output02Dir -Force | Out-Null
    Write-Host "Created: $output02Dir"
}

# Move files from root to output_0.2fps
$filesToMove = @('scene.psht', 'scene.ply')
foreach ($file in $filesToMove) {
    $srcPath = Join-Path $scene1 $file
    $dstPath = Join-Path $output02Dir $file
    if (Test-Path $srcPath) {
        Move-Item -LiteralPath $srcPath -Destination $dstPath -Force
        Write-Host "Moved: $file -> output_0.2fps/"
    }
}

# Move directories from root to output_0.2fps
$dirsToMove = @('colmap_output', 'images', 'visualizations')
foreach ($dir in $dirsToMove) {
    $srcPath = Join-Path $scene1 $dir
    $dstPath = Join-Path $output02Dir $dir
    # Only move if it exists at root AND doesn't exist in output/
    if ((Test-Path $srcPath) -and -not (Test-Path (Join-Path $scene1 "output\$dir"))) {
        # This is root-level directory, move it
        Move-Item -LiteralPath $srcPath -Destination $dstPath -Force
        Write-Host "Moved: $dir/ -> output_0.2fps/"
    } elseif (Test-Path $srcPath) {
        # Root has it but output also has it - check if different
        $rootCount = (Get-ChildItem -LiteralPath $srcPath -Recurse -File).Count
        $outputPath = Join-Path $scene1 "output\$dir"
        $outputCount = if (Test-Path $outputPath) { (Get-ChildItem -LiteralPath $outputPath -Recurse -File).Count } else { 0 }

        if ($rootCount -ne $outputCount) {
            # Different content, move root version
            if (Test-Path $dstPath) { Remove-Item $dstPath -Recurse -Force }
            Move-Item -LiteralPath $srcPath -Destination $dstPath -Force
            Write-Host "Moved: $dir/ -> output_0.2fps/ ($rootCount files, different from output/)"
        } else {
            Write-Host "Skipped: $dir/ (same content as output/)"
        }
    }
}

Write-Host ""
Write-Host "=== Verifying Results ===" -ForegroundColor Cyan

# Check output_0.2fps contents
Write-Host "output_0.2fps/ contents:"
Get-ChildItem -LiteralPath $output02Dir -ErrorAction SilentlyContinue | ForEach-Object {
    $size = if ($_.PSIsContainer) { "" } else { " ($([math]::Round($_.Length/1MB, 2)) MB)" }
    Write-Host "  $($_.Name)$size"
}

# Check output/ contents (0.5fps reference)
Write-Host ""
Write-Host "output/ contents (0.5fps reference):"
$outputDir = Join-Path $scene1 'output'
Get-ChildItem -LiteralPath $outputDir -ErrorAction SilentlyContinue | ForEach-Object {
    $size = if ($_.PSIsContainer) { "" } else { " ($([math]::Round($_.Length/1MB, 2)) MB)" }
    Write-Host "  $($_.Name)$size"
}

# Count frames in each
Write-Host ""
Write-Host "=== Frame Counts ===" -ForegroundColor Cyan

$output05Images = Join-Path $scene1 'output\images'
if (Test-Path $output05Images) {
    $wCount = (Get-ChildItem -LiteralPath (Join-Path $output05Images 'video_W') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.jpg') }).Count
    $zCount = (Get-ChildItem -LiteralPath (Join-Path $output05Images 'video_Z') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.jpg') }).Count
    Write-Host "0.5fps (output/): W=$wCount, Z=$zCount, Total=$($wCount + $zCount)"
}

$output02Images = Join-Path $output02Dir 'images'
if (Test-Path $output02Images) {
    $wCount = (Get-ChildItem -LiteralPath (Join-Path $output02Images 'video_W') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.jpg') }).Count
    $zCount = (Get-ChildItem -LiteralPath (Join-Path $output02Images 'video_Z') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.jpg') }).Count
    Write-Host "0.2fps (output_0.2fps/): W=$wCount, Z=$zCount, Total=$($wCount + $zCount)"
} else {
    Write-Host "0.2fps: No images directory found in output_0.2fps/"
}

Write-Host ""
Write-Host "Done."

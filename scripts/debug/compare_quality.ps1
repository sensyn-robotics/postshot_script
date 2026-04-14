# Compare quality metrics between original output and output_simple_radial
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName

Write-Host "=== Quality Comparison: Scene 1 ==="
Write-Host ""

$outputs = @("output", "output_simple_radial")

foreach ($outName in $outputs) {
    $outDir = "$scene1\$outName"
    if (-not (Test-Path $outDir)) { continue }

    Write-Host "--- $outName ---"

    # COLMAP sparse stats
    $sparseDir = "$outDir\sparse\0"
    if (Test-Path $sparseDir) {
        $pointsFile = "$sparseDir\points3D.bin"
        $imagesFile = "$sparseDir\images.bin"

        if (Test-Path $pointsFile) {
            $pointsSize = [math]::Round((Get-Item $pointsFile).Length / 1MB, 2)
            Write-Host "  points3D.bin size: $pointsSize MB"
        }
        if (Test-Path $imagesFile) {
            $imagesSize = [math]::Round((Get-Item $imagesFile).Length / 1MB, 2)
            Write-Host "  images.bin size: $imagesSize MB"
        }
    } else {
        Write-Host "  No sparse/0 directory"
    }

    # Check for text model with exact counts
    $txtDir = "$outDir\sparse_txt"
    if (Test-Path "$txtDir\images.txt") {
        $content = Get-Content "$txtDir\images.txt" -Head 5
        foreach ($line in $content) {
            if ($line -match "Number of images: (\d+)") {
                Write-Host "  Registered images: $($Matches[1])"
            }
            if ($line -match "mean observations per image: ([\d.]+)") {
                Write-Host "  Mean observations/image: $([math]::Round([double]$Matches[1], 0))"
            }
        }
    }
    if (Test-Path "$txtDir\points3D.txt") {
        $pointCount = (Get-Content "$txtDir\points3D.txt" | Where-Object { $_ -match '^\d+\s' }).Count
        Write-Host "  3D points: $pointCount"
    }

    # Postshot output
    $psht = Get-ChildItem $outDir -Filter "*.psht" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($psht) {
        $pshtSize = [math]::Round($psht.Length / 1MB, 1)
        Write-Host "  PSHT size: $pshtSize MB"
    }

    Write-Host ""
}

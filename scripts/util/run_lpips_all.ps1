param(
    [string]$OutputDir = "output_default"
)

$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
$scenes = Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name

Set-Location C:\postshot_script

foreach ($scene in $scenes) {
    Write-Host "`n======== $($scene.Name) ========" -ForegroundColor Cyan

    $outDir = Join-Path $scene.FullName $OutputDir
    $ply = Join-Path $outDir "postshot\scene.ply"
    $sparseDir = Join-Path $outDir "colmap\sparse"
    $imagesDir = Join-Path $outDir "images"
    $lpipsJson = Join-Path $outDir "postshot\lpips.json"

    if (-not (Test-Path -LiteralPath $ply)) {
        Write-Host "  SKIP: PLY not found at $ply" -ForegroundColor Yellow
        continue
    }

    # Find the sparse model (largest reconstruction)
    $sparseModels = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $sparseModels) {
        Write-Host "  SKIP: No sparse model in $sparseDir" -ForegroundColor Yellow
        continue
    }
    $sparsePath = ($sparseModels | Sort-Object { (Get-Item -LiteralPath (Join-Path $_.FullName "images.bin")).Length } -Descending | Select-Object -First 1).FullName

    # Create junction to avoid Japanese path issues
    $junction = "C:\Postshot_Temp\lpips_$($scene.Name.Substring(0,1))"
    if (Test-Path $junction) { cmd /c "rmdir `"$junction`"" }
    cmd /c "mklink /J `"$junction`" `"$($scene.FullName)`""

    $jPly = Join-Path $junction "$OutputDir\postshot\scene.ply"
    $jSparse = $sparsePath.Replace($scene.FullName, $junction)
    $jImages = Join-Path $junction "$OutputDir\images"
    $jOutput = Join-Path $junction "$OutputDir\postshot\lpips.json"

    Write-Host "  PLY: $jPly"
    Write-Host "  Sparse: $jSparse"
    Write-Host "  Images: $jImages"

    & uv run python scripts/compute_lpips.py --ply $jPly --sparse $jSparse --images $jImages --output $jOutput --max-images 50

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $jOutput)) {
        $data = Get-Content $jOutput -Raw | ConvertFrom-Json
        Write-Host "  LPIPS: $($data.lpips_mean)" -ForegroundColor Green
    } else {
        Write-Host "  FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
    }

    cmd /c "rmdir `"$junction`""
}

Write-Host "`n======== DONE ========" -ForegroundColor Green

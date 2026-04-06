param(
    [int]$MaxImages = 15
)

$env:PYTHONUTF8 = "1"
$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
Set-Location C:\postshot_script

$scene1 = (Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name | Select-Object -First 1).FullName

$results = @()

foreach ($dir in (Get-ChildItem -LiteralPath $scene1 -Directory | Where-Object { $_.Name -match '^output' } | Sort-Object Name)) {
    $ply = Join-Path $dir.FullName "postshot\scene.ply"
    $sparseDir = Join-Path $dir.FullName "colmap\sparse"
    $imagesDir = Join-Path $dir.FullName "images"
    $qjson = Join-Path $dir.FullName "postshot\quality.json"

    if (-not (Test-Path -LiteralPath $ply)) { continue }
    if (-not (Test-Path -LiteralPath $sparseDir)) { continue }

    # Find best sparse model
    $sparseModels = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue
    if (-not $sparseModels) { continue }
    $sparsePath = ($sparseModels | Sort-Object {
        $imgBin = Join-Path $_.FullName "images.bin"
        if (Test-Path $imgBin) { (Get-Item $imgBin).Length } else { 0 }
    } -Descending | Select-Object -First 1).FullName

    # Get SSIM from quality.json
    $ssim = "N/A"
    if (Test-Path -LiteralPath $qjson) {
        $q = Get-Content $qjson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($q.PSObject.Properties['ssim']) { $ssim = $q.ssim }
    }

    Write-Host "`n======== $($dir.Name) (SSIM=$ssim) ========" -ForegroundColor Cyan

    # Create junction to avoid Japanese path issues
    $junction = "C:\Postshot_Temp\metrics_tmp"
    if (Test-Path $junction) { cmd /c "rmdir `"$junction`"" }
    cmd /c "mklink /J `"$junction`" `"$scene1`"" | Out-Null

    $jPly = Join-Path $junction "$($dir.Name)\postshot\scene.ply"
    $jSparse = $sparsePath.Replace($scene1, $junction)
    $jImages = Join-Path $junction "$($dir.Name)\images"
    $jOutput = Join-Path $junction "$($dir.Name)\postshot\metrics.json"

    $ErrorActionPreference = 'Continue'
    & uv run python scripts/compute_lpips.py --ply $jPly --sparse $jSparse --images $jImages --output $jOutput --max-images $MaxImages 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $ErrorActionPreference = 'Stop'

    $lpips = "N/A"
    $psnr = "N/A"
    $jOutputLocal = Join-Path $junction "$($dir.Name)\postshot\metrics.json"
    if (Test-Path -LiteralPath $jOutputLocal) {
        $data = Get-Content $jOutputLocal -Raw | ConvertFrom-Json
        $lpips = $data.lpips_mean
        $psnr = $data.psnr_mean
    }

    cmd /c "rmdir `"$junction`""

    $results += [PSCustomObject]@{
        Experiment = $dir.Name
        SSIM = $ssim
        LPIPS = $lpips
        PSNR = $psnr
        Date = (Get-Item $ply).LastWriteTime.ToString("MM-dd")
    }

    Write-Host "  => SSIM=$ssim LPIPS=$lpips PSNR=$psnr" -ForegroundColor Green
}

Write-Host "`n`n========== SUMMARY ==========" -ForegroundColor Yellow
$results | Format-Table -AutoSize

# Save CSV
$csvPath = Join-Path $scene1 "scene1_all_metrics.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "Saved to: $csvPath" -ForegroundColor Green

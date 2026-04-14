# Render preview video for quality review
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$outputDir = "$scene1\output_simple_radial"
$pshtFile = "$outputDir\scene.psht"
$postshotCli = "C:\Program Files\Jawset Postshot\bin\postshot-cli.exe"

if (-not (Test-Path $pshtFile)) {
    Write-Host "ERROR: PSHT file not found: $pshtFile"
    exit 1
}

Write-Host "=== Rendering Preview Video ==="
Write-Host "Model: $pshtFile"
Write-Host ""

# Render video
$outputVideo = "$outputDir\render_preview.mp4"
Write-Host "Output: $outputVideo"
Write-Host ""

Write-Host "Starting render..."
& $postshotCli render `
    --input $pshtFile `
    --output $outputVideo `
    --width 1920 `
    --height 1080 `
    --fps 30 `
    --orbit `
    --duration 10

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: Video rendered"
    $size = [math]::Round((Get-Item $outputVideo).Length / 1MB, 1)
    Write-Host "File size: $size MB"
    Write-Host "Location: $outputVideo"
} else {
    Write-Host "ERROR: Render failed with code $LASTEXITCODE"
}

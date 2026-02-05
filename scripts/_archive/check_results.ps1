# Check results after pipeline completion
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

Write-Host "=== Results Check ===" -ForegroundColor Cyan
Write-Host "Scene1: $scene1"
Write-Host ""

Write-Host "Root contents:" -ForegroundColor Yellow
Get-ChildItem -LiteralPath $scene1 | ForEach-Object {
    Write-Host "  $($_.Name)$(if ($_.PSIsContainer) { '/' })"
}

Write-Host ""
Write-Host "output/ contents:" -ForegroundColor Yellow
$outputDir = Join-Path $scene1 'output'
if (Test-Path $outputDir) {
    Get-ChildItem -LiteralPath $outputDir | ForEach-Object {
        Write-Host "  $($_.Name)$(if ($_.PSIsContainer) { '/' })"
    }
} else {
    Write-Host "  [Directory not found]" -ForegroundColor Red
}

Write-Host ""
Write-Host "output_0.2fps/ contents:" -ForegroundColor Yellow
$output02Dir = Join-Path $scene1 'output_0.2fps'
if (Test-Path $output02Dir) {
    Get-ChildItem -LiteralPath $output02Dir | ForEach-Object {
        Write-Host "  $($_.Name)$(if ($_.PSIsContainer) { '/' })"
    }
} else {
    Write-Host "  [Directory not found]" -ForegroundColor Red
}

Write-Host ""
Write-Host "visualizations/ contents:" -ForegroundColor Yellow
$vizDir = Join-Path $scene1 'visualizations'
if (Test-Path $vizDir) {
    Get-ChildItem -LiteralPath $vizDir | ForEach-Object {
        Write-Host "  $($_.Name) ($($_.Length) bytes)"
    }
} else {
    Write-Host "  [Directory not found]" -ForegroundColor Red
}

Write-Host ""
Write-Host "output/visualizations/ contents:" -ForegroundColor Yellow
$vizOutputDir = Join-Path $scene1 'output\visualizations'
if (Test-Path $vizOutputDir) {
    Get-ChildItem -LiteralPath $vizOutputDir | ForEach-Object {
        Write-Host "  $($_.Name) ($($_.Length) bytes)"
    }
} else {
    Write-Host "  [Directory not found]" -ForegroundColor Red
}

Write-Host ""
Write-Host "Looking for .psht and .ply files:" -ForegroundColor Yellow
Get-ChildItem -LiteralPath $scene1 -Recurse -Include @('*.psht', '*.ply') -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  $($_.FullName -replace [regex]::Escape($scene1), '.')"
}

Write-Host ""
Write-Host "Done."

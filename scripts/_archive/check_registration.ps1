# Check COLMAP registration for Scene 1
param()

# Find Python
$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
if (-not (Test-Path $pythonPath)) {
    $pythonPath = "python"
}

# Get scene1 path
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]

Write-Host "Scene: $($scene1.Name)" -ForegroundColor Cyan
Write-Host ""

$sparseDir = Join-Path $scene1.FullName 'output\colmap_output\sparse'
if (-not (Test-Path -LiteralPath $sparseDir)) {
    Write-Host "ERROR: Sparse directory not found: $sparseDir" -ForegroundColor Red
    exit 1
}

# Check each reconstruction
$reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory | Sort-Object Name

foreach ($recon in $reconFolders) {
    Write-Host "========================================" -ForegroundColor White
    Write-Host "Reconstruction $($recon.Name)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor White

    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $recon.FullName
    Write-Host ""
}

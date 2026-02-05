# Simple merge - just merge the first two reconstructions
param()

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$scenes = Get-ChildItem -LiteralPath 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName

$sparsePath = Join-Path $scene1 "output_improved_registration\sparse"
$outputPath = Join-Path $scene1 "output_improved_registration\sparse_merged_final"

Write-Host "Merging reconstructions 0 and 1..." -ForegroundColor Cyan

# Clean output
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$mergeArgs = @(
    "model_merger",
    "--input_path1", (Join-Path $sparsePath "0"),
    "--input_path2", (Join-Path $sparsePath "1"),
    "--output_path", $outputPath
)

Write-Host "Running: colmap $($mergeArgs -join ' ')" -ForegroundColor DarkGray

$process = Start-Process -FilePath $colmapExe -ArgumentList $mergeArgs -NoNewWindow -Wait -PassThru

Write-Host ""
Write-Host "Output: $outputPath" -ForegroundColor Green

# Check result
$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
if (Test-Path $pythonPath) {
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $outputPath
}

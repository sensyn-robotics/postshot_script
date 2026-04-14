# Find PSHT and PLY files
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$outputDir = "$scene1\output_simple_radial"

Write-Host "Looking in: $outputDir"
Write-Host ""

$files = Get-ChildItem $outputDir -Recurse -File | Where-Object { $_.Extension -in ".psht",".ply" }
foreach ($f in $files) {
    $sizeMB = [math]::Round($f.Length / 1MB, 1)
    $relPath = $f.FullName.Replace($outputDir, "")
    Write-Host "$relPath ($sizeMB MB)"
}

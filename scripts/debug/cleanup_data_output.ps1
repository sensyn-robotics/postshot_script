# Cleanup output directories from C:\postshot_script\data scenes
$dataPath = "C:\postshot_script\data"
$scenes = Get-ChildItem -LiteralPath $dataPath -Directory
foreach ($scene in $scenes) {
    $outDir = Join-Path $scene.FullName "output"
    if (Test-Path -LiteralPath $outDir) {
        Write-Host "Removing: $outDir"
        Remove-Item -LiteralPath $outDir -Recurse -Force
    }
}
Write-Host "Cleanup complete."

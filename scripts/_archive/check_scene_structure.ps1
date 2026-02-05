# Check scene structure
param([int]$SceneIndex = 0)
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[$SceneIndex]
Write-Host "Scene: $($scene.Name)"
$outputPath = Join-Path $scene.FullName "output_simple_radial"
Write-Host "Output path: $outputPath"
if (Test-Path -LiteralPath $outputPath) {
    Get-ChildItem -LiteralPath $outputPath -Recurse -Directory | ForEach-Object {
        Write-Host "  $($_.FullName)"
    }
} else {
    Write-Host "Output path does not exist"
}

# List output directories in scene1
$scenes = Get-ChildItem -LiteralPath "C:\postshot_test_data" -Directory | Sort-Object Name
$scene = $scenes[0].FullName
Write-Host "Scene: $($scenes[0].Name)"
Write-Host ""
Write-Host "Existing outputs:"
Get-ChildItem -LiteralPath $scene -Directory | Where-Object { $_.Name -like "output*" } | ForEach-Object {
    Write-Host ("  " + $_.Name)
}

$scenes = Get-ChildItem "C:\postshot_test_data" -Directory
foreach ($scene in $scenes) {
    Write-Host "=== $($scene.Name) ==="
    Get-ChildItem $scene.FullName -Directory | ForEach-Object { Write-Host "  $($_.Name)" }
}

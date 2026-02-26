$scenes = Get-ChildItem -LiteralPath 'C:\postshot_script\data\tower' -Directory | Sort-Object Name
foreach ($scene in $scenes) {
    Write-Host "`n=== $($scene.Name) ==="
    $imagesDir = Join-Path $scene.FullName "output\images"
    if (Test-Path -LiteralPath $imagesDir) {
        $subDirs = Get-ChildItem -LiteralPath $imagesDir -Directory -ErrorAction SilentlyContinue
        foreach ($sub in $subDirs) {
            $count = (Get-ChildItem -LiteralPath $sub.FullName -File -ErrorAction SilentlyContinue).Count
            Write-Host "  $($sub.Name): $count frames"
        }
    } else {
        Write-Host "  No images directory"
    }
}

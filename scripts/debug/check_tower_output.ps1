$scenes = Get-ChildItem -LiteralPath 'C:\postshot_script\data\tower' -Directory | Sort-Object Name
foreach ($scene in $scenes) {
    Write-Host "`n=== $($scene.Name) ==="
    $outputDir = Join-Path $scene.FullName "output"
    if (Test-Path -LiteralPath $outputDir) {
        $items = Get-ChildItem -LiteralPath $outputDir
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                $count = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                Write-Host "  [DIR] $($item.Name) ($count files)"
            } else {
                $sizeMB = [math]::Round($item.Length / 1MB, 1)
                Write-Host "  $($item.Name) (${sizeMB} MB)"
            }
        }
    } else {
        Write-Host "  No output directory"
    }
}

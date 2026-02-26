$scenes = Get-ChildItem -LiteralPath 'C:\postshot_script\data\tower' -Directory | Sort-Object Name
foreach ($scene in $scenes) {
    Write-Host "`n=== $($scene.Name) ==="
    $items = Get-ChildItem -LiteralPath $scene.FullName
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            Write-Host "  [DIR] $($item.Name)"
            $subItems = Get-ChildItem -LiteralPath $item.FullName -ErrorAction SilentlyContinue
            foreach ($sub in $subItems) {
                if ($sub.PSIsContainer) {
                    Write-Host "    [DIR] $($sub.Name)"
                } else {
                    Write-Host "    $($sub.Name)"
                }
            }
        } else {
            $sizeMB = [math]::Round($item.Length / 1MB, 1)
            Write-Host "  $($item.Name) (${sizeMB} MB)"
        }
    }
}

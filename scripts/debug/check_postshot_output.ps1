# Check Postshot output for scene 1 reconstructions
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName

$outputs = Get-ChildItem $scene1 -Directory | Where-Object { $_.Name -like "output*" }

Write-Host "=== Postshot outputs for Scene 1 ==="
Write-Host ""

foreach ($out in $outputs) {
    $psht = Get-ChildItem $out.FullName -Recurse -Filter "*.psht" -ErrorAction SilentlyContinue | Select-Object -First 1
    $ply = Get-ChildItem $out.FullName -Recurse -Filter "*.ply" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($psht -or $ply) {
        Write-Host "$($out.Name):"
        if ($psht) {
            $sizeMB = [math]::Round($psht.Length / 1MB, 1)
            Write-Host "  PSHT: $($psht.Name) ($sizeMB MB)"
        }
        if ($ply) {
            $sizeMB = [math]::Round($ply.Length / 1MB, 1)
            Write-Host "  PLY:  $($ply.Name) ($sizeMB MB)"
        }
        Write-Host ""
    }
}

# Show which directories have no Postshot output
Write-Host "=== Without Postshot output ==="
foreach ($out in $outputs) {
    $psht = Get-ChildItem $out.FullName -Recurse -Filter "*.psht" -ErrorAction SilentlyContinue
    $ply = Get-ChildItem $out.FullName -Recurse -Filter "*.ply" -ErrorAction SilentlyContinue

    if (-not $psht -and -not $ply) {
        # Check if sparse exists
        $hasSparse = Test-Path "$($out.FullName)\sparse\0"
        if ($hasSparse) {
            Write-Host "  $($out.Name) (has sparse, no Postshot)"
        } else {
            Write-Host "  $($out.Name) (no sparse, no Postshot)"
        }
    }
}

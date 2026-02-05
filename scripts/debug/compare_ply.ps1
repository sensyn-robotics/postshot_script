# Compare PLY files
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName

Write-Host "=== PLY Comparison ==="
Write-Host ""

$outputs = @("output", "output_simple_radial")
foreach ($outName in $outputs) {
    $plyFile = "$scene1\$outName\scene.ply"
    if (Test-Path $plyFile) {
        Write-Host "--- $outName ---"
        $sizeMB = [math]::Round((Get-Item $plyFile).Length / 1MB, 1)
        Write-Host "  Size: $sizeMB MB"

        # Read vertex count from header
        $reader = [System.IO.StreamReader]::new($plyFile)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -match "element vertex (\d+)") {
                Write-Host "  Splats: $($Matches[1])"
                break
            }
            if ($line -eq "end_header") { break }
        }
        $reader.Close()
        Write-Host ""
    }
}

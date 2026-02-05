# Count cameras in the converted images.txt
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName
$imagesTxt = "$scene1\output_simple_radial\sparse_txt\images.txt"

if (Test-Path $imagesTxt) {
    $content = Get-Content $imagesTxt
    Write-Host "Total lines: $($content.Count)"
    Write-Host ""

    # First few lines
    Write-Host "=== First 10 lines ==="
    $content | Select-Object -First 10

    Write-Host ""
    Write-Host "=== Camera counts ==="
    $wLines = $content | Where-Object { $_ -match 'video_W' }
    $zLines = $content | Where-Object { $_ -match 'video_Z' }
    Write-Host "Lines with video_W: $($wLines.Count)"
    Write-Host "Lines with video_Z: $($zLines.Count)"
    Write-Host ""
    Write-Host "Total registered: $($wLines.Count + $zLines.Count)"
} else {
    Write-Host "File not found: $imagesTxt"
}

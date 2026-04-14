# Check sparse reconstruction quality for scene 1 outputs
$scene1 = (Get-ChildItem "C:\postshot_test_data" -Directory | Select-Object -First 1).FullName

Write-Host "`n=== Scene 1 Reconstruction Quality ===" -ForegroundColor Cyan

$outputs = Get-ChildItem $scene1 -Directory | Where-Object { $_.Name -like "output*" }
foreach ($out in $outputs) {
    $sparseDir = "$($out.FullName)\sparse\0"
    if (Test-Path $sparseDir) {
        $points3D = "$sparseDir\points3D.bin"
        $images = "$sparseDir\images.bin"
        if (Test-Path $points3D) {
            $pointsSize = (Get-Item $points3D).Length / 1KB
            $imagesSize = if (Test-Path $images) { (Get-Item $images).Length / 1KB } else { 0 }
            Write-Host "`n$($out.Name):" -ForegroundColor Yellow
            Write-Host "  points3D.bin: $([math]::Round($pointsSize, 1)) KB"
            Write-Host "  images.bin: $([math]::Round($imagesSize, 1)) KB"
        }
    } else {
        Write-Host "`n$($out.Name): No sparse/0 directory" -ForegroundColor DarkGray
    }
}

# Test new cross-camera matching with temporal overlap

$testDataPath = "C:\postshot_test_data"
$scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Select-Object -First 1
$imagesDir = Join-Path $scene1Dir.FullName "output\images"
$outputPath = "C:\Postshot_Temp\test_match_pairs.txt"

Write-Host "=== Testing New Match Pairs Generation ===" -ForegroundColor Cyan
Write-Host "Images dir: $imagesDir"
Write-Host "Output: $outputPath"
Write-Host ""

# Run with default CrossCameraTemporalOverlap = 5
$scriptPath = Join-Path $PSScriptRoot "generate_match_pairs.ps1"
& $scriptPath -ImagesDir $imagesDir -OutputPath $outputPath -TemporalOverlap 10 -CrossCameraTemporalOverlap 5

# Count pairs by type
Write-Host ""
Write-Host "=== Counting Pairs by Type ===" -ForegroundColor Cyan

$content = Get-Content -LiteralPath $outputPath
$totalPairs = $content.Count

$wwPairs = 0
$zzPairs = 0
$wzPairs = 0

foreach ($line in $content) {
    if ($line -match "video_W.*video_W") {
        $wwPairs++
    }
    elseif ($line -match "video_Z.*video_Z") {
        $zzPairs++
    }
    elseif ($line -match "video_W.*video_Z" -or $line -match "video_Z.*video_W") {
        $wzPairs++
    }
}

Write-Host ""
Write-Host "Total pairs: $totalPairs"
Write-Host "  W <-> W (intra-Wide):  $wwPairs"
Write-Host "  Z <-> Z (intra-Zoom):  $zzPairs"
Write-Host "  W <-> Z (cross-camera): $wzPairs" -ForegroundColor Yellow

$crossRatio = [math]::Round(($wzPairs / $totalPairs) * 100, 1)
Write-Host ""
Write-Host "Cross-camera ratio: $crossRatio%" -ForegroundColor $(if ($crossRatio -lt 10) { "Red" } elseif ($crossRatio -lt 20) { "Yellow" } else { "Green" })

# Compare with old
Write-Host ""
Write-Host "=== Comparison ===" -ForegroundColor Cyan
Write-Host "Old cross-camera pairs: 253 (4.9%)" -ForegroundColor Gray
Write-Host "New cross-camera pairs: $wzPairs ($crossRatio%)" -ForegroundColor Green

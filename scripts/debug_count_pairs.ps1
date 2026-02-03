# Debug script to count match pairs by type

$testDataPath = "C:\postshot_test_data"
$scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Select-Object -First 1
$matchPairsPath = Join-Path $scene1Dir.FullName "output\colmap_output\match_pairs.txt"

if (-not (Test-Path -LiteralPath $matchPairsPath)) {
    Write-Host "ERROR: Match pairs file not found: $matchPairsPath" -ForegroundColor Red
    exit 1
}

Write-Host "=== Match Pairs Analysis ===" -ForegroundColor Cyan
Write-Host "File: $matchPairsPath" -ForegroundColor Gray

$content = Get-Content -LiteralPath $matchPairsPath
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
Write-Host "Cross-camera ratio: $crossRatio%" -ForegroundColor $(if ($crossRatio -lt 10) { "Red" } else { "Green" })

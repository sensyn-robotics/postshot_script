# Check frame counts
$scenes = Get-ChildItem 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]
$wDir = Join-Path $scene1.FullName 'output\images\video_W'
$zDir = Join-Path $scene1.FullName 'output\images\video_Z'
Write-Host "Scene 1: $($scene1.FullName)"
Write-Host "W frames: $((Get-ChildItem $wDir -Filter '*.png' -ErrorAction SilentlyContinue).Count)"
Write-Host "Z frames: $((Get-ChildItem $zDir -Filter '*.png' -ErrorAction SilentlyContinue).Count)"
$dbPath = Join-Path $scene1.FullName 'output\colmap_output\database.db'
Write-Host "Database exists: $(Test-Path $dbPath)"

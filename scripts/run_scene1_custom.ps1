# Temporary script to run Scene 1 with custom matching
$scenes = Get-ChildItem 'C:\postshot_test_data' -Directory | Sort-Object Name
$scene1 = $scenes[0]
Write-Host "Running pipeline on: $($scene1.FullName)"
& "$PSScriptRoot\run_pipeline_dual_camera.ps1" -InputPath $scene1.FullName

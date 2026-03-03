$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
$configPath = "config\pipeline_tower.json"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name

# Scene 1: COLMAP done, resume from stage 6
Write-Host "`n======== Scene 1 (stages 6-7): $($scenes[0].Name) ========" -ForegroundColor Cyan
& ".\scripts\run_pipeline_single.ps1" `
    -ConfigPath $configPath `
    -ScenePath $scenes[0].FullName `
    -StartStage 6 -EndStage 7
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Scene 1 failed with exit code $LASTEXITCODE" -ForegroundColor Red
}

# Scenes 2 and 3: full COLMAP + Postshot (stages 3-7)
foreach ($s in $scenes[1..2]) {
    Write-Host "`n======== Processing (stages 3-7): $($s.Name) ========" -ForegroundColor Cyan
    & ".\scripts\run_pipeline_single.ps1" `
        -ConfigPath $configPath `
        -ScenePath $s.FullName `
        -StartStage 3 -EndStage 7
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Scene $($s.Name) failed with exit code $LASTEXITCODE" -ForegroundColor Red
    }
}
Write-Host "`n======== ALL SCENES DONE ========" -ForegroundColor Green

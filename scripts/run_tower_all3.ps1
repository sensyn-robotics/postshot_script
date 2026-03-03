param(
    [int]$StartStage = 3,
    [int]$EndStage = 7
)

$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
$configPath = "config\pipeline_tower.json"
$scenes = Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name

Write-Host "Found $($scenes.Count) scenes:"
foreach ($s in $scenes) { Write-Host "  $($s.Name)" }

foreach ($s in $scenes) {
    Write-Host "`n======== Processing: $($s.Name) ========" -ForegroundColor Cyan
    & ".\scripts\run_pipeline_single.ps1" `
        -ConfigPath $configPath `
        -ScenePath $s.FullName `
        -StartStage $StartStage -EndStage $EndStage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Scene $($s.Name) failed with exit code $LASTEXITCODE" -ForegroundColor Red
    }
}
Write-Host "`n======== ALL SCENES DONE ========" -ForegroundColor Green

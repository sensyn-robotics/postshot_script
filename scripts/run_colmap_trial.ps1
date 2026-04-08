# run_colmap_trial.ps1
# Fast COLMAP-only trial: runs stages 1-5 on all scenes, checks registration.
# Stops immediately if any scene fails 50% registration threshold.
# Prevents sleep, runs in foreground.

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [int]$StartStage = 1,

    [Parameter(Mandatory=$false)]
    [double]$MinRegistrationPct = 50.0
)

$ErrorActionPreference = 'Stop'
Set-Location C:\postshot_script

# Prevent sleep, allow screen lock
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 1
powercfg /change monitor-timeout-dc 1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACTIVE SCHEME_CURRENT

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$towerPath = $config.pipeline.test_data_path
$scenes = Get-ChildItem -LiteralPath $towerPath -Directory | Sort-Object Name
$outputDirName = $config.output.dir_name
$pythonExe = $config.paths.python

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  COLMAP Trial (stages $StartStage-5)" -ForegroundColor Cyan
Write-Host "  Min registration: $MinRegistrationPct%" -ForegroundColor Cyan
Write-Host "  Scenes: $($scenes.Count)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$allPass = $true

foreach ($scene in $scenes) {
    Write-Host ""
    Write-Host "--- $($scene.Name) ---" -ForegroundColor Cyan

    & .\scripts\run_pipeline_allscene.ps1 -ConfigPath $ConfigPath -ScenePath $scene.FullName -StartStage $StartStage -EndStage 5

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED: Pipeline error (exit code $LASTEXITCODE)" -ForegroundColor Red
        $allPass = $false
        break
    }

    # Check registration
    $sparseDir = Join-Path $scene.FullName "$outputDirName\colmap\sparse"
    $imagesDir = Join-Path $scene.FullName "$outputDirName\images"

    if (-not (Test-Path -LiteralPath $sparseDir)) {
        Write-Host "  FAILED: No sparse directory" -ForegroundColor Red
        $allPass = $false
        break
    }

    $totalImages = (Get-ChildItem -LiteralPath $imagesDir -Recurse -File |
        Where-Object { $_.Extension -in @('.png','.jpg','.jpeg','.PNG','.JPG','.JPEG') }).Count

    $regResult = & $pythonExe -c @"
import struct, os
base = r'$($sparseDir.Replace("'","''"))'
best = 0
for m in os.listdir(base):
    p = os.path.join(base, m, 'images.bin')
    if os.path.isfile(p):
        with open(p, 'rb') as f:
            n = struct.unpack('<Q', f.read(8))[0]
        if n > best: best = n
print(best)
"@ 2>&1

    $registered = [int]$regResult
    $pct = [math]::Round(100 * $registered / $totalImages, 1)

    Write-Host "  Registration: $registered / $totalImages ($pct%)" -ForegroundColor $(if ($pct -ge $MinRegistrationPct) { "Green" } else { "Red" })

    if ($pct -lt $MinRegistrationPct) {
        Write-Host "  FAILED: Below $MinRegistrationPct% threshold. Stopping trial." -ForegroundColor Red
        $allPass = $false
        break
    }
}

# Restore sleep
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5

Write-Host ""
if ($allPass) {
    Write-Host "ALL SCENES PASSED REGISTRATION CHECK" -ForegroundColor Green
} else {
    Write-Host "TRIAL FAILED - parameter set rejected" -ForegroundColor Red
}

exit $(if ($allPass) { 0 } else { 1 })

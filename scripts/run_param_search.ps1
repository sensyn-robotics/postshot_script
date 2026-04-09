# run_param_search.ps1
# Automated parameter search: changes 1 parameter at a time.
# Always uses sequential matching. Tests fps, max_features, min_model_size.
# Stops immediately on registration failure, moves to next parameter set.
#
# Usage:
#   .\scripts\run_param_search.ps1 -ConfigPath config\pipeline.json

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [double]$MinRegistrationPct = 50.0
)

$ErrorActionPreference = 'Stop'
Set-Location C:\postshot_script

# Prevent sleep, allow screen lock
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 10
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACTIVE SCHEME_CURRENT

# Baseline: COLMAP defaults + sequential matching + filter_degenerate
# Only change 1 parameter per trial from this baseline
$baseline = @{
    fps = 2
    target_frames = 600
    max_features = 8192    # COLMAP default
    min_model_size = 10    # COLMAP default
}

# Parameter search: change 1 param at a time
$paramSets = @(
    # --- Baseline (COLMAP defaults) ---
    @{ name = "baseline_2fps_8k_mms10"; fps = 2; target_frames = 600; max_features = 8192; min_model_size = 10; start_stage = 1 },

    # --- Vary max_features (keep fps=2, mms=10) ---
    @{ name = "features_16k"; fps = 2; target_frames = 600; max_features = 16384; min_model_size = 10; start_stage = 3 },

    # --- Vary min_model_size (keep fps=2, features=8k) ---
    @{ name = "mms_30"; fps = 2; target_frames = 600; max_features = 8192; min_model_size = 30; start_stage = 5 },
    @{ name = "mms_50"; fps = 2; target_frames = 600; max_features = 8192; min_model_size = 50; start_stage = 5 },

    # --- Vary fps (keep features=8k, mms=10) ---
    @{ name = "fps_1"; fps = 1; target_frames = 600; max_features = 8192; min_model_size = 10; start_stage = 1 },
    @{ name = "fps_3"; fps = 3; target_frames = 600; max_features = 8192; min_model_size = 10; start_stage = 1 }
)

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$towerPath = $config.pipeline.test_data_path
$scenes = Get-ChildItem -LiteralPath $towerPath -Directory | Sort-Object Name
$outputDirName = $config.output.dir_name
$pythonExe = $config.paths.python

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Parameter Search (1 param at a time)" -ForegroundColor Cyan
Write-Host "  Baseline: fps=2, features=8192, mms=10" -ForegroundColor Cyan
Write-Host "  Matching: sequential (always)" -ForegroundColor Cyan
Write-Host "  Trials: $($paramSets.Count)" -ForegroundColor Cyan
Write-Host "  Scenes: $($scenes.Count)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Apply-ParamSet {
    param($configPath, $ps)
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $cfg.pipeline.overwrite_result = $true
    $cfg.stage_01_extract.fps = $ps.fps
    $cfg.stage_01_extract.target_frames = $ps.target_frames
    $cfg.stage_03_features.max_features = $ps.max_features
    $cfg.stage_04_matching.type = "sequential"
    $cfg.stage_05_mapper.min_model_size = $ps.min_model_size
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

function Check-Registration {
    param($scenePath, $outputDirName, $pythonExe, $minPct)
    $sparseDir = Join-Path $scenePath "$outputDirName\colmap\sparse"
    $imagesDir = Join-Path $scenePath "$outputDirName\images"
    if (-not (Test-Path -LiteralPath $sparseDir)) { return @{ pass = $false; pct = 0; registered = 0; total = 0 } }
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
    $pct = if ($totalImages -gt 0) { [math]::Round(100 * $registered / $totalImages, 1) } else { 0 }
    return @{ pass = ($pct -ge $minPct); pct = $pct; registered = $registered; total = $totalImages }
}

$winningTrial = $null
$results = @()

foreach ($ps in $paramSets) {
    Write-Host ""
    Write-Host "########################################################" -ForegroundColor Yellow
    Write-Host "  $($ps.name)" -ForegroundColor Yellow
    Write-Host "  fps=$($ps.fps) features=$($ps.max_features) min_model_size=$($ps.min_model_size)" -ForegroundColor Yellow
    Write-Host "  start_stage=$($ps.start_stage)" -ForegroundColor Yellow
    Write-Host "########################################################" -ForegroundColor Yellow

    Apply-ParamSet -configPath $ConfigPath -ps $ps

    $allPass = $true
    $trialResults = @()

    foreach ($scene in $scenes) {
        Write-Host ""
        Write-Host "--- $($scene.Name) ---" -ForegroundColor Cyan

        try {
            & .\scripts\run_pipeline_allscene.ps1 -ConfigPath $ConfigPath -ScenePath $scene.FullName -StartStage $ps.start_stage -EndStage 5
        } catch {
            Write-Host "  Pipeline error: $_" -ForegroundColor Red
            $LASTEXITCODE = 1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED: exit code $LASTEXITCODE" -ForegroundColor Red
            $allPass = $false
            $trialResults += "$($scene.Name.Substring(0,20)): FAILED"
            break
        }

        $reg = Check-Registration -scenePath $scene.FullName -outputDirName $outputDirName -pythonExe $pythonExe -minPct $MinRegistrationPct
        $trialResults += "$($scene.Name.Substring(0,20)): $($reg.registered)/$($reg.total) ($($reg.pct)%)"
        Write-Host "  Registration: $($reg.registered)/$($reg.total) ($($reg.pct)%)" -ForegroundColor $(if ($reg.pass) { "Green" } else { "Red" })

        if (-not $reg.pass) {
            Write-Host "  FAILED: Below $MinRegistrationPct%. Aborting trial." -ForegroundColor Red
            $allPass = $false
            break
        }
    }

    $results += [PSCustomObject]@{ Trial = $ps.name; Pass = $allPass; Details = ($trialResults -join " | ") }

    if ($allPass) {
        Write-Host ""
        Write-Host "ALL SCENES PASSED with $($ps.name)!" -ForegroundColor Green
        $winningTrial = $ps
        break
    } else {
        Write-Host ""
        Write-Host "Trial $($ps.name) FAILED. Next..." -ForegroundColor Yellow
    }
}

# Summary of all trials
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SEARCH RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Wrap

if ($winningTrial) {
    Write-Host ""
    Write-Host "  WINNER: $($winningTrial.name)" -ForegroundColor Green
    Write-Host "  Running full training (stages 6-7)..." -ForegroundColor Green

    foreach ($scene in $scenes) {
        Write-Host ""
        Write-Host "--- Training: $($scene.Name) ---" -ForegroundColor Cyan
        try {
            & .\scripts\run_pipeline_allscene.ps1 -ConfigPath $ConfigPath -ScenePath $scene.FullName -StartStage 6 -EndStage 7
        } catch {
            Write-Host "  Training error: $_" -ForegroundColor Red
            $LASTEXITCODE = 1
        }
    }

    # Final quality
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  FINAL QUALITY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    foreach ($scene in $scenes) {
        $qPath = Join-Path $scene.FullName "$outputDirName\postshot\quality.json"
        if (Test-Path -LiteralPath $qPath) {
            $q = Get-Content $qPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pass = ($q.ssim -ge 0.8 -and $q.lpips -lt 0.5)
            Write-Host "  $($scene.Name.Substring(0,30))... SSIM=$($q.ssim) LPIPS=$($q.lpips) $(if ($pass) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($pass) { "Green" } else { "Red" })
        } else {
            Write-Host "  $($scene.Name.Substring(0,30))... NO DATA" -ForegroundColor Red
        }
    }
} else {
    Write-Host ""
    Write-Host "  ALL TRIALS FAILED" -ForegroundColor Red
}

# Restore sleep
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 100
powercfg /change monitor-timeout-dc 5
Write-Host "Sleep settings restored" -ForegroundColor Yellow

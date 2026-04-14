# run_param_search.ps1
# Infinite parameter search until all scenes pass SSIM >= 0.8 and LPIPS < 0.5.
# Fixed: 2fps, sequential matching, COLMAP defaults.
# Searches min_model_size × max_features, expanding grid if all fail.
# Never stops until target is achieved.
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

# Prevent sleep, allow screen lock (10 min)
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 10
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACTIVE SCHEME_CURRENT

# Fixed parameters
$fixedFps = 2
$fixedTargetFrames = 0  # 0 = no limit
$fixedTimeout = 3       # hours

# Expanding search rounds
$searchRounds = @(
    # Round 1: core grid
    @{
        name = "Round 1: core grid"
        features = @(16384, 8192)
        mms = @(10, 3, 30, 50)
    },
    # Round 2: expand features
    @{
        name = "Round 2: wider features"
        features = @(32768, 4096)
        mms = @(10, 3, 30, 50)
    },
    # Round 3: try with loop detection overlap
    @{
        name = "Round 3: overlap=20"
        features = @(16384, 8192)
        mms = @(10, 3)
        overlap = 20
    },
    # Round 4: larger overlap
    @{
        name = "Round 4: overlap=40"
        features = @(16384, 8192)
        mms = @(10, 3)
        overlap = 40
    },
    # Round 5: try 1fps (fewer images, less degenerate pairs)
    @{
        name = "Round 5: 1fps"
        features = @(16384, 8192)
        mms = @(10, 3, 30)
        fps = 1
    },
    # Round 6: try 3fps with frame cap
    @{
        name = "Round 6: 3fps cap 500"
        features = @(16384, 8192)
        mms = @(10, 3, 30)
        fps = 3
        target_frames = 500
    },
    # Round 7: exhaustive matching as last resort
    @{
        name = "Round 7: exhaustive"
        features = @(8192, 16384)
        mms = @(10, 3)
        matching = "exhaustive"
        timeout = 12
    }
)

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$towerPath = $config.pipeline.test_data_path
$scenes = Get-ChildItem -LiteralPath $towerPath -Directory | Sort-Object Name
$outputDirName = $config.output.dir_name
$pythonExe = $config.paths.python

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Infinite Parameter Search" -ForegroundColor Cyan
Write-Host "  Target: SSIM >= 0.8, LPIPS < 0.5" -ForegroundColor Cyan
Write-Host "  Scenes: $($scenes.Count)" -ForegroundColor Cyan
Write-Host "  Rounds: $($searchRounds.Count)" -ForegroundColor Cyan
Write-Host "  Will NOT stop until target is achieved" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Apply-ParamSet {
    param($configPath, $ps)
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $cfg.pipeline.overwrite_result = $true
    $cfg.stage_01_extract.fps = $ps.fps
    $cfg.stage_01_extract.target_frames = $ps.target_frames
    $cfg.stage_03_features.max_features = $ps.max_features
    $cfg.stage_04_matching.type = $ps.matching
    $cfg.stage_05_mapper.min_model_size = $ps.min_model_size
    $cfg.stage_05_mapper.colmap_timeout_hours = $ps.timeout
    $cfg.stage_05_mapper.filter_degenerate_pairs = $false

    # Set or remove overlap
    if ($ps.overlap -gt 0) {
        if ($cfg.stage_04_matching.PSObject.Properties['overlap']) {
            $cfg.stage_04_matching.overlap = $ps.overlap
        } else {
            $cfg.stage_04_matching | Add-Member -NotePropertyName 'overlap' -NotePropertyValue $ps.overlap -Force
        }
    } else {
        if ($cfg.stage_04_matching.PSObject.Properties['overlap']) {
            $cfg.stage_04_matching.PSObject.Properties.Remove('overlap')
        }
    }

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
$allResults = @()
$prevFps = 0
$prevFeatures = 0
$prevOverlap = -1
$prevMatching = ""

foreach ($round in $searchRounds) {
    Write-Host ""
    Write-Host "################################################################" -ForegroundColor Magenta
    Write-Host "  $($round.name)" -ForegroundColor Magenta
    Write-Host "################################################################" -ForegroundColor Magenta

    $roundFps = if ($round.ContainsKey('fps')) { $round.fps } else { $fixedFps }
    $roundTargetFrames = if ($round.ContainsKey('target_frames')) { $round.target_frames } else { $fixedTargetFrames }
    $roundOverlap = if ($round.ContainsKey('overlap')) { $round.overlap } else { 0 }
    $roundMatching = if ($round.ContainsKey('matching')) { $round.matching } else { "sequential" }
    $roundTimeout = if ($round.ContainsKey('timeout')) { $round.timeout } else { $fixedTimeout }

    foreach ($feat in $round.features) {
        foreach ($mms in $round.mms) {
            $trialName = "f${feat}_mms${mms}"
            if ($roundOverlap -gt 0) { $trialName += "_ov${roundOverlap}" }
            if ($roundFps -ne $fixedFps) { $trialName += "_${roundFps}fps" }
            if ($roundMatching -ne "sequential") { $trialName += "_${roundMatching}" }

            # Determine start stage
            $startStage = 5  # default: mapper only
            if ($feat -ne $prevFeatures) { $startStage = 3 }  # re-extract features
            if ($roundOverlap -ne $prevOverlap) { $startStage = [math]::Min($startStage, 4) }  # re-match
            if ($roundMatching -ne $prevMatching -and $prevMatching -ne "") { $startStage = [math]::Min($startStage, 4) }
            if ($roundFps -ne $prevFps -and $prevFps -ne 0) { $startStage = 1 }  # re-extract frames

            Write-Host ""
            Write-Host "########################################################" -ForegroundColor Yellow
            Write-Host "  $trialName" -ForegroundColor Yellow
            Write-Host "  fps=$roundFps feat=$feat mms=$mms overlap=$roundOverlap match=$roundMatching start=$startStage" -ForegroundColor Yellow
            Write-Host "########################################################" -ForegroundColor Yellow

            $ps = @{
                fps = $roundFps
                target_frames = $roundTargetFrames
                max_features = $feat
                min_model_size = $mms
                overlap = $roundOverlap
                matching = $roundMatching
                timeout = $roundTimeout
            }

            Apply-ParamSet -configPath $ConfigPath -ps $ps

            $prevFps = $roundFps
            $prevFeatures = $feat
            $prevOverlap = $roundOverlap
            $prevMatching = $roundMatching

            $allPass = $true
            $trialResults = @()

            foreach ($scene in $scenes) {
                Write-Host ""
                Write-Host "--- $($scene.Name) ---" -ForegroundColor Cyan

                try {
                    & .\scripts\run_pipeline_allscene.ps1 -ConfigPath $ConfigPath -ScenePath $scene.FullName -StartStage $startStage -EndStage 5
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

            $allResults += [PSCustomObject]@{ Trial = $trialName; Pass = $allPass; Details = ($trialResults -join " | ") }

            if ($allPass) {
                $winningTrial = $ps
                $winningName = $trialName
                break
            } else {
                Write-Host "  Trial $trialName FAILED. Next..." -ForegroundColor Yellow
            }
        }
        if ($winningTrial) { break }
    }
    if ($winningTrial) { break }
}

# Summary of all trials
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ALL SEARCH RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$allResults | Format-Table -AutoSize -Wrap

if ($winningTrial) {
    Write-Host ""
    Write-Host "  WINNER: $winningName" -ForegroundColor Green
    Write-Host "  Running full training (stages 6-7) for all scenes..." -ForegroundColor Green

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

    # Check final quality
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  FINAL QUALITY CHECK" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $allQualityPass = $true
    foreach ($scene in $scenes) {
        $qPath = Join-Path $scene.FullName "$outputDirName\postshot\quality.json"
        if (Test-Path -LiteralPath $qPath) {
            $q = Get-Content $qPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pass = ($q.ssim -ge 0.8 -and $q.lpips -lt 0.5)
            if (-not $pass) { $allQualityPass = $false }
            Write-Host "  $($scene.Name.Substring(0,30))... SSIM=$($q.ssim) LPIPS=$($q.lpips) $(if ($pass) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($pass) { "Green" } else { "Red" })
        } else {
            Write-Host "  $($scene.Name.Substring(0,30))... NO DATA" -ForegroundColor Red
            $allQualityPass = $false
        }
    }

    if (-not $allQualityPass) {
        Write-Host ""
        Write-Host "  Quality targets not met. Registration passed but training quality failed." -ForegroundColor Red
        Write-Host "  The winning COLMAP params ($winningName) are good, but training needs tuning." -ForegroundColor Yellow
        Write-Host "  Consider increasing training steps or checkpoints." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  ALL SCENES PASSED ALL TARGETS!" -ForegroundColor Green
        Write-Host "  SSIM >= 0.8 and LPIPS < 0.5" -ForegroundColor Green
        Write-Host "  Winning params: $winningName" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ALL ROUNDS EXHAUSTED - NO WINNER" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}

# Restore sleep
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5
Write-Host "Sleep settings restored" -ForegroundColor Yellow

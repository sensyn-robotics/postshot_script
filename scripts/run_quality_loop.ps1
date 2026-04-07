# run_quality_loop.ps1
# Iteratively run pipeline on all 3 tower scenes until quality targets are met.
# If targets not met, adjusts parameters and retries.
#
# Targets: SSIM >= 0.8, LPIPS < 0.5
#
# Usage:
#   .\scripts\run_quality_loop.ps1 -ConfigPath config\pipeline.json

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [int]$StartStage = 1,

    [Parameter(Mandatory=$false)]
    [int]$MaxIterations = 5
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

Set-Location $projectRoot

# Prevent sleep but allow screen lock
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 1
powercfg /change monitor-timeout-dc 1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACTIVE SCHEME_CURRENT
Write-Host "Sleep disabled, screen locks after 1 min" -ForegroundColor Yellow

$targetSSIM = 0.8
$targetLPIPS = 0.5

# Discover scenes
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$towerPath = $config.pipeline.test_data_path
$scenes = Get-ChildItem -LiteralPath $towerPath -Directory | Sort-Object Name

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Quality Loop" -ForegroundColor Cyan
Write-Host "  Targets: SSIM >= $targetSSIM, LPIPS < $targetLPIPS" -ForegroundColor Cyan
Write-Host "  Scenes: $($scenes.Count)" -ForegroundColor Cyan
Write-Host "  Max iterations: $MaxIterations" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Get-SceneQuality {
    param([string]$ScenePath, [string]$OutputDirName)
    $qPath = Join-Path $ScenePath "$OutputDirName\postshot\quality.json"
    if (Test-Path -LiteralPath $qPath) {
        $q = Get-Content $qPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @{
            ssim = $q.ssim
            lpips = $q.lpips
            pass = ($q.ssim -ge $targetSSIM -and $q.lpips -lt $targetLPIPS)
        }
    }
    return $null
}

for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
    Write-Host ""
    Write-Host "########################################################" -ForegroundColor Yellow
    Write-Host "  ITERATION $iteration / $MaxIterations" -ForegroundColor Yellow
    Write-Host "########################################################" -ForegroundColor Yellow

    # Reload config each iteration (may have been updated)
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $outputDirName = $config.output.dir_name

    $allPass = $true
    $results = @()

    foreach ($scene in $scenes) {
        Write-Host ""
        Write-Host "--- Processing: $($scene.Name) ---" -ForegroundColor Cyan

        # Check if already passing
        $existing = Get-SceneQuality -ScenePath $scene.FullName -OutputDirName $outputDirName
        if ($existing -and $existing.pass) {
            Write-Host "  Already passing: SSIM=$($existing.ssim), LPIPS=$($existing.lpips)" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Scene = $scene.Name
                SSIM = $existing.ssim
                LPIPS = $existing.lpips
                Pass = $true
            }
            continue
        }

        # Run pipeline
        Write-Host "  Running pipeline (stages $StartStage-7)..." -ForegroundColor White
        try {
            & "$projectRoot\scripts\run_pipeline_allscene.ps1" -ConfigPath $ConfigPath -ScenePath $scene.FullName -StartStage $StartStage -EndStage 7
        } catch {
            Write-Host "  ERROR: Pipeline failed: $_" -ForegroundColor Red
            $allPass = $false
            $results += [PSCustomObject]@{
                Scene = $scene.Name
                SSIM = "FAILED"
                LPIPS = "FAILED"
                Pass = $false
            }
            continue
        }

        # Check quality
        $quality = Get-SceneQuality -ScenePath $scene.FullName -OutputDirName $outputDirName
        if ($quality) {
            $passStr = if ($quality.pass) { "PASS" } else { "FAIL" }
            Write-Host "  Result: SSIM=$($quality.ssim), LPIPS=$($quality.lpips) [$passStr]" -ForegroundColor $(if ($quality.pass) { "Green" } else { "Red" })
            $results += [PSCustomObject]@{
                Scene = $scene.Name
                SSIM = $quality.ssim
                LPIPS = $quality.lpips
                Pass = $quality.pass
            }
            if (-not $quality.pass) { $allPass = $false }
        } else {
            Write-Host "  ERROR: No quality.json found" -ForegroundColor Red
            $allPass = $false
            $results += [PSCustomObject]@{
                Scene = $scene.Name
                SSIM = "NO DATA"
                LPIPS = "NO DATA"
                Pass = $false
            }
        }
    }

    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Iteration $iteration Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize

    if ($allPass) {
        Write-Host "ALL SCENES PASSED! Target achieved." -ForegroundColor Green
        break
    }

    if ($iteration -lt $MaxIterations) {
        Write-Host "  Some scenes failed. Adjusting parameters for next iteration..." -ForegroundColor Yellow

        # Strategy: increase training steps and checkpoints
        # Iteration 2: increase to 50k steps
        # Iteration 3: increase to 100k steps, increase FPS to 3
        # Iteration 4: exhaustive matching
        # Iteration 5: increase max_features to 32768

        $configObj = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        switch ($iteration) {
            1 {
                Write-Host "  -> Increasing training to 50k steps" -ForegroundColor Yellow
                $configObj.stage_06_train.checkpoints = @(10000, 30000, 50000)
                $configObj.pipeline.overwrite_result = $true
            }
            2 {
                Write-Host "  -> Increasing training to 100k steps, FPS to 3" -ForegroundColor Yellow
                $configObj.stage_06_train.checkpoints = @(30000, 50000, 100000)
                $configObj.stage_01_extract.fps = 3
                $configObj.pipeline.overwrite_result = $true
            }
            3 {
                Write-Host "  -> Switching to exhaustive matching" -ForegroundColor Yellow
                $configObj.stage_04_matching.type = "exhaustive"
                $configObj.pipeline.overwrite_result = $true
            }
            4 {
                Write-Host "  -> Increasing max_features to 32768" -ForegroundColor Yellow
                $configObj.stage_03_features.max_features = 32768
                $configObj.pipeline.overwrite_result = $true
            }
        }

        $configObj | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
        Write-Host "  Config updated. Starting next iteration..." -ForegroundColor Yellow

        # Reset StartStage for re-run (need full pipeline if FPS/matching changed)
        if ($iteration -ge 2) {
            $StartStage = 1
        }
    }
}

# Restore sleep settings
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5
Write-Host "Sleep settings restored" -ForegroundColor Yellow

# Final summary
Write-Host ""
Write-Host "========================================" -ForegroundColor $(if ($allPass) { "Green" } else { "Red" })
Write-Host "  QUALITY LOOP $(if ($allPass) { 'SUCCEEDED' } else { 'FINISHED (targets not fully met)' })" -ForegroundColor $(if ($allPass) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor $(if ($allPass) { "Green" } else { "Red" })

# run_scene1_quality_loop.ps1
# Infinite loop: keeps trying COLMAP strategies until quality gate passes,
# then trains Postshot and checks LPIPS. Stops only when LPIPS target is met.
#
# Usage:
#   powershell -NoProfile -File scripts\run_scene1_quality_loop.ps1
#   powershell -NoProfile -File scripts\run_scene1_quality_loop.ps1 -StartFrom 1

param(
    [int]$StartFrom = 1,
    [double]$TargetSsim = 0.80,
    [double]$TargetLpips = 0.50,
    [string]$ConfigPath = "config\pipeline_tower_scene1_fix.json"
)

$ErrorActionPreference = 'Stop'
$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
Set-Location C:\postshot_script

$scene1 = (Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name | Select-Object -First 1).FullName
$tempBase = "C:\Postshot_Temp"
$stagesDir = "C:\postshot_script\scripts\stages"
$qualityScript = "C:\postshot_script\scripts\check_sparse_quality.py"

# ============================================================
# Strategies: ordered by likelihood of success based on previous results
# Exhaustive matching is key for single-model reconstruction.
# ============================================================
$strategies = @(
    # --- Already ran (skip with -StartFrom 3) ---
    @{
        name = "11_2fps_exhaustive_16k_merge"
        desc = "2fps + exhaustive + 16k features + merge [ALREADY RAN: COLMAP FAIL]"
        fps = 2; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $true; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "12_2fps_exhaustive_16k_sift07"
        desc = "2fps + exhaustive + 16k + sift07 [ALREADY RAN: SSIM=0.686 LPIPS=0.734]"
        fps = 2; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.7; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    # --- New strategies: focus on more frames + higher features for tower ---
    @{
        name = "13_3fps_exhaustive_16k"
        desc = "3fps + exhaustive + 16k (more frames, auto train steps)"
        fps = 3; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "14_2fps_exhaustive_32k"
        desc = "2fps + exhaustive + 32k features (max features for dense points)"
        fps = 2; max_features = 32768; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "15_4fps_exhaustive_16k"
        desc = "4fps + exhaustive + 16k (maximum frame coverage)"
        fps = 4; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "16_3fps_exhaustive_32k"
        desc = "3fps + exhaustive + 32k features (max frames + max features)"
        fps = 3; max_features = 32768; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "17_2fps_exhaustive_32k_sift07"
        desc = "2fps + exhaustive + 32k + strict SIFT 0.7"
        fps = 2; max_features = 32768; matcher = "exhaustive"
        sift_max_ratio = 0.7; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "18_5fps_exhaustive_16k"
        desc = "5fps + exhaustive + 16k (very dense frames)"
        fps = 5; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "19_4fps_exhaustive_32k"
        desc = "4fps + exhaustive + 32k (dense frames + dense features)"
        fps = 4; max_features = 32768; matcher = "exhaustive"
        sift_max_ratio = 0.8; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    },
    @{
        name = "20_3fps_exhaustive_16k_sift07"
        desc = "3fps + exhaustive + 16k + strict SIFT 0.7"
        fps = 3; max_features = 16384; matcher = "exhaustive"
        sift_max_ratio = 0.7; guided = $false; loop_det = $false
        merge = $false; camera_model = "SIMPLE_RADIAL"
        min_model_size = 10; init_inliers = 100; abs_inliers = 30; abs_ratio = 0.25
    }
)

# ============================================================
# Helper: Build a temp config for an experiment
# ============================================================
function Build-Config {
    param($Strategy)

    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $cfg.pipeline.overwrite_result = $true
    $cfg.output.dir_name = "output_exp_$($Strategy.name)"

    $cfg.stage_01_extract.fps = $Strategy.fps
    $cfg.stage_03_features.max_features = $Strategy.max_features
    $cfg.stage_03_features.camera_model = $Strategy.camera_model
    $cfg.stage_04_matching.type = $Strategy.matcher
    $cfg.stage_04_matching.sift_max_ratio = $Strategy.sift_max_ratio
    $cfg.stage_04_matching.guided_matching = $Strategy.guided
    $cfg.stage_04_matching.loop_detection = $Strategy.loop_det
    $cfg.stage_05_mapper.merge_models = $Strategy.merge
    $cfg.stage_05_mapper.quality_gate = $true
    $cfg.stage_05_mapper.min_model_size = $Strategy.min_model_size
    $cfg.stage_05_mapper.init_min_num_inliers = $Strategy.init_inliers
    $cfg.stage_05_mapper.abs_pose_min_num_inliers = $Strategy.abs_inliers
    $cfg.stage_05_mapper.abs_pose_min_inlier_ratio = $Strategy.abs_ratio

    # Use higher training steps for better quality
    $cfg.stage_06_train.train_steps_limit = 0  # auto (until convergence)
    $cfg.stage_06_train.max_image_size = 3840

    $tempPath = Join-Path $tempBase "config_qloop_$($Strategy.name).json"
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $tempPath -Encoding UTF8
    return $tempPath
}

# ============================================================
# Helper: Check if images can be reused from an existing experiment
# ============================================================
function Find-ReusableImages {
    param([int]$Fps)

    $fpsMap = @{
        1 = "output_exp_01_sequential"
        2 = "output_exp_01_2fps_seq_loop_guided"
        3 = "output_exp_05_3fps_seq_loop_guided"
    }

    if ($fpsMap.ContainsKey($Fps)) {
        $reuseDir = Join-Path (Join-Path $scene1 $fpsMap[$Fps]) "images"
        if (Test-Path -LiteralPath $reuseDir) { return $reuseDir }
    }

    # Also check any output_exp_* that has the right fps in its images
    foreach ($dir in (Get-ChildItem -LiteralPath $scene1 -Directory | Where-Object { $_.Name -match '^output_exp_' })) {
        $imgDir = Join-Path $dir.FullName "images"
        if (Test-Path -LiteralPath $imgDir) {
            $imgCount = (Get-ChildItem -LiteralPath (Join-Path $imgDir "video_single") -File -ErrorAction SilentlyContinue).Count
            if ($imgCount -gt 0) {
                # Check if frame count matches expected fps
                # rough: 233/fps ~= 233 for 1fps, 466 for 2fps, 700 for 3fps
                $expectedMin = $Fps * 200
                $expectedMax = $Fps * 300
                if ($imgCount -ge $expectedMin -and $imgCount -le $expectedMax) {
                    return $imgDir
                }
            }
        }
    }
    return $null
}

# ============================================================
# Helper: Compute LPIPS
# ============================================================
function Compute-Lpips {
    param([string]$OutputDir)

    $plyPath = Join-Path $OutputDir "postshot\scene.ply"
    $sparseDir = Join-Path $OutputDir "colmap\sparse"
    $lpipsJson = Join-Path $OutputDir "postshot\lpips.json"

    if (-not (Test-Path -LiteralPath $plyPath)) { return 999.0 }

    $sparseModels = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue
    if (-not $sparseModels) { return 999.0 }
    $sparsePath = ($sparseModels | Sort-Object {
        (Get-Item -LiteralPath (Join-Path $_.FullName "images.bin") -ErrorAction SilentlyContinue).Length
    } -Descending | Select-Object -First 1).FullName

    # Use junction to avoid Japanese path issues
    $junction = "C:\Postshot_Temp\lpips_qloop"
    if (Test-Path $junction) { cmd /c "rmdir `"$junction`"" }
    cmd /c "mklink /J `"$junction`" `"$scene1`"" | Out-Null

    $outputDirName = Split-Path -Leaf $OutputDir

    # Redirect stdout to Write-Host so it doesn't pollute return value
    # Temporarily allow errors (Python warnings on stderr trigger Stop mode)
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lpipsOutput = & uv run python scripts/compute_lpips.py `
        --ply (Join-Path $junction "$outputDirName\postshot\scene.ply") `
        --sparse ($sparsePath.Replace($scene1, $junction)) `
        --images (Join-Path $junction "$outputDirName\images") `
        --output (Join-Path $junction "$outputDirName\postshot\lpips.json") `
        --max-images 50 2>&1
    $ErrorActionPreference = $prevEA
    $lpipsOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $lpips = 999.0
    $jLpips = Join-Path $junction "$outputDirName\postshot\lpips.json"
    if (Test-Path -LiteralPath $jLpips) {
        $lData = Get-Content $jLpips -Raw | ConvertFrom-Json
        $lpips = [double]$lData.lpips_mean
    }
    cmd /c "rmdir `"$junction`""
    return [double]$lpips
}

# ============================================================
# MAIN LOOP
# ============================================================
$allResults = @()
$totalStart = Get-Date
$resultsFile = Join-Path $scene1 "quality_loop_results.json"
$csvFile = Join-Path (Split-Path $scene1) "scene1_quality_loop_results.csv"

Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  COLMAP Quality Loop - Scene 1                               #" -ForegroundColor Cyan
Write-Host "#  Target SSIM >= $TargetSsim, LPIPS <= $TargetLpips                        #" -ForegroundColor Cyan
Write-Host "#  Strategies: $($strategies.Count) (starting from #$StartFrom)                         #" -ForegroundColor Cyan
Write-Host "#  COLMAP quality gate: ENABLED                                #" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan

for ($i = 0; $i -lt $strategies.Count; $i++) {
    $strat = $strategies[$i]
    $expNum = $i + 1

    if ($expNum -lt $StartFrom) {
        Write-Host "`n  SKIP #$expNum $($strat.name) (StartFrom=$StartFrom)" -ForegroundColor DarkGray
        continue
    }

    $outputDirName = "output_exp_$($strat.name)"
    $outputDir = Join-Path $scene1 $outputDirName

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "  #$expNum/$($strategies.Count): $($strat.name)" -ForegroundColor Magenta
    Write-Host "  $($strat.desc)" -ForegroundColor Magenta
    Write-Host "  fps=$($strat.fps) features=$($strat.max_features) matcher=$($strat.matcher)" -ForegroundColor Magenta
    Write-Host "  sift=$($strat.sift_max_ratio) guided=$($strat.guided) merge=$($strat.merge) camera=$($strat.camera_model)" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta

    $expStart = Get-Date

    # Build config
    $tempConfig = Build-Config -Strategy $strat

    # --- Stage 1: Extract frames ---
    # Try to reuse existing images
    $imagesDir = Join-Path $outputDir "images"
    $reuseImages = Find-ReusableImages -Fps $strat.fps
    if ($reuseImages -and -not (Test-Path -LiteralPath $imagesDir)) {
        # Create output dir structure
        foreach ($d in @($outputDir, (Join-Path $outputDir "colmap"), (Join-Path $outputDir "postshot"), (Join-Path $outputDir "visualizations"))) {
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        }
        cmd /c "mklink /J `"$imagesDir`" `"$reuseImages`"" | Out-Null
        Write-Host "  Reusing images from: $reuseImages" -ForegroundColor DarkGray
    } else {
        Write-Host "  >>> Stage 1: Extract frames ($($strat.fps)fps)" -ForegroundColor Cyan
        & (Join-Path $stagesDir "01_extract_frames.ps1") -ConfigPath $tempConfig -ScenePath $scene1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  !!! Stage 1 FAILED" -ForegroundColor Red
            $allResults += @{ name=$strat.name; colmap_pass=$false; lpips=999; reason="extract_failed" }
            continue
        }
    }

    # --- Stage 3: Feature extraction ---
    # Need to re-run if camera model or max_features changed
    $colmapDir = Join-Path $outputDir "colmap"
    $dbPath = Join-Path $colmapDir "database.db"
    if (-not (Test-Path -LiteralPath $colmapDir)) { New-Item -ItemType Directory -Path $colmapDir -Force | Out-Null }

    # Clean previous COLMAP results
    $sparseDir = Join-Path $colmapDir "sparse"
    if (Test-Path -LiteralPath $sparseDir) { Remove-Item -LiteralPath $sparseDir -Recurse -Force }
    if (Test-Path -LiteralPath $dbPath) { Remove-Item -LiteralPath $dbPath -Force }

    Write-Host "  >>> Stage 3: Feature extraction" -ForegroundColor Cyan
    & (Join-Path $stagesDir "03_colmap_features.ps1") -ConfigPath $tempConfig -ScenePath $scene1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!! Stage 3 FAILED" -ForegroundColor Red
        $allResults += @{ name=$strat.name; colmap_pass=$false; lpips=999; reason="features_failed" }
        continue
    }

    # --- Stage 4: Matching ---
    Write-Host "  >>> Stage 4: Feature matching ($($strat.matcher))" -ForegroundColor Cyan
    & (Join-Path $stagesDir "04_colmap_matching.ps1") -ConfigPath $tempConfig -ScenePath $scene1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!! Stage 4 FAILED" -ForegroundColor Red
        $allResults += @{ name=$strat.name; colmap_pass=$false; lpips=999; reason="matching_failed" }
        continue
    }

    # --- Stage 5: Mapper (with quality gate!) ---
    Write-Host "  >>> Stage 5: Mapper + Quality Gate" -ForegroundColor Cyan
    & (Join-Path $stagesDir "05_colmap_mapper.ps1") -ConfigPath $tempConfig -ScenePath $scene1
    $mapperExit = $LASTEXITCODE

    # Read quality result
    $colmapQualityJson = Join-Path $colmapDir "sparse_quality.json"
    $qualityResult = $null
    if (Test-Path -LiteralPath $colmapQualityJson) {
        $qualityResult = Get-Content $colmapQualityJson -Raw | ConvertFrom-Json
    }

    if ($mapperExit -eq 2) {
        # Quality gate failed - skip training
        $reasons = if ($qualityResult) { $qualityResult.reasons -join "; " } else { "unknown" }
        Write-Host ""
        Write-Host "  COLMAP QUALITY FAILED: $reasons" -ForegroundColor Red
        Write-Host "  Skipping training, moving to next strategy..." -ForegroundColor Yellow

        $result = @{
            name = $strat.name
            desc = $strat.desc
            colmap_pass = $false
            lpips = 999
            reason = $reasons
            num_models = if ($qualityResult) { $qualityResult.checks.num_models } else { 0 }
            registered = if ($qualityResult) { $qualityResult.checks.registered_images } else { 0 }
            planarity = if ($qualityResult -and $qualityResult.checks.structure) { $qualityResult.checks.structure.planarity_ratio } else { 0 }
            reproj_err = if ($qualityResult) { $qualityResult.checks.mean_reprojection_error } else { 0 }
            duration = ((Get-Date) - $expStart).ToString('hh\:mm\:ss')
        }
        $allResults += $result
        $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsFile -Encoding UTF8
        continue

    } elseif ($mapperExit -ne 0) {
        Write-Host "  !!! Mapper CRASHED (exit=$mapperExit)" -ForegroundColor Red
        $allResults += @{ name=$strat.name; colmap_pass=$false; lpips=999; reason="mapper_crash_$mapperExit" }
        $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsFile -Encoding UTF8
        continue
    }

    # Quality gate PASSED!
    Write-Host ""
    Write-Host "  COLMAP QUALITY PASSED!" -ForegroundColor Green
    if ($qualityResult) {
        Write-Host "    Models: $($qualityResult.checks.num_models) | Registered: $($qualityResult.checks.registered_images)/$($qualityResult.checks.total_images)" -ForegroundColor Green
        Write-Host "    PCA ratio: $($qualityResult.checks.structure.planarity_ratio) | Reproj: $($qualityResult.checks.mean_reprojection_error) px" -ForegroundColor Green
    }

    # --- Stage 6: Postshot training ---
    Write-Host "  >>> Stage 6: Postshot training" -ForegroundColor Cyan
    & (Join-Path $stagesDir "06_postshot_train.ps1") -ConfigPath $tempConfig -ScenePath $scene1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!! Training FAILED" -ForegroundColor Red
        $allResults += @{ name=$strat.name; colmap_pass=$true; lpips=999; reason="train_failed" }
        $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsFile -Encoding UTF8
        continue
    }

    # --- Stage 7: Export PLY ---
    Write-Host "  >>> Stage 7: Export PLY" -ForegroundColor Cyan
    & (Join-Path $stagesDir "07_postshot_export.ps1") -ConfigPath $tempConfig -ScenePath $scene1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!! Export FAILED" -ForegroundColor Red
        $allResults += @{ name=$strat.name; colmap_pass=$true; lpips=999; reason="export_failed" }
        $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsFile -Encoding UTF8
        continue
    }

    # --- Compute LPIPS ---
    Write-Host "  >>> Computing LPIPS..." -ForegroundColor Cyan
    $lpips = Compute-Lpips -OutputDir $outputDir

    # Read SSIM from quality.json
    $ssim = 0.0
    $qJson = Join-Path $outputDir "postshot\quality.json"
    if (Test-Path -LiteralPath $qJson) {
        $qData = Get-Content $qJson -Raw | ConvertFrom-Json
        if ($qData.PSObject.Properties['ssim']) { $ssim = [double]$qData.ssim }
    }

    $expDuration = (Get-Date) - $expStart

    $result = @{
        name = $strat.name
        desc = $strat.desc
        colmap_pass = $true
        ssim = $ssim
        lpips = $lpips
        num_models = if ($qualityResult) { $qualityResult.checks.num_models } else { 1 }
        registered = if ($qualityResult) { $qualityResult.checks.registered_images } else { 0 }
        total_images = if ($qualityResult) { $qualityResult.checks.total_images } else { 0 }
        planarity = if ($qualityResult -and $qualityResult.checks.structure) { $qualityResult.checks.structure.planarity_ratio } else { 0 }
        reproj_err = if ($qualityResult) { $qualityResult.checks.mean_reprojection_error } else { 0 }
        num_points = if ($qualityResult -and $qualityResult.checks.structure) { $qualityResult.checks.structure.num_points } else { 0 }
        duration = $expDuration.ToString('hh\:mm\:ss')
        reason = ""
    }
    $allResults += $result

    $ssimPass = $ssim -ge $TargetSsim
    $lpipsPass = $lpips -le $TargetLpips
    $passed = $ssimPass -and $lpipsPass

    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })
    Write-Host "  #$expNum $($strat.name) ($($expDuration.ToString('hh\:mm\:ss')))" -ForegroundColor White
    Write-Host "    COLMAP: PASS (models=$($result.num_models) reg=$($result.registered)/$($result.total_images) PCA=$($result.planarity) reproj=$($result.reproj_err)px pts=$($result.num_points))" -ForegroundColor Green
    Write-Host "    SSIM:   $ssim $(if ($ssimPass) { 'PASS' } else { 'FAIL (target >= ' + $TargetSsim + ')' })" -ForegroundColor $(if ($ssimPass) { "Green" } else { "Red" })
    Write-Host "    LPIPS:  $lpips $(if ($lpipsPass) { 'PASS' } else { 'FAIL (target <= ' + $TargetLpips + ')' })" -ForegroundColor $(if ($lpipsPass) { "Green" } else { "Red" })
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })

    # Save results
    $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsFile -Encoding UTF8

    # Also save CSV
    $csvHeader = '"experiment","colmap_pass","ssim","lpips","num_models","registered","total_images","planarity","reproj_err","num_points","duration","reason"'
    $csvLines = @($csvHeader)
    foreach ($r in $allResults) {
        $csvLines += '"{0}","{1}","{2}","{3}","{4}","{5}","{6}","{7}","{8}","{9}","{10}","{11}"' -f `
            $r.name, $r.colmap_pass, $r.ssim, $r.lpips, $r.num_models, $r.registered, $r.total_images, `
            $r.planarity, $r.reproj_err, $r.num_points, $r.duration, $r.reason
    }
    $csvLines -join "`n" | Set-Content -Path $csvFile -Encoding UTF8

    if ($passed) {
        Write-Host ""
        Write-Host "################################################################" -ForegroundColor Green
        Write-Host "#  TARGET ACHIEVED!                                            #" -ForegroundColor Green
        Write-Host "#  $($strat.name): SSIM=$ssim LPIPS=$lpips" -ForegroundColor Green
        Write-Host "################################################################" -ForegroundColor Green
        break
    }
}

# Final summary
$totalDuration = (Get-Date) - $totalStart
Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  QUALITY LOOP SUMMARY                                        #" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan
foreach ($r in $allResults) {
    $colmapStatus = if ($r.colmap_pass) { "COLMAP:PASS" } else { "COLMAP:FAIL" }
    $color = if ($r.colmap_pass -and $r.lpips -le $TargetLpips) { "Green" } elseif ($r.colmap_pass) { "Yellow" } else { "Red" }
    Write-Host "  $($r.name): $colmapStatus LPIPS=$($r.lpips) $($r.duration) $($r.reason)" -ForegroundColor $color
}
Write-Host ""
Write-Host "  Total: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "  Results: $resultsFile" -ForegroundColor DarkGray

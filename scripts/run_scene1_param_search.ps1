# run_scene1_param_search.ps1
# Infinite parameter search for scene 1 - focuses on getting good COLMAP result
# Runs until SSIM >= target AND LPIPS <= target
#
# Usage:
#   .\scripts\run_scene1_param_search.ps1                    # Start from experiment 1
#   .\scripts\run_scene1_param_search.ps1 -StartFrom 5       # Resume from experiment 5

param(
    [int]$StartFrom = 1,
    [double]$TargetSsim = 0.80,
    [double]$TargetLpips = 0.60
)

$ErrorActionPreference = 'Stop'
$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH
Set-Location C:\postshot_script

$baseConfig = "config\pipeline_tower.json"
$scene1 = (Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name | Select-Object -First 1).FullName
$tempBase = "C:\Postshot_Temp"
$stagesDir = "C:\postshot_script\scripts\stages"

# ============================================================
# Experiment definitions
# Each experiment specifies:
#   - config changes from base
#   - start_stage: earliest stage needed (1=extract, 3=features, 4=matching)
#   - reuse_from: output dir to copy images/db from (null = run from scratch)
# ============================================================
$experiments = @(
    # --- Group A: FPS variations (need full re-run from stage 1) ---
    @{
        name = "01_2fps_seq_loop_guided"
        desc = "2fps + sequential + loop detection + guided matching (old successful config)"
        start_stage = 1
        reuse_from = $null
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_04_matching.type" = "sequential"
            "stage_04_matching.overlap" = 20
            "stage_04_matching.loop_detection" = $true
            "stage_04_matching.loop_detection_period" = 10
            "stage_04_matching.loop_detection_num_images" = 50
            "stage_04_matching.guided_matching" = $true
        }
    },
    @{
        name = "02_2fps_exhaustive"
        desc = "2fps + exhaustive (default matching, more frames)"
        start_stage = 3  # reuse 2fps images from exp01
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
        }
    },
    @{
        name = "03_2fps_exhaustive_sift07"
        desc = "2fps + exhaustive + sift_max_ratio=0.7"
        start_stage = 4  # reuse db from exp02
        reuse_from = "output_exp_02_2fps_exhaustive"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_04_matching.sift_max_ratio" = 0.7
        }
    },
    @{
        name = "04_2fps_seq_loop_guided_sift07"
        desc = "2fps + sequential + loop + guided + sift=0.7"
        start_stage = 4  # reuse db from exp01
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_04_matching.type" = "sequential"
            "stage_04_matching.overlap" = 20
            "stage_04_matching.loop_detection" = $true
            "stage_04_matching.loop_detection_period" = 10
            "stage_04_matching.loop_detection_num_images" = 50
            "stage_04_matching.guided_matching" = $true
            "stage_04_matching.sift_max_ratio" = 0.7
        }
    },
    # --- Group B: 3fps (even more images) ---
    @{
        name = "05_3fps_seq_loop_guided"
        desc = "3fps + sequential + loop + guided"
        start_stage = 1
        reuse_from = $null
        changes = @{
            "stage_01_extract.fps" = 3
            "stage_04_matching.type" = "sequential"
            "stage_04_matching.overlap" = 20
            "stage_04_matching.loop_detection" = $true
            "stage_04_matching.loop_detection_period" = 10
            "stage_04_matching.loop_detection_num_images" = 50
            "stage_04_matching.guided_matching" = $true
        }
    },
    @{
        name = "06_3fps_exhaustive"
        desc = "3fps + exhaustive"
        start_stage = 3
        reuse_from = "output_exp_05_3fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 3
        }
    },
    # --- Group C: 2fps with mapper tuning ---
    @{
        name = "07_2fps_seq_loop_guided_relaxed"
        desc = "2fps + seq + loop + guided + relaxed mapper (min_model=30, inliers=50)"
        start_stage = 4
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_04_matching.type" = "sequential"
            "stage_04_matching.overlap" = 20
            "stage_04_matching.loop_detection" = $true
            "stage_04_matching.loop_detection_period" = 10
            "stage_04_matching.loop_detection_num_images" = 50
            "stage_04_matching.guided_matching" = $true
            "stage_05_mapper.min_model_size" = 30
            "stage_05_mapper.init_min_num_inliers" = 50
            "stage_05_mapper.abs_pose_min_num_inliers" = 15
            "stage_05_mapper.abs_pose_min_inlier_ratio" = 0.15
        }
    },
    @{
        name = "08_2fps_exhaustive_16k"
        desc = "2fps + exhaustive + 16384 features"
        start_stage = 3
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_03_features.max_features" = 16384
        }
    },
    # --- Group D: 2fps with vocab_tree matcher ---
    @{
        name = "09_2fps_vocab_tree"
        desc = "2fps + vocab_tree matcher"
        start_stage = 4
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_04_matching.type" = "vocab_tree"
            "stage_04_matching.loop_detection" = $false
        }
    },
    # --- Group E: 2fps camera model variations ---
    @{
        name = "10_2fps_seq_loop_opencv"
        desc = "2fps + seq + loop + guided + OPENCV camera model"
        start_stage = 3  # camera model change requires re-extraction
        reuse_from = "output_exp_01_2fps_seq_loop_guided"
        changes = @{
            "stage_01_extract.fps" = 2
            "stage_03_features.camera_model" = "OPENCV"
            "stage_04_matching.type" = "sequential"
            "stage_04_matching.overlap" = 20
            "stage_04_matching.loop_detection" = $true
            "stage_04_matching.loop_detection_period" = 10
            "stage_04_matching.loop_detection_num_images" = 50
            "stage_04_matching.guided_matching" = $true
        }
    }
)

# ============================================================
# Helper functions
# ============================================================

function Set-ConfigValue {
    param($Config, [string]$Key, $Value)
    $parts = $Key -split '\.'
    $section = $parts[0]
    $prop = $parts[1]
    if (-not $Config.PSObject.Properties[$section]) {
        $Config | Add-Member -NotePropertyName $section -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $Config.$section | Add-Member -NotePropertyName $prop -NotePropertyValue $Value -Force
}

function Prepare-Reuse {
    param(
        [string]$ScenePath,
        [string]$OutputDirName,
        [string]$ReuseFrom,
        [int]$StartStage
    )

    $outputDir = Join-Path $ScenePath $OutputDirName
    $sourceDir = Join-Path $ScenePath $ReuseFrom

    foreach ($d in @($outputDir, (Join-Path $outputDir "colmap"), (Join-Path $outputDir "postshot"), (Join-Path $outputDir "visualizations"))) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # Link images
    $imagesDir = Join-Path $outputDir "images"
    if (-not (Test-Path -LiteralPath $imagesDir)) {
        $sourceImages = Join-Path $sourceDir "images"
        if (Test-Path -LiteralPath $sourceImages) {
            cmd /c "mklink /J `"$imagesDir`" `"$sourceImages`"" | Out-Null
            Write-Host "    Linked images from $ReuseFrom" -ForegroundColor DarkGray
        }
    }

    # Copy database if starting from stage 4+
    if ($StartStage -ge 4) {
        $targetDb = Join-Path $outputDir "colmap\database.db"
        $sourceDb = Join-Path $sourceDir "colmap\database.db"
        if ((Test-Path -LiteralPath $sourceDb) -and -not (Test-Path -LiteralPath $targetDb)) {
            Copy-Item -LiteralPath $sourceDb -Destination $targetDb -Force
            Write-Host "    Copied database.db from $ReuseFrom" -ForegroundColor DarkGray
        }
    }
}

function Compute-SceneLpips {
    param([string]$ScenePath, [string]$OutputDirName)

    $outputDir = Join-Path $ScenePath $OutputDirName
    $plyPath = Join-Path $outputDir "postshot\scene.ply"
    $sparseDir = Join-Path $outputDir "colmap\sparse"
    $lpipsJson = Join-Path $outputDir "postshot\lpips.json"

    if (-not (Test-Path -LiteralPath $plyPath)) { return 999.0 }

    $sparseModels = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue
    if (-not $sparseModels) { return 999.0 }
    $sparsePath = ($sparseModels | Sort-Object { (Get-Item -LiteralPath (Join-Path $_.FullName "images.bin")).Length } -Descending | Select-Object -First 1).FullName

    $junction = "C:\Postshot_Temp\lpips_search"
    if (Test-Path $junction) { cmd /c "rmdir `"$junction`"" }
    cmd /c "mklink /J `"$junction`" `"$ScenePath`"" | Out-Null

    & uv run python scripts/compute_lpips.py `
        --ply ($plyPath.Replace($ScenePath, $junction)) `
        --sparse ($sparsePath.Replace($ScenePath, $junction)) `
        --images ((Join-Path $outputDir "images").Replace($ScenePath, $junction)) `
        --output ($lpipsJson.Replace($ScenePath, $junction)) `
        --max-images 50

    $lpips = 999.0
    $jOutput = $lpipsJson.Replace($ScenePath, $junction)
    if (Test-Path -LiteralPath $jOutput) {
        $lData = Get-Content $jOutput -Raw | ConvertFrom-Json
        $lpips = [double]$lData.lpips_mean
    }
    cmd /c "rmdir `"$junction`""
    return $lpips
}

function Get-SparseStats {
    param([string]$SparseDir)
    $regCount = 0; $ptsSize = 0; $numRecons = 0
    if (-not (Test-Path -LiteralPath $SparseDir)) { return @{ reg=0; pts=0; recons=0 } }
    $recons = Get-ChildItem -LiteralPath $SparseDir -Directory -ErrorAction SilentlyContinue
    foreach ($r in $recons) {
        $numRecons++
        $imgBin = Join-Path $r.FullName "images.bin"
        if (Test-Path -LiteralPath $imgBin) {
            $bytes = [System.IO.File]::ReadAllBytes($imgBin)
            $n = [BitConverter]::ToUInt64($bytes, 0)
            if ($n -gt $regCount) { $regCount = $n }
        }
        $ptsBin = Join-Path $r.FullName "points3D.bin"
        if (Test-Path -LiteralPath $ptsBin) {
            $s = (Get-Item -LiteralPath $ptsBin).Length
            if ($s -gt $ptsSize) { $ptsSize = $s }
        }
    }
    return @{ reg=$regCount; pts=$ptsSize; recons=$numRecons }
}

# ============================================================
# Main loop
# ============================================================

$allResults = @()
$totalStart = Get-Date

Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  Scene 1 Parameter Search                                    #" -ForegroundColor Cyan
Write-Host "#  Target: SSIM >= $TargetSsim, LPIPS <= $TargetLpips                        #" -ForegroundColor Cyan
Write-Host "#  Experiments: $($experiments.Count)                                           #" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan

for ($i = 0; $i -lt $experiments.Count; $i++) {
    $exp = $experiments[$i]
    $expNum = $i + 1

    if ($expNum -lt $StartFrom) {
        Write-Host "`n  SKIP #$expNum $($exp.name) (StartFrom=$StartFrom)" -ForegroundColor DarkGray
        continue
    }

    $outputDirName = "output_exp_$($exp.name)"

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "  #$expNum/$($experiments.Count): $($exp.name)" -ForegroundColor Magenta
    Write-Host "  $($exp.desc)" -ForegroundColor Magenta
    Write-Host "  Start stage: $($exp.start_stage) | Reuse: $(if ($exp.reuse_from) { $exp.reuse_from } else { 'none' })" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta

    # Build config
    $expConfig = Get-Content $baseConfig -Raw | ConvertFrom-Json
    $expConfig.output.dir_name = $outputDirName
    $expConfig.pipeline.overwrite_result = $true
    foreach ($key in $exp.changes.Keys) {
        Set-ConfigValue -Config $expConfig -Key $key -Value $exp.changes[$key]
    }
    $tempConfigPath = Join-Path $tempBase "config_search_$($exp.name).json"
    $expConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfigPath -Encoding UTF8

    # Prepare reuse
    $outputDir = Join-Path $scene1 $outputDirName
    if ($exp.reuse_from) {
        Prepare-Reuse -ScenePath $scene1 -OutputDirName $outputDirName -ReuseFrom $exp.reuse_from -StartStage $exp.start_stage
    }

    # Clean sparse/postshot for re-run
    $sparseDir = Join-Path $outputDir "colmap\sparse"
    if (Test-Path -LiteralPath $sparseDir) { Remove-Item -LiteralPath $sparseDir -Recurse -Force }
    foreach ($f in @("scene.psht", "scene.ply", "quality.json", "lpips.json")) {
        $fp = Join-Path $outputDir "postshot\$f"
        if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force }
    }

    # Run stages
    $expStart = Get-Date
    $failed = $false

    # Determine which stages to run (skip stage 2 always)
    $stagesToRun = @()
    for ($s = $exp.start_stage; $s -le 7; $s++) {
        if ($s -eq 2) { continue }
        $stagesToRun += $s
    }

    foreach ($stageNum in $stagesToRun) {
        $stageFile = switch ($stageNum) {
            1 { "01_extract_frames.ps1" }
            3 { "03_colmap_features.ps1" }
            4 { "04_colmap_matching.ps1" }
            5 { "05_colmap_mapper.ps1" }
            6 { "06_postshot_train.ps1" }
            7 { "07_postshot_export.ps1" }
        }

        Write-Host "`n  >>> Stage $stageNum" -ForegroundColor Cyan
        & (Join-Path $stagesDir $stageFile) -ConfigPath $tempConfigPath -ScenePath $scene1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  !!! Stage $stageNum FAILED" -ForegroundColor Red
            $failed = $true
            break
        }
    }

    $expDuration = (Get-Date) - $expStart

    if ($failed) {
        $allResults += @{ name=$exp.name; ssim=0; lpips=999; passed=$false; duration=$expDuration.ToString('hh\:mm\:ss') }
        Write-Host "`n  FAILED - continuing to next experiment" -ForegroundColor Red
        continue
    }

    # Read SSIM
    $ssim = 0.0
    $qualityJson = Join-Path $outputDir "postshot\quality.json"
    if (Test-Path -LiteralPath $qualityJson) {
        $qData = Get-Content $qualityJson -Raw | ConvertFrom-Json
        if ($qData.PSObject.Properties['ssim']) { $ssim = [double]$qData.ssim }
    }

    # Compute LPIPS
    Write-Host "`n  Computing LPIPS..." -ForegroundColor Cyan
    $lpips = Compute-SceneLpips -ScenePath $scene1 -OutputDirName $outputDirName

    # Sparse stats
    $stats = Get-SparseStats -SparseDir (Join-Path $outputDir "colmap\sparse")

    $passed = ($ssim -ge $TargetSsim) -and ($lpips -le $TargetLpips)

    $result = @{
        name     = $exp.name
        desc     = $exp.desc
        ssim     = $ssim
        lpips    = $lpips
        passed   = $passed
        reg      = $stats.reg
        ptsMB    = [math]::Round($stats.pts/1MB, 1)
        recons   = $stats.recons
        duration = $expDuration.ToString('hh\:mm\:ss')
    }
    $allResults += $result

    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })
    Write-Host "  #$expNum $($exp.name) ($($expDuration.ToString('hh\:mm\:ss')))" -ForegroundColor White
    Write-Host "    SSIM:  $ssim $(if ($ssim -ge $TargetSsim) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($ssim -ge $TargetSsim) { "Green" } else { "Red" })
    Write-Host "    LPIPS: $lpips $(if ($lpips -le $TargetLpips) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($lpips -le $TargetLpips) { "Green" } else { "Red" })
    Write-Host "    Reg: $($stats.reg) imgs, $($stats.recons) recon(s), pts=$([math]::Round($stats.pts/1MB,1))MB" -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })

    # Save running results
    $resultsJson = Join-Path $scene1 "param_search_results.json"
    $allResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsJson -Encoding UTF8

    if ($passed) {
        Write-Host ""
        Write-Host "################################################################" -ForegroundColor Green
        Write-Host "#  TARGET ACHIEVED: $($exp.name)" -ForegroundColor Green
        Write-Host "#  SSIM=$ssim  LPIPS=$lpips" -ForegroundColor Green
        Write-Host "################################################################" -ForegroundColor Green
        break
    }
}

# Final summary
$totalDuration = (Get-Date) - $totalStart

Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  PARAMETER SEARCH SUMMARY" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $allResults) {
    $status = if ($r.passed) { "PASS" } else { "FAIL" }
    $color = if ($r.passed) { "Green" } else { "Yellow" }
    Write-Host "  $($r.name): SSIM=$($r.ssim) LPIPS=$($r.lpips) reg=$($r.reg) pts=$($r.ptsMB)MB $($r.duration) [$status]" -ForegroundColor $color
}

Write-Host ""
Write-Host "  Total: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "  Results: $resultsJson" -ForegroundColor DarkGray

$winner = $allResults | Where-Object { $_.passed } | Select-Object -First 1
if (-not $winner) {
    Write-Host ""
    Write-Host "  No experiment achieved target. Consider adding more experiments." -ForegroundColor Red
    exit 1
}
exit 0

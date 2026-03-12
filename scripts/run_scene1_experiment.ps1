# run_scene1_experiment.ps1
# Iterative experiment: try countermeasures one-by-one for scene 1
# Target: SSIM >= 0.80 AND LPIPS <= 0.60
#
# Each experiment changes exactly ONE parameter from default.
# Reuses previous stage outputs where possible:
#   - All experiments reuse images from output_default (same 1fps)
#   - Experiments changing only matching/mapper reuse database.db (same features)
#   - Start from the earliest affected stage to save computation time

param(
    [int]$StartFrom = 1  # Resume from experiment N
)

$ErrorActionPreference = 'Stop'

$env:PATH = [System.IO.Path]::Combine($env:USERPROFILE, '.local', 'bin') + ';' + $env:PATH

Set-Location C:\postshot_script

$baseConfig = "config\pipeline_tower.json"
$scene1 = (Get-ChildItem -LiteralPath "C:\postshot_script\data\tower" -Directory | Sort-Object Name | Select-Object -First 1).FullName
$tempBase = "C:\Postshot_Temp"

# Target thresholds
$targetSsim = 0.80
$targetLpips = 0.60

# Source output to copy reusable data from
$sourceOutput = Join-Path $scene1 "output_default"

# Define experiments: each changes exactly ONE thing from default
# start_stage: earliest stage affected by the change
# reuse_db: whether to copy database.db from output_default (features unchanged)
$experiments = @(
    @{
        name        = "01_sequential"
        description = "Change matcher: exhaustive -> sequential (overlap=20)"
        start_stage = 4
        reuse_db    = $true
        config_overrides = @{
            "stage_04_matching.type"    = "sequential"
            "stage_04_matching.overlap" = 20
        }
    },
    @{
        name        = "02_sift07"
        description = "Change sift_max_ratio: 0.8 -> 0.7"
        start_stage = 4
        reuse_db    = $true
        config_overrides = @{
            "stage_04_matching.sift_max_ratio" = 0.7
        }
    },
    @{
        name        = "03_guided"
        description = "Enable guided_matching: false -> true"
        start_stage = 4
        reuse_db    = $true
        config_overrides = @{
            "stage_04_matching.guided_matching" = $true
        }
    },
    @{
        name        = "04_features16k"
        description = "Change max_features: 8192 -> 16384"
        start_stage = 3
        reuse_db    = $false
        config_overrides = @{
            "stage_03_features.max_features" = 16384
        }
    },
    @{
        name        = "05_seq_sift07"
        description = "Combine: sequential + sift_max_ratio=0.7"
        start_stage = 4
        reuse_db    = $true
        config_overrides = @{
            "stage_04_matching.type"           = "sequential"
            "stage_04_matching.overlap"        = 20
            "stage_04_matching.sift_max_ratio" = 0.7
        }
    }
)

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

function Prepare-OutputDir {
    param(
        [string]$ScenePath,
        [string]$OutputDirName,
        [string]$SourceOutput,
        [bool]$ReuseDb,
        [int]$StartStage
    )

    $outputDir = Join-Path $ScenePath $OutputDirName

    # Create output directory structure
    $colmapDir = Join-Path $outputDir "colmap"
    $imagesDir = Join-Path $outputDir "images"
    $postshotDir = Join-Path $outputDir "postshot"
    $vizDir = Join-Path $outputDir "visualizations"

    foreach ($d in @($outputDir, $colmapDir, $postshotDir, $vizDir)) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # Copy images from source (junction to save disk space)
    $sourceImages = Join-Path $SourceOutput "images"
    if ((Test-Path -LiteralPath $sourceImages) -and -not (Test-Path -LiteralPath $imagesDir)) {
        Write-Host "  Linking images from $SourceOutput" -ForegroundColor DarkGray
        cmd /c "mklink /J `"$imagesDir`" `"$sourceImages`""
    }

    # Copy database.db if reusing features
    if ($ReuseDb -and $StartStage -ge 4) {
        $sourceDb = Join-Path $SourceOutput "colmap\database.db"
        $targetDb = Join-Path $colmapDir "database.db"
        if ((Test-Path -LiteralPath $sourceDb) -and -not (Test-Path -LiteralPath $targetDb)) {
            Write-Host "  Copying database.db (reusing features)..." -ForegroundColor DarkGray
            Copy-Item -LiteralPath $sourceDb -Destination $targetDb -Force
        }
    }
}

function Compute-Lpips {
    param(
        [string]$ScenePath,
        [string]$OutputDirName
    )

    $outputDir = Join-Path $ScenePath $OutputDirName
    $plyPath = Join-Path $outputDir "postshot\scene.ply"
    $sparseDir = Join-Path $outputDir "colmap\sparse"
    $imagesDir = Join-Path $outputDir "images"
    $lpipsJson = Join-Path $outputDir "postshot\lpips.json"

    if (-not (Test-Path -LiteralPath $plyPath)) { return 999.0 }

    # Find largest sparse model
    $sparseModels = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue
    if (-not $sparseModels) { return 999.0 }
    $sparsePath = ($sparseModels | Sort-Object { (Get-Item -LiteralPath (Join-Path $_.FullName "images.bin")).Length } -Descending | Select-Object -First 1).FullName

    # Create junction for Japanese paths
    $workPly = $plyPath; $workSparse = $sparsePath; $workImages = $imagesDir; $workOutput = $lpipsJson
    $junction = $null

    if ($ScenePath -match '[^\x00-\x7F]') {
        $junction = Join-Path $tempBase "lpips_exp"
        if (Test-Path $junction) { cmd /c "rmdir `"$junction`"" }
        cmd /c "mklink /J `"$junction`" `"$ScenePath`"" | Out-Null
        $workPly = $plyPath.Replace($ScenePath, $junction)
        $workSparse = $sparsePath.Replace($ScenePath, $junction)
        $workImages = $imagesDir.Replace($ScenePath, $junction)
        $workOutput = $lpipsJson.Replace($ScenePath, $junction)
    }

    & uv run python scripts/compute_lpips.py --ply $workPly --sparse $workSparse --images $workImages --output $workOutput --max-images 50

    $lpips = 999.0
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $workOutput)) {
        $lData = Get-Content $workOutput -Raw | ConvertFrom-Json
        $lpips = [double]$lData.lpips_mean
    }

    if ($junction -and (Test-Path $junction)) { cmd /c "rmdir `"$junction`"" }
    return $lpips
}

# ============================================================
# Main
# ============================================================

$results = @()
$startTime = Get-Date

Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  Scene 1 Iterative Experiment (one change at a time)         #" -ForegroundColor Cyan
Write-Host "#  Target: SSIM >= $targetSsim, LPIPS <= $targetLpips                        #" -ForegroundColor Cyan
Write-Host "#  Base: output_default (exhaustive, default settings)         #" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host ""

# Show baseline
Write-Host "  Baseline (output_default): SSIM=0.725 LPIPS=0.756" -ForegroundColor Yellow
Write-Host ""

for ($i = 0; $i -lt $experiments.Count; $i++) {
    $exp = $experiments[$i]
    $expNum = $i + 1

    if ($expNum -lt $StartFrom) {
        Write-Host "Skipping experiment $expNum/$($experiments.Count): $($exp.name)" -ForegroundColor DarkGray
        continue
    }

    $outputDirName = "output_exp_$($exp.name)"

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "  Experiment $expNum/$($experiments.Count): $($exp.name)" -ForegroundColor Magenta
    Write-Host "  $($exp.description)" -ForegroundColor Magenta
    Write-Host "  Output: $outputDirName" -ForegroundColor Magenta
    Write-Host "  Start stage: $($exp.start_stage) | Reuse DB: $($exp.reuse_db)" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta

    # Build config: start from base, apply only this experiment's overrides
    $expConfig = Get-Content $baseConfig -Raw | ConvertFrom-Json
    $expConfig.output.dir_name = $outputDirName
    $expConfig.pipeline.overwrite_result = $true

    foreach ($key in $exp.config_overrides.Keys) {
        Set-ConfigValue -Config $expConfig -Key $key -Value $exp.config_overrides[$key]
    }

    # Write temp config
    $tempConfigPath = Join-Path $tempBase "config_exp_$($exp.name).json"
    $expConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfigPath -Encoding UTF8

    # Prepare output directory with reusable data
    Prepare-OutputDir -ScenePath $scene1 -OutputDirName $outputDirName `
        -SourceOutput $sourceOutput -ReuseDb $exp.reuse_db -StartStage $exp.start_stage

    # Run pipeline from the appropriate start stage
    $expStartTime = Get-Date
    & "$PSScriptRoot\run_pipeline_single.ps1" `
        -ConfigPath $tempConfigPath `
        -ScenePath $scene1 `
        -StartStage $exp.start_stage `
        -EndStage 7

    $expDuration = (Get-Date) - $expStartTime

    # Read SSIM from quality.json
    $ssim = 0.0
    $qualityJson = Join-Path $scene1 "$outputDirName\postshot\quality.json"
    if (Test-Path -LiteralPath $qualityJson) {
        $qData = Get-Content $qualityJson -Raw | ConvertFrom-Json
        if ($qData.PSObject.Properties['ssim']) { $ssim = [double]$qData.ssim }
    }

    # Compute LPIPS
    Write-Host ""
    Write-Host "  Computing LPIPS..." -ForegroundColor Cyan
    $lpips = Compute-Lpips -ScenePath $scene1 -OutputDirName $outputDirName

    # Get sparse model info
    $sparseDir = Join-Path $scene1 "$outputDirName\colmap\sparse"
    $regCount = 0; $ptsSize = 0; $numRecons = 0
    if (Test-Path -LiteralPath $sparseDir) {
        $recons = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue
        $numRecons = $recons.Count
        foreach ($r in $recons) {
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
    }

    $passed = ($ssim -ge $targetSsim) -and ($lpips -le $targetLpips)

    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })
    Write-Host "  Results: $($exp.name) ($($expDuration.ToString('hh\:mm\:ss')))" -ForegroundColor White
    Write-Host "    SSIM:  $ssim $(if ($ssim -ge $targetSsim) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($ssim -ge $targetSsim) { "Green" } else { "Red" })
    Write-Host "    LPIPS: $lpips $(if ($lpips -le $targetLpips) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($lpips -le $targetLpips) { "Green" } else { "Red" })
    Write-Host "    Registered: $regCount images, $numRecons reconstruction(s)" -ForegroundColor White
    Write-Host "    points3D: $([math]::Round($ptsSize/1MB, 1)) MB" -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor $(if ($passed) { "Green" } else { "Yellow" })

    $results += @{
        name       = $exp.name
        description = $exp.description
        ssim       = $ssim
        lpips      = $lpips
        passed     = $passed
        regCount   = $regCount
        numRecons  = $numRecons
        ptsSizeMB  = [math]::Round($ptsSize/1MB, 1)
        duration   = $expDuration.ToString('hh\:mm\:ss')
    }

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
$totalDuration = (Get-Date) - $startTime

Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#  EXPERIMENT SUMMARY" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Baseline: SSIM=0.725 LPIPS=0.756 (output_default)" -ForegroundColor DarkGray

foreach ($r in $results) {
    $status = if ($r.passed) { "PASS" } else { "FAIL" }
    $color = if ($r.passed) { "Green" } else { "Yellow" }
    Write-Host "  $($r.name): SSIM=$($r.ssim) LPIPS=$($r.lpips) reg=$($r.regCount) pts=$($r.ptsSizeMB)MB $($r.duration) [$status]" -ForegroundColor $color
}

Write-Host ""
Write-Host "  Total time: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White

# Save results
$resultsJson = Join-Path $scene1 "experiment_results.json"
$results | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsJson -Encoding UTF8
Write-Host "  Results saved to: $resultsJson" -ForegroundColor DarkGray

if (-not ($results | Where-Object { $_.passed })) {
    Write-Host ""
    Write-Host "  WARNING: No experiment achieved the target." -ForegroundColor Red
    exit 1
}
exit 0

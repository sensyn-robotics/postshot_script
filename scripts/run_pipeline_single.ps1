# run_pipeline_single.ps1
# Pipeline runner for single-video scenes with quality gate and auto-retry
#
# Processes each scene through COLMAP + Postshot with automatic retry on failure
# or low quality (SSIM < threshold). Retry strategy: lower fps, then scale down.
#
# Usage:
#   .\run_pipeline_single.ps1 -ConfigPath config\pipeline_single.json                    # All scenes
#   .\run_pipeline_single.ps1 -ConfigPath config\pipeline_single.json -ScenePath C:\path  # Single scene

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [int]$StartStage = 1,

    [Parameter(Mandatory=$false)]
    [int]$EndStage = 7
)

$ErrorActionPreference = 'Stop'

# Resolve config path
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "..\$ConfigPath"
}
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

# Load configuration
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "ERROR: Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Read quality gate settings
$minSsim = 0.80
$retryStrategy = @(
    @{ fps = 2; scale = 1.0 },
    @{ fps = 1; scale = 1.0 },
    @{ fps = 1; scale = 0.8 },
    @{ fps = 1; scale = 0.64 },
    @{ fps = 1; scale = 0.512 }
)

if ($config.PSObject.Properties['quality_gate']) {
    if ($config.quality_gate.PSObject.Properties['min_ssim']) {
        $minSsim = $config.quality_gate.min_ssim
    }
    if ($config.quality_gate.PSObject.Properties['retry_strategy']) {
        $retryStrategy = @()
        foreach ($entry in $config.quality_gate.retry_strategy) {
            $retryStrategy += @{ fps = $entry.fps; scale = $entry.scale }
        }
    }
}

# Detect 360 mode
$is360Mode = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['mode'] -and $config.pipeline.mode -eq "360") {
    $is360Mode = $true
}
if ($config.PSObject.Properties['stage_01b_cubemap'] -and $config.stage_01b_cubemap.PSObject.Properties['enabled'] -and $config.stage_01b_cubemap.enabled) {
    $is360Mode = $true
}

if ($is360Mode) {
    Write-Host "  Mode: 360 (cubemap decomposition enabled)" -ForegroundColor Yellow
}

# Stage definitions
$stages = @(
    @{ Number = 1; Name = "01_extract_frames.ps1"; Description = "Frame Extraction" },
    @{ Number = 2; Name = "02_filter_frames.ps1"; Description = "Frame Filtering" },
    @{ Number = 3; Name = "03_colmap_features.ps1"; Description = "COLMAP Features" },
    @{ Number = 4; Name = "04_colmap_matching.ps1"; Description = "COLMAP Matching" },
    @{ Number = 5; Name = "05_colmap_mapper.ps1"; Description = "COLMAP Mapper" },
    @{ Number = 6; Name = "06_postshot_train.ps1"; Description = "Postshot Training" },
    @{ Number = 7; Name = "07_postshot_export.ps1"; Description = "Postshot Export" }
)

# Function to clean output for retry (keep videos, delete pipeline artifacts)
function Clean-OutputForRetry {
    param(
        [string]$ScenePath,
        [object]$Config,
        [bool]$PreserveImages = $false
    )

    $outputDir = Join-Path $ScenePath $Config.output.dir_name

    $dirsToClean = @(
        (Join-Path $outputDir $Config.output.colmap_subdir),
        (Join-Path $outputDir $Config.output.postshot_subdir),
        (Join-Path $outputDir $Config.output.visualizations_subdir),
        (Join-Path $outputDir "equirect_originals")
    )

    if (-not $PreserveImages) {
        $dirsToClean = @((Join-Path $outputDir $Config.output.images_subdir)) + $dirsToClean
    } else {
        Write-Host "    Preserving images (StartStage > 1)" -ForegroundColor DarkGray
    }

    foreach ($dir in $dirsToClean) {
        if (Test-Path -LiteralPath $dir) {
            Write-Host "    Cleaning: $dir" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Function to run all stages for a scene with specific fps/scale
function Run-StagesForScene {
    param(
        [string]$ScenePath,
        [string]$ConfigPath,
        [int]$StartStage,
        [int]$EndStage,
        [double]$FpsOverride,
        [double]$ScaleOverride
    )

    $stagesDir = Join-Path $PSScriptRoot "stages"

    for ($i = $StartStage; $i -le $EndStage; $i++) {
        $stage = $stages[$i - 1]

        # Check if stage 2 is disabled
        if ($i -eq 2 -and -not $config.stage_02_filter.enabled) {
            Write-Host ""
            Write-Host ">>> Stage $i : $($stage.Description) - SKIPPED (disabled in config)" -ForegroundColor DarkGray
            continue
        }

        Write-Host ""
        Write-Host ">>> Stage $i : $($stage.Description)" -ForegroundColor Cyan

        $stageScript = Join-Path $stagesDir $stage.Name

        if (-not (Test-Path -LiteralPath $stageScript)) {
            Write-Host "ERROR: Stage script not found: $stageScript" -ForegroundColor Red
            return $false
        }

        $stageStartTime = Get-Date

        # Stage 1 gets fps/scale overrides
        if ($i -eq 1) {
            & $stageScript -ConfigPath $ConfigPath -ScenePath $ScenePath -FpsOverride $FpsOverride -ScaleOverride $ScaleOverride
        } else {
            & $stageScript -ConfigPath $ConfigPath -ScenePath $ScenePath
        }

        $stageExitCode = $LASTEXITCODE
        $stageDuration = (Get-Date) - $stageStartTime

        if ($stageExitCode -ne 0) {
            Write-Host "!!! Stage $i FAILED with exit code $stageExitCode" -ForegroundColor Red
            return $false
        }

        Write-Host ">>> Stage $i completed in $($stageDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green

        # Run cubemap decomposition after frame extraction in 360 mode
        if ($is360Mode -and $i -eq 1) {
            Write-Host ""
            Write-Host ">>> Stage 1b: Cubemap Decomposition" -ForegroundColor Cyan

            $cubemapScript = Join-Path $stagesDir "01b_cubemap_decompose.ps1"
            if (-not (Test-Path -LiteralPath $cubemapScript)) {
                Write-Host "ERROR: 01b_cubemap_decompose.ps1 not found: $cubemapScript" -ForegroundColor Red
                return $false
            }

            $cubemapStartTime = Get-Date
            & $cubemapScript -ConfigPath $ConfigPath -ScenePath $ScenePath

            $cubemapExitCode = $LASTEXITCODE
            $cubemapDuration = (Get-Date) - $cubemapStartTime

            if ($cubemapExitCode -ne 0) {
                Write-Host "!!! Stage 1b FAILED with exit code $cubemapExitCode" -ForegroundColor Red
                return $false
            }

            Write-Host ">>> Stage 1b completed in $($cubemapDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
        }
    }

    return $true
}

# Function to check quality gate
function Check-QualityGate {
    param(
        [string]$ScenePath,
        [object]$Config,
        [double]$MinSsim
    )

    $outputDir = Join-Path $ScenePath $Config.output.dir_name
    $postshotDir = Join-Path $outputDir $Config.output.postshot_subdir
    $qualityJsonPath = Join-Path $postshotDir "quality.json"

    if (-not (Test-Path -LiteralPath $qualityJsonPath)) {
        Write-Host "  quality.json not found - cannot check quality gate" -ForegroundColor Yellow
        return @{ passed = $false; ssim = 0; reason = "quality.json not found" }
    }

    $qualityData = Get-Content $qualityJsonPath -Raw | ConvertFrom-Json

    if ($qualityData.PSObject.Properties['ssim']) {
        $ssim = [double]$qualityData.ssim
        if ($ssim -ge $MinSsim) {
            return @{ passed = $true; ssim = $ssim; reason = "SSIM $ssim >= $MinSsim" }
        } else {
            return @{ passed = $false; ssim = $ssim; reason = "SSIM $ssim < $MinSsim" }
        }
    }

    # If only PSNR is available (no SSIM), pass if PSNR > 20
    if ($qualityData.PSObject.Properties['psnr']) {
        $psnr = [double]$qualityData.psnr
        if ($psnr -gt 20) {
            return @{ passed = $true; ssim = 0; reason = "PSNR $psnr > 20 (SSIM unavailable)" }
        } else {
            return @{ passed = $false; ssim = 0; reason = "PSNR $psnr <= 20 (SSIM unavailable)" }
        }
    }

    # No quality metric available - cannot verify
    Write-Host "  No quality metric found in quality.json" -ForegroundColor Yellow
    return @{ passed = $false; ssim = 0; reason = "No quality metric available" }
}

# Function to check if path contains non-ASCII characters
function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# Function to create an ASCII junction for a scene with non-ASCII path
function New-AsciiJunction {
    param(
        [string]$ScenePath,
        [string]$TempBase
    )

    $sceneName = Split-Path -Leaf $ScenePath
    # Create an ASCII alias using the first token (e.g. "1_zoom3x" from "1_zoom3x_日本語...")
    $asciiName = ($sceneName -replace '[^\x00-\x7F]', '') -replace '__+', '_' -replace '_$', ''
    if ([string]::IsNullOrWhiteSpace($asciiName)) {
        $asciiName = "scene_$(Get-Random -Maximum 9999)"
    }
    $junctionPath = Join-Path $TempBase $asciiName

    # Clean up existing junction
    if (Test-Path -LiteralPath $junctionPath) {
        [System.IO.Directory]::Delete($junctionPath)
    }

    New-Item -ItemType Junction -Path $junctionPath -Target $ScenePath | Out-Null
    return $junctionPath
}

# Function to process a single scene with retry loop
function Process-SceneWithRetry {
    param(
        [string]$ScenePath,
        [string]$ConfigPath,
        [int]$StartStage,
        [int]$EndStage,
        [double]$MinSsim,
        [array]$RetryStrategy
    )

    $sceneName = Split-Path -Leaf $ScenePath
    $junctionPath = $null

    Write-Host ""
    Write-Host "########################################################" -ForegroundColor Magenta
    Write-Host "#  Single-Video Pipeline: $sceneName" -ForegroundColor Magenta
    Write-Host "########################################################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Config: $ConfigPath" -ForegroundColor White
    Write-Host "  Scene:  $ScenePath" -ForegroundColor White
    Write-Host "  Quality gate: SSIM >= $MinSsim" -ForegroundColor White
    Write-Host "  Max attempts: $($RetryStrategy.Count)" -ForegroundColor White

    # Create ASCII junction if path contains non-ASCII characters
    # This prevents OpenCV imread, COLMAP, and Postshot-cli from failing on Japanese paths
    $workingScenePath = $ScenePath
    if (Test-NonAsciiPath $ScenePath) {
        $tempBase = $config.paths.temp
        if (-not (Test-Path -LiteralPath $tempBase)) {
            New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
        }
        $junctionPath = New-AsciiJunction -ScenePath $ScenePath -TempBase $tempBase
        $workingScenePath = $junctionPath
        Write-Host "  Junction: $junctionPath -> $ScenePath" -ForegroundColor Yellow
    }

    Write-Host ""

    try {
        # Check if scene already has a passing quality result (skip if overwrite=false)
        $overwrite = $false
        if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
            $overwrite = $config.pipeline.overwrite_result
        }

        if (-not $overwrite) {
            $existingCheck = Check-QualityGate -ScenePath $workingScenePath -Config $config -MinSsim $MinSsim
            if ($existingCheck.passed) {
                Write-Host "  Scene already passes quality gate: $($existingCheck.reason)" -ForegroundColor Green
                Write-Host "  Skipping (overwrite_result=false)" -ForegroundColor Yellow
                return $true
            }
        }

        $sceneStartTime = Get-Date

        for ($attempt = 0; $attempt -lt $RetryStrategy.Count; $attempt++) {
            $strategy = $RetryStrategy[$attempt]
            $attemptFps = $strategy.fps
            $attemptScale = $strategy.scale

            Write-Host ""
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "  Attempt $($attempt + 1)/$($RetryStrategy.Count): fps=$attemptFps, scale=${attemptScale}x" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow

            # Clean previous attempt output (except first attempt)
            if ($attempt -gt 0) {
                Write-Host "  Cleaning previous attempt output..." -ForegroundColor Yellow
                Clean-OutputForRetry -ScenePath $workingScenePath -Config $config -PreserveImages ($StartStage -gt 1)
            }

            # Run all stages
            $pipelineResult = Run-StagesForScene `
                -ScenePath $workingScenePath `
                -ConfigPath $ConfigPath `
                -StartStage $StartStage `
                -EndStage $EndStage `
                -FpsOverride $attemptFps `
                -ScaleOverride $attemptScale

            if (-not $pipelineResult) {
                Write-Host ""
                Write-Host "  Pipeline FAILED on attempt $($attempt + 1). Retrying..." -ForegroundColor Red
                continue
            }

            # Check quality gate
            $qualityResult = Check-QualityGate -ScenePath $workingScenePath -Config $config -MinSsim $MinSsim

            if ($qualityResult.passed) {
                $sceneDuration = (Get-Date) - $sceneStartTime
                Write-Host ""
                Write-Host "########################################################" -ForegroundColor Green
                Write-Host "#  QUALITY GATE PASSED" -ForegroundColor Green
                Write-Host "#  $($qualityResult.reason)" -ForegroundColor Green
                Write-Host "#  Attempt: $($attempt + 1)/$($RetryStrategy.Count) (fps=$attemptFps, scale=${attemptScale}x)" -ForegroundColor Green
                Write-Host "#  Duration: $($sceneDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
                Write-Host "########################################################" -ForegroundColor Green
                return $true
            }

            Write-Host ""
            Write-Host "  Quality gate FAILED: $($qualityResult.reason)" -ForegroundColor Red
            if ($attempt -lt $RetryStrategy.Count - 1) {
                Write-Host "  Retrying with different settings..." -ForegroundColor Yellow
            }
        }

        # All attempts exhausted
        $sceneDuration = (Get-Date) - $sceneStartTime
        Write-Host ""
        Write-Host "########################################################" -ForegroundColor Red
        Write-Host "#  WARNING: All $($RetryStrategy.Count) attempts exhausted for $sceneName" -ForegroundColor Red
        Write-Host "#  Duration: $($sceneDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Red
        Write-Host "########################################################" -ForegroundColor Red
        return $false
    }
    finally {
        # Clean up junction
        if ($junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
            Write-Host "  Cleaning up junction: $junctionPath" -ForegroundColor DarkGray
            [System.IO.Directory]::Delete($junctionPath)
        }
    }
}

# ============================================================
# Main execution
# ============================================================
$totalStartTime = Get-Date
$scenesToProcess = @()

Write-Host ""
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "#  Single-Video Pipeline with Quality Gate              #" -ForegroundColor Magenta
Write-Host "#                                                      #" -ForegroundColor Magenta
Write-Host "########################################################" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Config: $ConfigPath" -ForegroundColor White
Write-Host "  Quality gate: SSIM >= $minSsim" -ForegroundColor White
Write-Host "  Retry levels: $($retryStrategy.Count)" -ForegroundColor White
for ($i = 0; $i -lt $retryStrategy.Count; $i++) {
    $s = $retryStrategy[$i]
    Write-Host "    [$($i+1)] fps=$($s.fps), scale=$($s.scale)x" -ForegroundColor DarkGray
}
Write-Host ""

# Determine scenes to process
if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    $testDataPath = $null
    if ($config.pipeline -and $config.pipeline.PSObject.Properties['test_data_path']) {
        $testDataPath = $config.pipeline.test_data_path
    }

    if ([string]::IsNullOrWhiteSpace($testDataPath)) {
        if (-not [string]::IsNullOrWhiteSpace($config.input.scene_path)) {
            $scenesToProcess = @($config.input.scene_path)
        } else {
            Write-Host "ERROR: No ScenePath provided and no test_data_path in config" -ForegroundColor Red
            exit 1
        }
    } else {
        if (-not (Test-Path -LiteralPath $testDataPath)) {
            Write-Host "ERROR: test_data_path not found: $testDataPath" -ForegroundColor Red
            exit 1
        }

        $sceneFolders = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
        if ($sceneFolders.Count -eq 0) {
            Write-Host "ERROR: No scene folders found in: $testDataPath" -ForegroundColor Red
            exit 1
        }

        $scenesToProcess = $sceneFolders | ForEach-Object { $_.FullName }

        Write-Host "  Found $($scenesToProcess.Count) scene(s):" -ForegroundColor White
        foreach ($scene in $scenesToProcess) {
            Write-Host "    - $(Split-Path -Leaf $scene)" -ForegroundColor Cyan
        }
        Write-Host ""
    }
} else {
    if (-not (Test-Path -LiteralPath $ScenePath)) {
        Write-Host "ERROR: Scene path not found: $ScenePath" -ForegroundColor Red
        exit 1
    }
    $scenesToProcess = @($ScenePath)
}

# Process each scene
$successCount = 0
$failCount = 0

foreach ($scene in $scenesToProcess) {
    $result = Process-SceneWithRetry `
        -ScenePath $scene `
        -ConfigPath $ConfigPath `
        -StartStage $StartStage `
        -EndStage $EndStage `
        -MinSsim $minSsim `
        -RetryStrategy $retryStrategy

    if ($result) {
        $successCount++
    } else {
        $failCount++
        Write-Host "WARNING: Scene failed all attempts, continuing with next scene..." -ForegroundColor Yellow
    }
}

# Final summary
$totalDuration = (Get-Date) - $totalStartTime

Write-Host ""
Write-Host "########################################################" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "#                                                      #" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "#  ALL SCENES COMPLETE                                 #" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "#                                                      #" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "########################################################" -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
Write-Host ""
Write-Host "  Total scenes: $($scenesToProcess.Count)" -ForegroundColor White
Write-Host "  Passed:       $successCount" -ForegroundColor Green
Write-Host "  Failed:       $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
Write-Host "  Total time:   $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host ""

if ($failCount -gt 0) {
    exit 1
}
exit 0

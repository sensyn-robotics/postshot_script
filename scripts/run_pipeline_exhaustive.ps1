# run_pipeline_exhaustive.ps1
# Pipeline using exhaustive matching with periodic visualization
#
# This script uses COLMAP's exhaustive_matcher instead of custom pairs,
# which may provide better cross-camera connections for W+Z footage.
#
# Visualization images are saved every ~10 minutes to monitor progress.

param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [int]$VisualizationIntervalMinutes = 10
)

$ErrorActionPreference = 'Stop'

# Import dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")
. (Join-Path $scriptDir "colmap_processor.ps1")
. (Join-Path $scriptDir "video_extractor.ps1")
. (Join-Path $scriptDir "postshot_runner.ps1")

# === HELPER FUNCTIONS ===

function Get-ProjectPaths {
    param([string]$BasePath)

    $outputDir = Join-Path $BasePath "output"

    return [PSCustomObject]@{
        Base = $BasePath
        Output = $outputDir
        Images = Join-Path $outputDir "images"
        ColmapOutput = Join-Path $outputDir "colmap_output"
        Sparse = Join-Path $outputDir "colmap_output\sparse"
        Psht = Join-Path $outputDir "scene.psht"
        Ply = Join-Path $outputDir "scene.ply"
        Visualizations = Join-Path $outputDir "visualizations"
    }
}

function Save-Visualization {
    param(
        [string]$Type,
        [string]$SourcePath,
        [string]$OutputDir,
        [int]$StepNumber
    )

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $OutputDir "${Type}_step${StepNumber}_${timestamp}.png"

    Write-Host "  Saving visualization: $outputFile" -ForegroundColor Gray

    if ($Type -eq "colmap") {
        & (Join-Path $scriptDir "visualize_colmap.ps1") -SparsePath $SourcePath -OutputImage $outputFile
    }
    elseif ($Type -eq "postshot") {
        & (Join-Path $scriptDir "visualize_postshot.ps1") -PshtPath $SourcePath -OutputImage $outputFile
    }
}

function Start-VisualizationMonitor {
    param(
        [string]$Type,
        [string]$WatchPath,
        [string]$OutputDir,
        [int]$IntervalMinutes
    )

    # Start a background job that periodically saves visualizations
    $job = Start-Job -ScriptBlock {
        param($Type, $WatchPath, $OutputDir, $IntervalMinutes, $ScriptDir)

        $stepNumber = 0
        while ($true) {
            Start-Sleep -Seconds ($IntervalMinutes * 60)

            if (Test-Path $WatchPath) {
                $stepNumber++
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $outputFile = Join-Path $OutputDir "${Type}_step${stepNumber}_${timestamp}.png"

                # Call visualization script
                if ($Type -eq "colmap") {
                    & (Join-Path $ScriptDir "visualize_colmap.ps1") -SparsePath $WatchPath -OutputImage $outputFile 2>&1 | Out-Null
                }
            }
        }
    } -ArgumentList $Type, $WatchPath, $OutputDir, $IntervalMinutes, $scriptDir

    return $job
}

# === MAIN PIPELINE ===

function Run-ExhaustivePipeline {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [int]$VisualizationIntervalMinutes = 10
    )

    $result = [PSCustomObject]@{
        Success = $false
        ProjectPath = $null
        ImagesPath = $null
        ColmapPath = $null
        PshtPath = $null
        PlyPath = $null
        Errors = @()
    }

    Write-Host ""
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host "#  Exhaustive Matching Pipeline        #" -ForegroundColor Magenta
    Write-Host "#  with Periodic Visualization         #" -ForegroundColor Magenta
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Strategy: Exhaustive Feature Matching" -ForegroundColor Cyan
    Write-Host "  1. Extract frames from W and Z videos" -ForegroundColor Gray
    Write-Host "  2. Feature extraction on ALL images (W+Z)" -ForegroundColor Gray
    Write-Host "  3. Exhaustive matching (all pairs)" -ForegroundColor Gray
    Write-Host "  4. Run COLMAP mapper" -ForegroundColor Gray
    Write-Host "  5. Run Postshot on best reconstruction" -ForegroundColor Gray
    Write-Host "  Visualization interval: $VisualizationIntervalMinutes minutes" -ForegroundColor Gray
    Write-Host ""

    $paths = Get-ProjectPaths -BasePath $InputPath
    $result.ProjectPath = $InputPath

    # Create visualizations directory
    if (-not (Test-Path $paths.Visualizations)) {
        New-Item -ItemType Directory -Path $paths.Visualizations -Force | Out-Null
    }

    # === Stage 1: Frame Extraction ===
    Write-Host "--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow

    # Find W and Z videos
    $videos = Get-ChildItem -LiteralPath $InputPath -File | Where-Object {
        $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV", ".avi", ".AVI")
    }

    $wVideos = $videos | Where-Object { $_.Name -match "_W[-.]" }
    $zVideos = $videos | Where-Object { $_.Name -match "_Z[-.]" }

    Write-Host "  Found $($wVideos.Count) Wide video(s), $($zVideos.Count) Zoom video(s)"

    # Create images directory structure
    $wImagesDir = Join-Path $paths.Images "video_W"
    $zImagesDir = Join-Path $paths.Images "video_Z"

    foreach ($dir in @($paths.Images, $wImagesDir, $zImagesDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Extract W frames
    foreach ($video in $wVideos) {
        Write-Host "  Extracting W frames: $($video.Name)" -ForegroundColor Cyan
        $extractResult = Extract-VideoFrames -VideoPath $video.FullName -OutputDir $wImagesDir -Config $Config
        if (-not $extractResult) {
            $result.Errors += "Failed to extract W frames from $($video.Name)"
        }
    }

    # Extract Z frames
    foreach ($video in $zVideos) {
        Write-Host "  Extracting Z frames: $($video.Name)" -ForegroundColor Cyan
        $extractResult = Extract-VideoFrames -VideoPath $video.FullName -OutputDir $zImagesDir -Config $Config
        if (-not $extractResult) {
            $result.Errors += "Failed to extract Z frames from $($video.Name)"
        }
    }

    $result.ImagesPath = $paths.Images

    # Count extracted frames
    $wCount = (Get-ChildItem -LiteralPath $wImagesDir -File -ErrorAction SilentlyContinue).Count
    $zCount = (Get-ChildItem -LiteralPath $zImagesDir -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Extracted: $wCount Wide frames, $zCount Zoom frames" -ForegroundColor Green

    if ($wCount -eq 0 -and $zCount -eq 0) {
        $result.Errors += "No frames extracted"
        return $result
    }

    # === Stage 2: COLMAP with Exhaustive Matching ===
    Write-Host ""
    Write-Host "--- Stage 2: COLMAP Processing (Exhaustive Matching) ---" -ForegroundColor Yellow

    $colmapExe = $Config.paths.colmap_exe
    $databasePath = Join-Path $paths.ColmapOutput "database.db"
    $sparsePath = $paths.Sparse

    # Create output directories
    foreach ($dir in @($paths.ColmapOutput, $sparsePath)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Step 2a: Feature Extraction
    Write-Host "  Running feature extraction..." -ForegroundColor Cyan
    $featureResult = Run-ColmapFeatureExtraction -ColmapExe $colmapExe -DatabasePath $databasePath -ImagePath $paths.Images -Config $Config
    if (-not $featureResult) {
        $result.Errors += "Feature extraction failed"
        return $result
    }

    # Step 2b: Exhaustive Matching
    Write-Host "  Running exhaustive matching..." -ForegroundColor Cyan
    $matchResult = Run-ColmapMatching -ColmapExe $colmapExe -DatabasePath $databasePath -MatcherType "exhaustive" -Config $Config
    if (-not $matchResult) {
        $result.Errors += "Exhaustive matching failed"
        return $result
    }

    # Step 2c: Mapper
    Write-Host "  Running mapper..." -ForegroundColor Cyan
    $mapperResult = Run-ColmapMapper -ColmapExe $colmapExe -DatabasePath $databasePath -ImagePath $paths.Images -OutputPath $sparsePath -Config $Config
    if (-not $mapperResult) {
        $result.Errors += "Mapper failed"
        return $result
    }

    # Find and visualize the largest reconstruction
    $largestRecon = Get-LargestReconstruction -SparsePath $sparsePath
    if ($largestRecon) {
        $result.ColmapPath = $largestRecon
        Write-Host "  Best reconstruction: $largestRecon" -ForegroundColor Green

        # Save COLMAP visualization
        Save-Visualization -Type "colmap" -SourcePath $largestRecon -OutputDir $paths.Visualizations -StepNumber 1
    } else {
        $result.Errors += "No valid reconstruction found"
        return $result
    }

    # === Stage 3: Postshot Training with Periodic Visualization ===
    Write-Host ""
    Write-Host "--- Stage 3: Postshot Training ---" -ForegroundColor Yellow
    Write-Host "  Images: $($paths.Images)" -ForegroundColor Cyan
    Write-Host "  COLMAP sparse: $largestRecon" -ForegroundColor Cyan

    # Start Postshot training
    $postshotResult = Run-PostshotPipeline `
        -InputPath $paths.Images `
        -OutputPath $paths.Psht `
        -Config $Config `
        -ExportPly $Config.postshot.export_ply `
        -ColmapSparsePath $largestRecon

    if (-not $postshotResult.Success) {
        $result.Errors += "Postshot training failed"
        return $result
    }

    $result.PshtPath = $postshotResult.PshtPath
    $result.PlyPath = $postshotResult.PlyPath

    # Save final Postshot visualization
    if ($postshotResult.PshtPath -and (Test-Path $postshotResult.PshtPath)) {
        Save-Visualization -Type "postshot" -SourcePath $postshotResult.PshtPath -OutputDir $paths.Visualizations -StepNumber 99
    }

    $result.Success = $true
    return $result
}

# === MAIN EXECUTION ===

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Exhaustive Pipeline Runner" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "  Input: $InputPath" -ForegroundColor Cyan
Write-Host "  Visualization interval: $VisualizationIntervalMinutes min" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor White

# Load configuration
$Config = Load-Config -CustomConfigPath $ConfigPath

# Validate configuration
Write-Host "`nValidating configuration..." -ForegroundColor Cyan
$configValid = Validate-Config -Config $Config

if (-not $configValid) {
    Write-Host "`nWARNING: Some required tools are missing." -ForegroundColor Yellow
    exit 1
}

# Run the pipeline
$startTime = Get-Date
$result = Run-ExhaustivePipeline -InputPath $InputPath -Config $Config -VisualizationIntervalMinutes $VisualizationIntervalMinutes
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Pipeline Complete" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "  Success: $($result.Success)" -ForegroundColor $(if ($result.Success) { "Green" } else { "Red" })

if ($result.Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "  Errors:" -ForegroundColor Red
    foreach ($err in $result.Errors) {
        Write-Host "    - $err" -ForegroundColor Red
    }
}

if ($result.Success) {
    Write-Host ""
    Write-Host "  Output Files:" -ForegroundColor Green
    Write-Host "    PSHT: $($result.PshtPath)" -ForegroundColor Cyan
    if ($result.PlyPath) {
        Write-Host "    PLY:  $($result.PlyPath)" -ForegroundColor Cyan
    }
    Write-Host "    Visualizations: $(Join-Path $InputPath 'output\visualizations')" -ForegroundColor Cyan
}

Write-Host "========================================" -ForegroundColor White

if ($result.Success) {
    exit 0
} else {
    exit 1
}

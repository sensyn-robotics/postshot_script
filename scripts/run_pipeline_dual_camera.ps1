# run_pipeline_dual_camera.ps1
# Pipeline for dual-camera systems (e.g., DJI H30T with Wide + Zoom)
#
# Strategy: Custom Pair Matching
#   1. Extract frames from W and Z videos
#   2. Run COLMAP feature extraction on ALL images (W+Z)
#   3. Generate custom match pairs (W<->W temporal, Z<->Z temporal, W<->Z same-timestamp)
#   4. Run COLMAP with custom pair matching for better convergence
#   5. Run Postshot on unified model
#
# This approach works better than W-only + merge because:
#   - Both cameras contribute to feature matching
#   - Custom pairs avoid problematic distant W<->Z matches
#   - Bundle adjustment gets cleaner input data
#
# See docs/dual_camera_strategy.md for detailed explanation.
#
# Usage:
#   .\run_pipeline_dual_camera.ps1 -InputPath "C:\data\scene1"
#
# Expected input structure:
#   scene1/
#   +-- DJI_xxx_W.MP4  (Wide camera video)
#   +-- DJI_xxx_Z.MP4  (Zoom camera video)
#
# Output structure:
#   scene1/output/
#   +-- images/
#   |   +-- video_W/  (extracted frames from Wide)
#   |   +-- video_Z/  (extracted frames from Zoom)
#   +-- colmap_output/
#   |   +-- match_pairs.txt   (generated custom pairs)
#   |   +-- sparse/0/         (unified COLMAP model with W+Z)
#   +-- scene.psht
#   +-- scene.ply

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("exhaustive", "sequential", "custom_pairs")]
    [string]$MatcherType = "custom_pairs",  # Custom pairs for dual-camera

    [Parameter(Mandatory=$false)]
    [int]$TemporalOverlap = 10,  # Neighbors to match within each camera

    [Parameter(Mandatory=$false)]
    [int]$VisualizationIntervalMinutes = 10  # Interval for periodic visualization
)

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

# Import modules
. (Join-Path $rootDir "lib\config_loader.ps1")
. (Join-Path $scriptDir "video_extractor.ps1")
. (Join-Path $scriptDir "colmap_processor.ps1")
. (Join-Path $scriptDir "postshot_runner.ps1")
# Note: generate_match_pairs.ps1 is called as external script, not dot-sourced

# Stop on errors
$ErrorActionPreference = 'Stop'

function Get-DualCameraProjectPaths {
    <#
    .SYNOPSIS
    Generate paths for dual-camera project
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BasePath
    )

    $outputDir = Join-Path $BasePath "output"

    return [PSCustomObject]@{
        Base = $BasePath
        Output = $outputDir
        Images = Join-Path $outputDir "images"
        ImagesW = Join-Path $outputDir "images\video_W"
        ImagesZ = Join-Path $outputDir "images\video_Z"
        ColmapOutput = Join-Path $outputDir "colmap_output"
        MatchPairs = Join-Path $outputDir "colmap_output\match_pairs.txt"
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

function Run-DualCameraPipeline {
    <#
    .SYNOPSIS
    Run the complete dual-camera pipeline with custom pair matching
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [ValidateSet("exhaustive", "sequential", "custom_pairs")]
        [string]$MatcherType = "custom_pairs",

        [Parameter(Mandatory=$false)]
        [int]$TemporalOverlap = 10,

        [Parameter(Mandatory=$false)]
        [int]$VisualizationIntervalMinutes = 10
    )

    $result = [PSCustomObject]@{
        Success = $false
        PshtPath = $null
        PlyPath = $null
        Errors = @()
    }

    Write-Host ""
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host "#  Dual-Camera Pipeline (Custom Pairs) #" -ForegroundColor Magenta
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Strategy: Custom Pair Matching" -ForegroundColor Cyan
    Write-Host "  1. Extract frames from W and Z videos" -ForegroundColor Gray
    Write-Host "  2. Feature extraction on ALL images (W+Z)" -ForegroundColor Gray
    Write-Host "  3. Generate custom match pairs (W<->W, Z<->Z, W<->Z)" -ForegroundColor Gray
    Write-Host "  4. Run COLMAP with custom pairs" -ForegroundColor Gray
    Write-Host "  5. Run Postshot on unified model" -ForegroundColor Gray
    Write-Host ""

    $paths = Get-DualCameraProjectPaths -BasePath $InputPath

    # === Stage 1: Frame Extraction ===
    Write-Host "--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow

    # Find W and Z videos
    $videos = Get-ChildItem -LiteralPath $InputPath -File | Where-Object {
        $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV", ".avi", ".AVI")
    }

    # Match both _W.MP4 and _W-002.MP4 naming patterns
    $wVideos = $videos | Where-Object { $_.Name -match "_W[-.]" }
    $zVideos = $videos | Where-Object { $_.Name -match "_Z[-.]" }

    if ($wVideos.Count -eq 0) {
        $result.Errors += "No Wide (_W) videos found"
        Write-Host "ERROR: No Wide (_W) videos found in $InputPath" -ForegroundColor Red
        return $result
    }

    if ($zVideos.Count -eq 0) {
        $result.Errors += "No Zoom (_Z) videos found"
        Write-Host "ERROR: No Zoom (_Z) videos found in $InputPath" -ForegroundColor Red
        return $result
    }

    Write-Host "  Found $($wVideos.Count) Wide video(s), $($zVideos.Count) Zoom video(s)" -ForegroundColor Cyan

    # Extract W frames
    foreach ($video in $wVideos) {
        $outputDir = $paths.ImagesW
        Write-Host "  Extracting W frames: $($video.Name)" -ForegroundColor Gray
        $extractResult = Extract-VideoFrames -VideoPath $video.FullName -OutputDir $outputDir -Config $Config
        if (-not $extractResult) {
            $result.Errors += "Failed to extract W frames"
            return $result
        }
    }

    # Extract Z frames
    foreach ($video in $zVideos) {
        $outputDir = $paths.ImagesZ
        Write-Host "  Extracting Z frames: $($video.Name)" -ForegroundColor Gray
        $extractResult = Extract-VideoFrames -VideoPath $video.FullName -OutputDir $outputDir -Config $Config
        if (-not $extractResult) {
            $result.Errors += "Failed to extract Z frames"
            return $result
        }
    }

    # === Stage 2: Generate Match Pairs (for custom_pairs matcher) ===
    if ($MatcherType -eq "custom_pairs") {
        Write-Host ""
        Write-Host "--- Stage 2: Generate Match Pairs ---" -ForegroundColor Yellow

        # Create colmap_output directory
        if (-not (Test-Path $paths.ColmapOutput)) {
            New-Item -ItemType Directory -Path $paths.ColmapOutput -Force | Out-Null
        }

        # Get temporal overlap from config or use parameter
        $configOverlap = $Config.colmap.matcher.temporal_overlap
        if ($configOverlap) {
            $TemporalOverlap = $configOverlap
        }

        Write-Host "  Generating match pairs with temporal_overlap=$TemporalOverlap" -ForegroundColor Gray

        # Call generate_match_pairs.ps1
        $generateScript = Join-Path $scriptDir "generate_match_pairs.ps1"
        & $generateScript `
            -ImagesDir $paths.Images `
            -OutputPath $paths.MatchPairs `
            -TemporalOverlap $TemporalOverlap `
            -CrossCameraSameTimestamp

        if ($LASTEXITCODE -ne 0) {
            $result.Errors += "Failed to generate match pairs"
            Write-Host "ERROR: Match pairs generation failed" -ForegroundColor Red
            return $result
        }

        if (-not (Test-Path $paths.MatchPairs)) {
            $result.Errors += "Match pairs file not created"
            Write-Host "ERROR: Match pairs file not found at: $($paths.MatchPairs)" -ForegroundColor Red
            return $result
        }
    }

    # === Stage 3: COLMAP on W+Z with Custom Pairs ===
    Write-Host ""
    Write-Host "--- Stage 3: COLMAP on W+Z Images ---" -ForegroundColor Yellow

    # Run COLMAP pipeline on all images (W+Z) with custom pair matching
    $colmapParams = @{
        ImageDir = $paths.Images
        OutputDir = $paths.ColmapOutput
        Config = $Config
        MatcherType = $MatcherType
    }

    if ($MatcherType -eq "custom_pairs") {
        $colmapParams.MatchPairsPath = $paths.MatchPairs
    }

    $colmapResult = Run-ColmapPipeline @colmapParams

    if (-not $colmapResult) {
        $result.Errors += "COLMAP processing failed"
        return $result
    }

    # Save COLMAP visualization
    if (Test-Path $colmapResult) {
        Save-Visualization -Type "colmap" -SourcePath $colmapResult -OutputDir $paths.Visualizations -StepNumber 1
    }

    # === Stage 4: Postshot Training ===
    Write-Host ""
    Write-Host "--- Stage 4: Postshot Training ---" -ForegroundColor Yellow
    Write-Host "  Images: $($paths.Images)" -ForegroundColor Cyan
    Write-Host "  COLMAP sparse: $colmapResult" -ForegroundColor Cyan

    $postshotResult = Run-PostshotPipeline `
        -InputPath $paths.Images `
        -OutputPath $paths.Psht `
        -Config $Config `
        -ExportPly $Config.postshot.export_ply `
        -ColmapSparsePath $colmapResult

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
Write-Host "  Dual-Camera Pipeline Runner" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "  Input: $InputPath" -ForegroundColor Cyan
Write-Host "  Matcher: $MatcherType" -ForegroundColor Cyan
if ($MatcherType -eq "custom_pairs") {
    Write-Host "  Temporal Overlap: $TemporalOverlap" -ForegroundColor Cyan
}
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
$result = Run-DualCameraPipeline -InputPath $InputPath -Config $Config -MatcherType $MatcherType -TemporalOverlap $TemporalOverlap -VisualizationIntervalMinutes $VisualizationIntervalMinutes
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Pipeline Complete" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "  Success: $($result.Success)" -ForegroundColor $(if ($result.Success) { "Green" } else { "Red" })

if ($result.Success) {
    Write-Host ""
    Write-Host "  Output Files:" -ForegroundColor Green
    if ($result.PshtPath) {
        Write-Host "    PSHT: $($result.PshtPath)" -ForegroundColor Green
    }
    if ($result.PlyPath) {
        Write-Host "    PLY:  $($result.PlyPath)" -ForegroundColor Green
    }
}
else {
    Write-Host ""
    Write-Host "  Errors:" -ForegroundColor Red
    foreach ($err in $result.Errors) {
        Write-Host "    - $err" -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor White

if ($result.Success) {
    exit 0
}
else {
    exit 1
}

# 04_colmap_matching.ps1
# Stage 4: COLMAP feature matching
#
# Input: output/colmap/database.db
# Output: database with matches

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [string]$MatcherTypeOverride = "",

    [Parameter(Mandatory=$false)]
    [int]$SequentialOverlapOverride = 0,

    [Parameter(Mandatory=$false)]
    [string]$LoopDetectionOverride = "",

    [Parameter(Mandatory=$false)]
    [string]$GuidedMatchingOverride = ""
)

$ErrorActionPreference = 'Stop'

# Load configuration
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Use ScenePath if provided, otherwise use config
if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    $ScenePath = $config.input.scene_path
}

if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    Write-Host "ERROR: ScenePath is required (via parameter or config)" -ForegroundColor Red
    exit 1
}

# Resolve paths
$outputDir = Join-Path $ScenePath $config.output.dir_name
$colmapDir = Join-Path $outputDir $config.output.colmap_subdir
$databasePath = Join-Path $colmapDir "database.db"
$colmapExe = $config.paths.colmap

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 4: COLMAP Feature Matching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Database: $databasePath" -ForegroundColor White
$effectiveMatcherType = if (-not [string]::IsNullOrWhiteSpace($MatcherTypeOverride)) { $MatcherTypeOverride } else { $config.stage_04_matching.type }
$effectiveLoopDetection = if (-not [string]::IsNullOrWhiteSpace($LoopDetectionOverride)) { $LoopDetectionOverride -eq "true" } else { $config.stage_04_matching.PSObject.Properties['loop_detection'] -and $config.stage_04_matching.loop_detection -eq $true }
$effectiveGuidedMatching = if (-not [string]::IsNullOrWhiteSpace($GuidedMatchingOverride)) { $GuidedMatchingOverride -eq "true" } else { $config.stage_04_matching.PSObject.Properties['guided_matching'] -and $config.stage_04_matching.guided_matching -eq $true }

Write-Host "  Matcher type: $effectiveMatcherType$(if (-not [string]::IsNullOrWhiteSpace($MatcherTypeOverride)) { ' (override)' })" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate COLMAP
if (-not (Test-Path -LiteralPath $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
    exit 1
}

# Validate database
if (-not (Test-Path -LiteralPath $databasePath)) {
    Write-Host "ERROR: Database not found: $databasePath" -ForegroundColor Red
    Write-Host "  Run stage 03 (feature extraction) first" -ForegroundColor Yellow
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check if sparse directory exists (indicates matching was already done)
$sparseDir = Join-Path $colmapDir "sparse"
if ((Test-Path -LiteralPath $sparseDir) -and -not $overwrite) {
    $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
    if ($reconFolders.Count -gt 0) {
        Write-Host "  Sparse reconstruction already exists" -ForegroundColor Yellow
        Write-Host "  Skipping matching (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Stage 4 Complete (skipped - reconstruction exists)" -ForegroundColor Green
        exit 0
    }
}

# Get COLMAP binary path
$colmapBin = if ($colmapExe -like "*.bat") {
    $colmapBinDir = Split-Path -Parent $colmapExe
    Join-Path $colmapBinDir "bin\colmap.exe"
} else {
    $colmapExe
}

# Set up COLMAP environment
$colmapRootDir = if ($colmapExe -like "*.bat") {
    Split-Path -Parent $colmapExe
} else {
    Split-Path -Parent (Split-Path -Parent $colmapExe)
}

$env:PATH = "$(Join-Path $colmapRootDir 'bin');$env:PATH"
$env:QT_PLUGIN_PATH = Join-Path $colmapRootDir "plugins"

# Build matching arguments based on type
$matcherType = $effectiveMatcherType
$matcherCommand = "${matcherType}_matcher"

$colmapArgs = @(
    $matcherCommand,
    "--database_path", $databasePath
)

# Sequential matcher advanced options
if ($matcherType -eq "sequential") {
    # Overlap (number of neighboring images to match)
    $effectiveOverlap = if ($SequentialOverlapOverride -gt 0) { $SequentialOverlapOverride } elseif ($config.stage_04_matching.PSObject.Properties['overlap']) { $config.stage_04_matching.overlap } else { 0 }
    if ($effectiveOverlap -gt 0) {
        $colmapArgs += @("--SequentialMatching.overlap", $effectiveOverlap)
        Write-Host "  Overlap: $effectiveOverlap$(if ($SequentialOverlapOverride -gt 0) { ' (override)' })" -ForegroundColor White
    }

    # Loop detection via vocab tree
    if ($effectiveLoopDetection) {
        # Resolve vocab tree path
        $vocabTreePath = $null
        if ($config.stage_04_matching.PSObject.Properties['loop_detection_vocab_tree_path']) {
            $vocabTreePath = $config.stage_04_matching.loop_detection_vocab_tree_path
        } else {
            # Default location next to COLMAP
            $colmapRoot = Split-Path -Parent $colmapExe
            $vocabTreePath = Join-Path $colmapRoot "vocab_tree_flickr100K_words32K.bin"
        }

        # Auto-download vocab tree if not found
        if (-not (Test-Path -LiteralPath $vocabTreePath)) {
            Write-Host "  Vocab tree not found at: $vocabTreePath" -ForegroundColor Yellow
            Write-Host "  Downloading vocab tree (this only happens once)..." -ForegroundColor Yellow
            # Use faiss-compatible vocab tree (COLMAP switched from flann to faiss in May 2025)
            $vocabTreeUrl = "https://github.com/ZachMckennedyFWig/ColmapFaissVocabTrees/raw/main/vocab_tree_flickr100K_words32K.bin"
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $vocabTreeUrl -OutFile $vocabTreePath -UseBasicParsing
                Write-Host "  Downloaded vocab tree to: $vocabTreePath" -ForegroundColor Green
            } catch {
                Write-Host "ERROR: Failed to download vocab tree: $_" -ForegroundColor Red
                Write-Host "  Download manually from: $vocabTreeUrl" -ForegroundColor Yellow
                Write-Host "  Save to: $vocabTreePath" -ForegroundColor Yellow
                exit 1
            }
        }

        $colmapArgs += @("--SequentialMatching.loop_detection", "1")
        $colmapArgs += @("--SequentialMatching.vocab_tree_path", $vocabTreePath)
        Write-Host "  Loop detection: enabled" -ForegroundColor White
        Write-Host "  Vocab tree: $vocabTreePath" -ForegroundColor White

        # Loop detection period
        if ($config.stage_04_matching.PSObject.Properties['loop_detection_period']) {
            $period = $config.stage_04_matching.loop_detection_period
            $colmapArgs += @("--SequentialMatching.loop_detection_period", $period)
            Write-Host "  Loop detection period: $period" -ForegroundColor White
        }

        # Loop detection num images
        if ($config.stage_04_matching.PSObject.Properties['loop_detection_num_images']) {
            $numImages = $config.stage_04_matching.loop_detection_num_images
            $colmapArgs += @("--SequentialMatching.loop_detection_num_images", $numImages)
            Write-Host "  Loop detection candidates: $numImages" -ForegroundColor White
        }
    }
}

# SIFT matching max_ratio (Lowe's ratio test - lower = stricter)
$siftMaxRatio = if ($config.stage_04_matching.PSObject.Properties['sift_max_ratio']) {
    $config.stage_04_matching.sift_max_ratio
} else { 0.8 }  # COLMAP default
$colmapArgs += @("--SiftMatching.max_ratio", $siftMaxRatio)
Write-Host "  SIFT max_ratio: $siftMaxRatio" -ForegroundColor White

# Guided matching (works with any matcher type)
if ($effectiveGuidedMatching) {
    $colmapArgs += @("--FeatureMatching.guided_matching", "1")
    Write-Host "  Guided matching: enabled" -ForegroundColor White
}

Write-Host ""
Write-Host "  Running $matcherType matching..." -ForegroundColor Cyan
Write-Host "  Command: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

$timeoutHours = 12
if ($config.stage_04_matching -and $config.stage_04_matching.PSObject.Properties['colmap_timeout_hours']) {
    $timeoutHours = $config.stage_04_matching.colmap_timeout_hours
} elseif ($config.stage_05_mapper -and $config.stage_05_mapper.PSObject.Properties['colmap_timeout_hours']) {
    $timeoutHours = $config.stage_05_mapper.colmap_timeout_hours
}
$timeoutMs = [int]($timeoutHours * 3600 * 1000)

$startTime = Get-Date

$process = Start-Process -FilePath $colmapBin `
    -ArgumentList $colmapArgs `
    -NoNewWindow -PassThru

$exited = $process.WaitForExit($timeoutMs)
$duration = (Get-Date) - $startTime

if (-not $exited) {
    Write-Host "ERROR: Feature matching timed out after $timeoutHours hours. Killing process." -ForegroundColor Red
    $process.Kill()
    exit 1
}

if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature matching failed with exit code $($process.ExitCode)" -ForegroundColor Red
    exit 1
}

$dbSize = (Get-Item -LiteralPath $databasePath).Length / 1MB

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 4 Complete" -ForegroundColor Green
Write-Host "  Database size: $('{0:N2}' -f $dbSize) MB" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

# colmap_processor.ps1
# COLMAP SfM pipeline for sparse reconstruction
#
# NOTE: Script-level params use _Script prefix to avoid conflicts when dot-sourced

param(
    [Parameter(Mandatory=$false)]
    [string]$_ScriptImageDir,

    [Parameter(Mandatory=$false)]
    [string]$_ScriptOutputDir,

    [Parameter(Mandatory=$false)]
    [PSCustomObject]$_ScriptConfig,

    [Parameter(Mandatory=$false)]
    [ValidateSet("exhaustive", "sequential", "custom_pairs")]
    [string]$_ScriptMatcherType = "exhaustive",

    [Parameter(Mandatory=$false)]
    [string]$_ScriptMatchPairsPath
)

# Import config loader
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")

function Setup-ColmapEnvironment {
    <#
    .SYNOPSIS
    Set up environment for COLMAP execution

    .PARAMETER ColmapPath
    Path to COLMAP installation (parent of bin folder)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ColmapPath
    )

    $binPath = Join-Path $ColmapPath "bin"
    $pluginsPath = Join-Path $ColmapPath "plugins"

    # Add COLMAP bin to PATH if not already present
    if ($env:PATH -notlike "*$binPath*") {
        $env:PATH = "$binPath;$env:PATH"
    }

    # Set Qt plugin path
    $env:QT_PLUGIN_PATH = $pluginsPath
}

function Run-ColmapFeatureExtraction {
    <#
    .SYNOPSIS
    Run COLMAP feature extraction

    .PARAMETER ColmapExe
    Path to COLMAP executable or batch file

    .PARAMETER DatabasePath
    Path to COLMAP database file

    .PARAMETER ImagePath
    Path to images directory

    .PARAMETER Config
    Configuration object with feature extractor settings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ColmapExe,

        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,

        [Parameter(Mandatory=$true)]
        [string]$ImagePath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    Write-Host ""
    Write-Host "=== COLMAP Feature Extraction ===" -ForegroundColor Cyan

    # Set up COLMAP environment
    $colmapDir = Split-Path -Parent (Split-Path -Parent $ColmapExe)
    if ($ColmapExe -like "*.bat") {
        $colmapDir = Split-Path -Parent $ColmapExe
    }
    Setup-ColmapEnvironment -ColmapPath $colmapDir

    # Get the actual colmap.exe path
    $colmapBin = if ($ColmapExe -like "*.bat") {
        Join-Path $colmapDir "bin\colmap.exe"
    } else {
        $ColmapExe
    }

    $featureConfig = $Config.colmap.feature_extractor

    $colmapArgs = @(
        "feature_extractor",
        "--database_path", $DatabasePath,
        "--image_path", $ImagePath
    )

    # Add feature extractor options from config (use --Option=value format)
    foreach ($prop in $featureConfig.PSObject.Properties) {
        $colmapArgs += "--$($prop.Name)=$($prop.Value)"
    }

    Write-Host "Running: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host "  single_camera_per_folder: $($featureConfig.'ImageReader.single_camera_per_folder')" -ForegroundColor Yellow

    # Use call operator to run in current environment (inherits PATH changes)
    & $colmapBin $colmapArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "ERROR: Feature extraction failed with exit code: $exitCode" -ForegroundColor Red
        return $false
    }

    Write-Host "Feature extraction completed successfully" -ForegroundColor Green
    return $true
}

function Run-ColmapMatching {
    <#
    .SYNOPSIS
    Run COLMAP feature matching

    .PARAMETER ColmapExe
    Path to COLMAP executable or batch file

    .PARAMETER DatabasePath
    Path to COLMAP database file

    .PARAMETER MatcherType
    Type of matcher: "exhaustive", "sequential", or "custom_pairs"

    .PARAMETER Config
    Configuration object with matcher settings

    .PARAMETER MatchPairsPath
    Path to match_pairs.txt file (required for custom_pairs matcher)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ColmapExe,

        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("exhaustive", "sequential", "custom_pairs")]
        [string]$MatcherType,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [string]$MatchPairsPath
    )

    Write-Host ""
    Write-Host "=== COLMAP Feature Matching ($MatcherType) ===" -ForegroundColor Cyan

    # Set up COLMAP environment
    $colmapDir = if ($ColmapExe -like "*.bat") {
        Split-Path -Parent $ColmapExe
    } else {
        Split-Path -Parent (Split-Path -Parent $ColmapExe)
    }
    Setup-ColmapEnvironment -ColmapPath $colmapDir

    # Get the actual colmap.exe path
    $colmapBin = if ($ColmapExe -like "*.bat") {
        Join-Path $colmapDir "bin\colmap.exe"
    } else {
        $ColmapExe
    }

    $matcherConfig = $Config.colmap.matcher

    # Handle custom_pairs matcher differently
    if ($MatcherType -eq "custom_pairs") {
        if (-not $MatchPairsPath -or -not (Test-Path $MatchPairsPath)) {
            Write-Host "ERROR: Custom pairs matcher requires a valid match_pairs.txt file" -ForegroundColor Red
            Write-Host "  Expected at: $MatchPairsPath" -ForegroundColor Red
            return $false
        }

        # Use matches_importer for custom pairs
        $colmapArgs = @(
            "matches_importer",
            "--database_path", $DatabasePath,
            "--match_list_path", $MatchPairsPath,
            "--match_type", "pairs"
        )

        # Add SIFT matching options from config (skip non-SIFT properties)
        foreach ($prop in $matcherConfig.PSObject.Properties) {
            if ($prop.Name -in @("type", "temporal_overlap", "cross_camera_same_timestamp")) { continue }
            $colmapArgs += "--$($prop.Name)=$($prop.Value)"
        }

        Write-Host "  Using custom pairs from: $MatchPairsPath" -ForegroundColor Yellow
        Write-Host "Running: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

        & $colmapBin $colmapArgs
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host "ERROR: matches_importer failed with exit code: $exitCode" -ForegroundColor Red
            return $false
        }
    }
    else {
        # Standard exhaustive or sequential matcher
        $matcherCommand = "${MatcherType}_matcher"
        $colmapArgs = @(
            $matcherCommand,
            "--database_path", $DatabasePath
        )

        # Add matcher options from config (skip 'type' property, use --Option=value format)
        foreach ($prop in $matcherConfig.PSObject.Properties) {
            if ($prop.Name -in @("type", "temporal_overlap", "cross_camera_same_timestamp")) { continue }
            $colmapArgs += "--$($prop.Name)=$($prop.Value)"
        }

        Write-Host "Running: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

        & $colmapBin $colmapArgs
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host "ERROR: Feature matching failed with exit code: $exitCode" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "Feature matching completed successfully" -ForegroundColor Green
    return $true
}

function Run-ColmapMapper {
    <#
    .SYNOPSIS
    Run COLMAP sparse reconstruction (mapper)

    .PARAMETER ColmapExe
    Path to COLMAP executable or batch file

    .PARAMETER DatabasePath
    Path to COLMAP database file

    .PARAMETER ImagePath
    Path to images directory

    .PARAMETER OutputPath
    Path to output sparse reconstruction

    .PARAMETER Config
    Configuration object with mapper settings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ColmapExe,

        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,

        [Parameter(Mandatory=$true)]
        [string]$ImagePath,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    Write-Host ""
    Write-Host "=== COLMAP Mapper (Sparse Reconstruction) ===" -ForegroundColor Cyan

    # Set up COLMAP environment
    $colmapDir = if ($ColmapExe -like "*.bat") {
        Split-Path -Parent $ColmapExe
    } else {
        Split-Path -Parent (Split-Path -Parent $ColmapExe)
    }
    Setup-ColmapEnvironment -ColmapPath $colmapDir

    # Get the actual colmap.exe path
    $colmapBin = if ($ColmapExe -like "*.bat") {
        Join-Path $colmapDir "bin\colmap.exe"
    } else {
        $ColmapExe
    }

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $mapperConfig = $Config.colmap.mapper

    $colmapArgs = @(
        "mapper",
        "--database_path", $DatabasePath,
        "--image_path", $ImagePath,
        "--output_path", $OutputPath
    )

    # Add mapper options from config (use --Option=value format)
    foreach ($prop in $mapperConfig.PSObject.Properties) {
        $colmapArgs += "--$($prop.Name)=$($prop.Value)"
    }

    Write-Host "Running: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

    & $colmapBin $colmapArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "ERROR: Mapper failed with exit code: $exitCode" -ForegroundColor Red
        return $false
    }

    # Check if reconstruction was successful (sparse/0 should exist)
    $sparseDir = Join-Path $OutputPath "0"
    if (-not (Test-Path $sparseDir)) {
        Write-Host "ERROR: No reconstruction created (sparse/0 not found)" -ForegroundColor Red
        return $false
    }

    # Verify required files exist
    $requiredFiles = @("cameras.bin", "images.bin", "points3D.bin")
    $allFilesExist = $true

    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $sparseDir $file
        if (-not (Test-Path $filePath)) {
            Write-Host "ERROR: Required file not found: $file" -ForegroundColor Red
            $allFilesExist = $false
        }
    }

    if (-not $allFilesExist) {
        return $false
    }

    Write-Host "Sparse reconstruction completed successfully" -ForegroundColor Green
    return $true
}

function Run-ColmapPipeline {
    <#
    .SYNOPSIS
    Run the complete COLMAP pipeline: feature extraction, matching, and mapping

    .PARAMETER ImageDir
    Path to directory containing images

    .PARAMETER OutputDir
    Path to output directory for COLMAP results

    .PARAMETER Config
    Configuration object

    .PARAMETER MatcherType
    Type of matcher to use

    .PARAMETER MatchPairsPath
    Path to match_pairs.txt file (required for custom_pairs matcher)

    .OUTPUTS
    Returns the sparse reconstruction path on success, $null on failure
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImageDir,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [ValidateSet("exhaustive", "sequential", "custom_pairs")]
        [string]$MatcherType = "exhaustive",

        [Parameter(Mandatory=$false)]
        [string]$MatchPairsPath
    )

    $colmapExe = $Config.paths.colmap_exe

    # Validate COLMAP exists
    if (-not (Test-Path $colmapExe)) {
        Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
        return $null
    }

    # Validate image directory
    if (-not (Test-Path $ImageDir)) {
        Write-Host "ERROR: Image directory not found: $ImageDir" -ForegroundColor Red
        return $null
    }

    # Count images
    $imageCount = (Get-ChildItem -Path $ImageDir -Recurse -Include @("*.jpg", "*.jpeg", "*.png", "*.JPG", "*.JPEG", "*.PNG")).Count
    if ($imageCount -eq 0) {
        Write-Host "ERROR: No images found in: $ImageDir" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  COLMAP Processing Pipeline" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  Image directory: $ImageDir" -ForegroundColor Cyan
    Write-Host "  Image count: $imageCount" -ForegroundColor Cyan
    Write-Host "  Output directory: $OutputDir" -ForegroundColor Cyan
    Write-Host "  Matcher type: $MatcherType" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor White

    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $databasePath = Join-Path $OutputDir "database.db"
    $sparsePath = Join-Path $OutputDir "sparse"

    # Remove existing database if present
    if (Test-Path $databasePath) {
        Write-Host "Removing existing database: $databasePath" -ForegroundColor Yellow
        Remove-Item $databasePath -Force
    }

    # Step 1: Feature Extraction
    $result = Run-ColmapFeatureExtraction -ColmapExe $colmapExe -DatabasePath $databasePath -ImagePath $ImageDir -Config $Config
    if (-not $result) {
        return $null
    }

    # Step 2: Feature Matching
    $matchingParams = @{
        ColmapExe = $colmapExe
        DatabasePath = $databasePath
        MatcherType = $MatcherType
        Config = $Config
    }
    if ($MatchPairsPath) {
        $matchingParams.MatchPairsPath = $MatchPairsPath
    }
    $result = Run-ColmapMatching @matchingParams
    if (-not $result) {
        return $null
    }

    # Step 3: Mapper (Sparse Reconstruction)
    $result = Run-ColmapMapper -ColmapExe $colmapExe -DatabasePath $databasePath -ImagePath $ImageDir -OutputPath $sparsePath -Config $Config
    if (-not $result) {
        return $null
    }

    $sparseResultPath = Join-Path $sparsePath "0"
    Write-Host ""
    Write-Host "COLMAP pipeline completed successfully!" -ForegroundColor Green
    Write-Host "Sparse reconstruction: $sparseResultPath" -ForegroundColor Green

    return $sparseResultPath
}

function Get-ColmapStats {
    <#
    .SYNOPSIS
    Get statistics from a COLMAP sparse reconstruction

    .PARAMETER SparsePath
    Path to sparse reconstruction directory (containing cameras.bin, images.bin, points3D.bin)

    .PARAMETER ColmapExe
    Path to COLMAP executable or batch file

    .OUTPUTS
    PSCustomObject with reconstruction statistics
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SparsePath,

        [Parameter(Mandatory=$true)]
        [string]$ColmapExe
    )

    Write-Host ""
    Write-Host "=== COLMAP Reconstruction Statistics ===" -ForegroundColor Cyan

    # Set up COLMAP environment
    $colmapDir = if ($ColmapExe -like "*.bat") {
        Split-Path -Parent $ColmapExe
    } else {
        Split-Path -Parent (Split-Path -Parent $ColmapExe)
    }
    Setup-ColmapEnvironment -ColmapPath $colmapDir

    # Get the actual colmap.exe path
    $colmapBin = if ($ColmapExe -like "*.bat") {
        Join-Path $colmapDir "bin\colmap.exe"
    } else {
        $ColmapExe
    }

    # Run model_analyzer to get stats
    $colmapArgs = @(
        "model_analyzer",
        "--path", $SparsePath
    )

    try {
        $output = & $colmapBin $colmapArgs 2>&1
        Write-Host $output -ForegroundColor DarkGray

        # Parse basic stats from output
        $stats = [PSCustomObject]@{
            Path = $SparsePath
            Valid = $true
        }

        return $stats
    }
    catch {
        Write-Host "WARNING: Could not analyze model: $_" -ForegroundColor Yellow
        return $null
    }
}

# Main execution when script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    # Load config if not provided via script params
    if (-not $_ScriptConfig) {
        $_ScriptConfig = Load-Config
    }

    $pipelineParams = @{
        ImageDir = $_ScriptImageDir
        OutputDir = $_ScriptOutputDir
        Config = $_ScriptConfig
        MatcherType = $_ScriptMatcherType
    }
    if ($_ScriptMatchPairsPath) {
        $pipelineParams.MatchPairsPath = $_ScriptMatchPairsPath
    }
    $result = Run-ColmapPipeline @pipelineParams
    if ($result) {
        Write-Host "COLMAP processing completed successfully" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "COLMAP processing failed" -ForegroundColor Red
        exit 1
    }
}

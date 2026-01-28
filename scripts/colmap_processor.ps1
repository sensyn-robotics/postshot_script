# colmap_processor.ps1
# COLMAP SfM pipeline for sparse reconstruction

param(
    [Parameter(Mandatory=$true)]
    [string]$ImageDir,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [PSCustomObject]$Config,

    [Parameter(Mandatory=$false)]
    [ValidateSet("exhaustive", "sequential")]
    [string]$MatcherType = "exhaustive"
)

# Import config loader
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")

# Load config if not provided
if (-not $Config) {
    $Config = Load-Config
}

function Run-ColmapFeatureExtraction {
    <#
    .SYNOPSIS
    Run COLMAP feature extraction

    .PARAMETER ColmapExe
    Path to COLMAP executable

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

    $featureConfig = $Config.colmap.feature_extractor

    $args = @(
        "feature_extractor",
        "--database_path", $DatabasePath,
        "--image_path", $ImagePath
    )

    # Add feature extractor options from config
    foreach ($prop in $featureConfig.PSObject.Properties) {
        $args += "--$($prop.Name)"
        $args += "$($prop.Value)"
    }

    Write-Host "Running: colmap $($args -join ' ')" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $ColmapExe -ArgumentList $args -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: Feature extraction failed with exit code: $($process.ExitCode)" -ForegroundColor Red
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
    Path to COLMAP executable

    .PARAMETER DatabasePath
    Path to COLMAP database file

    .PARAMETER MatcherType
    Type of matcher: "exhaustive" or "sequential"

    .PARAMETER Config
    Configuration object with matcher settings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ColmapExe,

        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("exhaustive", "sequential")]
        [string]$MatcherType,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    Write-Host ""
    Write-Host "=== COLMAP Feature Matching ($MatcherType) ===" -ForegroundColor Cyan

    $matcherConfig = $Config.colmap.matcher

    $matcherCommand = "${MatcherType}_matcher"
    $args = @(
        $matcherCommand,
        "--database_path", $DatabasePath
    )

    # Add matcher options from config (skip 'type' property)
    foreach ($prop in $matcherConfig.PSObject.Properties) {
        if ($prop.Name -eq "type") { continue }
        $args += "--$($prop.Name)"
        $args += "$($prop.Value)"
    }

    Write-Host "Running: colmap $($args -join ' ')" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $ColmapExe -ArgumentList $args -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: Feature matching failed with exit code: $($process.ExitCode)" -ForegroundColor Red
        return $false
    }

    Write-Host "Feature matching completed successfully" -ForegroundColor Green
    return $true
}

function Run-ColmapMapper {
    <#
    .SYNOPSIS
    Run COLMAP sparse reconstruction (mapper)

    .PARAMETER ColmapExe
    Path to COLMAP executable

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

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $mapperConfig = $Config.colmap.mapper

    $args = @(
        "mapper",
        "--database_path", $DatabasePath,
        "--image_path", $ImagePath,
        "--output_path", $OutputPath
    )

    # Add mapper options from config
    foreach ($prop in $mapperConfig.PSObject.Properties) {
        $args += "--$($prop.Name)"
        $args += "$($prop.Value)"
    }

    Write-Host "Running: colmap $($args -join ' ')" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $ColmapExe -ArgumentList $args -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: Mapper failed with exit code: $($process.ExitCode)" -ForegroundColor Red
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
        [ValidateSet("exhaustive", "sequential")]
        [string]$MatcherType = "exhaustive"
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
    $result = Run-ColmapMatching -ColmapExe $colmapExe -DatabasePath $databasePath -MatcherType $MatcherType -Config $Config
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
    Path to COLMAP executable

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

    # Run model_analyzer to get stats
    $args = @(
        "model_analyzer",
        "--path", $SparsePath
    )

    try {
        $output = & $ColmapExe $args 2>&1
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
    $result = Run-ColmapPipeline -ImageDir $ImageDir -OutputDir $OutputDir -Config $Config -MatcherType $MatcherType
    if ($result) {
        Write-Host "COLMAP processing completed successfully" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "COLMAP processing failed" -ForegroundColor Red
        exit 1
    }
}

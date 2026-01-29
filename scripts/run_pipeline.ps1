# run_pipeline.ps1
# Main entry point for COLMAP + Postshot pipeline
# Supports video files, image folders, and existing COLMAP projects

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("exhaustive", "sequential")]
    [string]$MatcherType = "exhaustive"
)

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

# Import modules
. (Join-Path $rootDir "lib\config_loader.ps1")
. (Join-Path $scriptDir "video_extractor.ps1")
. (Join-Path $scriptDir "colmap_processor.ps1")
. (Join-Path $scriptDir "postshot_runner.ps1")

# Stop on errors
$ErrorActionPreference = 'Stop'

function Detect-InputType {
    <#
    .SYNOPSIS
    Detect the type of input provided

    .PARAMETER InputPath
    Path to input file or directory

    .OUTPUTS
    String: "video_file", "video_folder", "image_folder", "colmap_project", or "unknown"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath
    )

    if (-not (Test-Path $InputPath)) {
        return "not_found"
    }

    # Check if it's a file
    if (Test-Path $InputPath -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($InputPath).ToLower()
        if ($ext -in @(".mp4", ".mov", ".avi", ".mkv")) {
            return "video_file"
        }
        return "unknown_file"
    }

    # It's a directory - check contents
    $hasVideos = (Get-ChildItem -Path $InputPath -File | Where-Object {
        $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV", ".avi", ".AVI", ".mkv", ".MKV")
    }).Count -gt 0

    $hasImages = (Get-ChildItem -Path $InputPath -File | Where-Object {
        $_.Extension -in @(".jpg", ".JPG", ".jpeg", ".JPEG", ".png", ".PNG")
    }).Count -gt 0

    $hasImageSubfolders = (Get-ChildItem -Path $InputPath -Directory | Where-Object {
        (Get-ChildItem -Path $_.FullName -File | Where-Object {
            $_.Extension -in @(".jpg", ".JPG", ".jpeg", ".JPEG", ".png", ".PNG")
        }).Count -gt 0
    }).Count -gt 0

    # Check for existing COLMAP project
    $sparseDir = Join-Path $InputPath "sparse"
    $imagesDir = Join-Path $InputPath "images"
    $colmapOutputDir = Join-Path $InputPath "colmap_output"

    if ((Test-Path $sparseDir) -and (Test-Path $imagesDir)) {
        return "colmap_project"
    }

    if ((Test-Path $colmapOutputDir) -and (Test-Path $imagesDir)) {
        return "colmap_project"
    }

    if ($hasVideos) {
        return "video_folder"
    }

    if ($hasImages -or $hasImageSubfolders) {
        return "image_folder"
    }

    return "unknown"
}

function Get-ProjectPaths {
    <#
    .SYNOPSIS
    Generate standard paths for a project

    .PARAMETER BasePath
    Base directory for the project

    .OUTPUTS
    PSCustomObject with all project paths
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BasePath
    )

    return [PSCustomObject]@{
        Base = $BasePath
        Images = Join-Path $BasePath "images"
        ColmapOutput = Join-Path $BasePath "colmap_output"
        Sparse = Join-Path $BasePath "colmap_output\sparse\0"
        Psht = Join-Path $BasePath "scene.psht"
        Ply = Join-Path $BasePath "scene.ply"
    }
}

function Run-FullPipeline {
    <#
    .SYNOPSIS
    Run the complete pipeline: video extraction -> COLMAP -> Postshot

    .PARAMETER InputPath
    Path to input

    .PARAMETER Config
    Configuration object

    .PARAMETER MatcherType
    COLMAP matcher type

    .OUTPUTS
    PSCustomObject with results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [string]$MatcherType = "exhaustive"
    )

    $result = [PSCustomObject]@{
        Success = $false
        InputType = $null
        ProjectPath = $null
        ImagesPath = $null
        ColmapPath = $null
        PshtPath = $null
        PlyPath = $null
        Errors = @()
    }

    # Detect input type
    $inputType = Detect-InputType -InputPath $InputPath
    $result.InputType = $inputType

    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  COLMAP + Postshot Pipeline" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  Input: $InputPath" -ForegroundColor Cyan
    Write-Host "  Input Type: $inputType" -ForegroundColor Cyan
    Write-Host "  Matcher: $MatcherType" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor White

    # Handle different input types
    switch ($inputType) {
        "not_found" {
            $result.Errors += "Input path not found: $InputPath"
            Write-Host "ERROR: Input path not found" -ForegroundColor Red
            return $result
        }

        "video_file" {
            # Single video file - use parent directory as project
            $projectDir = Split-Path -Parent $InputPath
            $paths = Get-ProjectPaths -BasePath $projectDir
            $result.ProjectPath = $projectDir

            Write-Host "`n--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow

            # Create images folder
            $videoName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
            $outputDir = Join-Path $paths.Images $videoName

            $extractResult = Extract-VideoFrames -VideoPath $InputPath -OutputDir $outputDir -Config $Config
            if (-not $extractResult) {
                $result.Errors += "Video extraction failed"
                return $result
            }
            $result.ImagesPath = $paths.Images
        }

        "video_folder" {
            # Folder with video files
            $paths = Get-ProjectPaths -BasePath $InputPath
            $result.ProjectPath = $InputPath

            Write-Host "`n--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow

            $extractedDirs = Extract-AllVideosInFolder -FolderPath $InputPath -OutputBaseDir $paths.Images -Config $Config
            if ($extractedDirs.Count -eq 0) {
                $result.Errors += "No frames extracted from videos"
                return $result
            }
            $result.ImagesPath = $paths.Images
        }

        "image_folder" {
            # Folder with images
            $paths = Get-ProjectPaths -BasePath $InputPath
            $result.ProjectPath = $InputPath

            # Check if images are in root or in subfolders
            $rootImages = (Get-ChildItem -Path $InputPath -File | Where-Object {
                $_.Extension -in @(".jpg", ".JPG", ".jpeg", ".JPEG", ".png", ".PNG")
            }).Count

            if ($rootImages -gt 0) {
                # Images in root - move to images/ subfolder
                Write-Host "Images found in root directory, will use directly" -ForegroundColor Cyan
                $result.ImagesPath = $InputPath
                $paths.Images = $InputPath
            }
            else {
                # Images in subfolders
                $result.ImagesPath = $InputPath
                $paths.Images = $InputPath
            }

            Write-Host "--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow
            Write-Host "  Skipped (images already present)" -ForegroundColor Gray
        }

        "colmap_project" {
            # Existing COLMAP project - skip to Postshot
            $paths = Get-ProjectPaths -BasePath $InputPath
            $result.ProjectPath = $InputPath

            # Check if it's colmap_output structure or sparse structure
            $colmapOutputSparse = Join-Path $InputPath "colmap_output\sparse\0"
            $directSparse = Join-Path $InputPath "sparse\0"

            if (Test-Path $colmapOutputSparse) {
                $paths.Sparse = $colmapOutputSparse
            }
            elseif (Test-Path $directSparse) {
                $paths.Sparse = $directSparse
            }

            Write-Host "--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow
            Write-Host "  Skipped (COLMAP project detected)" -ForegroundColor Gray

            Write-Host "`n--- Stage 2: COLMAP Processing ---" -ForegroundColor Yellow
            Write-Host "  Skipped (existing COLMAP project)" -ForegroundColor Gray

            $result.ImagesPath = Join-Path $InputPath "images"
            $result.ColmapPath = $paths.Sparse
        }

        default {
            $result.Errors += "Unknown input type: $inputType"
            Write-Host "ERROR: Cannot determine input type" -ForegroundColor Red
            return $result
        }
    }

    # Stage 2: COLMAP Processing (skip if already a COLMAP project)
    if ($inputType -ne "colmap_project") {
        Write-Host "`n--- Stage 2: COLMAP Processing ---" -ForegroundColor Yellow

        $colmapResult = Run-ColmapPipeline -ImageDir $paths.Images -OutputDir $paths.ColmapOutput -Config $Config -MatcherType $MatcherType
        if (-not $colmapResult) {
            $result.Errors += "COLMAP processing failed"
            return $result
        }
        $result.ColmapPath = $colmapResult
        $paths.Sparse = $colmapResult
    }

    # Stage 3: Postshot Training
    Write-Host "`n--- Stage 3: Postshot Training ---" -ForegroundColor Yellow

    # For Postshot, input is images folder, and we pass COLMAP sparse for camera poses and point initialization
    $postshotInput = $paths.Images
    $colmapSparse = $paths.Sparse

    Write-Host "  Images: $postshotInput" -ForegroundColor Cyan
    Write-Host "  COLMAP sparse: $colmapSparse" -ForegroundColor Cyan

    $postshotResult = Run-PostshotPipeline -InputPath $postshotInput -OutputPath $paths.Psht -Config $Config -ExportPly $Config.postshot.export_ply -ColmapSparsePath $colmapSparse
    if (-not $postshotResult.Success) {
        $result.Errors += "Postshot training failed"
        return $result
    }

    $result.PshtPath = $postshotResult.PshtPath
    $result.PlyPath = $postshotResult.PlyPath
    $result.Success = $true

    return $result
}

# --- MAIN EXECUTION ---

Write-Host ""
Write-Host "########################################" -ForegroundColor Magenta
Write-Host "#  Postshot Script - Pipeline Runner  #" -ForegroundColor Magenta
Write-Host "########################################" -ForegroundColor Magenta

# Load configuration
$Config = Load-Config -CustomConfigPath $ConfigPath

# Validate configuration
Write-Host "`nValidating configuration..." -ForegroundColor Cyan
$configValid = Validate-Config -Config $Config

if (-not $configValid) {
    Write-Host "`nWARNING: Some required tools are missing. Pipeline may fail." -ForegroundColor Yellow
    Write-Host "Press Enter to continue anyway, or Ctrl+C to abort..." -ForegroundColor Yellow
    Read-Host
}

# Run the pipeline
$startTime = Get-Date
$result = Run-FullPipeline -InputPath $InputPath -Config $Config -MatcherType $MatcherType
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
    foreach ($error in $result.Errors) {
        Write-Host "    - $error" -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor White

if ($result.Success) {
    exit 0
}
else {
    exit 1
}

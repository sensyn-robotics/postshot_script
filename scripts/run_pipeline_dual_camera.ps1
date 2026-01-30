# run_pipeline_dual_camera.ps1
# Pipeline for dual-camera systems (e.g., DJI H30T with Wide + Zoom)
# where both cameras capture from the SAME POSITION simultaneously.
#
# Strategy:
#   1. Run COLMAP on video_W (wide) images only - easier to match
#   2. Copy camera POSES from W to Z images (same position, different intrinsics)
#   3. Create merged COLMAP model with both W and Z images
#   4. Run Postshot on merged model for unified 3DGS
#
# Usage:
#   .\run_pipeline_dual_camera.ps1 -InputPath "C:\data\scene1"
#
# Expected input structure:
#   scene1/
#   ├── DJI_xxx_W.MP4  (Wide camera video)
#   └── DJI_xxx_Z.MP4  (Zoom camera video)
#
# Output structure:
#   scene1/output/
#   ├── images/
#   │   ├── video_W/  (extracted frames from Wide)
#   │   └── video_Z/  (extracted frames from Zoom)
#   ├── colmap_output/
#   │   ├── sparse_W/0/      (COLMAP result from W only)
#   │   └── sparse_merged/0/ (merged model with W+Z)
#   ├── scene.psht
#   └── scene.ply

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("exhaustive", "sequential")]
    [string]$MatcherType = "sequential"  # Sequential is better for video
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
        SparseW = Join-Path $outputDir "colmap_output\sparse_W"
        SparseMerged = Join-Path $outputDir "colmap_output\sparse_merged"
        Psht = Join-Path $outputDir "scene.psht"
        Ply = Join-Path $outputDir "scene.ply"
    }
}

function Merge-DualCameraModel {
    <#
    .SYNOPSIS
    Merge Z images into W COLMAP model, sharing camera positions

    .DESCRIPTION
    Takes COLMAP sparse reconstruction from W images and creates a merged model
    that includes Z images. Z images get the same camera POSITIONS as their
    corresponding W images (by frame number), but with different camera INTRINSICS.

    .PARAMETER SparseWPath
    Path to COLMAP sparse reconstruction from W images (contains cameras.bin, images.bin, points3D.bin)

    .PARAMETER SparseMergedPath
    Path to output merged model

    .PARAMETER ImagesWPath
    Path to W images folder

    .PARAMETER ImagesZPath
    Path to Z images folder

    .PARAMETER ColmapExe
    Path to COLMAP executable
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SparseWPath,

        [Parameter(Mandatory=$true)]
        [string]$SparseMergedPath,

        [Parameter(Mandatory=$true)]
        [string]$ImagesWPath,

        [Parameter(Mandatory=$true)]
        [string]$ImagesZPath,

        [Parameter(Mandatory=$true)]
        [string]$ColmapExe
    )

    Write-Host ""
    Write-Host "=== Merging Dual-Camera Model ===" -ForegroundColor Cyan
    Write-Host "  W sparse: $SparseWPath" -ForegroundColor Gray
    Write-Host "  Output: $SparseMergedPath" -ForegroundColor Gray

    # Create output directory
    if (-not (Test-Path $SparseMergedPath)) {
        New-Item -ItemType Directory -Path $SparseMergedPath -Force | Out-Null
    }

    # Get COLMAP binary path
    $colmapDir = if ($ColmapExe -like "*.bat") {
        Split-Path -Parent $ColmapExe
    } else {
        Split-Path -Parent (Split-Path -Parent $ColmapExe)
    }
    Setup-ColmapEnvironment -ColmapPath $colmapDir

    $colmapBin = if ($ColmapExe -like "*.bat") {
        Join-Path $colmapDir "bin\colmap.exe"
    } else {
        $ColmapExe
    }

    # First, export W model to text format for easier manipulation
    $textModelPath = Join-Path (Split-Path -Parent $SparseMergedPath) "text_model"
    if (Test-Path $textModelPath) {
        Remove-Item $textModelPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $textModelPath -Force | Out-Null

    Write-Host "  Exporting W model to text format..." -ForegroundColor Gray
    & $colmapBin model_converter `
        --input_path $SparseWPath `
        --output_path $textModelPath `
        --output_type TXT

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to export model to text" -ForegroundColor Red
        return $false
    }

    # Read cameras.txt
    $camerasFile = Join-Path $textModelPath "cameras.txt"
    $imagesFile = Join-Path $textModelPath "images.txt"
    $points3DFile = Join-Path $textModelPath "points3D.txt"

    # Read files (handle CRLF line endings)
    $camerasContent = [System.IO.File]::ReadAllText($camerasFile)
    $imagesContent = [System.IO.File]::ReadAllLines($imagesFile)
    $points3DContent = [System.IO.File]::ReadAllText($points3DFile)

    # Parse existing camera (camera 1 = W)
    # Format: CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]
    $cameraLines = @($camerasContent -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })

    if ($cameraLines.Count -eq 0) {
        Write-Host "ERROR: No camera found in W model" -ForegroundColor Red
        return $false
    }

    # Get W camera info
    $wCameraLine = [string]$cameraLines[0]
    $wCameraParts = @($wCameraLine -split "\s+" | Where-Object { $_ })
    $wCameraId = $wCameraParts[0]
    $wCameraModel = $wCameraParts[1]
    $wWidth = $wCameraParts[2]
    $wHeight = $wCameraParts[3]

    Write-Host "  W Camera: ID=$wCameraId, Model=$wCameraModel, ${wWidth}x${wHeight}" -ForegroundColor Gray

    # Get Z images and estimate focal length
    # Z camera typically has longer focal length (more zoomed in)
    $zImages = Get-ChildItem $ImagesZPath -Filter "*.png" | Sort-Object Name
    $wImages = Get-ChildItem $ImagesWPath -Filter "*.png" | Sort-Object Name

    if ($zImages.Count -eq 0) {
        $zImages = Get-ChildItem $ImagesZPath -Filter "*.jpg" | Sort-Object Name
        $wImages = Get-ChildItem $ImagesWPath -Filter "*.jpg" | Sort-Object Name
    }

    Write-Host "  W images: $($wImages.Count), Z images: $($zImages.Count)" -ForegroundColor Gray

    # Create Z camera entry (camera 2)
    # Estimate Z focal length - typically 3-7x zoom, let's use the same and let Postshot refine
    # Or we could try to estimate from metadata, but for now use same as W
    # The key is the POSES are shared, intrinsics can be refined by Postshot
    $zCameraId = 2
    $zCameraLine = "$zCameraId $wCameraModel $wWidth $wHeight " + ($wCameraParts[4..($wCameraParts.Length-1)] -join " ")

    Write-Host "  Z Camera: ID=$zCameraId (same intrinsics initially, Postshot will refine)" -ForegroundColor Gray

    # Parse W images to get their poses
    # Format: IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME
    #         POINTS2D[] as (X, Y, POINT3D_ID)
    $imageLines = @($imagesContent | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })

    # Build mapping of W frame names to their poses
    $wPoses = @{}
    for ($i = 0; $i -lt $imageLines.Count; $i += 2) {
        $imageLine = [string]$imageLines[$i]
        if ($imageLine -match "^\d+") {
            $parts = @($imageLine -split "\s+" | Where-Object { $_ })
            $imageId = $parts[0]
            $qw = $parts[1]
            $qx = $parts[2]
            $qy = $parts[3]
            $qz = $parts[4]
            $tx = $parts[5]
            $ty = $parts[6]
            $tz = $parts[7]
            $cameraId = $parts[8]
            $imageName = $parts[9]

            # Extract frame number from name (e.g., video_W/frame_00001.png -> 00001)
            if ($imageName -match "frame_(\d+)") {
                $frameNum = $matches[1]
                $wPoses[$frameNum] = @{
                    QW = $qw; QX = $qx; QY = $qy; QZ = $qz
                    TX = $tx; TY = $ty; TZ = $tz
                    Points2D = $imageLines[$i + 1]
                }
            }
        }
    }

    Write-Host "  Parsed $($wPoses.Count) W image poses" -ForegroundColor Gray

    # Create new images.txt with both W and Z images
    $newImagesContent = @()
    $newImagesContent += "# Image list with two lines of data per image:"
    $newImagesContent += "#   IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME"
    $newImagesContent += "#   POINTS2D[] as (X, Y, POINT3D_ID)"

    $nextImageId = 1

    # Add W images (keep original)
    for ($i = 0; $i -lt $imageLines.Count; $i += 2) {
        $imageLine = [string]$imageLines[$i]
        if ($imageLine -match "^\d+") {
            $parts = @($imageLine -split "\s+" | Where-Object { $_ })
            # Update image ID to be sequential
            $parts[0] = $nextImageId.ToString()
            $newImagesContent += ($parts -join " ")
            $newImagesContent += $imageLines[$i + 1]
            $nextImageId++
        }
    }

    # Add Z images with same poses as corresponding W frames
    $zAddedCount = 0
    foreach ($zImage in $zImages) {
        if ($zImage.Name -match "frame_(\d+)") {
            $frameNum = $matches[1]
            if ($wPoses.ContainsKey($frameNum)) {
                $pose = $wPoses[$frameNum]
                $zImageName = "video_Z/$($zImage.Name)"

                # Z image with same pose but camera 2
                $newImagesContent += "$nextImageId $($pose.QW) $($pose.QX) $($pose.QY) $($pose.QZ) $($pose.TX) $($pose.TY) $($pose.TZ) $zCameraId $zImageName"
                # Empty points2D for Z images (no 3D points associated yet)
                $newImagesContent += ""

                $nextImageId++
                $zAddedCount++
            }
        }
    }

    Write-Host "  Added $zAddedCount Z images with shared poses" -ForegroundColor Gray

    # Write new cameras.txt
    $newCamerasContent = @()
    $newCamerasContent += "# Camera list with one line of data per camera:"
    $newCamerasContent += "#   CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]"
    $newCamerasContent += $wCameraLine
    $newCamerasContent += $zCameraLine

    # Write merged model files
    $mergedTextPath = Join-Path (Split-Path -Parent $SparseMergedPath) "text_merged"
    if (Test-Path $mergedTextPath) {
        Remove-Item $mergedTextPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $mergedTextPath -Force | Out-Null

    Set-Content -Path (Join-Path $mergedTextPath "cameras.txt") -Value ($newCamerasContent -join "`n")
    Set-Content -Path (Join-Path $mergedTextPath "images.txt") -Value ($newImagesContent -join "`n")
    Copy-Item $points3DFile -Destination (Join-Path $mergedTextPath "points3D.txt")

    # Convert merged text model back to binary
    Write-Host "  Converting merged model to binary format..." -ForegroundColor Gray
    & $colmapBin model_converter `
        --input_path $mergedTextPath `
        --output_path $SparseMergedPath `
        --output_type BIN

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to convert merged model to binary" -ForegroundColor Red
        return $false
    }

    Write-Host "Dual-camera model merged successfully!" -ForegroundColor Green
    Write-Host "  Total images: $($nextImageId - 1) (W: $($wPoses.Count), Z: $zAddedCount)" -ForegroundColor Green

    return $true
}

function Run-DualCameraPipeline {
    <#
    .SYNOPSIS
    Run the complete dual-camera pipeline
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [string]$MatcherType = "sequential"
    )

    $result = [PSCustomObject]@{
        Success = $false
        PshtPath = $null
        PlyPath = $null
        Errors = @()
    }

    Write-Host ""
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host "#  Dual-Camera Pipeline (W+Z Merge)   #" -ForegroundColor Magenta
    Write-Host "########################################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Strategy:" -ForegroundColor Cyan
    Write-Host "  1. Extract frames from W and Z videos" -ForegroundColor Gray
    Write-Host "  2. Run COLMAP on W images only (easier matching)" -ForegroundColor Gray
    Write-Host "  3. Merge Z images using W camera poses" -ForegroundColor Gray
    Write-Host "  4. Run Postshot on merged model" -ForegroundColor Gray
    Write-Host ""

    $paths = Get-DualCameraProjectPaths -BasePath $InputPath

    # === Stage 1: Frame Extraction ===
    Write-Host "--- Stage 1: Frame Extraction ---" -ForegroundColor Yellow

    # Find W and Z videos
    $videos = Get-ChildItem -Path $InputPath -File | Where-Object {
        $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV", ".avi", ".AVI")
    }

    $wVideos = $videos | Where-Object { $_.Name -match "_W\." }
    $zVideos = $videos | Where-Object { $_.Name -match "_Z\." }

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

    # === Stage 2: COLMAP on W only ===
    Write-Host ""
    Write-Host "--- Stage 2: COLMAP on Wide Images Only ---" -ForegroundColor Yellow

    # Create sparse_W output directory
    if (-not (Test-Path $paths.SparseW)) {
        New-Item -ItemType Directory -Path $paths.SparseW -Force | Out-Null
    }

    # Run COLMAP pipeline on W images only
    $colmapResult = Run-ColmapPipeline `
        -ImageDir $paths.ImagesW `
        -OutputDir (Split-Path -Parent $paths.SparseW) `
        -Config $Config `
        -MatcherType $MatcherType

    if (-not $colmapResult) {
        $result.Errors += "COLMAP processing failed on W images"
        return $result
    }

    # The sparse output is in sparse/0, move to sparse_W/0
    $sparseDefault = Join-Path (Split-Path -Parent $paths.SparseW) "sparse\0"
    if (Test-Path $sparseDefault) {
        if (-not (Test-Path "$($paths.SparseW)\0")) {
            New-Item -ItemType Directory -Path "$($paths.SparseW)\0" -Force | Out-Null
        }
        Copy-Item "$sparseDefault\*" -Destination "$($paths.SparseW)\0" -Force
    }

    # === Stage 3: Merge W+Z Model ===
    Write-Host ""
    Write-Host "--- Stage 3: Merging W and Z Images ---" -ForegroundColor Yellow

    $mergeResult = Merge-DualCameraModel `
        -SparseWPath "$($paths.SparseW)\0" `
        -SparseMergedPath "$($paths.SparseMerged)\0" `
        -ImagesWPath $paths.ImagesW `
        -ImagesZPath $paths.ImagesZ `
        -ColmapExe $Config.paths.colmap_exe

    if (-not $mergeResult) {
        $result.Errors += "Failed to merge dual-camera model"
        return $result
    }

    # === Stage 4: Postshot Training ===
    Write-Host ""
    Write-Host "--- Stage 4: Postshot Training ---" -ForegroundColor Yellow
    Write-Host "  Images: $($paths.Images)" -ForegroundColor Cyan
    Write-Host "  COLMAP merged: $($paths.SparseMerged)\0" -ForegroundColor Cyan

    $postshotResult = Run-PostshotPipeline `
        -InputPath $paths.Images `
        -OutputPath $paths.Psht `
        -Config $Config `
        -ExportPly $Config.postshot.export_ply `
        -ColmapSparsePath "$($paths.SparseMerged)\0"

    if (-not $postshotResult.Success) {
        $result.Errors += "Postshot training failed"
        return $result
    }

    $result.PshtPath = $postshotResult.PshtPath
    $result.PlyPath = $postshotResult.PlyPath
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
$result = Run-DualCameraPipeline -InputPath $InputPath -Config $Config -MatcherType $MatcherType
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

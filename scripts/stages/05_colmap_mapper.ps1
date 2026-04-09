# 05_colmap_mapper.ps1
# Stage 5: COLMAP sparse reconstruction (mapper)
#
# Input: output/colmap/database.db + output/images/
# Output: output/colmap/sparse/0/ (binary) + output/colmap/sparse/0/points3D.ply

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [int]$MinModelSizeOverride = 0,

    [Parameter(Mandatory=$false)]
    [int]$InitMinNumInliersOverride = 0,

    [Parameter(Mandatory=$false)]
    [int]$AbsPoseMinNumInliersOverride = 0,

    [Parameter(Mandatory=$false)]
    [double]$AbsPoseMinInlierRatioOverride = 0
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
$imagesDir = Join-Path $outputDir $config.output.images_subdir
$colmapDir = Join-Path $outputDir $config.output.colmap_subdir
$databasePath = Join-Path $colmapDir "database.db"
$sparseDir = Join-Path $colmapDir "sparse"
$vizDir = Join-Path $outputDir $config.output.visualizations_subdir
$colmapExe = $config.paths.colmap

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 5: COLMAP Mapper" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Database: $databasePath" -ForegroundColor White
Write-Host "  Images: $imagesDir" -ForegroundColor White
Write-Host "  Output: $sparseDir" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate COLMAP
if (-not (Test-Path -LiteralPath $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
    exit 1
}

# Validate database
if (-not (Test-Path -LiteralPath $databasePath)) {
    Write-Host "ERROR: Database not found: $databasePath" -ForegroundColor Red
    Write-Host "  Run stages 03-04 first" -ForegroundColor Yellow
    exit 1
}

# Resolve COLMAP binary path and set up environment
$colmapBin = if ($colmapExe -like "*.bat") {
    Join-Path (Split-Path -Parent $colmapExe) "bin\colmap.exe"
} else {
    $colmapExe
}

$colmapRootDir = if ($colmapExe -like "*.bat") {
    Split-Path -Parent $colmapExe
} else {
    Split-Path -Parent (Split-Path -Parent $colmapExe)
}

$env:PATH = "$(Join-Path $colmapRootDir 'bin');$env:PATH"
$env:QT_PLUGIN_PATH = Join-Path $colmapRootDir "plugins"

# Export sparse model to PLY using colmap model_converter
# NOTE: PLY is exported to colmap/ dir (NOT inside sparse/N/) to avoid confusing Postshot-cli
# which would try to read it and fail with "PlyReader: unexpected table size"
function Export-SparsePly {
    param(
        [string]$ReconPath,
        [string]$OutputDir
    )

    $reconName = Split-Path -Leaf $ReconPath
    $plyPath = Join-Path $OutputDir "sparse_${reconName}_points3D.ply"
    if (Test-Path -LiteralPath $plyPath) {
        $plySizeMB = [math]::Round((Get-Item -LiteralPath $plyPath).Length / 1MB, 2)
        Write-Host "  PLY already exists: $plyPath ($plySizeMB MB)" -ForegroundColor Yellow
        return
    }

    # Remove any stale PLY from inside sparse/N/ (legacy location that breaks Postshot)
    $legacyPly = Join-Path $ReconPath "points3D.ply"
    if (Test-Path -LiteralPath $legacyPly) {
        Write-Host "  Removing legacy PLY from sparse dir (breaks Postshot): $legacyPly" -ForegroundColor Yellow
        Remove-Item -LiteralPath $legacyPly -Force
    }

    Write-Host "  Exporting sparse model to PLY..." -ForegroundColor Cyan
    $convertProcess = Start-Process -FilePath $colmapBin `
        -ArgumentList @("model_converter", "--input_path", $ReconPath, "--output_path", $plyPath, "--output_type", "PLY") `
        -NoNewWindow -Wait -PassThru

    if ($convertProcess.ExitCode -eq 0 -and (Test-Path -LiteralPath $plyPath)) {
        $plySizeMB = [math]::Round((Get-Item -LiteralPath $plyPath).Length / 1MB, 2)
        Write-Host "  PLY exported: $plyPath ($plySizeMB MB)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: PLY export failed (exit code $($convertProcess.ExitCode))" -ForegroundColor Yellow
    }
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check for existing reconstruction
if (Test-Path -LiteralPath $sparseDir) {
    if ($overwrite) {
        Write-Host "  Deleting existing sparse directory (overwrite_result=true)..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $sparseDir -Recurse -Force
    } else {
        $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
        if ($reconFolders.Count -gt 0) {
            # Verify at least one has required files
            $validRecon = $false
            foreach ($recon in $reconFolders) {
                $imagesFile = Join-Path $recon.FullName "images.bin"
                if (Test-Path -LiteralPath $imagesFile) {
                    $validRecon = $true
                    Write-Host "  Found existing reconstruction: $($recon.Name)" -ForegroundColor Yellow
                    break
                }
            }
            if ($validRecon) {
                Write-Host "  Skipping mapper (overwrite_result=false)" -ForegroundColor Yellow
                Export-SparsePly -ReconPath $recon.FullName -OutputDir $colmapDir
                Write-Host ""
                Write-Host "Stage 5 Complete (skipped - reconstruction exists)" -ForegroundColor Green
                exit 0
            }
        }
    }
}

# === Filter pure-rotation frames: create image list excluding continuous rotation segments ===
$filterDegenerate = $true
if ($config.stage_05_mapper.PSObject.Properties['filter_degenerate_pairs']) {
    $filterDegenerate = $config.stage_05_mapper.filter_degenerate_pairs
}

$imageListPath = $null
if ($filterDegenerate) {
    $pythonExe = $config.paths.python
    $imageListFile = Join-Path $colmapDir "image_list.txt"

    Write-Host ""
    Write-Host "  Filtering pure-rotation frames..." -ForegroundColor Cyan

    $filterResult = & $pythonExe -c @"
import sqlite3, os
from collections import defaultdict

db = sqlite3.connect(r'$($databasePath.Replace("'","''"))')

imgs = db.execute('SELECT image_id, name FROM images ORDER BY name').fetchall()
id_to_name = {img_id: name for img_id, name in imgs}

# Parse frame numbers
def frame_num(name):
    try:
        return int(name.rsplit('_', 1)[-1].split('.')[0])
    except:
        return -1

id_to_frame = {img_id: frame_num(name) for img_id, name in imgs}
frame_to_name = {frame_num(name): name for _, name in imgs}

def pair_id_to_ids(pair_id):
    id2 = pair_id % 2147483647
    id1 = (pair_id - id2) // 2147483647
    return int(id1), int(id2)

tvg = db.execute('SELECT pair_id, rows, config FROM two_view_geometries WHERE rows > 0').fetchall()

# For each frame, check if it has any non-degenerate (type 2 or 3) pair
# with a close neighbor (within 5 frames)
has_close_good = set()
for pair_id, rows, config in tvg:
    if config in (4, 5, 6):
        continue
    id1, id2 = pair_id_to_ids(pair_id)
    f1 = id_to_frame.get(id1, -1)
    f2 = id_to_frame.get(id2, -1)
    if f1 < 0 or f2 < 0:
        continue
    if abs(f1 - f2) <= 5:
        has_close_good.add(f1)
        has_close_good.add(f2)

all_frames = sorted(frame_to_name.keys())

# Find continuous segments of frames WITHOUT close good pairs
bad_frames = sorted(set(all_frames) - has_close_good)

# Group into continuous segments
segments = []
if bad_frames:
    start = bad_frames[0]
    prev = start
    for f in bad_frames[1:]:
        if f == prev + 1:
            prev = f
        else:
            segments.append((start, prev))
            start = f
            prev = f
    segments.append((start, prev))

# Exclude frames in continuous pure-rotation segments (length >= 3)
exclude = set()
for s, e in segments:
    if e - s + 1 >= 3:
        exclude.update(range(s, e + 1))

# Write image list (include all except excluded)
keep_names = [frame_to_name[f] for f in all_frames if f not in exclude]

with open(r'$($imageListFile.Replace("'","''"))', 'w') as fout:
    for name in keep_names:
        fout.write(name + '\n')

db.close()
print(f'{len(exclude)}/{len(all_frames)}/{len(keep_names)}')
"@ 2>&1

    if ($filterResult -match '(\d+)/(\d+)/(\d+)') {
        $excluded = [int]$Matches[1]
        $total = [int]$Matches[2]
        $kept = [int]$Matches[3]
        if ($excluded -gt 0) {
            Write-Host "  Excluded $excluded/$total pure-rotation frames ($kept kept)" -ForegroundColor Yellow
            $imageListPath = $imageListFile
        } else {
            Write-Host "  No pure-rotation segments found ($total frames)" -ForegroundColor Green
        }
    } else {
        Write-Host "  WARNING: Filter output unexpected: $filterResult" -ForegroundColor Yellow
    }
}

# Create sparse output directory
if (-not (Test-Path -LiteralPath $sparseDir)) {
    New-Item -ItemType Directory -Path $sparseDir -Force | Out-Null
}

# Create visualizations directory
if (-not (Test-Path -LiteralPath $vizDir)) {
    New-Item -ItemType Directory -Path $vizDir -Force | Out-Null
}

# Resolve effective min_model_size (override > config > COLMAP default 10)
$effectiveMinModelSize = if ($MinModelSizeOverride -gt 0) { $MinModelSizeOverride } else { $config.stage_05_mapper.min_model_size }
if ($MinModelSizeOverride -gt 0) { Write-Host "  min_model_size: $effectiveMinModelSize (override)" -ForegroundColor Yellow }

# Build mapper arguments
$multipleModels = if ($config.stage_05_mapper.multiple_models) { 1 } else { 0 }

$colmapArgs = @(
    "mapper",
    "--database_path", $databasePath,
    "--image_path", $imagesDir,
    "--output_path", $sparseDir,
    "--Mapper.multiple_models=$multipleModels",
    "--Mapper.min_model_size=$effectiveMinModelSize"
)

# Add optional parameters only if explicitly set in config
if ($config.stage_05_mapper.PSObject.Properties['ba_global_max_iterations']) {
    $colmapArgs += @("--Mapper.ba_global_max_num_iterations=$($config.stage_05_mapper.ba_global_max_iterations)")
}
if ($config.stage_05_mapper.PSObject.Properties['ba_local_max_iterations']) {
    $colmapArgs += @("--Mapper.ba_local_max_num_iterations=$($config.stage_05_mapper.ba_local_max_iterations)")
}
if ($config.stage_05_mapper.PSObject.Properties['init_min_num_inliers']) {
    $colmapArgs += @("--Mapper.init_min_num_inliers=$($config.stage_05_mapper.init_min_num_inliers)")
}
if ($config.stage_05_mapper.PSObject.Properties['abs_pose_min_num_inliers']) {
    $colmapArgs += @("--Mapper.abs_pose_min_num_inliers=$($config.stage_05_mapper.abs_pose_min_num_inliers)")
}
if ($config.stage_05_mapper.PSObject.Properties['abs_pose_min_inlier_ratio']) {
    $colmapArgs += @("--Mapper.abs_pose_min_inlier_ratio=$($config.stage_05_mapper.abs_pose_min_inlier_ratio)")
}

# Add image list if pure-rotation filter created one
if ($imageListPath -and (Test-Path -LiteralPath $imageListPath)) {
    $colmapArgs += @("--Mapper.image_list_path", $imageListPath)
    Write-Host "  Using image list: $imageListPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Running mapper..." -ForegroundColor Cyan
Write-Host "  Command: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

# Log file for visualization monitor
$vizLog = Join-Path $vizDir "mapper_progress.log"
Add-Content -Path $vizLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting COLMAP mapper"

$timeoutHours = 12
if ($config.stage_05_mapper.PSObject.Properties['colmap_timeout_hours']) {
    $timeoutHours = $config.stage_05_mapper.colmap_timeout_hours
}
$timeoutMs = [int]($timeoutHours * 3600 * 1000)

Write-Host "  Timeout: $timeoutHours hours" -ForegroundColor DarkGray

$startTime = Get-Date

$process = Start-Process -FilePath $colmapBin `
    -ArgumentList $colmapArgs `
    -NoNewWindow -PassThru

$exited = $process.WaitForExit($timeoutMs)
$duration = (Get-Date) - $startTime

if (-not $exited) {
    Write-Host "ERROR: Mapper timed out after $timeoutHours hours. Killing process." -ForegroundColor Red
    Add-Content -Path $vizLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Mapper TIMED OUT after $timeoutHours hours"
    $process.Kill()
    exit 1
}

Add-Content -Path $vizLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Mapper completed with exit code $($process.ExitCode)"

if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Mapper failed with exit code $($process.ExitCode)" -ForegroundColor Red
    exit 1
}

# Find reconstructions
$reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }

if ($reconFolders.Count -eq 0) {
    Write-Host "ERROR: No reconstruction created" -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($reconFolders.Count) reconstruction(s)" -ForegroundColor Cyan

# === COLMAP Quality Gate Config ===
$colmapQualityGate = $false
if ($config.stage_05_mapper.PSObject.Properties['quality_gate']) {
    $colmapQualityGate = $config.stage_05_mapper.quality_gate
}

$mergeModels = $false
if ($config.stage_05_mapper.PSObject.Properties['merge_models']) {
    $mergeModels = $config.stage_05_mapper.merge_models
}

# === Auto-merge if multiple models and merge_models enabled ===
if ($mergeModels -and $reconFolders.Count -gt 1) {
    Write-Host ""
    Write-Host "  Auto-merge: $($reconFolders.Count) models detected, merging..." -ForegroundColor Yellow

    $sortedRecons = $reconFolders | Sort-Object Name
    $currentInput = $sortedRecons[0].FullName
    $mergeDir = Join-Path $sparseDir "merge_temp"

    for ($mi = 1; $mi -lt $sortedRecons.Count; $mi++) {
        $nextRecon = $sortedRecons[$mi].FullName
        $tempOutput = Join-Path $mergeDir "step_$mi"

        if (Test-Path -LiteralPath $tempOutput) {
            Remove-Item -LiteralPath $tempOutput -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null

        Write-Host "    Merging model $($sortedRecons[$mi].Name) into accumulated result..." -ForegroundColor Gray

        $mergeArgs = @(
            "model_merger",
            "--input_path1", $currentInput,
            "--input_path2", $nextRecon,
            "--output_path", $tempOutput
        )

        $mergeProcess = Start-Process -FilePath $colmapBin -ArgumentList $mergeArgs -NoNewWindow -Wait -PassThru

        $mergeOutputImages = Join-Path $tempOutput "images.bin"
        if ($mergeProcess.ExitCode -eq 0 -and (Test-Path -LiteralPath $mergeOutputImages)) {
            $currentInput = $tempOutput
            Write-Host "    Merge step $mi successful" -ForegroundColor Green
        } else {
            Write-Host "    Merge step $mi failed (model $($sortedRecons[$mi].Name) skipped)" -ForegroundColor Yellow
        }
    }

    # Run image_registrator on merged model to register remaining images
    Write-Host "    Running image_registrator on merged model..." -ForegroundColor Cyan
    $registratorOutput = Join-Path $mergeDir "registered"
    if (Test-Path -LiteralPath $registratorOutput) {
        Remove-Item -LiteralPath $registratorOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Path $registratorOutput -Force | Out-Null

    # Copy current merged model to registrator input
    Copy-Item -LiteralPath (Join-Path $currentInput "*") -Destination $registratorOutput -Recurse -Force

    $regArgs = @(
        "image_registrator",
        "--database_path", $databasePath,
        "--input_path", $registratorOutput,
        "--output_path", $registratorOutput,
        "--Mapper.abs_pose_min_num_inliers=10",
        "--Mapper.abs_pose_min_inlier_ratio=0.1"
    )

    $regProcess = Start-Process -FilePath $colmapBin -ArgumentList $regArgs -NoNewWindow -Wait -PassThru
    if ($regProcess.ExitCode -eq 0) {
        Write-Host "    Image registrator completed" -ForegroundColor Green
    } else {
        Write-Host "    Image registrator failed (continuing with merged model)" -ForegroundColor Yellow
    }

    # Run bundle_adjuster to refine
    Write-Host "    Running bundle_adjuster on merged model..." -ForegroundColor Cyan
    $baArgs = @(
        "bundle_adjuster",
        "--input_path", $registratorOutput,
        "--output_path", $registratorOutput
    )

    $baProcess = Start-Process -FilePath $colmapBin -ArgumentList $baArgs -NoNewWindow -Wait -PassThru
    if ($baProcess.ExitCode -eq 0) {
        Write-Host "    Bundle adjustment completed" -ForegroundColor Green
    } else {
        Write-Host "    Bundle adjustment failed (continuing with current model)" -ForegroundColor Yellow
    }

    # Replace sparse/0 with final merged result
    $finalMergedImages = Join-Path $registratorOutput "images.bin"
    if (Test-Path -LiteralPath $finalMergedImages) {
        # Remove all existing reconstruction folders
        foreach ($recon in $reconFolders) {
            Remove-Item -LiteralPath $recon.FullName -Recurse -Force
        }

        # Create sparse/0 with merged result
        $mergedTarget = Join-Path $sparseDir "0"
        New-Item -ItemType Directory -Path $mergedTarget -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $registratorOutput "*") -Destination $mergedTarget -Recurse -Force

        Write-Host "    Merged model saved to sparse/0" -ForegroundColor Green
    } else {
        Write-Host "    WARNING: Merge produced no output, keeping original models" -ForegroundColor Yellow
    }

    # Clean up merge temp directory
    if (Test-Path -LiteralPath $mergeDir) {
        Remove-Item -LiteralPath $mergeDir -Recurse -Force
    }

    # Re-scan reconstruction folders after merge
    $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
    Write-Host "  After merge: $($reconFolders.Count) reconstruction(s)" -ForegroundColor Cyan
}

# Find largest reconstruction
$largestRecon = $null
$largestSize = 0

foreach ($recon in $reconFolders) {
    $imagesBin = Join-Path $recon.FullName "images.bin"
    if (Test-Path -LiteralPath $imagesBin) {
        $size = (Get-Item -LiteralPath $imagesBin).Length
        Write-Host "    Reconstruction $($recon.Name): images.bin = $size bytes" -ForegroundColor Gray
        if ($size -gt $largestSize) {
            $largestSize = $size
            $largestRecon = $recon
        }
    }
}

if (-not $largestRecon) {
    Write-Host "ERROR: No valid reconstruction found" -ForegroundColor Red
    exit 1
}

Write-Host "  Selected reconstruction: $($largestRecon.Name)" -ForegroundColor Green

# === Remove outlier cameras (degenerate pose estimation) ===
$filterDegenerate = $true
if ($config.stage_05_mapper.PSObject.Properties['filter_degenerate_pairs']) {
    $filterDegenerate = $config.stage_05_mapper.filter_degenerate_pairs
}

if ($filterDegenerate) {
    $pythonExe = $config.paths.python
    Write-Host ""
    Write-Host "  Removing outlier cameras..." -ForegroundColor Cyan

    $filterResult = & $pythonExe -c @"
import struct, numpy as np, os, shutil

def read_images_bin(path):
    images = []
    raw_data = []
    with open(path, 'rb') as f:
        num = struct.unpack('<Q', f.read(8))[0]
        for _ in range(num):
            start = f.tell()
            img_id = struct.unpack('<I', f.read(4))[0]
            qw, qx, qy, qz = struct.unpack('<4d', f.read(32))
            tx, ty, tz = struct.unpack('<3d', f.read(24))
            cam_id = struct.unpack('<I', f.read(4))[0]
            name = b''
            while True:
                c = f.read(1)
                if c == b'\x00': break
                name += c
            num_pts = struct.unpack('<Q', f.read(8))[0]
            for _ in range(num_pts):
                f.read(24)
            end = f.tell()
            R = np.array([
                [1-2*(qy**2+qz**2), 2*(qx*qy-qz*qw), 2*(qx*qz+qy*qw)],
                [2*(qx*qy+qz*qw), 1-2*(qx**2+qz**2), 2*(qy*qz-qx*qw)],
                [2*(qx*qz-qy*qw), 2*(qy*qz+qx*qw), 1-2*(qx**2+qy**2)]
            ])
            pos = -R.T @ np.array([tx, ty, tz])
            images.append({'id': img_id, 'name': name.decode(), 'pos': pos, 'start': start, 'end': end})
    return images

recon_path = r'$($largestRecon.FullName.Replace("'","''"))'
images_bin = os.path.join(recon_path, 'images.bin')
images = read_images_bin(images_bin)

if len(images) < 10:
    print('0/' + str(len(images)))
    exit(0)

positions = np.array([img['pos'] for img in images])
median_pos = np.median(positions, axis=0)
dists = np.linalg.norm(positions - median_pos, axis=1)

q1, q3 = np.percentile(dists, [25, 75])
iqr = q3 - q1
threshold = q3 + 3 * iqr

outlier_ids = set()
for i, img in enumerate(images):
    if dists[i] > threshold:
        outlier_ids.add(img['id'])

if not outlier_ids:
    print('0/' + str(len(images)))
    exit(0)

# Rewrite images.bin without outliers
with open(images_bin, 'rb') as f:
    raw = f.read()

# Backup
shutil.copy2(images_bin, images_bin + '.bak')

with open(images_bin, 'wb') as f:
    f.write(struct.pack('<Q', len(images) - len(outlier_ids)))
    for img in images:
        if img['id'] not in outlier_ids:
            f.write(raw[img['start']:img['end']])

print(f'{len(outlier_ids)}/{len(images)}')
"@ 2>&1

    if ($filterResult -match '(\d+)/(\d+)') {
        $removed = [int]$Matches[1]
        $total = [int]$Matches[2]
        if ($removed -gt 0) {
            Write-Host "  Removed $removed/$total outlier cameras" -ForegroundColor Yellow

            # Re-run bundle adjustment to refine after removing outliers
            Write-Host "  Re-running bundle adjustment..." -ForegroundColor Cyan
            $baArgs = @(
                "bundle_adjuster",
                "--input_path", $largestRecon.FullName,
                "--output_path", $largestRecon.FullName
            )
            $baProcess = Start-Process -FilePath $colmapBin -ArgumentList $baArgs -NoNewWindow -Wait -PassThru
            if ($baProcess.ExitCode -eq 0) {
                Write-Host "  Bundle adjustment completed" -ForegroundColor Green
            } else {
                Write-Host "  WARNING: Bundle adjustment failed (continuing with filtered model)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No outlier cameras found ($total cameras)" -ForegroundColor Green
        }
    } else {
        Write-Host "  WARNING: Outlier filter output unexpected: $filterResult" -ForegroundColor Yellow
    }
}

# === Registration check: at least 50% of images must be registered ===
$pythonExe = $config.paths.python
$totalImageCount = (Get-ChildItem -LiteralPath $imagesDir -Recurse -File |
    Where-Object { $_.Extension -in @('.png','.jpg','.jpeg','.PNG','.JPG','.JPEG') }).Count

$regResult = & $pythonExe -c @"
import struct
with open(r'$($largestRecon.FullName.Replace("'","''"))\images.bin', 'rb') as f:
    n = struct.unpack('<Q', f.read(8))[0]
print(n)
"@ 2>&1

$registeredCount = [int]$regResult
$regPct = [math]::Round(100 * $registeredCount / $totalImageCount, 1)
Write-Host "  Registration: $registeredCount / $totalImageCount ($regPct%)" -ForegroundColor $(if ($regPct -ge 50) { "Green" } else { "Red" })

if ($regPct -lt 50) {
    Write-Host "ERROR: Only $regPct% images registered (need >= 50%)" -ForegroundColor Red
    exit 1
}

# === COLMAP Quality Gate Check ===
if ($colmapQualityGate) {
    $qualityScript = Join-Path (Split-Path $PSScriptRoot) "util\check_sparse_quality.py"
    $colmapQualityJson = Join-Path $colmapDir "sparse_quality.json"

    # Count total images from images directory
    $totalImageCount = (Get-ChildItem -LiteralPath $imagesDir -Recurse -File |
        Where-Object { $_.Extension -in @('.png','.jpg','.jpeg','.PNG','.JPG','.JPEG') }).Count

    $pythonExe = $config.paths.python

    Write-Host ""
    Write-Host "  Running COLMAP quality check..." -ForegroundColor Cyan
    & $pythonExe $qualityScript --sparse $sparseDir --output $colmapQualityJson --total-images $totalImageCount

    if (Test-Path -LiteralPath $colmapQualityJson) {
        $qualityResult = Get-Content $colmapQualityJson -Raw | ConvertFrom-Json

        Write-Host ""
        Write-Host "  COLMAP Quality Check:" -ForegroundColor Cyan
        Write-Host "    Models: $($qualityResult.checks.num_models)" -ForegroundColor White
        Write-Host "    Registered: $($qualityResult.checks.registered_images)/$($qualityResult.checks.total_images)" -ForegroundColor White
        if ($qualityResult.checks.structure) {
            $is3d = if ($qualityResult.checks.structure.is_3d) { 'YES' } else { 'NO (PLANAR!)' }
            Write-Host "    3D structure: $is3d (ratio=$($qualityResult.checks.structure.planarity_ratio))" -ForegroundColor White
        }
        if ($qualityResult.checks.mean_reprojection_error) {
            Write-Host "    Reprojection error: $($qualityResult.checks.mean_reprojection_error) px" -ForegroundColor White
        }

        if (-not $qualityResult.pass) {
            Write-Host ""
            Write-Host "  COLMAP QUALITY GATE FAILED" -ForegroundColor Red
            foreach ($reason in $qualityResult.reasons) {
                Write-Host "    - $reason" -ForegroundColor Red
            }
            exit 2  # Exit code 2 = COLMAP quality failure (not crash)
        }

        Write-Host "    Result: PASS" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Quality check script did not produce output" -ForegroundColor Yellow
    }
}

# Export PLY
Export-SparsePly -ReconPath $largestRecon.FullName -OutputDir $colmapDir

# Save visualization (simple point cloud stats for now)
$vizInfoFile = Join-Path $vizDir "reconstruction_info.txt"
$points3dBin = Join-Path $largestRecon.FullName "points3D.bin"
$points3dSize = if (Test-Path -LiteralPath $points3dBin) { (Get-Item -LiteralPath $points3dBin).Length } else { 0 }

$vizInfo = @"
COLMAP Reconstruction Summary
=============================
Reconstruction folder: $($largestRecon.Name)
images.bin size: $largestSize bytes
points3D.bin size: $points3dSize bytes
Duration: $($duration.ToString('hh\:mm\:ss'))
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

Set-Content -Path $vizInfoFile -Value $vizInfo

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 5 Complete" -ForegroundColor Green
Write-Host "  Reconstruction: $($largestRecon.FullName)" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

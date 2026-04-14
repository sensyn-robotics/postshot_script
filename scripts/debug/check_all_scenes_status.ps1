# check_all_scenes_status.ps1
# Check status of all scenes in the test data directory
#
# Usage: .\scripts\debug\check_all_scenes_status.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDataPath = "C:\postshot_test_data"
)

Write-Host ""
Write-Host "########################################################" -ForegroundColor Cyan
Write-Host "#         All Scenes Status Check                      #" -ForegroundColor Cyan
Write-Host "########################################################" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Test data path: $TestDataPath" -ForegroundColor White
Write-Host ""

if (-not (Test-Path -LiteralPath $TestDataPath)) {
    Write-Host "ERROR: Test data path not found: $TestDataPath" -ForegroundColor Red
    exit 1
}

$scenes = Get-ChildItem -LiteralPath $TestDataPath -Directory | Sort-Object Name

if ($scenes.Count -eq 0) {
    Write-Host "No scene directories found." -ForegroundColor Yellow
    exit 0
}

$completeCount = 0
$incompleteCount = 0

foreach ($scene in $scenes) {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Scene: $($scene.Name)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow

    # Check all output directories
    $outputDirs = Get-ChildItem -LiteralPath $scene.FullName -Directory | Where-Object { $_.Name -like "output*" } | Sort-Object Name

    if ($outputDirs.Count -eq 0) {
        Write-Host "  No output directories found" -ForegroundColor Gray
        $incompleteCount++
        Write-Host ""
        continue
    }

    $sceneComplete = $false

    foreach ($outDir in $outputDirs) {
        Write-Host "  --- $($outDir.Name) ---" -ForegroundColor Cyan

        # Check for videos (input)
        $videos = Get-ChildItem -LiteralPath $scene.FullName -File | Where-Object { $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV") }
        Write-Host "    Videos: $($videos.Count) found" -ForegroundColor White

        # Check images
        $imagesDir = Join-Path $outDir.FullName "images"
        if (Test-Path -LiteralPath $imagesDir) {
            $wDir = Join-Path $imagesDir "video_W"
            $zDir = Join-Path $imagesDir "video_Z"
            $wCount = if (Test-Path -LiteralPath $wDir) { (Get-ChildItem -LiteralPath $wDir -File -ErrorAction SilentlyContinue).Count } else { 0 }
            $zCount = if (Test-Path -LiteralPath $zDir) { (Get-ChildItem -LiteralPath $zDir -File -ErrorAction SilentlyContinue).Count } else { 0 }
            Write-Host "    Frames: W=$wCount, Z=$zCount, Total=$($wCount + $zCount)" -ForegroundColor White
        } else {
            Write-Host "    Frames: Not extracted" -ForegroundColor Gray
        }

        # Check COLMAP
        $colmapDir = Join-Path $outDir.FullName "colmap"
        $sparseDir = Join-Path $colmapDir "sparse"
        $databasePath = Join-Path $colmapDir "database.db"

        if (Test-Path -LiteralPath $databasePath) {
            $dbSize = [math]::Round((Get-Item -LiteralPath $databasePath).Length / 1MB, 1)
            Write-Host "    COLMAP DB: $dbSize MB" -ForegroundColor White
        } else {
            Write-Host "    COLMAP DB: Not created" -ForegroundColor Gray
        }

        if (Test-Path -LiteralPath $sparseDir) {
            $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
            if ($reconFolders.Count -gt 0) {
                Write-Host "    Sparse: $($reconFolders.Count) reconstruction(s)" -ForegroundColor Green

                # Check camera model in the first reconstruction
                $firstRecon = $reconFolders | Select-Object -First 1
                $camerasBin = Join-Path $firstRecon.FullName "cameras.bin"
                if (Test-Path -LiteralPath $camerasBin) {
                    # Read first byte to get camera model ID (simple check)
                    $fileSize = (Get-Item -LiteralPath $camerasBin).Length
                    Write-Host "    Cameras.bin: $fileSize bytes" -ForegroundColor White
                }
            } else {
                Write-Host "    Sparse: No reconstructions" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    Sparse: Not created" -ForegroundColor Gray
        }

        # Check Postshot output
        $postshotDir = Join-Path $outDir.FullName "postshot"
        $pshtPath = Join-Path $postshotDir "scene.psht"
        $plyPath = Join-Path $postshotDir "scene.ply"

        if (Test-Path -LiteralPath $pshtPath) {
            $pshtSize = [math]::Round((Get-Item -LiteralPath $pshtPath).Length / 1MB, 0)
            Write-Host "    PSHT: $pshtSize MB" -ForegroundColor Green
            $sceneComplete = $true
        } else {
            Write-Host "    PSHT: Not created" -ForegroundColor Yellow
        }

        if (Test-Path -LiteralPath $plyPath) {
            $plySize = [math]::Round((Get-Item -LiteralPath $plyPath).Length / 1MB, 0)
            Write-Host "    PLY: $plySize MB" -ForegroundColor Green
        } else {
            Write-Host "    PLY: Not created" -ForegroundColor Yellow
        }

        # Check visualizations
        $vizDir = Join-Path $outDir.FullName "visualizations"
        if (Test-Path -LiteralPath $vizDir) {
            $vizFiles = Get-ChildItem -LiteralPath $vizDir -File -ErrorAction SilentlyContinue
            $pngCount = ($vizFiles | Where-Object { $_.Extension -eq ".png" }).Count
            Write-Host "    Visualizations: $pngCount PNG files" -ForegroundColor White
        }

        Write-Host ""
    }

    if ($sceneComplete) {
        $completeCount++
    } else {
        $incompleteCount++
    }
}

# Summary
Write-Host "########################################################" -ForegroundColor Green
Write-Host "#                    Summary                           #" -ForegroundColor Green
Write-Host "########################################################" -ForegroundColor Green
Write-Host ""
Write-Host "  Total scenes: $($scenes.Count)" -ForegroundColor White
Write-Host "  Complete:     $completeCount" -ForegroundColor $(if ($completeCount -eq $scenes.Count) { "Green" } else { "White" })
Write-Host "  Incomplete:   $incompleteCount" -ForegroundColor $(if ($incompleteCount -gt 0) { "Yellow" } else { "White" })
Write-Host ""

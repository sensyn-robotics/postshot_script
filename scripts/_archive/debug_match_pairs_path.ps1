# Debug script to test path handling with Japanese characters
# Usage: .\debug_match_pairs_path.ps1 -ImagesDir <path>

param(
    [Parameter(Mandatory=$false)]
    [string]$ImagesDir = "C:\postshot_test_data"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug: Path Handling Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Direct path access
Write-Host "Test 1: Direct path access to test data" -ForegroundColor Yellow
$scenes = Get-ChildItem $ImagesDir -Directory -ErrorAction SilentlyContinue
Write-Host "  Found $($scenes.Count) scene directories" -ForegroundColor Gray

foreach ($scene in $scenes) {
    Write-Host ""
    Write-Host "  Scene: $($scene.Name)" -ForegroundColor Cyan

    $imagesPath = Join-Path $scene.FullName "output\images"
    Write-Host "    Images path: $imagesPath" -ForegroundColor Gray
    Write-Host "    Path exists: $(Test-Path $imagesPath)" -ForegroundColor Gray

    if (Test-Path $imagesPath) {
        $videoW = Join-Path $imagesPath "video_W"
        $videoZ = Join-Path $imagesPath "video_Z"

        Write-Host "    video_W path: $videoW" -ForegroundColor Gray
        Write-Host "    video_W exists: $(Test-Path $videoW)" -ForegroundColor Gray

        if (Test-Path $videoW) {
            # Method 1: Standard Get-ChildItem
            $images1 = @(Get-ChildItem -Path $videoW -File -ErrorAction SilentlyContinue)
            Write-Host "    Method 1 (Get-ChildItem -File): $($images1.Count) files" -ForegroundColor Gray

            # Method 2: With extension filter using Where-Object
            $imageExtensions = @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG")
            $images2 = @(Get-ChildItem -Path $videoW -File -ErrorAction SilentlyContinue | Where-Object { $imageExtensions -contains $_.Extension })
            Write-Host "    Method 2 (Where-Object extension): $($images2.Count) images" -ForegroundColor Gray

            # Method 3: With -Filter parameter
            $images3 = @(Get-ChildItem -Path $videoW -Filter "*.png" -ErrorAction SilentlyContinue)
            Write-Host "    Method 3 (Filter *.png): $($images3.Count) images" -ForegroundColor Gray

            # Method 4: Using literal path
            $images4 = @(Get-ChildItem -LiteralPath $videoW -Filter "*.png" -ErrorAction SilentlyContinue)
            Write-Host "    Method 4 (LiteralPath + Filter): $($images4.Count) images" -ForegroundColor Gray

            # Show sample files
            if ($images4.Count -gt 0) {
                Write-Host "    Sample files:" -ForegroundColor Gray
                $images4 | Select-Object -First 3 | ForEach-Object {
                    Write-Host "      - $($_.Name)" -ForegroundColor DarkGray
                }
            }
        }
    }
}

# Test 2: Test passing path as parameter
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 2: Path encoding check" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

$testPath = "C:\postshot_test_data\①腕金を両サイド1本ずつ\output\images"
Write-Host "  Test path: $testPath" -ForegroundColor Gray
Write-Host "  Path length: $($testPath.Length)" -ForegroundColor Gray
Write-Host "  Path exists: $(Test-Path $testPath)" -ForegroundColor Gray

if (Test-Path $testPath) {
    $subDirs = Get-ChildItem $testPath -Directory
    Write-Host "  Subdirectories:" -ForegroundColor Gray
    foreach ($dir in $subDirs) {
        Write-Host "    - $($dir.Name)" -ForegroundColor DarkGray
    }
}

# Test 3: Byte-level path check
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 3: Encoding details" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "  Console OutputEncoding: $([Console]::OutputEncoding.EncodingName)" -ForegroundColor Gray
Write-Host "  PSDefaultParameterValues: $($PSDefaultParameterValues.Count) entries" -ForegroundColor Gray

# Test 4: Test with -Include parameter (which requires -Recurse)
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test 4: Include parameter test" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

if (Test-Path $testPath) {
    $allImages = @(Get-ChildItem -Path $testPath -Recurse -Include "*.png" -ErrorAction SilentlyContinue)
    Write-Host "  Total PNG files found recursively: $($allImages.Count)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# generate_match_pairs.ps1
# Generates match_pairs.txt for COLMAP custom pair matching
#
# Creates three types of pairs:
#   1. W<->W temporal: Wide camera frames matched to neighboring frames
#   2. Z<->Z temporal: Zoom camera frames matched to neighboring frames
#   3. W<->Z same-timestamp: Cross-camera matches at same frame numbers
#
# Usage:
#   .\generate_match_pairs.ps1 -ImagesDir "C:\data\images" -OutputPath "C:\data\match_pairs.txt"
#
# Expected input structure:
#   images/
#   +-- video_W/
#   |   +-- frame_00001.png
#   |   +-- frame_00002.png
#   |   +-- ...
#   +-- video_Z/
#       +-- frame_00001.png
#       +-- frame_00002.png
#       +-- ...

param(
    [Parameter(Mandatory=$true)]
    [string]$ImagesDir,

    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [int]$TemporalOverlap = 10,

    [Parameter(Mandatory=$false)]
    [switch]$CrossCameraSameTimestamp = $true,

    [Parameter(Mandatory=$false)]
    [switch]$ShowDetails
)

function Get-FrameNumber {
    <#
    .SYNOPSIS
    Extract frame number from filename
    #>
    param([string]$FileName)

    if ($FileName -match "frame_(\d+)") {
        return [int]$matches[1]
    }
    elseif ($FileName -match "(\d+)") {
        return [int]$matches[1]
    }
    return -1
}

function Generate-TemporalPairs {
    <#
    .SYNOPSIS
    Generate temporal pairs within a single camera's images

    .PARAMETER Images
    Array of image file objects

    .PARAMETER SubfolderName
    Name of subfolder (e.g., "video_W")

    .PARAMETER Overlap
    Number of neighboring frames to match

    .OUTPUTS
    Array of pair strings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Images,

        [Parameter(Mandatory=$true)]
        [string]$SubfolderName,

        [Parameter(Mandatory=$true)]
        [int]$Overlap
    )

    $pairs = @()
    $imageCount = $Images.Count

    for ($i = 0; $i -lt $imageCount; $i++) {
        $img1 = $Images[$i]
        $img1Path = "$SubfolderName/$($img1.Name)"

        # Match with next N images (forward neighbors)
        for ($j = 1; $j -le $Overlap; $j++) {
            $nextIdx = $i + $j
            if ($nextIdx -lt $imageCount) {
                $img2 = $Images[$nextIdx]
                $img2Path = "$SubfolderName/$($img2.Name)"
                $pairs += "$img1Path $img2Path"
            }
        }
    }

    return $pairs
}

function Generate-CrossCameraPairs {
    <#
    .SYNOPSIS
    Generate cross-camera pairs for same timestamps

    .PARAMETER WImages
    Array of Wide camera image file objects

    .PARAMETER ZImages
    Array of Zoom camera image file objects

    .PARAMETER WSubfolder
    Subfolder name for Wide images

    .PARAMETER ZSubfolder
    Subfolder name for Zoom images

    .OUTPUTS
    Array of pair strings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$WImages,

        [Parameter(Mandatory=$true)]
        [array]$ZImages,

        [Parameter(Mandatory=$true)]
        [string]$WSubfolder,

        [Parameter(Mandatory=$true)]
        [string]$ZSubfolder
    )

    $pairs = @()

    # Build lookup table for Z images by frame number
    $zByFrame = @{}
    foreach ($zImg in $ZImages) {
        $frameNum = Get-FrameNumber -FileName $zImg.Name
        if ($frameNum -ge 0) {
            $zByFrame[$frameNum] = $zImg
        }
    }

    # Match W images to corresponding Z images
    foreach ($wImg in $WImages) {
        $frameNum = Get-FrameNumber -FileName $wImg.Name
        if ($frameNum -ge 0 -and $zByFrame.ContainsKey($frameNum)) {
            $zImg = $zByFrame[$frameNum]
            $wPath = "$WSubfolder/$($wImg.Name)"
            $zPath = "$ZSubfolder/$($zImg.Name)"
            $pairs += "$wPath $zPath"
        }
    }

    return $pairs
}

# === MAIN EXECUTION ===

Write-Host ""
Write-Host "=== Generate Match Pairs ===" -ForegroundColor Cyan
Write-Host "  Images directory: $ImagesDir" -ForegroundColor Gray
Write-Host "  Output: $OutputPath" -ForegroundColor Gray
Write-Host "  Temporal overlap: $TemporalOverlap" -ForegroundColor Gray
Write-Host "  Cross-camera same-timestamp: $CrossCameraSameTimestamp" -ForegroundColor Gray

# Validate images directory
if (-not (Test-Path $ImagesDir)) {
    Write-Host "ERROR: Images directory not found: $ImagesDir" -ForegroundColor Red
    exit 1
}

# Find Wide and Zoom subfolders
$wSubfolder = "video_W"
$zSubfolder = "video_Z"
$wPath = Join-Path $ImagesDir $wSubfolder
$zPath = Join-Path $ImagesDir $zSubfolder

if (-not (Test-Path $wPath)) {
    Write-Host "ERROR: Wide images folder not found: $wPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $zPath)) {
    Write-Host "ERROR: Zoom images folder not found: $zPath" -ForegroundColor Red
    exit 1
}

# Get images from each folder
# Note: -Include requires -Recurse in PowerShell, so we use Where-Object instead
$imageExtensions = @(".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG")
$wImages = @(Get-ChildItem -Path $wPath -File | Where-Object { $imageExtensions -contains $_.Extension } | Sort-Object Name)
$zImages = @(Get-ChildItem -Path $zPath -File | Where-Object { $imageExtensions -contains $_.Extension } | Sort-Object Name)

Write-Host ""
Write-Host "  Wide images: $($wImages.Count)" -ForegroundColor Cyan
Write-Host "  Zoom images: $($zImages.Count)" -ForegroundColor Cyan

if ($wImages.Count -eq 0) {
    Write-Host "ERROR: No images found in Wide folder" -ForegroundColor Red
    exit 1
}

if ($zImages.Count -eq 0) {
    Write-Host "ERROR: No images found in Zoom folder" -ForegroundColor Red
    exit 1
}

$allPairs = @()

# Generate W<->W temporal pairs
Write-Host ""
Write-Host "  Generating W<->W temporal pairs..." -ForegroundColor Gray
$wPairs = Generate-TemporalPairs -Images $wImages -SubfolderName $wSubfolder -Overlap $TemporalOverlap
$allPairs += $wPairs
Write-Host "    Generated $($wPairs.Count) W<->W pairs" -ForegroundColor Gray

# Generate Z<->Z temporal pairs
Write-Host "  Generating Z<->Z temporal pairs..." -ForegroundColor Gray
$zPairs = Generate-TemporalPairs -Images $zImages -SubfolderName $zSubfolder -Overlap $TemporalOverlap
$allPairs += $zPairs
Write-Host "    Generated $($zPairs.Count) Z<->Z pairs" -ForegroundColor Gray

# Generate W<->Z cross-camera pairs
if ($CrossCameraSameTimestamp) {
    Write-Host "  Generating W<->Z cross-camera pairs..." -ForegroundColor Gray
    $crossPairs = Generate-CrossCameraPairs -WImages $wImages -ZImages $zImages -WSubfolder $wSubfolder -ZSubfolder $zSubfolder
    $allPairs += $crossPairs
    Write-Host "    Generated $($crossPairs.Count) W<->Z pairs" -ForegroundColor Gray
}

# Write match pairs file
Write-Host ""
Write-Host "  Writing match pairs file..." -ForegroundColor Gray

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value ($allPairs -join "`n") -Encoding UTF8

$totalPairs = $allPairs.Count
Write-Host ""
Write-Host "Match pairs generated successfully!" -ForegroundColor Green
Write-Host "  Total pairs: $totalPairs" -ForegroundColor Green
Write-Host "  Output file: $OutputPath" -ForegroundColor Green

# Calculate comparison to exhaustive
$totalImages = $wImages.Count + $zImages.Count
$exhaustivePairs = ($totalImages * ($totalImages - 1)) / 2
$reduction = [math]::Round((1 - ($totalPairs / $exhaustivePairs)) * 100, 1)
Write-Host ""
Write-Host "  Exhaustive would be: $exhaustivePairs pairs" -ForegroundColor Gray
Write-Host "  Reduction: $reduction%" -ForegroundColor Gray

if ($ShowDetails) {
    Write-Host ""
    Write-Host "Sample pairs:" -ForegroundColor Gray
    $allPairs | Select-Object -First 10 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor DarkGray
    }
    Write-Host "    ..." -ForegroundColor DarkGray
}

exit 0

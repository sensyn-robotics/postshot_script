# video_extractor.ps1
# Extract frames from video files using FFmpeg

param(
    [Parameter(Mandatory=$false)]
    [string]$VideoPath,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [PSCustomObject]$Config
)

# Import config loader
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")

# Load config if not provided
if (-not $Config) {
    $Config = Load-Config
}

function Extract-VideoFrames {
    <#
    .SYNOPSIS
    Extract frames from a video file using FFmpeg

    .PARAMETER VideoPath
    Path to the input video file

    .PARAMETER OutputDir
    Directory to save extracted frames

    .PARAMETER Config
    Configuration object with video extraction settings

    .OUTPUTS
    Returns the output directory path on success, $null on failure
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$VideoPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    # Validate video file exists
    if (-not (Test-Path $VideoPath)) {
        Write-Host "ERROR: Video file not found: $VideoPath" -ForegroundColor Red
        return $null
    }

    $ffmpegPath = $Config.paths.ffmpeg_exe
    if (-not (Test-Path $ffmpegPath)) {
        Write-Host "ERROR: FFmpeg not found at: $ffmpegPath" -ForegroundColor Red
        return $null
    }

    # Get video extraction settings
    $fps = $Config.video_extraction.fps
    $format = $Config.video_extraction.output_format
    $quality = $Config.video_extraction.quality

    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Get video filename without extension for naming
    $videoName = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
    $outputPattern = Join-Path $OutputDir "frame_%05d.$format"

    Write-Host "Extracting frames from: $VideoPath" -ForegroundColor Cyan
    Write-Host "  Output directory: $OutputDir" -ForegroundColor Cyan
    Write-Host "  FPS: $fps, Format: $format, Quality: $quality" -ForegroundColor Cyan

    # Build FFmpeg command
    $ffmpegArgs = @(
        "-i", "`"$VideoPath`"",
        "-vf", "fps=$fps",
        "-q:v", "$quality",
        "-start_number", "1",
        "`"$outputPattern`""
    )

    $ffmpegCmd = "& `"$ffmpegPath`" $($ffmpegArgs -join ' ')"
    Write-Host "Running: $ffmpegCmd" -ForegroundColor DarkGray

    try {
        # Execute FFmpeg
        $process = Start-Process -FilePath $ffmpegPath `
            -ArgumentList @("-i", $VideoPath, "-vf", "fps=$fps", "-q:v", $quality, "-start_number", "1", $outputPattern) `
            -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            Write-Host "ERROR: FFmpeg exited with code: $($process.ExitCode)" -ForegroundColor Red
            return $null
        }

        # Count extracted frames
        $frameCount = (Get-ChildItem -Path $OutputDir -Filter "*.$format").Count
        Write-Host "Extracted $frameCount frames to: $OutputDir" -ForegroundColor Green

        return $OutputDir
    }
    catch {
        Write-Host "ERROR: Failed to extract frames: $_" -ForegroundColor Red
        return $null
    }
}

function Extract-AllVideosInFolder {
    <#
    .SYNOPSIS
    Extract frames from all video files in a folder, each to a separate subfolder

    .PARAMETER FolderPath
    Path to folder containing video files

    .PARAMETER OutputBaseDir
    Base directory for output (frames will be in subfolders named by video)

    .PARAMETER Config
    Configuration object

    .OUTPUTS
    Array of output directory paths
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputBaseDir,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    # Find all video files
    $videoExtensions = @("*.mp4", "*.MP4", "*.mov", "*.MOV", "*.avi", "*.AVI", "*.mkv", "*.MKV")
    $videoFiles = @()

    foreach ($ext in $videoExtensions) {
        $videoFiles += Get-ChildItem -Path $FolderPath -Filter $ext -File
    }

    if ($videoFiles.Count -eq 0) {
        Write-Host "No video files found in: $FolderPath" -ForegroundColor Yellow
        return @()
    }

    Write-Host "Found $($videoFiles.Count) video file(s) in: $FolderPath" -ForegroundColor Cyan

    # Create images base directory
    if (-not (Test-Path $OutputBaseDir)) {
        New-Item -ItemType Directory -Path $OutputBaseDir -Force | Out-Null
    }

    $outputDirs = @()

    foreach ($video in $videoFiles) {
        # Create subfolder named after video (e.g., video_W for DJI_xxx_W.MP4)
        $videoBaseName = [System.IO.Path]::GetFileNameWithoutExtension($video.Name)

        # Extract camera identifier (W or Z) from filename like DJI_xxx_W.MP4 or DJI_xxx_Z.MP4
        if ($videoBaseName -match '_([WZ])(-\d+)?$') {
            $subfolder = "video_$($Matches[1])"
        }
        else {
            # Fallback to full video name
            $subfolder = $videoBaseName
        }

        $outputDir = Join-Path $OutputBaseDir $subfolder

        Write-Host ""
        Write-Host "Processing video: $($video.Name) -> $subfolder/" -ForegroundColor White

        $result = Extract-VideoFrames -VideoPath $video.FullName -OutputDir $outputDir -Config $Config

        if ($result) {
            $outputDirs += $result
        }
    }

    return $outputDirs
}

function Get-VideoInfo {
    <#
    .SYNOPSIS
    Get basic information about a video file using FFprobe

    .PARAMETER VideoPath
    Path to the video file

    .PARAMETER Config
    Configuration object

    .OUTPUTS
    PSCustomObject with video information
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$VideoPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    $ffmpegDir = Split-Path -Parent $Config.paths.ffmpeg_exe
    $ffprobePath = Join-Path $ffmpegDir "ffprobe.exe"

    if (-not (Test-Path $ffprobePath)) {
        Write-Host "WARNING: FFprobe not found, cannot get video info" -ForegroundColor Yellow
        return $null
    }

    try {
        $output = & $ffprobePath -v quiet -show_entries stream=width,height,duration,r_frame_rate -of json $VideoPath 2>&1
        $info = $output | ConvertFrom-Json

        if ($info.streams -and $info.streams.Count -gt 0) {
            $stream = $info.streams[0]
            return [PSCustomObject]@{
                Width = $stream.width
                Height = $stream.height
                Duration = $stream.duration
                FrameRate = $stream.r_frame_rate
            }
        }
    }
    catch {
        Write-Host "WARNING: Could not parse video info: $_" -ForegroundColor Yellow
    }

    return $null
}

# Main execution when script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    $result = Extract-VideoFrames -VideoPath $VideoPath -OutputDir $OutputDir -Config $Config
    if ($result) {
        Write-Host "Frame extraction completed successfully" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "Frame extraction failed" -ForegroundColor Red
        exit 1
    }
}

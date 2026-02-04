# run_all_exhaustive.ps1
# Run exhaustive matching pipeline on all scenes with periodic visualization
#
# Usage:
#   .\run_all_exhaustive.ps1 -DataPath "C:\postshot_test_data"

param(
    [Parameter(Mandatory=$false)]
    [string]$DataPath = "C:\postshot_test_data",

    [Parameter(Mandatory=$false)]
    [switch]$ClearOutput,

    [Parameter(Mandatory=$false)]
    [int]$VisualizationIntervalMinutes = 10
)

$ErrorActionPreference = 'Stop'

# Import dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")

# Create timestamped log file in DataPath
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $DataPath "exhaustive_run_$timestamp.log"

function Write-Log {
    param([string]$Message)
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $logEntry
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
}

# Find all scene directories
$scenes = Get-ChildItem -LiteralPath $DataPath -Directory | Where-Object {
    # Check if it has video files
    $videos = Get-ChildItem -LiteralPath $_.FullName -File | Where-Object {
        $_.Extension -in @(".mp4", ".MP4", ".mov", ".MOV")
    }
    $videos.Count -gt 0
} | Sort-Object Name

Write-Log "=========================================="
Write-Log "Exhaustive Matching Pipeline - All Scenes"
Write-Log "=========================================="
Write-Log "Log file: $logFile"
Write-Log "Data path: $DataPath"
Write-Log "Clear output: $ClearOutput"
Write-Log "Visualization interval: $VisualizationIntervalMinutes min"
Write-Log "Found $($scenes.Count) scenes"

foreach ($scene in $scenes) {
    Write-Log "  - $($scene.Name)"
}

Write-Log ""

$results = @()
$startTime = Get-Date
$sceneNum = 0

foreach ($scene in $scenes) {
    $sceneNum++
    $sceneName = $scene.Name
    $sceneStart = Get-Date

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Scene $sceneNum/$($scenes.Count): $sceneName"
    Write-Log "=========================================="

    $outputDir = Join-Path $scene.FullName "output"

    # Clear output if requested
    if ($ClearOutput -and (Test-Path $outputDir)) {
        Write-Log "Clearing output directory: $outputDir"
        Remove-Item -LiteralPath $outputDir -Recurse -Force
    }

    Write-Log "Starting pipeline at $(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')"

    try {
        # Run the exhaustive pipeline
        $pipelineScript = Join-Path $scriptDir "run_pipeline_exhaustive.ps1"

        # Use call operator in same process to preserve Unicode path encoding
        $pipelineOutput = & $pipelineScript -InputPath $scene.FullName -VisualizationIntervalMinutes $VisualizationIntervalMinutes 2>&1
        $exitCode = $LASTEXITCODE

        # Log pipeline output
        $pipelineOutput | ForEach-Object { Add-Content -Path $logFile -Value $_ -Encoding UTF8 }

        $sceneEnd = Get-Date
        $sceneDuration = $sceneEnd - $sceneStart

        # Check results
        $pshtPath = Join-Path $outputDir "scene.psht"
        $plyPath = Join-Path $outputDir "scene.ply"
        $vizDir = Join-Path $outputDir "visualizations"

        # Check if any sparse reconstruction exists
        $sparseDir = Join-Path $outputDir "colmap_output\sparse"
        $hasSparse = $false
        if (Test-Path -LiteralPath $sparseDir) {
            $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory | Where-Object { $_.Name -match '^\d+$' }
            $hasSparse = ($reconFolders.Count -gt 0)
        }

        # Count visualizations
        $vizCount = 0
        if (Test-Path $vizDir) {
            $vizCount = (Get-ChildItem -LiteralPath $vizDir -File -Filter "*.png").Count
        }

        $result = [PSCustomObject]@{
            Scene = $sceneName
            Success = ($exitCode -eq 0)
            Duration = $sceneDuration.ToString('hh\:mm\:ss')
            HasSparse = $hasSparse
            HasPsht = (Test-Path $pshtPath)
            HasPly = (Test-Path $plyPath)
            Visualizations = $vizCount
        }
        $results += $result

        Write-Log "Scene $sceneNum completed in $($sceneDuration.ToString('hh\:mm\:ss'))"
        Write-Log "  Exit code: $exitCode"
        Write-Log "  Has sparse: $($result.HasSparse)"
        Write-Log "  Has PSHT: $($result.HasPsht)"
        Write-Log "  Has PLY: $($result.HasPly)"
        Write-Log "  Visualizations: $vizCount"
    }
    catch {
        Write-Log "ERROR: Scene $sceneNum failed with exception: $_"
        $results += [PSCustomObject]@{
            Scene = $sceneName
            Success = $false
            Duration = "N/A"
            HasSparse = $false
            HasPsht = $false
            HasPly = $false
            Visualizations = 0
        }
    }
}

$endTime = Get-Date
$totalDuration = $endTime - $startTime

Write-Log ""
Write-Log "=========================================="
Write-Log "All Scenes Complete"
Write-Log "=========================================="
Write-Log "Total duration: $($totalDuration.ToString('hh\:mm\:ss'))"
Write-Log ""
Write-Log "Results Summary:"
Write-Log ""

# Display results table
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_ }

# Save results to JSON in DataPath
$resultsFile = Join-Path $DataPath "exhaustive_results_$timestamp.json"
$results | ConvertTo-Json | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Log "Results saved to: $resultsFile"

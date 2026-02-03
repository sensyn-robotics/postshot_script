# Run all scenes with custom pair matching strategy
# This script runs the dual-camera pipeline on all scenes in the test data directory
#
# Usage: .\run_all_custom_pairs.ps1 [-DataPath <path>] [-ClearOutput]
#
# Parameters:
#   -DataPath: Path to directory containing scene folders (default: C:\postshot_test_data)
#   -ClearOutput: If specified, clears output directories before running

param(
    [Parameter(Mandatory=$false)]
    [string]$DataPath = "C:\postshot_test_data",

    [Parameter(Mandatory=$false)]
    [switch]$ClearOutput,

    [Parameter(Mandatory=$false)]
    [string]$LogDir = "C:\Postshot_Temp"
)

$ErrorActionPreference = 'Continue'
$startTime = Get-Date

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Get ALL scene directories
$scenes = @(Get-ChildItem $DataPath -Directory | Sort-Object Name | ForEach-Object { $_.FullName })

$logFile = Join-Path $LogDir "custom_pairs_run_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
}

Write-Log "=========================================="
Write-Log "Custom Pair Matching Pipeline - All Scenes"
Write-Log "=========================================="
Write-Log "Log file: $logFile"
Write-Log "Data path: $DataPath"
Write-Log "Clear output: $ClearOutput"
Write-Log "Found $($scenes.Count) scenes"
foreach ($s in $scenes) {
    Write-Log "  - $(Split-Path $s -Leaf)"
}
Write-Log ""

$results = @()

# Get script directory for relative paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pipelineScript = Join-Path $scriptDir "run_pipeline_dual_camera.ps1"

for ($i = 0; $i -lt $scenes.Count; $i++) {
    $scene = $scenes[$i]
    $sceneName = Split-Path $scene -Leaf
    $sceneNum = $i + 1

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Scene $sceneNum/$($scenes.Count): $sceneName"
    Write-Log "=========================================="

    # Optionally clear output directory
    $outputDir = Join-Path $scene "output"
    if ($ClearOutput -and (Test-Path $outputDir)) {
        Write-Log "Clearing output directory: $outputDir"
        Remove-Item $outputDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Run pipeline
    $sceneStart = Get-Date
    Write-Log "Starting pipeline at $sceneStart"

    try {
        # Use call operator in same process to preserve Unicode path encoding
        # (spawning new powershell.exe process corrupts Japanese characters)
        $pipelineOutput = & $pipelineScript -InputPath $scene -MatcherType "custom_pairs" -TemporalOverlap 10 2>&1
        $exitCode = $LASTEXITCODE

        # Log pipeline output
        $pipelineOutput | ForEach-Object { Add-Content -Path $logFile -Value $_ -Encoding UTF8 }

        $sceneEnd = Get-Date
        $sceneDuration = $sceneEnd - $sceneStart

        # Check results
        $pshtPath = Join-Path $outputDir "scene.psht"
        $plyPath = Join-Path $outputDir "scene.ply"
        $sparseDir = Join-Path $outputDir "colmap_output\sparse"

        # Check if any sparse reconstruction exists (0, 1, 2, ...)
        $hasSparse = $false
        if (Test-Path -LiteralPath $sparseDir) {
            $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory | Where-Object { $_.Name -match '^\d+$' }
            $hasSparse = ($reconFolders.Count -gt 0)
        }

        $result = [PSCustomObject]@{
            Scene = $sceneName
            Success = ($exitCode -eq 0)
            Duration = $sceneDuration.ToString('hh\:mm\:ss')
            HasSparse = $hasSparse
            HasPsht = (Test-Path $pshtPath)
            HasPly = (Test-Path $plyPath)
        }
        $results += $result

        Write-Log "Scene $sceneNum completed in $($sceneDuration.ToString('hh\:mm\:ss'))"
        Write-Log "  Exit code: $exitCode"
        Write-Log "  Has sparse: $($result.HasSparse)"
        Write-Log "  Has PSHT: $($result.HasPsht)"
        Write-Log "  Has PLY: $($result.HasPly)"
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
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_ }

# Save results to JSON
$resultsJson = $results | ConvertTo-Json
$resultsPath = Join-Path $LogDir "custom_pairs_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
Set-Content -Path $resultsPath -Value $resultsJson -Encoding UTF8
Write-Log "Results saved to: $resultsPath"

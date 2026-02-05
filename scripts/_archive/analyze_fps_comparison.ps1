# analyze_fps_comparison.ps1
# Compare optical flow statistics between different FPS settings
#
# This script analyzes frame quality and flow statistics to help determine
# the optimal FPS setting for video extraction.

param(
    [Parameter(Mandatory=$true)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [string[]]$OutputDirs = @("output", "output_0.2fps"),

    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  FPS Comparison Analysis" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Scene: $ScenePath" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Check scene path exists
if (-not (Test-Path -LiteralPath $ScenePath)) {
    Write-Host "ERROR: Scene path not found: $ScenePath" -ForegroundColor Red
    exit 1
}

$results = @()

foreach ($outputDir in $OutputDirs) {
    $imagesPath = Join-Path $ScenePath "$outputDir\images"

    if (-not (Test-Path -LiteralPath $imagesPath)) {
        Write-Host "Skipping $outputDir (not found)" -ForegroundColor Yellow
        continue
    }

    Write-Host ""
    Write-Host "--- Analyzing: $outputDir ---" -ForegroundColor Cyan

    # Count frames
    $wCount = 0
    $zCount = 0

    $wDir = Join-Path $imagesPath "video_W"
    $zDir = Join-Path $imagesPath "video_Z"

    if (Test-Path -LiteralPath $wDir) {
        $wCount = (Get-ChildItem -LiteralPath $wDir -File | Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg") }).Count
    }
    if (Test-Path -LiteralPath $zDir) {
        $zCount = (Get-ChildItem -LiteralPath $zDir -File | Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg") }).Count
    }

    $totalFrames = $wCount + $zCount
    Write-Host "  Frame count: $totalFrames (W: $wCount, Z: $zCount)" -ForegroundColor Gray

    # Run optical flow analysis
    $flowCsv = Join-Path $imagesPath "optical_flow_analysis.csv"

    if (-not (Test-Path $flowCsv)) {
        Write-Host "  Running optical flow analysis..." -ForegroundColor Gray
        $pythonScript = Join-Path $scriptDir "optical_flow_analyzer.py"
        $output = & python $pythonScript $imagesPath --analyze 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Optical flow analysis failed" -ForegroundColor Yellow
            continue
        }
    }

    # Parse flow statistics
    if (Test-Path $flowCsv) {
        $flowData = Import-Csv $flowCsv
        $meanFlows = $flowData | ForEach-Object { [double]$_.mean_flow }
        $overlaps = $flowData | ForEach-Object { [double]$_.estimated_overlap }

        $avgFlow = ($meanFlows | Measure-Object -Average).Average
        $maxFlow = ($meanFlows | Measure-Object -Maximum).Maximum
        $avgOverlap = ($overlaps | Measure-Object -Average).Average
        $minOverlap = ($overlaps | Measure-Object -Minimum).Minimum

        Write-Host "  Average flow:   $([math]::Round($avgFlow, 2)) px" -ForegroundColor Gray
        Write-Host "  Max flow:       $([math]::Round($maxFlow, 2)) px" -ForegroundColor Gray
        Write-Host "  Average overlap: $([math]::Round($avgOverlap, 1))%" -ForegroundColor Gray
        Write-Host "  Min overlap:    $([math]::Round($minOverlap, 1))%" -ForegroundColor Gray

        $results += [PSCustomObject]@{
            OutputDir = $outputDir
            TotalFrames = $totalFrames
            WFrames = $wCount
            ZFrames = $zCount
            AvgFlow = [math]::Round($avgFlow, 2)
            MaxFlow = [math]::Round($maxFlow, 2)
            AvgOverlap = [math]::Round($avgOverlap, 1)
            MinOverlap = [math]::Round($minOverlap, 1)
        }
    }

    # Run blur analysis
    $blurCsv = Join-Path $imagesPath "blur_analysis.csv"

    if (-not (Test-Path $blurCsv)) {
        Write-Host "  Running blur analysis..." -ForegroundColor Gray
        $pythonScript = Join-Path $scriptDir "blur_detector.py"
        $output = & python $pythonScript $imagesPath --analyze --auto-threshold 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Blur analysis failed" -ForegroundColor Yellow
        }
    }

    if (Test-Path $blurCsv) {
        $blurData = Import-Csv $blurCsv
        $blurredCount = ($blurData | Where-Object { $_.is_blurred -eq "True" }).Count
        $totalAnalyzed = $blurData.Count

        Write-Host "  Blurred frames: $blurredCount / $totalAnalyzed ($([math]::Round(100 * $blurredCount / $totalAnalyzed, 1))%)" -ForegroundColor Gray
    }

    # Check COLMAP output
    $colmapOutput = Join-Path $ScenePath "$outputDir\colmap_output\sparse"
    if (Test-Path $colmapOutput) {
        $reconDirs = Get-ChildItem -LiteralPath $colmapOutput -Directory
        if ($reconDirs.Count -gt 0) {
            Write-Host "  COLMAP reconstructions: $($reconDirs.Count)" -ForegroundColor Green
        } else {
            Write-Host "  COLMAP: No reconstructions" -ForegroundColor Yellow
        }
    }

    # Check Postshot output
    $pshtPath = Join-Path $ScenePath "$outputDir\scene.psht"
    $plyPath = Join-Path $ScenePath "$outputDir\scene.ply"

    if (Test-Path $pshtPath) {
        Write-Host "  Postshot PSHT: EXISTS" -ForegroundColor Green
    } else {
        Write-Host "  Postshot PSHT: NOT FOUND" -ForegroundColor Yellow
    }

    if (Test-Path $plyPath) {
        $plySize = [math]::Round((Get-Item $plyPath).Length / 1MB, 2)
        Write-Host "  Postshot PLY:  EXISTS ($plySize MB)" -ForegroundColor Green
    }
}

# Summary comparison
if ($results.Count -gt 1) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  Comparison Summary" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""

    $results | Format-Table -AutoSize

    # Recommendation
    Write-Host ""
    Write-Host "Interpretation:" -ForegroundColor Cyan
    Write-Host "  - Lower FPS = fewer frames = faster processing" -ForegroundColor Gray
    Write-Host "  - Higher overlap = better feature matching" -ForegroundColor Gray
    Write-Host "  - Optimal: ~50% overlap between consecutive frames" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Flow Thresholds:" -ForegroundColor Cyan
    Write-Host "  < 5 px:   Redundant frames (reduce FPS)" -ForegroundColor Gray
    Write-Host "  5-15 px:  Good for matching" -ForegroundColor Gray
    Write-Host "  15-30 px: High motion (may need higher FPS)" -ForegroundColor Gray
    Write-Host "  > 30 px:  Risk of tracking failure" -ForegroundColor Gray
}

if ($GenerateReport) {
    $reportPath = Join-Path $ScenePath "fps_comparison_report.txt"
    $results | Format-Table -AutoSize | Out-String | Set-Content $reportPath
    Write-Host ""
    Write-Host "Report saved to: $reportPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Analysis Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Magenta

exit 0

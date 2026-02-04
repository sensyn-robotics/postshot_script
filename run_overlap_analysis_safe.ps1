# Run optical flow overlap analysis with temp directory to avoid encoding issues
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Use Python 3.11 from saved path
$pythonPathFile = Join-Path $scriptDir "python_path.txt"
if (Test-Path $pythonPathFile) {
    $pythonExe = (Get-Content $pythonPathFile -First 1).Trim()
} else {
    $pythonExe = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
}

Write-Host "=== Optical Flow Overlap Analysis ===" -ForegroundColor Cyan
Write-Host "Using Python: $pythonExe"

# Find scene1
$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName
$imagesDir = Join-Path $scene1 "output\images"

Write-Host "Scene: $($scenes[0].Name)"
Write-Host "Images: $imagesDir"

# Check if images exist
if (-not (Test-Path -LiteralPath $imagesDir)) {
    Write-Host "ERROR: Images directory not found" -ForegroundColor Red
    exit 1
}

# Create temp directory with ASCII path
$tempDir = "C:\postshot_temp_analysis"
$tempImages = Join-Path $tempDir "images"

Write-Host ""
Write-Host "Copying images to temp directory for analysis..." -ForegroundColor Yellow
Write-Host "  Temp: $tempImages"

# Clean and create temp directory
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy images
Copy-Item -LiteralPath $imagesDir -Destination $tempImages -Recurse
Write-Host "  Copy complete"

# Count images
$wCount = (Get-ChildItem -LiteralPath (Join-Path $tempImages "video_W") -File -ErrorAction SilentlyContinue).Count
$zCount = (Get-ChildItem -LiteralPath (Join-Path $tempImages "video_Z") -File -ErrorAction SilentlyContinue).Count
Write-Host "  W frames: $wCount, Z frames: $zCount"

# Run analysis
Write-Host ""
Write-Host "Running optical flow analysis..." -ForegroundColor Yellow
Write-Host "This may take several minutes..."
Write-Host ""

$analyzerScript = Join-Path $scriptDir "scripts\optical_flow_analyzer.py"
$outputCsv = Join-Path $tempDir "optical_flow_analysis.csv"

$output = & $pythonExe $analyzerScript $tempImages --analyze --output-csv $outputCsv 2>&1
$exitCode = $LASTEXITCODE

# Display output
foreach ($line in $output) {
    Write-Host $line
}

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Analysis failed with exit code $exitCode" -ForegroundColor Red
    exit $exitCode
}

# Check results
if (Test-Path $outputCsv) {
    Write-Host ""
    Write-Host "=== Results ===" -ForegroundColor Cyan

    # Copy results back to original location
    $originalCsv = Join-Path $scene1 "output\optical_flow_analysis.csv"
    Copy-Item $outputCsv -Destination $originalCsv -Force
    Write-Host "Results saved to: $originalCsv" -ForegroundColor Green

    # Show summary
    $data = Import-Csv $outputCsv

    $wData = $data | Where-Object { $_.camera -eq 'W' }
    $zData = $data | Where-Object { $_.camera -eq 'Z' }

    Write-Host ""
    if ($wData -and $wData.Count -gt 0) {
        $wAvgFlow = ($wData | Measure-Object -Property mean_flow -Average).Average
        $wAvgOverlap = ($wData | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host "Camera W: avg_flow = $([math]::Round($wAvgFlow, 2))px, avg_overlap = $([math]::Round($wAvgOverlap, 1))%"
    }

    if ($zData -and $zData.Count -gt 0) {
        $zAvgFlow = ($zData | Measure-Object -Property mean_flow -Average).Average
        $zAvgOverlap = ($zData | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host "Camera Z: avg_flow = $([math]::Round($zAvgFlow, 2))px, avg_overlap = $([math]::Round($zAvgOverlap, 1))%"
    }

    $allData = @()
    if ($wData) { $allData += $wData }
    if ($zData) { $allData += $zData }

    if ($allData.Count -gt 0) {
        $overallOverlap = ($allData | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Overall average overlap: $([math]::Round($overallOverlap, 1))%" -ForegroundColor Green
        Write-Host "Recommended target overlap: $([math]::Round($overallOverlap, 0))%" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        # Save recommended value
        $recommendedFile = Join-Path $scene1 "output\recommended_overlap.txt"
        "$([math]::Round($overallOverlap, 0))" | Out-File -FilePath $recommendedFile -Encoding UTF8
        Write-Host ""
        Write-Host "Recommended value saved to: $recommendedFile"
    }
}

# Cleanup temp directory
Write-Host ""
Write-Host "Cleaning up temp directory..."
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done."

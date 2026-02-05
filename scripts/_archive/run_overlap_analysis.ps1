# Run optical flow overlap analysis
$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Use Python 3.11 from saved path
$pythonPathFile = Join-Path $scriptDir "python_path.txt"
if (Test-Path $pythonPathFile) {
    $pythonExe = (Get-Content $pythonPathFile -First 1).Trim()
} else {
    $pythonExe = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
}

if (-not (Test-Path $pythonExe)) {
    Write-Host "ERROR: Python not found at $pythonExe" -ForegroundColor Red
    exit 1
}

Write-Host "=== Optical Flow Overlap Analysis ===" -ForegroundColor Cyan

# Find scene1
$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene1 = $scenes[0].FullName
$imagesDir = Join-Path $scene1 "output\images"

Write-Host "Scene: $($scenes[0].Name)"
Write-Host "Images: $imagesDir"

# Check if images exist
if (-not (Test-Path $imagesDir)) {
    Write-Host "ERROR: Images directory not found" -ForegroundColor Red
    exit 1
}

# Run optical flow analyzer
$analyzerScript = Join-Path $scriptDir "scripts\optical_flow_analyzer.py"

Write-Host ""
Write-Host "Running optical flow analysis..." -ForegroundColor Yellow
Write-Host "This may take several minutes..."
Write-Host ""

$outputCsv = Join-Path $scene1 "output\optical_flow_analysis.csv"

# Run analysis
Write-Host "Using Python: $pythonExe"
$output = & $pythonExe $analyzerScript $imagesDir --analyze --output-csv $outputCsv 2>&1
$exitCode = $LASTEXITCODE

# Display output
foreach ($line in $output) {
    Write-Host $line
}

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Analysis failed with exit code $exitCode" -ForegroundColor Red
    Write-Host "Python may not have required dependencies (opencv-python, numpy)" -ForegroundColor Yellow
    exit $exitCode
}

# Check results
if (Test-Path $outputCsv) {
    Write-Host ""
    Write-Host "Results saved to: $outputCsv" -ForegroundColor Green

    # Show summary
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    $data = Import-Csv $outputCsv

    $wData = $data | Where-Object { $_.camera -eq 'W' }
    $zData = $data | Where-Object { $_.camera -eq 'Z' }

    if ($wData) {
        $wAvgFlow = ($wData | Measure-Object -Property mean_flow -Average).Average
        $wAvgOverlap = ($wData | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host "Camera W: avg_flow = $([math]::Round($wAvgFlow, 2))px, avg_overlap = $([math]::Round($wAvgOverlap, 1))%"
    }

    if ($zData) {
        $zAvgFlow = ($zData | Measure-Object -Property mean_flow -Average).Average
        $zAvgOverlap = ($zData | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host "Camera Z: avg_flow = $([math]::Round($zAvgFlow, 2))px, avg_overlap = $([math]::Round($zAvgOverlap, 1))%"
    }

    if ($wData -and $zData) {
        $overallOverlap = (($wData + $zData) | Measure-Object -Property estimated_overlap -Average).Average
        Write-Host ""
        Write-Host "Overall average overlap: $([math]::Round($overallOverlap, 1))%" -ForegroundColor Green
        Write-Host "Recommended target overlap: $([math]::Round($overallOverlap, 0))%" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done."

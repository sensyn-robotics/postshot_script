# run_tests.ps1
# Test script for COLMAP + Postshot pipeline using sakaigawa test data

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDataDir = "C:\Users\m-ogawa\tower\data\20260121_sakaigawa",

    [Parameter(Mandatory=$false)]
    [switch]$SkipProcessing,

    [Parameter(Mandatory=$false)]
    [switch]$CleanupFirst
)

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

# Test results tracking
$testResults = @()

function Write-TestHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor White
    Write-Host "  $Message" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor White
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )

    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Details) {
        Write-Host "       $Details" -ForegroundColor Gray
    }

    $script:testResults += [PSCustomObject]@{
        Name = $TestName
        Passed = $Passed
        Details = $Details
    }
}

function Test-DirectoryStructure {
    <#
    .SYNOPSIS
    Verify the expected output structure exists for a processed directory
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir,

        [Parameter(Mandatory=$true)]
        [string]$TestName
    )

    Write-Host "`nVerifying: $TestName" -ForegroundColor Cyan

    $allPassed = $true

    # Test 1: images/ directory with video_W and video_Z subfolders
    $imagesDir = Join-Path $ProjectDir "images"
    $videoW = Join-Path $imagesDir "video_W"
    $videoZ = Join-Path $imagesDir "video_Z"

    $imagesExist = (Test-Path $imagesDir)
    Write-TestResult -TestName "$TestName - images/ exists" -Passed $imagesExist
    $allPassed = $allPassed -and $imagesExist

    if ($imagesExist) {
        # Check for frames in video subfolders
        $videoWFrames = 0
        $videoZFrames = 0

        if (Test-Path $videoW) {
            $videoWFrames = (Get-ChildItem -Path $videoW -Filter "*.jpg").Count
        }
        if (Test-Path $videoZ) {
            $videoZFrames = (Get-ChildItem -Path $videoZ -Filter "*.jpg").Count
        }

        $hasFrames = ($videoWFrames -gt 0) -or ($videoZFrames -gt 0)
        Write-TestResult -TestName "$TestName - frames extracted" -Passed $hasFrames -Details "W: $videoWFrames frames, Z: $videoZFrames frames"
        $allPassed = $allPassed -and $hasFrames
    }

    # Test 2: colmap_output/ with sparse reconstruction
    $colmapOutput = Join-Path $ProjectDir "colmap_output"
    $sparseDir = Join-Path $colmapOutput "sparse\0"

    $colmapExists = (Test-Path $colmapOutput)
    Write-TestResult -TestName "$TestName - colmap_output/ exists" -Passed $colmapExists
    $allPassed = $allPassed -and $colmapExists

    if ($colmapExists) {
        $databasePath = Join-Path $colmapOutput "database.db"
        $dbExists = (Test-Path $databasePath)
        Write-TestResult -TestName "$TestName - database.db exists" -Passed $dbExists
        $allPassed = $allPassed -and $dbExists

        $sparseExists = (Test-Path $sparseDir)
        Write-TestResult -TestName "$TestName - sparse/0/ exists" -Passed $sparseExists
        $allPassed = $allPassed -and $sparseExists

        if ($sparseExists) {
            $camerasFile = Join-Path $sparseDir "cameras.bin"
            $imagesFile = Join-Path $sparseDir "images.bin"
            $pointsFile = Join-Path $sparseDir "points3D.bin"

            $camerasExist = (Test-Path $camerasFile)
            $imagesExist = (Test-Path $imagesFile)
            $pointsExist = (Test-Path $pointsFile)

            Write-TestResult -TestName "$TestName - cameras.bin exists" -Passed $camerasExist
            Write-TestResult -TestName "$TestName - images.bin exists" -Passed $imagesExist
            Write-TestResult -TestName "$TestName - points3D.bin exists" -Passed $pointsExist

            $allPassed = $allPassed -and $camerasExist -and $imagesExist -and $pointsExist
        }
    }

    # Test 3: Postshot outputs
    $pshtPath = Join-Path $ProjectDir "scene.psht"
    $plyPath = Join-Path $ProjectDir "scene.ply"

    $pshtExists = (Test-Path $pshtPath)
    Write-TestResult -TestName "$TestName - scene.psht exists" -Passed $pshtExists

    if ($pshtExists) {
        $pshtSize = (Get-Item $pshtPath).Length / 1MB
        $pshtSizeOk = ($pshtSize -gt 1)
        Write-TestResult -TestName "$TestName - scene.psht size > 1MB" -Passed $pshtSizeOk -Details "$('{0:N2}' -f $pshtSize) MB"
        $allPassed = $allPassed -and $pshtSizeOk
    }
    else {
        $allPassed = $false
    }

    $plyExists = (Test-Path $plyPath)
    Write-TestResult -TestName "$TestName - scene.ply exists" -Passed $plyExists

    if ($plyExists) {
        $plySize = (Get-Item $plyPath).Length / 1MB
        Write-TestResult -TestName "$TestName - scene.ply generated" -Passed $true -Details "$('{0:N2}' -f $plySize) MB"
    }
    else {
        $allPassed = $false
    }

    return $allPassed
}

function Clean-OutputFiles {
    <#
    .SYNOPSIS
    Remove generated output files from a project directory
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectDir
    )

    Write-Host "Cleaning output files in: $ProjectDir" -ForegroundColor Yellow

    $pathsToRemove = @(
        (Join-Path $ProjectDir "images"),
        (Join-Path $ProjectDir "colmap_output"),
        (Join-Path $ProjectDir "scene.psht"),
        (Join-Path $ProjectDir "scene.ply")
    )

    foreach ($path in $pathsToRemove) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Write-Host "  Removed: $path" -ForegroundColor Gray
        }
    }
}

# --- MAIN TEST EXECUTION ---

Write-Host ""
Write-Host "########################################" -ForegroundColor Magenta
Write-Host "#  Postshot Script - Test Runner      #" -ForegroundColor Magenta
Write-Host "########################################" -ForegroundColor Magenta
Write-Host ""
Write-Host "Test Data Directory: $TestDataDir" -ForegroundColor Cyan

# Verify test data directory exists
if (-not (Test-Path $TestDataDir)) {
    Write-Host "ERROR: Test data directory not found: $TestDataDir" -ForegroundColor Red
    exit 1
}

# Get all subdirectories (test cases)
$testCases = Get-ChildItem -Path $TestDataDir -Directory

if ($testCases.Count -eq 0) {
    Write-Host "ERROR: No test case directories found in: $TestDataDir" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($testCases.Count) test case(s):" -ForegroundColor Cyan
foreach ($tc in $testCases) {
    Write-Host "  - $($tc.Name)" -ForegroundColor Gray
}

# Cleanup if requested
if ($CleanupFirst) {
    Write-TestHeader "Cleaning Previous Output"
    foreach ($tc in $testCases) {
        Clean-OutputFiles -ProjectDir $tc.FullName
    }
}

# Process each test case
if (-not $SkipProcessing) {
    Write-TestHeader "Processing Test Cases"

    foreach ($tc in $testCases) {
        Write-Host ""
        Write-Host "Processing: $($tc.Name)" -ForegroundColor Yellow
        Write-Host ("-" * 50) -ForegroundColor Gray

        try {
            # Run the pipeline
            $pipelineScript = Join-Path $rootDir "scripts\run_pipeline.ps1"
            & $pipelineScript -InputPath $tc.FullName

            Write-Host "Processing completed for: $($tc.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR processing $($tc.Name): $_" -ForegroundColor Red
        }
    }
}

# Verify results
Write-TestHeader "Verification Results"

$allTestsPassed = $true
foreach ($tc in $testCases) {
    $passed = Test-DirectoryStructure -ProjectDir $tc.FullName -TestName $tc.Name
    $allTestsPassed = $allTestsPassed -and $passed
}

# Summary
Write-TestHeader "Test Summary"

$totalTests = $testResults.Count
$passedTests = ($testResults | Where-Object { $_.Passed }).Count
$failedTests = $totalTests - $passedTests

Write-Host ""
Write-Host "Total Tests:  $totalTests" -ForegroundColor Cyan
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failedTests -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
    }
}

Write-Host ""
if ($allTestsPassed) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}

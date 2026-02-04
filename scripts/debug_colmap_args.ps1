# Debug script to test COLMAP argument passing

$colmapExe = "C:\COLMAP\bin\colmap.exe"
$testDbPath = "C:\Postshot_Temp\test_args.db"
$testImgPath = "C:\Postshot_Temp\test_images"

# Create test directory structure
if (-not (Test-Path $testImgPath)) {
    New-Item -ItemType Directory -Path $testImgPath -Force | Out-Null
    New-Item -ItemType Directory -Path "$testImgPath\video_W" -Force | Out-Null
    New-Item -ItemType Directory -Path "$testImgPath\video_Z" -Force | Out-Null
}

# Remove old database
if (Test-Path $testDbPath) {
    Remove-Item $testDbPath -Force
}

Write-Host "=== Testing COLMAP Argument Passing ===" -ForegroundColor Cyan

# Build arguments like the script does
$colmapArgs = @(
    "feature_extractor",
    "--database_path", $testDbPath,
    "--image_path", $testImgPath,
    "--ImageReader.single_camera_per_folder=1",
    "--ImageReader.camera_model=OPENCV",
    "--SiftExtraction.max_num_features=8192"
)

Write-Host ""
Write-Host "Method 1: Start-Process with array" -ForegroundColor Yellow
Write-Host "Arguments array:"
$colmapArgs | ForEach-Object { Write-Host "  '$_'" }

Write-Host ""
Write-Host "Running with Start-Process..." -ForegroundColor Gray
$process = Start-Process -FilePath $colmapExe -ArgumentList $colmapArgs -NoNewWindow -Wait -PassThru
Write-Host "Exit code: $($process.ExitCode)"

# Check if database was created and has cameras
if (Test-Path $testDbPath) {
    Write-Host ""
    Write-Host "Database created. Checking cameras table..." -ForegroundColor Green

    # Try with direct call operator for comparison
    Remove-Item $testDbPath -Force

    Write-Host ""
    Write-Host "Method 2: Call operator (&) with array" -ForegroundColor Yellow
    & $colmapExe $colmapArgs
    Write-Host "Exit code: $LASTEXITCODE"

    if (Test-Path $testDbPath) {
        Write-Host "Database created with call operator too" -ForegroundColor Green
    }
}
else {
    Write-Host "Database NOT created - feature extractor may have failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Method 3: Join arguments as single string" -ForegroundColor Yellow
Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue

$argString = $colmapArgs -join ' '
Write-Host "Argument string: $argString"

$process2 = Start-Process -FilePath $colmapExe -ArgumentList $argString -NoNewWindow -Wait -PassThru
Write-Host "Exit code: $($process2.ExitCode)"

if (Test-Path $testDbPath) {
    Write-Host "Database created with joined string" -ForegroundColor Green
}
else {
    Write-Host "Database NOT created" -ForegroundColor Red
}

# Cleanup
Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue
Remove-Item $testImgPath -Recurse -Force -ErrorAction SilentlyContinue

# 04_colmap_matching.ps1
# Stage 4: COLMAP feature matching
#
# Input: output/colmap/database.db
# Output: database with matches

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath
)

$ErrorActionPreference = 'Stop'

# Load configuration
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Use ScenePath if provided, otherwise use config
if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    $ScenePath = $config.input.scene_path
}

if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    Write-Host "ERROR: ScenePath is required (via parameter or config)" -ForegroundColor Red
    exit 1
}

# Resolve paths
$outputDir = Join-Path $ScenePath $config.output.dir_name
$colmapDir = Join-Path $outputDir $config.output.colmap_subdir
$databasePath = Join-Path $colmapDir "database.db"
$colmapExe = $config.paths.colmap

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 4: COLMAP Feature Matching" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Database: $databasePath" -ForegroundColor White
Write-Host "  Matcher type: $($config.stage_04_matching.type)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate COLMAP
if (-not (Test-Path -LiteralPath $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at: $colmapExe" -ForegroundColor Red
    exit 1
}

# Validate database
if (-not (Test-Path -LiteralPath $databasePath)) {
    Write-Host "ERROR: Database not found: $databasePath" -ForegroundColor Red
    Write-Host "  Run stage 03 (feature extraction) first" -ForegroundColor Yellow
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check if sparse directory exists (indicates matching was already done)
$sparseDir = Join-Path $colmapDir "sparse"
if ((Test-Path -LiteralPath $sparseDir) -and -not $overwrite) {
    $reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }
    if ($reconFolders.Count -gt 0) {
        Write-Host "  Sparse reconstruction already exists" -ForegroundColor Yellow
        Write-Host "  Skipping matching (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Stage 4 Complete (skipped - reconstruction exists)" -ForegroundColor Green
        exit 0
    }
}

# Get COLMAP binary path
$colmapBin = if ($colmapExe -like "*.bat") {
    $colmapBinDir = Split-Path -Parent $colmapExe
    Join-Path $colmapBinDir "bin\colmap.exe"
} else {
    $colmapExe
}

# Set up COLMAP environment
$colmapRootDir = if ($colmapExe -like "*.bat") {
    Split-Path -Parent $colmapExe
} else {
    Split-Path -Parent (Split-Path -Parent $colmapExe)
}

$env:PATH = "$(Join-Path $colmapRootDir 'bin');$env:PATH"
$env:QT_PLUGIN_PATH = Join-Path $colmapRootDir "plugins"

# Build matching arguments based on type
$matcherType = $config.stage_04_matching.type
$matcherCommand = "${matcherType}_matcher"

$colmapArgs = @(
    $matcherCommand,
    "--database_path", $databasePath
)

Write-Host ""
Write-Host "  Running $matcherType matching..." -ForegroundColor Cyan
Write-Host "  Command: colmap $($colmapArgs -join ' ')" -ForegroundColor DarkGray

$startTime = Get-Date

$process = Start-Process -FilePath $colmapBin `
    -ArgumentList $colmapArgs `
    -NoNewWindow -Wait -PassThru

$duration = (Get-Date) - $startTime

if ($process.ExitCode -ne 0) {
    Write-Host "ERROR: Feature matching failed with exit code $($process.ExitCode)" -ForegroundColor Red
    exit 1
}

$dbSize = (Get-Item -LiteralPath $databasePath).Length / 1MB

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Stage 4 Complete" -ForegroundColor Green
Write-Host "  Database size: $('{0:N2}' -f $dbSize) MB" -ForegroundColor White
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

exit 0

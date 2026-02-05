<#
.SYNOPSIS
Merge multiple COLMAP reconstructions into one.

.DESCRIPTION
Uses COLMAP model_merger to combine separate reconstructions that couldn't
be merged during the initial mapping process.

.PARAMETER SparsePath
Path to sparse directory containing numbered reconstruction folders

.PARAMETER OutputPath
Path to output merged reconstruction
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SparsePath,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# COLMAP executable
$colmapExe = "C:\COLMAP\bin\colmap.exe"
if (-not (Test-Path $colmapExe)) {
    Write-Host "ERROR: COLMAP not found at $colmapExe" -ForegroundColor Red
    exit 1
}

# Default output path
if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $SparsePath) "sparse_merged"
}

Write-Host ""
Write-Host "=== COLMAP Model Merger ===" -ForegroundColor Cyan
Write-Host "Input: $SparsePath" -ForegroundColor Yellow
Write-Host "Output: $OutputPath" -ForegroundColor Yellow
Write-Host ""

# Check for reconstruction folders
$reconFolders = @(Get-ChildItem -LiteralPath $SparsePath -Directory | Where-Object { $_.Name -match '^\d+$' } | Sort-Object Name)

if ($reconFolders.Count -lt 2) {
    Write-Host "ERROR: Need at least 2 reconstructions to merge" -ForegroundColor Red
    Write-Host "Found: $($reconFolders.Count) reconstruction(s)" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($reconFolders.Count) reconstructions to merge" -ForegroundColor Green
foreach ($recon in $reconFolders) {
    Write-Host "  $($recon.Name): $($recon.FullName)" -ForegroundColor Gray
}

# Create output directory
if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Start with the first reconstruction
$currentInput = $reconFolders[0].FullName
Write-Host ""
Write-Host "Starting merge from: $currentInput" -ForegroundColor Yellow

# Merge remaining reconstructions one by one
for ($i = 1; $i -lt $reconFolders.Count; $i++) {
    $nextRecon = $reconFolders[$i].FullName
    $tempOutput = Join-Path $OutputPath "temp_merge_$i"

    Write-Host ""
    Write-Host "Merging reconstruction ${i}: $nextRecon" -ForegroundColor Cyan

    # Create temp output
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null

    $mergeArgs = @(
        "model_merger",
        "--input_path1", $currentInput,
        "--input_path2", $nextRecon,
        "--output_path", $tempOutput
    )

    Write-Host "Running: colmap $($mergeArgs -join ' ')" -ForegroundColor DarkGray

    $process = Start-Process -FilePath $colmapExe -ArgumentList $mergeArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "WARNING: Merge failed for reconstruction ${i}" -ForegroundColor Yellow
        Write-Host "Continuing with previous result..." -ForegroundColor Yellow
        continue
    }

    # Check if merge produced output
    $outputImages = Join-Path $tempOutput "images.bin"
    if (Test-Path -LiteralPath $outputImages) {
        $currentInput = $tempOutput
        Write-Host "Merge successful" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Merge did not produce output" -ForegroundColor Yellow
    }
}

# Copy final result to output
$finalOutput = Join-Path $OutputPath "0"
if (Test-Path -LiteralPath $finalOutput) {
    Remove-Item -LiteralPath $finalOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $finalOutput -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $currentInput "*") -Destination $finalOutput -Recurse

Write-Host ""
Write-Host "=== Merge Complete ===" -ForegroundColor Green
Write-Host "Final reconstruction: $finalOutput" -ForegroundColor Cyan

# Clean up temp folders
Get-ChildItem -LiteralPath $OutputPath -Directory -Filter "temp_merge_*" | Remove-Item -Recurse -Force

# Analyze result
$pythonPath = "C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe"
if (Test-Path $pythonPath) {
    Write-Host ""
    Write-Host "Analyzing merged reconstruction..." -ForegroundColor Cyan
    & $pythonPath "C:\postshot_script\scripts\read_colmap_model.py" $finalOutput
}

# Test different COLMAP configurations to find what works best
param(
    [Parameter(Mandatory=$false)]
    [int]$SceneNumber = 1,

    [Parameter(Mandatory=$false)]
    [string]$ConfigName = "all"
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  COLMAP Configuration Test" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# Find scene
$testDataPath = "C:\postshot_test_data"
$scenes = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
$scene = $scenes[$SceneNumber - 1]
$scenePath = $scene.FullName

Write-Host "Scene: $($scene.Name)"
Write-Host ""

# Configurations to test
$configs = @(
    @{
        Name = "sequential"
        Config = "config\config_improved_colmap.json"
        OutputDir = "output_sequential"
        Description = "Sequential matcher + SIMPLE_RADIAL + relaxed settings"
    },
    @{
        Name = "hierarchical"
        Config = "config\config_hierarchical.json"
        OutputDir = "output_hierarchical"
        Description = "Hierarchical mapper + exhaustive matching"
    }
)

# Filter if specific config requested
if ($ConfigName -ne "all") {
    $configs = $configs | Where-Object { $_.Name -eq $ConfigName }
}

$results = @()

foreach ($cfg in $configs) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Testing: $($cfg.Name)" -ForegroundColor Cyan
    Write-Host "  $($cfg.Description)" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan

    $outputPath = Join-Path $scenePath $cfg.OutputDir
    $pshtPath = Join-Path $outputPath "scene.psht"

    # Skip if already done
    if (Test-Path $pshtPath) {
        Write-Host "Already complete, skipping..." -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Config = $cfg.Name
            Status = "SKIPPED"
            RegisteredImages = "?"
            Points3D = "?"
        }
        continue
    }

    $startTime = Get-Date

    try {
        & "$scriptDir\scripts\run_pipeline_exhaustive.ps1" `
            -InputPath $scenePath `
            -ConfigPath (Join-Path $scriptDir $cfg.Config) `
            -OutputDir $cfg.OutputDir

        $exitCode = $LASTEXITCODE
        $endTime = Get-Date
        $duration = $endTime - $startTime

        # Check registration quality
        $sparsePath = Join-Path $outputPath "colmap_output\sparse\0"
        $registeredImages = 0
        $points3D = 0

        if (Test-Path (Join-Path $sparsePath "images.bin")) {
            # Quick estimate from file size
            $imgSize = (Get-Item (Join-Path $sparsePath "images.bin")).Length
            $registeredImages = [math]::Round($imgSize / 1600)  # Rough estimate
        }

        if (Test-Path (Join-Path $sparsePath "points3D.bin")) {
            $ptSize = (Get-Item (Join-Path $sparsePath "points3D.bin")).Length
            $points3D = [math]::Round($ptSize / 65)  # Rough estimate
        }

        $status = if ($exitCode -eq 0 -and (Test-Path $pshtPath)) { "SUCCESS" } else { "FAILED" }

        Write-Host ""
        Write-Host "Result: $status" -ForegroundColor $(if ($status -eq "SUCCESS") { "Green" } else { "Red" })
        Write-Host "  Registered images (est): $registeredImages"
        Write-Host "  3D points (est): $points3D"
        Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))"

        $results += [PSCustomObject]@{
            Config = $cfg.Name
            Status = $status
            RegisteredImages = $registeredImages
            Points3D = $points3D
            Duration = $duration.ToString('hh\:mm\:ss')
        }
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Config = $cfg.Name
            Status = "ERROR"
            RegisteredImages = 0
            Points3D = 0
        }
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Summary" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Best result has highest RegisteredImages and Points3D"

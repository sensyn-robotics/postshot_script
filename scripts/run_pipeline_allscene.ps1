# run_pipeline_allscene.ps1
# Main pipeline runner that orchestrates all stages
# Can process a single scene or all scenes in test_data_path
#
# Usage:
#   .\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json                    # Process all scenes
#   .\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -ScenePath C:\path # Process single scene
#   .\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -StartStage 3 -EndStage 5

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath,

    [Parameter(Mandatory=$false)]
    [string]$ScenePath,

    [Parameter(Mandatory=$false)]
    [int]$StartStage = 1,

    [Parameter(Mandatory=$false)]
    [int]$EndStage = 7
)

$ErrorActionPreference = 'Stop'

# Resolve config path
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "..\$ConfigPath"
}
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

# Load configuration
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "ERROR: Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Stage definitions
$stages = @(
    @{ Number = 1; Name = "01_extract_frames.ps1"; Description = "Frame Extraction" },
    @{ Number = 2; Name = "02_filter_frames.ps1"; Description = "Frame Filtering" },
    @{ Number = 3; Name = "03_colmap_features.ps1"; Description = "COLMAP Features" },
    @{ Number = 4; Name = "04_colmap_matching.ps1"; Description = "COLMAP Matching" },
    @{ Number = 5; Name = "05_colmap_mapper.ps1"; Description = "COLMAP Mapper" },
    @{ Number = 6; Name = "06_postshot_train.ps1"; Description = "Postshot Training" },
    @{ Number = 7; Name = "07_postshot_export.ps1"; Description = "Postshot Export" }
)

# Function to run pipeline for a single scene
function Run-PipelineForScene {
    param(
        [string]$ScenePath,
        [string]$ConfigPath,
        [int]$StartStage,
        [int]$EndStage
    )

    $sceneName = Split-Path -Leaf $ScenePath

    # Print header
    Write-Host ""
    Write-Host "########################################################" -ForegroundColor Magenta
    Write-Host "#                                                      #" -ForegroundColor Magenta
    Write-Host "#       Modular 3DGS Pipeline Runner                   #" -ForegroundColor Magenta
    Write-Host "#                                                      #" -ForegroundColor Magenta
    Write-Host "########################################################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Config: $ConfigPath" -ForegroundColor White
    Write-Host "  Scene:  $ScenePath" -ForegroundColor White
    Write-Host "  Stages: $StartStage to $EndStage" -ForegroundColor White
    Write-Host ""

    # Check if scene is already complete (has PSHT file)
    $outputDir = Join-Path $ScenePath $config.output.dir_name
    $postshotDir = Join-Path $outputDir $config.output.postshot_subdir
    $pshtPath = Join-Path $postshotDir "scene.psht"
    $plyPath = Join-Path $postshotDir "scene.ply"

    # Check overwrite setting
    $overwrite = $false
    if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
        $overwrite = $config.pipeline.overwrite_result
    }

    if ((Test-Path -LiteralPath $pshtPath) -and -not $overwrite) {
        $pshtSize = (Get-Item -LiteralPath $pshtPath).Length / 1MB
        Write-Host "  Scene already complete!" -ForegroundColor Green
        Write-Host "    PSHT: $pshtPath ($('{0:N2}' -f $pshtSize) MB)" -ForegroundColor White
        if (Test-Path -LiteralPath $plyPath) {
            $plySize = (Get-Item -LiteralPath $plyPath).Length / 1MB
            Write-Host "    PLY:  $plyPath ($('{0:N2}' -f $plySize) MB)" -ForegroundColor White
        }
        Write-Host "  Skipping (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        return $true
    }

    # Print stage plan
    Write-Host "--- Stage Plan ---" -ForegroundColor Yellow
    for ($i = 1; $i -le 7; $i++) {
        $stage = $stages[$i - 1]
        $status = if ($i -lt $StartStage -or $i -gt $EndStage) {
            "[SKIP]"
        } elseif ($i -eq 2 -and -not $config.stage_02_filter.enabled) {
            "[SKIP - disabled]"
        } else {
            "[RUN]"
        }
        $color = if ($status -eq "[RUN]") { "Green" } else { "DarkGray" }
        Write-Host "  Stage $i : $($stage.Description) $status" -ForegroundColor $color
    }
    Write-Host ""

    $sceneStartTime = Get-Date
    $stagesDir = Join-Path $PSScriptRoot "stages"

    # Save pipeline config to output directory
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $savedConfigPath = Join-Path $outputDir "pipeline_config.json"
    Copy-Item -LiteralPath $ConfigPath -Destination $savedConfigPath -Force
    Write-Host "  Config saved to: $savedConfigPath" -ForegroundColor DarkGray

    # Run stages
    for ($i = $StartStage; $i -le $EndStage; $i++) {
        $stage = $stages[$i - 1]

        # Check if stage 2 is disabled
        if ($i -eq 2 -and -not $config.stage_02_filter.enabled) {
            Write-Host ""
            Write-Host ">>> Stage $i : $($stage.Description) - SKIPPED (disabled in config)" -ForegroundColor DarkGray
            continue
        }

        Write-Host ""
        Write-Host "########################################################" -ForegroundColor Cyan
        Write-Host ">>> Stage $i : $($stage.Description)" -ForegroundColor Cyan
        Write-Host "########################################################" -ForegroundColor Cyan

        $stageScript = Join-Path $stagesDir $stage.Name

        if (-not (Test-Path -LiteralPath $stageScript)) {
            Write-Host "ERROR: Stage script not found: $stageScript" -ForegroundColor Red
            return $false
        }

        $stageStartTime = Get-Date

        # Run stage script using call operator (&) to avoid dot-sourcing issues
        & $stageScript -ConfigPath $ConfigPath -ScenePath $ScenePath

        $stageExitCode = $LASTEXITCODE
        $stageDuration = (Get-Date) - $stageStartTime

        if ($stageExitCode -ne 0) {
            Write-Host ""
            Write-Host "########################################################" -ForegroundColor Red
            Write-Host "!!! Stage $i FAILED with exit code $stageExitCode" -ForegroundColor Red
            Write-Host "########################################################" -ForegroundColor Red
            return $false
        }

        Write-Host ">>> Stage $i completed in $($stageDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
    }

    # Scene Summary
    $sceneDuration = (Get-Date) - $sceneStartTime

    Write-Host ""
    Write-Host "########################################################" -ForegroundColor Green
    Write-Host "#       Scene Complete: $sceneName" -ForegroundColor Green
    Write-Host "########################################################" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Duration: $($sceneDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White

    # Show output files
    Write-Host "  Output files:" -ForegroundColor Cyan
    if (Test-Path -LiteralPath $pshtPath) {
        $pshtSize = (Get-Item -LiteralPath $pshtPath).Length / 1MB
        Write-Host "    PSHT: $pshtPath ($('{0:N2}' -f $pshtSize) MB)" -ForegroundColor White
    }
    if (Test-Path -LiteralPath $plyPath) {
        $plySize = (Get-Item -LiteralPath $plyPath).Length / 1MB
        Write-Host "    PLY:  $plyPath ($('{0:N2}' -f $plySize) MB)" -ForegroundColor White
    }

    Write-Host ""
    return $true
}

# Main execution
$totalStartTime = Get-Date
$scenesToProcess = @()

# Determine scenes to process
if ([string]::IsNullOrWhiteSpace($ScenePath)) {
    # No ScenePath provided - process all scenes from test_data_path
    $testDataPath = $null
    if ($config.pipeline -and $config.pipeline.PSObject.Properties['test_data_path']) {
        $testDataPath = $config.pipeline.test_data_path
    }

    if ([string]::IsNullOrWhiteSpace($testDataPath)) {
        # Fallback to config.input.scene_path
        if (-not [string]::IsNullOrWhiteSpace($config.input.scene_path)) {
            $scenesToProcess = @($config.input.scene_path)
        } else {
            Write-Host "ERROR: No ScenePath provided and no test_data_path in config" -ForegroundColor Red
            exit 1
        }
    } else {
        if (-not (Test-Path -LiteralPath $testDataPath)) {
            Write-Host "ERROR: test_data_path not found: $testDataPath" -ForegroundColor Red
            exit 1
        }

        # Get all scene directories
        $sceneFolders = Get-ChildItem -LiteralPath $testDataPath -Directory | Sort-Object Name
        if ($sceneFolders.Count -eq 0) {
            Write-Host "ERROR: No scene folders found in: $testDataPath" -ForegroundColor Red
            exit 1
        }

        $scenesToProcess = $sceneFolders | ForEach-Object { $_.FullName }

        Write-Host ""
        Write-Host "########################################################" -ForegroundColor Magenta
        Write-Host "#       Processing ALL SCENES                          #" -ForegroundColor Magenta
        Write-Host "########################################################" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  Test data path: $testDataPath" -ForegroundColor White
        Write-Host "  Found $($scenesToProcess.Count) scene(s):" -ForegroundColor White
        foreach ($scene in $scenesToProcess) {
            $sceneName = Split-Path -Leaf $scene
            Write-Host "    - $sceneName" -ForegroundColor Cyan
        }
        Write-Host ""
    }
} else {
    # Single scene mode
    if (-not (Test-Path -LiteralPath $ScenePath)) {
        Write-Host "ERROR: Scene path not found: $ScenePath" -ForegroundColor Red
        exit 1
    }
    $scenesToProcess = @($ScenePath)
}

# Process each scene
$successCount = 0
$failCount = 0
$skipCount = 0

foreach ($scene in $scenesToProcess) {
    $result = Run-PipelineForScene -ScenePath $scene -ConfigPath $ConfigPath -StartStage $StartStage -EndStage $EndStage

    if ($result -eq $true) {
        # Check if it was skipped or completed
        $outputDir = Join-Path $scene $config.output.dir_name
        $postshotDir = Join-Path $outputDir $config.output.postshot_subdir
        $pshtPath = Join-Path $postshotDir "scene.psht"
        if (Test-Path -LiteralPath $pshtPath) {
            $successCount++
        }
    } else {
        $failCount++
        Write-Host "WARNING: Scene failed, continuing with next scene..." -ForegroundColor Yellow
    }
}

# Final summary
$totalDuration = (Get-Date) - $totalStartTime

Write-Host ""
Write-Host "########################################################" -ForegroundColor Green
Write-Host "#                                                      #" -ForegroundColor Green
Write-Host "#       ALL SCENES COMPLETE                            #" -ForegroundColor Green
Write-Host "#                                                      #" -ForegroundColor Green
Write-Host "########################################################" -ForegroundColor Green
Write-Host ""
Write-Host "  Total scenes: $($scenesToProcess.Count)" -ForegroundColor White
Write-Host "  Successful:   $successCount" -ForegroundColor Green
Write-Host "  Failed:       $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
Write-Host "  Total time:   $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host ""
Write-Host "########################################################" -ForegroundColor Green

if ($failCount -gt 0) {
    exit 1
}
exit 0

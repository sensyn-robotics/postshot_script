# 06_postshot_train.ps1
# Stage 6: Postshot 3DGS training with visualization
#
# Input: output/images/ + output/colmap/sparse/0/
# Output: output/postshot/scene.psht + visualizations

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
$imagesDir = Join-Path $outputDir $config.output.images_subdir
$colmapDir = Join-Path $outputDir $config.output.colmap_subdir
$sparseDir = Join-Path $colmapDir "sparse"
$postshotDir = Join-Path $outputDir $config.output.postshot_subdir
$pshtPath = Join-Path $postshotDir "scene.psht"
$plyPath = Join-Path $postshotDir "scene.ply"
$vizDir = Join-Path $outputDir $config.output.visualizations_subdir
$postshotCli = $config.paths.postshot_cli
$pythonExe = $config.paths.python
$tempDir = $config.paths.temp
$scriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Determine train_camera setting (default: "all" for backward compat)
$trainCamera = "all"
if ($config.stage_06_train -and $config.stage_06_train.PSObject.Properties['train_camera']) {
    $trainCamera = $config.stage_06_train.train_camera
}

# Set up training images directory (may be overridden by junction)
$trainImagesDir = $imagesDir
$junctionDir = $null  # Will be set if we create a junction

if ($trainCamera -ne "all") {
    $cameraFolder = "video_$trainCamera"
    $cameraSourceDir = Join-Path $imagesDir $cameraFolder

    if (-not (Test-Path -LiteralPath $cameraSourceDir)) {
        Write-Host "ERROR: Camera folder not found: $cameraSourceDir" -ForegroundColor Red
        exit 1
    }

    # Create temporary junction directory for Z-only training
    $junctionDir = Join-Path $outputDir "images_${trainCamera}_train"

    # Clean up any leftover junction from a previous run
    if (Test-Path -LiteralPath $junctionDir) {
        # Remove junction subdir first, then the parent
        $existingJunction = Join-Path $junctionDir $cameraFolder
        if (Test-Path -LiteralPath $existingJunction) {
            [System.IO.Directory]::Delete($existingJunction)
        }
        Remove-Item -LiteralPath $junctionDir -Force -Recurse -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $junctionDir -Force | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $junctionDir $cameraFolder) -Target $cameraSourceDir | Out-Null

    $trainImagesDir = $junctionDir
    Write-Host "  Train camera: $trainCamera only (junction created)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 6: Postshot Training" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Images: $trainImagesDir$(if ($trainCamera -ne 'all') { " ($trainCamera camera only)" })" -ForegroundColor White
Write-Host "  COLMAP sparse: $sparseDir" -ForegroundColor White
Write-Host "  Output: $pshtPath" -ForegroundColor White

# Show checkpoints if configured
if ($config.stage_06_train -and $config.stage_06_train.checkpoints) {
    $checkpoints = $config.stage_06_train.checkpoints
    Write-Host "  Checkpoints: $($checkpoints -join ', ')" -ForegroundColor White
}

Write-Host "========================================" -ForegroundColor Cyan

# Validate Postshot CLI
if (-not (Test-Path -LiteralPath $postshotCli)) {
    Write-Host "ERROR: Postshot CLI not found at: $postshotCli" -ForegroundColor Red
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check for existing .psht file
if (Test-Path -LiteralPath $pshtPath) {
    if ($overwrite) {
        Write-Host "  Deleting existing PSHT (overwrite_result=true)..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $pshtPath -Force
    } else {
        $fileSize = (Get-Item -LiteralPath $pshtPath).Length / 1MB
        Write-Host "  Found existing PSHT: $pshtPath ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Yellow
        Write-Host "  Skipping training (overwrite_result=false)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Stage 6 Complete (skipped - model exists)" -ForegroundColor Green
        exit 0
    }
}

# Find best sparse reconstruction
$reconFolders = Get-ChildItem -LiteralPath $sparseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' }

if ($reconFolders.Count -eq 0) {
    Write-Host "ERROR: No sparse reconstruction found in: $sparseDir" -ForegroundColor Red
    Write-Host "  Run stages 03-05 first" -ForegroundColor Yellow
    exit 1
}

# Find largest reconstruction
$sparsePath = $null
$largestSize = 0

foreach ($recon in $reconFolders) {
    $imagesBin = Join-Path $recon.FullName "images.bin"
    if (Test-Path -LiteralPath $imagesBin) {
        $size = (Get-Item -LiteralPath $imagesBin).Length
        if ($size -gt $largestSize) {
            $largestSize = $size
            $sparsePath = $recon.FullName
        }
    }
}

if (-not $sparsePath) {
    Write-Host "ERROR: No valid sparse reconstruction found" -ForegroundColor Red
    exit 1
}

Write-Host "  Using sparse model: $sparsePath" -ForegroundColor Cyan

# Clean non-image files from images directory (Postshot chokes on CSV/TXT files)
# NOTE: Do NOT move blurred/skipped subdirectories - COLMAP indexed images in them
$nonImageFiles = Get-ChildItem -LiteralPath $trainImagesDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -notin @('.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG') }
if ($nonImageFiles.Count -gt 0) {
    $artifactsDir = Join-Path $outputDir "filter_artifacts"
    if (-not (Test-Path -LiteralPath $artifactsDir)) {
        New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
    }
    foreach ($f in $nonImageFiles) {
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $artifactsDir $f.Name) -Force
        Write-Host "  Moved artifact: $($f.Name) -> filter_artifacts/" -ForegroundColor DarkGray
    }
}

# Create output directories
if (-not (Test-Path -LiteralPath $postshotDir)) {
    New-Item -ItemType Directory -Path $postshotDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $vizDir)) {
    New-Item -ItemType Directory -Path $vizDir -Force | Out-Null
}

# Set temp directory to avoid path issues
$env:TEMP = $tempDir
$env:TMP = $tempDir
if (-not (Test-Path -LiteralPath $env:TEMP)) {
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
}

# Credential management
$CredentialDir = "$env:APPDATA\PostshotScript"
$CredentialFile = "$CredentialDir\postshot_creds.xml"

function Get-PostshotCredentials {
    if (-not (Test-Path $CredentialFile)) {
        Write-Host "Postshot credentials not found. Let's set them up." -ForegroundColor Yellow
        Write-Host "Please enter your Postshot.com credentials"
        $UserName = Read-Host -Prompt "  Email"
        $Password = Read-Host -Prompt "  Password" -AsSecureString

        $Cred = New-Object System.Management.Automation.PSCredential($UserName, $Password)

        if (-not (Test-Path $CredentialDir)) {
            New-Item -ItemType Directory -Path $CredentialDir | Out-Null
        }

        $Cred | Export-CliXml -Path $CredentialFile
        Write-Host "Credentials saved." -ForegroundColor Green
        return $Cred
    }
    else {
        $Cred = Import-CliXml -Path $CredentialFile
        Write-Host "  Loaded credentials for: $($Cred.UserName)" -ForegroundColor Cyan
        return $Cred
    }
}

# Get credentials
$Cred = Get-PostshotCredentials

# Convert password
$MarshalType = [System.Runtime.InteropServices.Marshal]
$BSTR = $MarshalType::SecureStringToBSTR($Cred.Password)
$PlainTextPassword = $MarshalType::PtrToStringAuto($BSTR)

try {
    # Read quality parameters from config (with defaults)
    $antiAliasing = $true
    $trainStepsLimit = 0  # 0 = auto (let Postshot decide based on image count)
    $maxNumFeatures = 16
    $maxShDegree = 3
    $maxImageSize = 3840
    $showTrainError = $true

    if ($config.stage_06_train) {
        $tc = $config.stage_06_train
        if ($tc.PSObject.Properties['anti_aliasing']) { $antiAliasing = $tc.anti_aliasing }
        if ($tc.PSObject.Properties['train_steps_limit']) { $trainStepsLimit = $tc.train_steps_limit }
        if ($tc.PSObject.Properties['max_num_features']) { $maxNumFeatures = $tc.max_num_features }
        if ($tc.PSObject.Properties['max_sh_degree']) { $maxShDegree = $tc.max_sh_degree }
        if ($tc.PSObject.Properties['max_image_size']) { $maxImageSize = $tc.max_image_size }
        if ($tc.PSObject.Properties['show_train_error']) { $showTrainError = $tc.show_train_error }
    }

    Write-Host ""
    Write-Host "  Quality settings:" -ForegroundColor Cyan
    Write-Host "    anti-aliasing:     $antiAliasing" -ForegroundColor White
    Write-Host "    train-steps-limit: $(if ($trainStepsLimit -gt 0) { "${trainStepsLimit}k steps" } else { 'auto' })" -ForegroundColor White
    Write-Host "    max-num-features:  ${maxNumFeatures}k" -ForegroundColor White
    Write-Host "    max-sh-degree:     $maxShDegree" -ForegroundColor White
    Write-Host "    max-image-size:    $maxImageSize px" -ForegroundColor White
    Write-Host "    show-train-error:  $showTrainError" -ForegroundColor White

    # OOM fallback levels (progressively reduce memory usage)
    $fallbackLevels = @(
        @{ max_image_size = $maxImageSize; max_num_features = $maxNumFeatures; train_steps_limit = $trainStepsLimit },
        @{ max_image_size = 2560; max_num_features = $maxNumFeatures; train_steps_limit = $trainStepsLimit },
        @{ max_image_size = 2560; max_num_features = 8; train_steps_limit = $trainStepsLimit },
        @{ max_image_size = 1920; max_num_features = 8; train_steps_limit = 40 }
    )

    $trainLogFile = Join-Path $postshotDir "train_output.log"
    $trainSuccess = $false
    $trainOutputText = ""
    $usedSettings = $null
    $startTime = Get-Date
    $duration = $null

    for ($attempt = 0; $attempt -lt $fallbackLevels.Count; $attempt++) {
        $settings = $fallbackLevels[$attempt]

        if ($attempt -gt 0) {
            Write-Host ""
            $stepsInfo = if ($settings.train_steps_limit -gt 0) { "train_steps_limit=$($settings.train_steps_limit)k" } else { "train_steps_limit=auto" }
            Write-Host "  OOM fallback attempt $($attempt + 1)/4: max_image_size=$($settings.max_image_size), max_num_features=$($settings.max_num_features)k, $stepsInfo" -ForegroundColor Yellow
            if (Test-Path -LiteralPath $pshtPath) {
                Remove-Item -LiteralPath $pshtPath -Force -ErrorAction SilentlyContinue
            }
        }

        # Build argument string with proper quoting
        $argsString = "--login `"$($Cred.UserName)`" --password `"$PlainTextPassword`" train"
        $argsString += " -i `"$trainImagesDir`" -i `"$sparsePath`" -o `"$pshtPath`""
        $argsString += " --anti-aliasing $($antiAliasing.ToString().ToLower())"
        if ($settings.train_steps_limit -gt 0) {
            $argsString += " --train-steps-limit $($settings.train_steps_limit)"
        }
        $argsString += " --max-num-features $($settings.max_num_features)"
        $argsString += " --max-sh-degree $maxShDegree"
        $argsString += " --max-image-size $($settings.max_image_size)"
        if ($showTrainError) { $argsString += " --show-train-error" }

        $stepsDisplay = if ($settings.train_steps_limit -gt 0) { " --train-steps-limit $($settings.train_steps_limit)" } else { "" }
        $displayCmd = "postshot-cli train --anti-aliasing $($antiAliasing.ToString().ToLower())$stepsDisplay --max-num-features $($settings.max_num_features) --max-sh-degree $maxShDegree --max-image-size $($settings.max_image_size)$(if ($showTrainError) { ' --show-train-error' })"

        Write-Host ""
        Write-Host "  Starting Postshot training..." -ForegroundColor Cyan
        Write-Host "  Command: $displayCmd" -ForegroundColor DarkGray
        Write-Host "  Log: $trainLogFile" -ForegroundColor DarkGray

        $startTime = Get-Date

        # Use .NET Process for stdout capture with real-time display
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $postshotCli
        $psi.Arguments = $argsString
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null

        # Read stderr asynchronously to prevent deadlock
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        # Read stdout line-by-line with real-time display
        $logContent = New-Object System.Text.StringBuilder
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -ne $line) {
                Write-Host "    $line" -ForegroundColor DarkGray
                [void]$logContent.AppendLine($line)
            }
        }
        $proc.WaitForExit()

        $stderrContent = $stderrTask.Result
        if ($stderrContent) {
            [void]$logContent.AppendLine($stderrContent)
            Write-Host "  [stderr]: $stderrContent" -ForegroundColor DarkYellow
        }

        $duration = (Get-Date) - $startTime
        $exitCode = $proc.ExitCode
        $trainOutputText = $logContent.ToString()
        Write-Host "  Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

        # Save log to file
        Set-Content -Path $trainLogFile -Value $trainOutputText -ErrorAction SilentlyContinue

        if ($exitCode -eq 0) {
            $trainSuccess = $true
            $usedSettings = $settings
            if ($attempt -gt 0) {
                Write-Host "  Training succeeded on fallback level $($attempt + 1)" -ForegroundColor Green
            }
            break
        }

        # Check if failure is OOM-related
        $isOom = $trainOutputText -match '(?i)(out of memory|CUDA|OOM|allocation.?failed|insufficient.?memory)'

        if (-not $isOom -or $attempt -eq ($fallbackLevels.Count - 1)) {
            Write-Host "ERROR: Postshot training failed with exit code $exitCode" -ForegroundColor Red
            if ($trainOutputText) {
                Write-Host "  See log: $trainLogFile" -ForegroundColor DarkGray
            }
            exit 1
        }

        Write-Host "  Training failed (possible OOM, exit code $exitCode). Retrying with reduced settings..." -ForegroundColor Yellow
    }

    if (-not $trainSuccess) {
        Write-Host "ERROR: All training attempts failed" -ForegroundColor Red
        exit 1
    }

    # Parse quality metrics from training output (SSIM or PSNR)
    $qualityMetric = "N/A"
    $qualityMetricName = "N/A"

    # Extract the last SSIM value from training output (format: "SSIM 0.xxx")
    $ssimMatches = [regex]::Matches($trainOutputText, 'SSIM\s+(\d+\.?\d*)')
    if ($ssimMatches.Count -gt 0) {
        $qualityMetric = $ssimMatches[$ssimMatches.Count - 1].Groups[1].Value
        $qualityMetricName = "SSIM"
        Write-Host "  Final training SSIM: $qualityMetric" -ForegroundColor Green
    } elseif ($trainOutputText -match '(?i)PSNR[:\s=]+(\d+\.?\d*)') {
        $qualityMetric = $Matches[1]
        $qualityMetricName = "PSNR"
        Write-Host "  Training PSNR: $qualityMetric dB" -ForegroundColor Green
    } else {
        Write-Host "  Quality metric not found in training output (check log: $trainLogFile)" -ForegroundColor Yellow
    }

    # Verify output
    if (-not (Test-Path -LiteralPath $pshtPath)) {
        Write-Host "ERROR: PSHT file was not created" -ForegroundColor Red
        exit 1
    }

    $fileSize = (Get-Item -LiteralPath $pshtPath).Length / 1MB
    Write-Host "  Training complete! PSHT size: $('{0:N2}' -f $fileSize) MB" -ForegroundColor Green

    # Export PLY for visualization
    Write-Host ""
    Write-Host "  Exporting PLY for visualization..." -ForegroundColor Cyan

    $ExportArgs = @(
        '--login', $Cred.UserName,
        '--password', $PlainTextPassword,
        'export',
        '-f', "`"$pshtPath`"",
        '--export-splat', "`"$plyPath`""
    )

    $exportProcess = Start-Process -FilePath $postshotCli `
        -ArgumentList $ExportArgs `
        -NoNewWindow -Wait -PassThru

    if ($exportProcess.ExitCode -ne 0) {
        Write-Host "WARNING: PLY export failed, skipping visualization" -ForegroundColor Yellow
    } elseif (Test-Path -LiteralPath $plyPath) {
        $plySize = (Get-Item -LiteralPath $plyPath).Length / 1MB
        Write-Host "  PLY exported: $('{0:N2}' -f $plySize) MB" -ForegroundColor Green

        # Generate checkpoint visualizations if save_visualization is enabled
        $saveViz = $false
        if ($config.stage_06_train -and $config.stage_06_train.PSObject.Properties['save_visualization']) {
            $saveViz = $config.stage_06_train.save_visualization
        }

        if ($saveViz) {
            Write-Host ""
            Write-Host "  Generating visualizations..." -ForegroundColor Cyan

            $renderScript = Join-Path $scriptDir "render_checkpoint.py"

            if (Test-Path -LiteralPath $renderScript) {
                # Get final checkpoint number from config (or default to 30000)
                $checkpointNum = "final"
                if ($config.stage_06_train -and $config.stage_06_train.checkpoints) {
                    $checkpoints = $config.stage_06_train.checkpoints
                    $checkpointNum = $checkpoints[-1]  # Last checkpoint
                }

                # Prefer "uv run python" if uv is available, else fall back to $pythonExe
                $uvExe = Get-Command "uv" -ErrorAction SilentlyContinue
                if ($uvExe) {
                    & $uvExe.Source run python $renderScript $plyPath $vizDir $checkpointNum
                } else {
                    & $pythonExe $renderScript $plyPath $vizDir $checkpointNum
                }

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Visualizations saved to: $vizDir" -ForegroundColor Green
                } else {
                    Write-Host "  WARNING: Visualization rendering failed" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  WARNING: render_checkpoint.py not found, skipping visualization" -ForegroundColor Yellow
            }
        }
    }

    # Compute LPIPS if PLY exists and compute_lpips.py is available
    $lpipsMean = $null
    $lpipsScript = Join-Path $scriptDir "compute_lpips.py"
    if ((Test-Path -LiteralPath $lpipsScript) -and (Test-Path -LiteralPath $plyPath)) {
        Write-Host ""
        Write-Host "  Computing LPIPS (perceptual quality)..." -ForegroundColor Cyan
        $lpipsJson = Join-Path $postshotDir "lpips.json"

        # Determine python command: prefer "uv run python" if uv is available
        $uvExe = Get-Command "uv" -ErrorAction SilentlyContinue
        if ($uvExe) {
            $lpipsProcess = Start-Process -FilePath $uvExe.Source `
                -ArgumentList @("run", "python", $lpipsScript, "--ply", $plyPath, "--sparse", $sparsePath, "--images", $trainImagesDir, "--output", $lpipsJson, "--max-images", "50") `
                -NoNewWindow -Wait -PassThru `
                -WorkingDirectory (Split-Path -Parent $scriptDir)
        } else {
            $lpipsProcess = Start-Process -FilePath $pythonExe `
                -ArgumentList @($lpipsScript, "--ply", $plyPath, "--sparse", $sparsePath, "--images", $trainImagesDir, "--output", $lpipsJson, "--max-images", "50") `
                -NoNewWindow -Wait -PassThru
        }

        if ($lpipsProcess.ExitCode -eq 0 -and (Test-Path -LiteralPath $lpipsJson)) {
            $lpipsData = Get-Content $lpipsJson -Raw | ConvertFrom-Json
            $lpipsMean = $lpipsData.lpips_mean
            Write-Host "  LPIPS: $lpipsMean" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: LPIPS computation failed (exit code: $($lpipsProcess.ExitCode))" -ForegroundColor Yellow
        }
    }

    # Write machine-readable quality.json for runner scripts
    $qualityJsonPath = Join-Path $postshotDir "quality.json"
    $qualityData = @{
        metric_name = $qualityMetricName
        steps = if ($usedSettings -and $usedSettings.train_steps_limit -gt 0) { $usedSettings.train_steps_limit * 1000 } elseif ($trainStepsLimit -gt 0) { $trainStepsLimit * 1000 } else { "auto" }
    }
    if ($qualityMetricName -eq "SSIM") {
        $qualityData.ssim = [double]$qualityMetric
    } elseif ($qualityMetricName -eq "PSNR") {
        $qualityData.psnr = [double]$qualityMetric
    }
    if ($null -ne $lpipsMean) {
        $qualityData.lpips = [double]$lpipsMean
    }
    $qualityData | ConvertTo-Json | Set-Content -Path $qualityJsonPath -Encoding UTF8
    Write-Host "  Quality data saved to: $qualityJsonPath" -ForegroundColor Green

    # Save training info with quality settings and PSNR
    $stepsUsedInfo = if ($usedSettings -and $usedSettings.train_steps_limit -gt 0) { "$($usedSettings.train_steps_limit)k" } elseif ($trainStepsLimit -gt 0) { "${trainStepsLimit}k" } else { "auto" }
    $settingsUsed = if ($usedSettings) { "max_image_size=$($usedSettings.max_image_size), max_num_features=$($usedSettings.max_num_features)k, train_steps_limit=$stepsUsedInfo" } else { "defaults" }
    $trainInfo = @"
Postshot Training Summary
=========================
Images: $trainImagesDir
Train camera: $trainCamera
Sparse model: $sparsePath
Output: $pshtPath

Quality Settings
----------------
anti-aliasing: $antiAliasing
train-steps-limit: $(if ($trainStepsLimit -gt 0) { "${trainStepsLimit}k steps" } else { "auto" })
max-num-features: ${maxNumFeatures}k
max-sh-degree: $maxShDegree
max-image-size: $(if ($usedSettings) { $usedSettings.max_image_size } else { $maxImageSize }) px (configured: $maxImageSize)
show-train-error: $showTrainError

Results
-------
Quality metric: $qualityMetricName = $qualityMetric
PSHT Size: $('{0:N2}' -f $fileSize) MB
PLY Size: $(if (Test-Path -LiteralPath $plyPath) { '{0:N2}' -f ((Get-Item -LiteralPath $plyPath).Length / 1MB) } else { 'N/A' }) MB
Duration: $($duration.ToString('hh\:mm\:ss'))
Settings used: $settingsUsed
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    $trainInfoFile = Join-Path $vizDir "training_info.txt"
    Set-Content -Path $trainInfoFile -Value $trainInfo

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Stage 6 Complete" -ForegroundColor Green
    Write-Host "  Output: $pshtPath" -ForegroundColor White
    Write-Host "  Size: $('{0:N2}' -f $fileSize) MB" -ForegroundColor White
    Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Green
}
finally {
    if ($PlainTextPassword) {
        $MarshalType::ZeroFreeBSTR($BSTR)
    }

    # Clean up junction directory
    if ($junctionDir -and (Test-Path -LiteralPath $junctionDir)) {
        Write-Host "  Cleaning up junction directory..." -ForegroundColor DarkGray
        $cameraFolder = "video_$trainCamera"
        $junctionTarget = Join-Path $junctionDir $cameraFolder
        if (Test-Path -LiteralPath $junctionTarget) {
            # Delete junction only - does NOT follow/delete target contents
            [System.IO.Directory]::Delete($junctionTarget)
        }
        Remove-Item -LiteralPath $junctionDir -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "  Junction cleaned up." -ForegroundColor DarkGray
    }
}

exit 0

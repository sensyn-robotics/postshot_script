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

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 6: Postshot Training" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Images: $imagesDir" -ForegroundColor White
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
if ((Test-Path -LiteralPath $pshtPath) -and -not $overwrite) {
    $fileSize = (Get-Item -LiteralPath $pshtPath).Length / 1MB
    Write-Host "  Found existing PSHT: $pshtPath ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Yellow
    Write-Host "  Skipping training (overwrite_result=false)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Stage 6 Complete (skipped - model exists)" -ForegroundColor Green
    exit 0
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
    # Build CLI arguments for training
    $CliArgs = @(
        '--login', $Cred.UserName,
        '--password', $PlainTextPassword,
        'train',
        '-i', "`"$imagesDir`"",
        '-i', "`"$sparsePath`"",
        '-o', "`"$pshtPath`""
    )

    Write-Host ""
    Write-Host "  Starting Postshot training..." -ForegroundColor Cyan
    Write-Host "  Command: postshot-cli --login [EMAIL] --password [REDACTED] train -i `"$imagesDir`" -i `"$sparsePath`" -o `"$pshtPath`"" -ForegroundColor DarkGray

    $startTime = Get-Date

    $process = Start-Process -FilePath $postshotCli `
        -ArgumentList $CliArgs `
        -NoNewWindow -Wait -PassThru

    $duration = (Get-Date) - $startTime

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: Postshot training failed with exit code $($process.ExitCode)" -ForegroundColor Red
        exit 1
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

        if ($saveViz -and (Test-Path -LiteralPath $pythonExe)) {
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

                $vizArgs = @(
                    $renderScript,
                    $plyPath,
                    $vizDir,
                    $checkpointNum
                )

                & $pythonExe $vizArgs

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

    # Save training info
    $trainInfo = @"
Postshot Training Summary
=========================
Images: $imagesDir
Sparse model: $sparsePath
Output: $pshtPath
PSHT Size: $('{0:N2}' -f $fileSize) MB
PLY Size: $(if (Test-Path -LiteralPath $plyPath) { '{0:N2}' -f ((Get-Item -LiteralPath $plyPath).Length / 1MB) } else { 'N/A' }) MB
Duration: $($duration.ToString('hh\:mm\:ss'))
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
}

exit 0

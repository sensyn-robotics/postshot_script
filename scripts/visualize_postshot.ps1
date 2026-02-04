# visualize_postshot.ps1
# Visualize Postshot 3DGS by exporting PLY and rendering it
#
# Since Postshot CLI doesn't have a direct render command,
# this exports the gaussian splats to PLY and renders them as a point cloud.

param(
    [Parameter(Mandatory=$true)]
    [string]$PshtPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputImage,

    [Parameter(Mandatory=$false)]
    [string]$Title = "3DGS Gaussian Splats"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import dependencies
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")
. (Join-Path $scriptDir "postshot_runner.ps1")

Write-Host "=== Postshot 3DGS Visualization ===" -ForegroundColor Cyan
Write-Host "  PSHT path: $PshtPath"
Write-Host "  Output image: $OutputImage"

# Check if psht exists
if (-not (Test-Path -LiteralPath $PshtPath)) {
    Write-Host "ERROR: PSHT file not found: $PshtPath" -ForegroundColor Red
    exit 1
}

# Create output directory if needed
$outputDir = Split-Path -Parent $OutputImage
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Load config for Postshot CLI path
$Config = Load-Config
$PostshotCli = $Config.paths.postshot_cli

# Get credentials
$Cred = Get-PostshotCredentials

# Convert SecureString to plain text
$MarshalType = [System.Runtime.InteropServices.Marshal]
$BSTR = $MarshalType::SecureStringToBSTR($Cred.Password)
$PlainTextPassword = $MarshalType::PtrToStringAuto($BSTR)

try {
    # Copy psht to temp location to avoid Unicode path issues
    $tempPsht = Join-Path $env:TEMP "viz_$(Get-Date -Format 'yyyyMMddHHmmss').psht"
    Copy-Item -LiteralPath $PshtPath -Destination $tempPsht

    # Export to PLY
    $tempPly = Join-Path $env:TEMP "viz_$(Get-Date -Format 'yyyyMMddHHmmss').ply"

    Write-Host "  Exporting gaussian splats to PLY..." -ForegroundColor Gray

    $ExportArgs = @(
        '--login', $Cred.UserName,
        '--password', $PlainTextPassword,
        'export',
        '-f', "`"$tempPsht`"",
        '--export-splat', "`"$tempPly`""
    )

    $exportProcess = Start-Process -FilePath $PostshotCli `
        -ArgumentList $ExportArgs `
        -NoNewWindow -Wait -PassThru

    if ($exportProcess.ExitCode -eq 0 -and (Test-Path $tempPly)) {
        # Use Python to render the gaussian splats
        $pythonScript = Join-Path $scriptDir "render_pointcloud.py"
        Write-Host "  Rendering point cloud..." -ForegroundColor Gray
        python $pythonScript $tempPly $OutputImage --title "$Title"

        if (Test-Path $OutputImage) {
            Write-Host "  Visualization saved: $OutputImage" -ForegroundColor Green
        }
    } else {
        Write-Host "ERROR: Failed to export PLY (exit code: $($exportProcess.ExitCode))" -ForegroundColor Red
    }

    # Cleanup
    Remove-Item $tempPsht -Force -ErrorAction SilentlyContinue
    Remove-Item $tempPly -Force -ErrorAction SilentlyContinue
}
finally {
    if ($PlainTextPassword) {
        $MarshalType::ZeroFreeBSTR($BSTR)
    }
}

if (Test-Path $OutputImage) {
    exit 0
} else {
    exit 1
}

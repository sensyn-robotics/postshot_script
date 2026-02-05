# 07_postshot_export.ps1
# Stage 7: Postshot PLY export
#
# Input: output/postshot/scene.psht
# Output: output/postshot/scene.ply

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
$postshotDir = Join-Path $outputDir $config.output.postshot_subdir
$pshtPath = Join-Path $postshotDir "scene.psht"
$plyPath = Join-Path $postshotDir "scene.ply"
$postshotCli = $config.paths.postshot_cli

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stage 7: Postshot PLY Export" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Input: $pshtPath" -ForegroundColor White
Write-Host "  Output: $plyPath" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# Validate Postshot CLI
if (-not (Test-Path -LiteralPath $postshotCli)) {
    Write-Host "ERROR: Postshot CLI not found at: $postshotCli" -ForegroundColor Red
    exit 1
}

# Validate PSHT file
if (-not (Test-Path -LiteralPath $pshtPath)) {
    Write-Host "ERROR: PSHT file not found: $pshtPath" -ForegroundColor Red
    Write-Host "  Run stage 06 (training) first" -ForegroundColor Yellow
    exit 1
}

# Check overwrite setting
$overwrite = $false
if ($config.pipeline -and $config.pipeline.PSObject.Properties['overwrite_result']) {
    $overwrite = $config.pipeline.overwrite_result
}

# Check for existing PLY
if ((Test-Path -LiteralPath $plyPath) -and -not $overwrite) {
    $fileSize = (Get-Item -LiteralPath $plyPath).Length / 1MB
    Write-Host "  Found existing PLY: $plyPath ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Yellow
    Write-Host "  Skipping export (overwrite_result=false)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Stage 7 Complete (skipped - PLY exists)" -ForegroundColor Green
    exit 0
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
    # Build CLI arguments
    $CliArgs = @(
        '--login', $Cred.UserName,
        '--password', $PlainTextPassword,
        'export',
        '-f', "`"$pshtPath`"",
        '--export-splat', "`"$plyPath`""
    )

    Write-Host ""
    Write-Host "  Starting PLY export..." -ForegroundColor Cyan
    Write-Host "  Command: postshot-cli --login $($Cred.UserName) --password [REDACTED] export -f `"$pshtPath`" --export-splat `"$plyPath`"" -ForegroundColor DarkGray

    $startTime = Get-Date

    $process = Start-Process -FilePath $postshotCli `
        -ArgumentList $CliArgs `
        -NoNewWindow -Wait -PassThru

    $duration = (Get-Date) - $startTime

    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: PLY export failed with exit code $($process.ExitCode)" -ForegroundColor Red
        exit 1
    }

    # Verify output
    if (-not (Test-Path -LiteralPath $plyPath)) {
        Write-Host "ERROR: PLY file was not created" -ForegroundColor Red
        exit 1
    }

    $fileSize = (Get-Item -LiteralPath $plyPath).Length / 1MB

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Stage 7 Complete" -ForegroundColor Green
    Write-Host "  Output: $plyPath" -ForegroundColor White
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

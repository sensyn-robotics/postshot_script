# postshot_runner.ps1
# Postshot CLI wrapper with credential management and COLMAP support

param(
    [Parameter(Mandatory=$false)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [PSCustomObject]$Config,

    [Parameter(Mandatory=$false)]
    [switch]$ExportPly
)

# Import config loader
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $scriptDir) "lib\config_loader.ps1")

# Load config if not provided
if (-not $Config) {
    $Config = Load-Config
}

# Stop script on errors
$ErrorActionPreference = 'Stop'

# --- CREDENTIAL MANAGEMENT ---

$CredentialDir = "$env:APPDATA\PostshotScript"
$CredentialFile = "$CredentialDir\postshot_creds.xml"

function Get-PostshotCredentials {
    <#
    .SYNOPSIS
    Get or create Postshot credentials

    .OUTPUTS
    PSCredential object
    #>

    if (-not (Test-Path $CredentialFile)) {
        Write-Host "Postshot credentials not found. Let's set them up one time." -ForegroundColor Yellow

        Write-Host "Please enter your Postshot.com credentials (for CLI login)"
        $UserName = Read-Host -Prompt "  Enter your Postshot.com email"
        $Password = Read-Host -Prompt "  Enter your Postshot.com password (input will be hidden)" -AsSecureString

        $Cred = New-Object System.Management.Automation.PSCredential($UserName, $Password)

        if ($null -eq $Cred -or $null -eq $Cred.Password -or $Cred.Password.Length -eq 0) {
            throw "No password was entered. Please run again and provide a password."
        }

        if (-not (Test-Path $CredentialDir)) {
            New-Item -ItemType Directory -Path $CredentialDir | Out-Null
        }

        $Cred | Export-CliXml -Path $CredentialFile
        Write-Host "Credentials securely saved for future runs." -ForegroundColor Green

        return $Cred
    }
    else {
        $Cred = Import-CliXml -Path $CredentialFile
        Write-Host "Securely loaded credentials for: $($Cred.UserName)" -ForegroundColor Cyan

        if ($null -eq $Cred -or $null -eq $Cred.Password -or $Cred.Password.Length -eq 0) {
            Write-Host "Failed to load credentials, or password is null or empty." -ForegroundColor Red
            Remove-Item -Path $CredentialFile -Force
            throw "Removed corrupt credential file. Please re-run the script."
        }

        return $Cred
    }
}

function Run-PostshotTrain {
    <#
    .SYNOPSIS
    Run Postshot training on input data

    .PARAMETER InputPath
    Path to input (COLMAP project directory or video file)

    .PARAMETER OutputPath
    Path to output .psht file

    .PARAMETER Config
    Configuration object

    .OUTPUTS
    Returns output path on success, $null on failure
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    $postshotCli = $Config.paths.postshot_cli

    # Validate Postshot CLI exists
    if (-not (Test-Path $postshotCli)) {
        Write-Host "ERROR: Postshot CLI not found at: $postshotCli" -ForegroundColor Red
        return $null
    }

    # Validate input path
    if (-not (Test-Path $InputPath)) {
        Write-Host "ERROR: Input path not found: $InputPath" -ForegroundColor Red
        return $null
    }

    # Ensure output path ends with .psht
    if (-not $OutputPath.EndsWith('.psht')) {
        Write-Host "ERROR: Output path must end with .psht" -ForegroundColor Red
        return $null
    }

    # Set temp directory to avoid Japanese path issues
    $env:TEMP = $Config.paths.temp_directory
    $env:TMP = $Config.paths.temp_directory
    if (-not (Test-Path $env:TEMP)) {
        New-Item -ItemType Directory -Path $env:TEMP | Out-Null
    }

    Write-Host ""
    Write-Host "=== Postshot Training ===" -ForegroundColor Cyan
    Write-Host "  Input: $InputPath" -ForegroundColor Cyan
    Write-Host "  Output: $OutputPath" -ForegroundColor Cyan
    Write-Host "  Temp directory: $env:TEMP" -ForegroundColor Gray

    # Get credentials
    $Cred = Get-PostshotCredentials

    # Convert SecureString to plain text
    $MarshalType = [System.Runtime.InteropServices.Marshal]
    $BSTR = $MarshalType::SecureStringToBSTR($Cred.Password)
    $PlainTextPassword = $MarshalType::PtrToStringAuto($BSTR)

    try {
        $CliArgs = @(
            '--login', $Cred.UserName,
            '--password', $PlainTextPassword,
            'train',
            '-i', $InputPath,
            '-o', $OutputPath
        )

        Write-Host "Starting Postshot CLI training. This may take a long time..." -ForegroundColor Yellow
        Write-Host "Command: $postshotCli --login $($Cred.UserName) --password [REDACTED] train -i `"$InputPath`" -o `"$OutputPath`"" -ForegroundColor DarkGray

        & $postshotCli $CliArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Postshot training failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            return $null
        }

        # Verify output file exists
        if (-not (Test-Path $OutputPath)) {
            Write-Host "ERROR: Output file not created: $OutputPath" -ForegroundColor Red
            return $null
        }

        $fileSize = (Get-Item $OutputPath).Length / 1MB
        Write-Host "Postshot training completed successfully" -ForegroundColor Green
        Write-Host "  Output file: $OutputPath ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Green

        return $OutputPath
    }
    finally {
        if ($PlainTextPassword) {
            $MarshalType::ZeroFreeBSTR($BSTR)
            Write-Host "Cleared plain text password from memory." -ForegroundColor Gray
        }
    }
}

function Run-PostshotExport {
    <#
    .SYNOPSIS
    Export Postshot project to PLY point cloud

    .PARAMETER InputPsht
    Path to input .psht file

    .PARAMETER OutputPly
    Path to output .ply file

    .PARAMETER Config
    Configuration object

    .OUTPUTS
    Returns output path on success, $null on failure
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPsht,

        [Parameter(Mandatory=$true)]
        [string]$OutputPly,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    $postshotCli = $Config.paths.postshot_cli

    # Validate Postshot CLI exists
    if (-not (Test-Path $postshotCli)) {
        Write-Host "ERROR: Postshot CLI not found at: $postshotCli" -ForegroundColor Red
        return $null
    }

    # Validate input .psht exists
    if (-not (Test-Path $InputPsht)) {
        Write-Host "ERROR: Input .psht file not found: $InputPsht" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "=== Postshot PLY Export ===" -ForegroundColor Cyan
    Write-Host "  Input: $InputPsht" -ForegroundColor Cyan
    Write-Host "  Output: $OutputPly" -ForegroundColor Cyan

    # Get credentials
    $Cred = Get-PostshotCredentials

    # Convert SecureString to plain text
    $MarshalType = [System.Runtime.InteropServices.Marshal]
    $BSTR = $MarshalType::SecureStringToBSTR($Cred.Password)
    $PlainTextPassword = $MarshalType::PtrToStringAuto($BSTR)

    try {
        $CliArgs = @(
            '--login', $Cred.UserName,
            '--password', $PlainTextPassword,
            'export',
            '-i', $InputPsht,
            '-o', $OutputPly
        )

        Write-Host "Starting Postshot CLI export..." -ForegroundColor Yellow
        Write-Host "Command: $postshotCli --login $($Cred.UserName) --password [REDACTED] export -i `"$InputPsht`" -o `"$OutputPly`"" -ForegroundColor DarkGray

        & $postshotCli $CliArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Postshot export failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            return $null
        }

        # Verify output file exists
        if (-not (Test-Path $OutputPly)) {
            Write-Host "ERROR: PLY file not created: $OutputPly" -ForegroundColor Red
            return $null
        }

        $fileSize = (Get-Item $OutputPly).Length / 1MB
        Write-Host "Postshot export completed successfully" -ForegroundColor Green
        Write-Host "  Output file: $OutputPly ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Green

        return $OutputPly
    }
    finally {
        if ($PlainTextPassword) {
            $MarshalType::ZeroFreeBSTR($BSTR)
            Write-Host "Cleared plain text password from memory." -ForegroundColor Gray
        }
    }
}

function Run-PostshotPipeline {
    <#
    .SYNOPSIS
    Run complete Postshot pipeline: train and optionally export PLY

    .PARAMETER InputPath
    Path to input (COLMAP project directory or video file)

    .PARAMETER OutputPath
    Path to output .psht file

    .PARAMETER Config
    Configuration object

    .PARAMETER ExportPly
    If true, also export to PLY after training

    .OUTPUTS
    PSCustomObject with output paths
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory=$false)]
        [bool]$ExportPly = $true
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host "  Postshot Processing Pipeline" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White

    $result = [PSCustomObject]@{
        PshtPath = $null
        PlyPath = $null
        Success = $false
    }

    # Step 1: Train
    $pshtPath = Run-PostshotTrain -InputPath $InputPath -OutputPath $OutputPath -Config $Config
    if (-not $pshtPath) {
        return $result
    }
    $result.PshtPath = $pshtPath

    # Step 2: Export PLY (if requested)
    if ($ExportPly) {
        $plyPath = $OutputPath -replace '\.psht$', '.ply'
        $plyResult = Run-PostshotExport -InputPsht $pshtPath -OutputPly $plyPath -Config $Config
        if ($plyResult) {
            $result.PlyPath = $plyResult
        }
    }

    $result.Success = $true
    return $result
}

# Main execution when script is run directly
if ($MyInvocation.InvocationName -ne '.') {
    $result = Run-PostshotPipeline -InputPath $InputPath -OutputPath $OutputPath -Config $Config -ExportPly $ExportPly
    if ($result.Success) {
        Write-Host "`nPostshot processing completed successfully" -ForegroundColor Green
        Write-Host "  PSHT: $($result.PshtPath)" -ForegroundColor Cyan
        if ($result.PlyPath) {
            Write-Host "  PLY: $($result.PlyPath)" -ForegroundColor Cyan
        }
        exit 0
    }
    else {
        Write-Host "`nPostshot processing failed" -ForegroundColor Red
        exit 1
    }
}

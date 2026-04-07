# run_pipeline_background.ps1
# Launches pipeline in a background process that survives sleep/lid close.
# Disables Windows sleep during training, re-enables when done.
#
# Usage:
#   .\scripts\run_pipeline_background.ps1 -ConfigPath config\pipeline.json -ScenePath "C:\path\to\scene"
#   .\scripts\run_pipeline_background.ps1 -ConfigPath config\pipeline.json -StartStage 5

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
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$logFile = Join-Path $projectRoot "training_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Build argument list for the inner pipeline
$innerArgs = @(
    "-NoProfile",
    "-Command",
    @"
`$ErrorActionPreference = 'Stop'
Set-Location '$projectRoot'

# Prevent sleep but allow screen lock
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 1
powercfg /change monitor-timeout-dc 1
# Lid close = do nothing
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /SETACTIVE SCHEME_CURRENT

Write-Host 'Sleep disabled, screen locks after 1 min' -ForegroundColor Yellow
Write-Host "Log file: $logFile" -ForegroundColor Cyan

try {
    & '.\scripts\run_pipeline_allscene.ps1' -ConfigPath '$ConfigPath' $(if ('$ScenePath') { "-ScenePath '$ScenePath'" } else { '' }) -StartStage $StartStage -EndStage $EndStage 2>&1 | Tee-Object -FilePath '$logFile'
} finally {
    # Restore default sleep settings (30 min AC, 15 min battery)
    powercfg /change standby-timeout-ac 30
    powercfg /change standby-timeout-dc 15
    powercfg /change monitor-timeout-ac 10
    powercfg /change monitor-timeout-dc 5
    Write-Host 'Sleep settings restored' -ForegroundColor Yellow
}
"@
)

Write-Host "Launching background training..." -ForegroundColor Cyan
Write-Host "  Log: $logFile" -ForegroundColor White

Start-Process -FilePath "powershell" -ArgumentList $innerArgs -WindowStyle Normal

Write-Host "Training launched in new window. Safe to close this terminal." -ForegroundColor Green

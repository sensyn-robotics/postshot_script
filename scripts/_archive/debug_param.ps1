# Debug parameter passing
param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "output"
)

Write-Host "InputPath: $InputPath"
Write-Host "OutputDir: $OutputDir"

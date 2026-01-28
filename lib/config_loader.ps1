# config_loader.ps1
# Configuration utilities for loading and merging JSON config files

function Get-ScriptRoot {
    <#
    .SYNOPSIS
    Gets the root directory of the postshot_script repository
    #>
    $scriptDir = Split-Path -Parent $PSScriptRoot
    return $scriptDir
}

function Load-Config {
    <#
    .SYNOPSIS
    Loads configuration from JSON file with optional custom config override

    .PARAMETER CustomConfigPath
    Optional path to a custom configuration file that overrides defaults

    .OUTPUTS
    PSCustomObject containing merged configuration
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$CustomConfigPath
    )

    $scriptRoot = Get-ScriptRoot
    $defaultConfigPath = Join-Path $scriptRoot "config\default_config.json"

    # Load default config
    if (-not (Test-Path $defaultConfigPath)) {
        throw "Default configuration file not found: $defaultConfigPath"
    }

    $config = Get-Content $defaultConfigPath -Raw | ConvertFrom-Json

    # Merge custom config if provided
    if ($CustomConfigPath -and (Test-Path $CustomConfigPath)) {
        Write-Host "Loading custom config from: $CustomConfigPath" -ForegroundColor Cyan
        $customConfig = Get-Content $CustomConfigPath -Raw | ConvertFrom-Json
        $config = Merge-Config -Base $config -Override $customConfig
    }

    return $config
}

function Merge-Config {
    <#
    .SYNOPSIS
    Recursively merges two configuration objects

    .PARAMETER Base
    The base configuration object

    .PARAMETER Override
    The override configuration object (values take precedence)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Base,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Override
    )

    $result = $Base.PSObject.Copy()

    foreach ($property in $Override.PSObject.Properties) {
        $propName = $property.Name
        $overrideValue = $property.Value

        if ($result.PSObject.Properties[$propName]) {
            $baseValue = $result.$propName

            # If both are objects, merge recursively
            if ($baseValue -is [PSCustomObject] -and $overrideValue -is [PSCustomObject]) {
                $result.$propName = Merge-Config -Base $baseValue -Override $overrideValue
            }
            else {
                # Override the value
                $result.$propName = $overrideValue
            }
        }
        else {
            # Add new property
            $result | Add-Member -NotePropertyName $propName -NotePropertyValue $overrideValue
        }
    }

    return $result
}

function Validate-Config {
    <#
    .SYNOPSIS
    Validates that all required paths in the configuration exist

    .PARAMETER Config
    The configuration object to validate

    .OUTPUTS
    Boolean indicating if validation passed
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    $valid = $true
    $requiredPaths = @(
        @{ Name = "COLMAP"; Path = $Config.paths.colmap_exe },
        @{ Name = "FFmpeg"; Path = $Config.paths.ffmpeg_exe },
        @{ Name = "Postshot CLI"; Path = $Config.paths.postshot_cli }
    )

    foreach ($item in $requiredPaths) {
        if (-not (Test-Path $item.Path)) {
            Write-Host "WARNING: $($item.Name) not found at: $($item.Path)" -ForegroundColor Yellow
            $valid = $false
        }
        else {
            Write-Host "OK: $($item.Name) found at: $($item.Path)" -ForegroundColor Green
        }
    }

    # Create temp directory if it doesn't exist
    $tempDir = $Config.paths.temp_directory
    if (-not (Test-Path $tempDir)) {
        Write-Host "Creating temp directory: $tempDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    return $valid
}

function Get-ColmapArgs {
    <#
    .SYNOPSIS
    Converts COLMAP config section to command-line arguments

    .PARAMETER ConfigSection
    The COLMAP configuration section (e.g., feature_extractor, matcher, mapper)

    .OUTPUTS
    Array of command-line argument strings
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ConfigSection
    )

    $args = @()

    foreach ($property in $ConfigSection.PSObject.Properties) {
        $name = $property.Name
        $value = $property.Value

        # Skip 'type' property (used for matcher type selection)
        if ($name -eq "type") { continue }

        $args += "--$name"
        $args += "$value"
    }

    return $args
}

# Export functions
Export-ModuleMember -Function Load-Config, Validate-Config, Get-ColmapArgs, Get-ScriptRoot

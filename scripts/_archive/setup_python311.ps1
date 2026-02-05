# Setup Python 3.11 after winget installation
$ErrorActionPreference = 'Continue'

Write-Host "=== Setting up Python 3.11 ===" -ForegroundColor Cyan

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Common Python 3.11 locations
$pythonPaths = @(
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "C:\Python311\python.exe",
    "C:\Program Files\Python311\python.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python311\python.exe"
)

$python311 = $null
foreach ($p in $pythonPaths) {
    if (Test-Path $p) {
        $python311 = $p
        break
    }
}

# If not found, search more broadly
if (-not $python311) {
    Write-Host "Searching for Python 3.11..." -ForegroundColor Yellow
    $found = Get-ChildItem -Path 'C:\Users', 'C:\Program Files', 'C:\' -Filter 'python.exe' -Recurse -ErrorAction SilentlyContinue -Depth 5 | Where-Object { $_.FullName -match 'Python311|Python3\.11' } | Select-Object -First 1
    if ($found) {
        $python311 = $found.FullName
    }
}

if (-not $python311) {
    Write-Host "ERROR: Python 3.11 not found" -ForegroundColor Red
    Write-Host "Try running: py -3.11 --version" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found Python: $python311" -ForegroundColor Green

# Check version
Write-Host ""
Write-Host "Python version:"
& $python311 --version

# Upgrade pip
Write-Host ""
Write-Host "Upgrading pip..." -ForegroundColor Yellow
& $python311 -m pip install --upgrade pip --quiet

# Install required packages
Write-Host ""
Write-Host "Installing numpy, pillow, opencv-python..." -ForegroundColor Yellow
& $python311 -m pip install numpy pillow opencv-python --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host "Packages installed successfully" -ForegroundColor Green
} else {
    Write-Host "WARNING: pip returned exit code $LASTEXITCODE" -ForegroundColor Yellow
}

# Verify
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Yellow
& $python311 -c "import numpy; print('numpy:', numpy.__version__)"
& $python311 -c "from PIL import Image; import PIL; print('PIL:', PIL.__version__)"
& $python311 -c "import cv2; print('opencv:', cv2.__version__)"

# Save Python path for other scripts
$pythonPathFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "python_path.txt"
$python311 | Out-File -FilePath $pythonPathFile -Encoding UTF8
Write-Host ""
Write-Host "Python path saved to: $pythonPathFile" -ForegroundColor Gray

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "Python: $python311"

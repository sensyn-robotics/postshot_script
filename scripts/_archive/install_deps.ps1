# Install Python dependencies for visualization
$ErrorActionPreference = 'Continue'

Write-Host "=== Installing Python Dependencies ===" -ForegroundColor Cyan

# Check Python
Write-Host "`nChecking Python installation..."
$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if ($pythonExe) {
    Write-Host "  Python found: $($pythonExe.Source)"
    & python --version
} else {
    Write-Host "  ERROR: Python not found" -ForegroundColor Red
    exit 1
}

# Install dependencies
Write-Host "`nInstalling numpy, pillow, opencv-python..."
& python -m pip install numpy pillow opencv-python 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nSUCCESS: Dependencies installed" -ForegroundColor Green
} else {
    Write-Host "`nWARNING: pip returned exit code $LASTEXITCODE" -ForegroundColor Yellow
}

# Verify installation
Write-Host "`nVerifying installations..."
& python -c "import numpy; print('numpy:', numpy.__version__)"
& python -c "from PIL import Image; import PIL; print('PIL:', PIL.__version__)"
& python -c "import cv2; print('opencv:', cv2.__version__)"

Write-Host "`nDone."

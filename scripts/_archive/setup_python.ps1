# Setup Python dependencies for visualization scripts
$ErrorActionPreference = 'Continue'

Write-Host "=== Python Setup for Visualization ===" -ForegroundColor Cyan
Write-Host ""

# Try to get pip working
Write-Host "Attempting to install packages via pip..." -ForegroundColor Yellow

# Method 1: Use python -m pip (recommended)
Write-Host "`n--- Method 1: python -m pip ---" -ForegroundColor Gray
$result = & python -m pip install --user numpy pillow opencv-python 2>&1
Write-Host $result

# Check if it worked
Write-Host "`n--- Verifying installation ---" -ForegroundColor Gray

$testCode = @"
import sys
print(f'Python: {sys.version}')
try:
    import numpy
    print(f'numpy: {numpy.__version__} - OK')
except ImportError as e:
    print(f'numpy: MISSING - {e}')

try:
    from PIL import Image
    import PIL
    print(f'PIL: {PIL.__version__} - OK')
except ImportError as e:
    print(f'PIL: MISSING - {e}')

try:
    import cv2
    print(f'opencv: {cv2.__version__} - OK')
except ImportError as e:
    print(f'opencv: MISSING - {e}')
"@

$testResult = & python -c $testCode 2>&1
Write-Host $testResult

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan

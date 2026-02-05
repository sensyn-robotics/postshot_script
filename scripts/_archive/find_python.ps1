# Find all Python installations on the system
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=== Searching for Python installations ===" -ForegroundColor Cyan

# Check for Anaconda/Miniconda
$condaPaths = @(
    'C:\ProgramData\Anaconda3\python.exe',
    'C:\ProgramData\miniconda3\python.exe',
    'C:\Anaconda3\python.exe',
    'C:\miniconda3\python.exe'
)

foreach ($p in $condaPaths) {
    if (Test-Path $p) {
        Write-Host "Found Conda Python: $p" -ForegroundColor Green
        & $p --version
    }
}

# Check for system-wide Python in standard locations
$stdPaths = @(
    'C:\Python27\python.exe',
    'C:\Python37\python.exe',
    'C:\Python38\python.exe',
    'C:\Python39\python.exe',
    'C:\Python310\python.exe',
    'C:\Python311\python.exe',
    'C:\Python312\python.exe'
)

foreach ($p in $stdPaths) {
    if (Test-Path $p) {
        Write-Host "Found Python: $p" -ForegroundColor Green
        & $p --version
    }
}

# Check Postshot for Python
Write-Host "`nChecking Postshot directory..." -ForegroundColor Gray
if (Test-Path 'C:\Program Files\Postshot') {
    Get-ChildItem 'C:\Program Files\Postshot' -Filter 'python*' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Found in Postshot: $($_.FullName)" -ForegroundColor Green
    }
}

# Check PATH for any python
Write-Host "`nPython in PATH:" -ForegroundColor Gray
$paths = $env:PATH -split ';'
foreach ($p in $paths) {
    $pyPath = Join-Path $p 'python.exe'
    if (Test-Path $pyPath) {
        Write-Host "  $pyPath" -ForegroundColor Green
    }
}

Write-Host "`nDone."

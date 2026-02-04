# visualize_colmap.ps1
# Visualize COLMAP sparse point cloud as an image
#
# Creates a multi-view rendering of the sparse 3D point cloud

param(
    [Parameter(Mandatory=$true)]
    [string]$SparsePath,

    [Parameter(Mandatory=$true)]
    [string]$OutputImage,

    [Parameter(Mandatory=$false)]
    [string]$Title = "COLMAP Sparse Reconstruction"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== COLMAP Point Cloud Visualization ===" -ForegroundColor Cyan
Write-Host "  Sparse path: $SparsePath"
Write-Host "  Output image: $OutputImage"

# Check if sparse path exists
if (-not (Test-Path -LiteralPath $SparsePath)) {
    Write-Host "ERROR: Sparse path not found: $SparsePath" -ForegroundColor Red
    exit 1
}

# Create output directory if needed
$outputDir = Split-Path -Parent $OutputImage
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Copy sparse to temp location to avoid Unicode path issues
$tempSparse = Join-Path $env:TEMP "sparse_viz_$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item -LiteralPath $SparsePath -Destination $tempSparse -Recurse

# Use Python render script
$pythonScript = Join-Path $scriptDir "render_pointcloud.py"

Write-Host "  Rendering point cloud..." -ForegroundColor Gray
python $pythonScript $tempSparse $OutputImage --title "$Title"

# Cleanup
Remove-Item $tempSparse -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $OutputImage) {
    Write-Host "  Visualization saved: $OutputImage" -ForegroundColor Green
    exit 0
} else {
    Write-Host "ERROR: Failed to create visualization" -ForegroundColor Red
    exit 1
}

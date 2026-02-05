# Debug script to check COLMAP database camera configuration

$testDataPath = "C:\postshot_test_data"
$scene1Dir = Get-ChildItem -LiteralPath $testDataPath -Directory | Select-Object -First 1
$dbPath = Join-Path $scene1Dir.FullName "output\colmap_output\database.db"

Write-Host "=== COLMAP Database Analysis ===" -ForegroundColor Cyan
Write-Host "Database: $dbPath" -ForegroundColor Gray

if (-not (Test-Path -LiteralPath $dbPath)) {
    Write-Host "ERROR: Database not found" -ForegroundColor Red
    exit 1
}

# Copy database to temp location with ASCII path
$tempDb = "C:\Postshot_Temp\temp_check.db"
Copy-Item -LiteralPath $dbPath -Destination $tempDb -Force

# Use Python to read SQLite database
$pythonScript = @"
import sqlite3
import struct

conn = sqlite3.connect(r'C:\Postshot_Temp\temp_check.db')
cursor = conn.cursor()

print('=== CAMERAS TABLE ===')
cursor.execute('SELECT camera_id, model, width, height, params, prior_focal_length FROM cameras')
cameras = cursor.fetchall()
print(f'Total cameras: {len(cameras)}')

# COLMAP camera model IDs
CAMERA_MODELS = {
    0: 'SIMPLE_PINHOLE',
    1: 'PINHOLE',
    2: 'SIMPLE_RADIAL',
    3: 'RADIAL',
    4: 'OPENCV',
    5: 'OPENCV_FISHEYE',
    6: 'FULL_OPENCV',
    7: 'FOV',
    8: 'SIMPLE_RADIAL_FISHEYE',
    9: 'RADIAL_FISHEYE',
    10: 'THIN_PRISM_FISHEYE'
}

for cam in cameras:
    cam_id, model_id, width, height, params_blob, prior_focal = cam
    model_name = CAMERA_MODELS.get(model_id, f'UNKNOWN({model_id})')

    # Parse params based on model
    if params_blob:
        num_params = len(params_blob) // 8
        params = struct.unpack(f'<{num_params}d', params_blob)
        if model_id == 4:  # OPENCV: fx, fy, cx, cy, k1, k2, p1, p2
            print(f'Camera {cam_id}: {model_name} {width}x{height}')
            print(f'  fx={params[0]:.2f}, fy={params[1]:.2f}')
            print(f'  cx={params[2]:.2f}, cy={params[3]:.2f}')
        else:
            print(f'Camera {cam_id}: {model_name} {width}x{height}, params={params[:4]}...')
    else:
        print(f'Camera {cam_id}: {model_name} {width}x{height}, no params')

print()
print('=== IMAGE TO CAMERA MAPPING ===')
cursor.execute('''
    SELECT c.camera_id, COUNT(i.image_id) as img_count
    FROM cameras c
    LEFT JOIN images i ON c.camera_id = i.camera_id
    GROUP BY c.camera_id
''')
for row in cursor.fetchall():
    print(f'Camera {row[0]}: {row[1]} images')

print()
print('=== SAMPLE IMAGES PER CAMERA ===')
for cam in cameras:
    cam_id = cam[0]
    cursor.execute('SELECT name FROM images WHERE camera_id = ? LIMIT 5', (cam_id,))
    images = cursor.fetchall()
    print(f'Camera {cam_id}:')
    for img in images:
        print(f'  - {img[0]}')

conn.close()
"@

# Save Python script
$pythonScript | Out-File -FilePath "C:\Postshot_Temp\check_db.py" -Encoding UTF8

# Run Python script
python "C:\Postshot_Temp\check_db.py"

# Cleanup
Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Postshot_Temp\check_db.py" -Force -ErrorAction SilentlyContinue

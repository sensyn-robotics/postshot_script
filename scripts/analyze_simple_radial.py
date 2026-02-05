"""Analyze SIMPLE_RADIAL model results"""
import sys, struct
from pathlib import Path

# Find scene1
test_data = Path('C:/postshot_test_data')
scenes = sorted([d for d in test_data.iterdir() if d.is_dir()])
scene1 = scenes[0]
sparse = scene1 / 'output_simple_radial' / 'sparse' / '0'

# Read images.bin
images_file = sparse / 'images.bin'
if not images_file.exists():
    print(f'No images.bin at {images_file}')
    sys.exit(1)

w_count = 0
z_count = 0
with open(images_file, 'rb') as f:
    num_images = struct.unpack('Q', f.read(8))[0]
    for _ in range(num_images):
        image_id = struct.unpack('I', f.read(4))[0]
        qw, qx, qy, qz = struct.unpack('dddd', f.read(32))
        tx, ty, tz = struct.unpack('ddd', f.read(24))
        camera_id = struct.unpack('I', f.read(4))[0]
        name = b''
        while True:
            c = f.read(1)
            if c == b'\x00':
                break
            name += c
        name = name.decode('utf-8')
        num_points2d = struct.unpack('Q', f.read(8))[0]
        f.read(num_points2d * 24)

        # Check both naming patterns - collect sample names
        is_w = '_W_' in name or name.startswith('W_') or '/W_' in name or '\\W_' in name or 'video_W' in name
        is_z = '_Z_' in name or name.startswith('Z_') or '/Z_' in name or '\\Z_' in name or 'video_Z' in name
        if is_w:
            w_count += 1
        elif is_z:
            z_count += 1
        # Print first few names to debug
        if w_count + z_count <= 3:
            print(f'  Sample image: {name}')

print(f'Scene: {scene1.name}')
print(f'Model path: {sparse}')
print(f'')
print(f'=== SIMPLE_RADIAL Results ===')
print(f'Total registered: {num_images}')
print(f'W images: {w_count} / 127')
print(f'Z images: {z_count} / 127')
print(f'Registration rate: {num_images}/254 = {num_images/254*100:.1f}%')
print(f'')
print(f'Comparison with previous OPENCV result:')
print(f'  OPENCV: 132 registered (127 W + 5 Z)')
print(f'  SIMPLE_RADIAL: {num_images} registered ({w_count} W + {z_count} Z)')

#!/usr/bin/env python3
"""
Render COLMAP sparse point cloud or 3DGS PLY to an image.

Usage:
    python render_pointcloud.py <input_ply_or_sparse_dir> <output_image> [--title "Title"]
"""

import sys
import struct
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path


def read_colmap_points3d_bin(filepath):
    """Read COLMAP points3D.bin file."""
    points = []
    colors = []

    with open(filepath, 'rb') as f:
        num_points = struct.unpack('<Q', f.read(8))[0]

        for _ in range(num_points):
            point_id = struct.unpack('<Q', f.read(8))[0]
            x, y, z = struct.unpack('<3d', f.read(24))
            r, g, b = struct.unpack('<3B', f.read(3))
            error = struct.unpack('<d', f.read(8))[0]

            # Read track
            track_length = struct.unpack('<Q', f.read(8))[0]
            f.read(track_length * 8)  # Skip track data

            points.append([x, y, z])
            colors.append([r, g, b])

    return np.array(points), np.array(colors)


def read_ply(filepath):
    """Read PLY file (binary or ASCII)."""
    points = []
    colors = []

    with open(filepath, 'rb') as f:
        # Read header
        header_lines = []
        while True:
            line = f.readline().decode('utf-8', errors='ignore').strip()
            header_lines.append(line)
            if line == 'end_header':
                break

        # Parse header
        vertex_count = 0
        is_binary = False
        properties = []

        for line in header_lines:
            if line.startswith('element vertex'):
                vertex_count = int(line.split()[-1])
            elif line.startswith('format binary'):
                is_binary = True
            elif line.startswith('property'):
                parts = line.split()
                if len(parts) >= 3:
                    properties.append((parts[1], parts[2]))

        if vertex_count == 0:
            return np.array([]), np.array([])

        # Determine format based on properties
        has_color = any(p[1] in ['red', 'r', 'diffuse_red'] for p in properties)

        if is_binary:
            # Try to read as COLMAP PLY format (x,y,z,nx,ny,nz,r,g,b)
            try:
                for _ in range(vertex_count):
                    data = struct.unpack('<3f3f3B', f.read(21))
                    x, y, z = data[0], data[1], data[2]
                    r, g, b = data[6], data[7], data[8]
                    points.append([x, y, z])
                    colors.append([r, g, b])
            except:
                # Fallback: try simpler format
                f.seek(0)
                for line in f:
                    if line.startswith(b'end_header'):
                        break
                for _ in range(vertex_count):
                    data = struct.unpack('<3f', f.read(12))
                    points.append([data[0], data[1], data[2]])
                    colors.append([128, 128, 128])
        else:
            # ASCII format
            for _ in range(vertex_count):
                line = f.readline().decode('utf-8', errors='ignore').strip()
                parts = line.split()
                if len(parts) >= 3:
                    x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                    points.append([x, y, z])
                    if len(parts) >= 6 and has_color:
                        r, g, b = int(float(parts[3])), int(float(parts[4])), int(float(parts[5]))
                        colors.append([r, g, b])
                    else:
                        colors.append([128, 128, 128])

    return np.array(points), np.array(colors)


def render_point_cloud(points, colors, output_path, width=1920, height=1080, title=None):
    """Render point cloud from multiple views."""
    if len(points) == 0:
        print('No points to render')
        return False

    # Center the points
    center = np.mean(points, axis=0)
    points_centered = points - center

    # Auto-scale
    max_range = np.max(np.abs(points_centered)) * 1.2
    if max_range == 0:
        max_range = 1.0

    # Create 2x2 grid of views
    views = [
        ('Top View (XZ)', 0, 2),      # Top-down: X, Z
        ('Front View (XY)', 0, 1),    # Front: X, Y
        ('Side View (ZY)', 2, 1),     # Side: Z, Y
        ('Perspective', None, None),   # 3D perspective
    ]

    img = np.zeros((height, width, 3), dtype=np.uint8)
    img.fill(30)  # Dark background

    half_w = width // 2
    half_h = height // 2
    margin = 40

    for idx, (view_name, axis1, axis2) in enumerate(views):
        # Calculate viewport
        vx = (idx % 2) * half_w + margin
        vy = (idx // 2) * half_h + margin
        vw = half_w - margin * 2
        vh = half_h - margin * 2

        if axis1 is not None:
            # Orthographic projection
            x_screen = ((points_centered[:, axis1] / max_range) * 0.45 + 0.5) * vw + vx
            y_screen = ((points_centered[:, axis2] / max_range) * 0.45 + 0.5) * vh + vy
        else:
            # Simple perspective projection
            angle = np.pi / 6
            cos_a, sin_a = np.cos(angle), np.sin(angle)

            # Rotate around Y axis
            x_rot = points_centered[:, 0] * cos_a + points_centered[:, 2] * sin_a
            z_rot = -points_centered[:, 0] * sin_a + points_centered[:, 2] * cos_a

            # Project
            depth = z_rot + max_range * 2
            depth[depth < 0.1] = 0.1
            scale = max_range / depth

            x_screen = (x_rot * scale / max_range * 0.45 + 0.5) * vw + vx
            y_screen = (points_centered[:, 1] * scale / max_range * 0.45 + 0.5) * vh + vy

        # Draw points
        valid_mask = (x_screen >= vx) & (x_screen < vx + vw) & (y_screen >= vy) & (y_screen < vy + vh)
        x_valid = x_screen[valid_mask].astype(int)
        y_valid = y_screen[valid_mask].astype(int)
        colors_valid = colors[valid_mask]

        for i in range(len(x_valid)):
            x, y = x_valid[i], y_valid[i]
            c = colors_valid[i]
            # Draw 2x2 pixel
            for dx in range(2):
                for dy in range(2):
                    if 0 <= x + dx < width and 0 <= y + dy < height:
                        img[y + dy, x + dx] = c

        # Draw border
        img[vy:vy+2, vx:vx+vw] = [80, 80, 80]
        img[vy+vh-2:vy+vh, vx:vx+vw] = [80, 80, 80]
        img[vy:vy+vh, vx:vx+2] = [80, 80, 80]
        img[vy:vy+vh, vx+vw-2:vx+vw] = [80, 80, 80]

    # Add text overlays
    pil_img = Image.fromarray(img)
    draw = ImageDraw.Draw(pil_img)

    try:
        font = ImageFont.truetype("arial.ttf", 20)
        font_small = ImageFont.truetype("arial.ttf", 16)
    except:
        font = ImageFont.load_default()
        font_small = font

    # View labels
    for idx, (view_name, _, _) in enumerate(views):
        vx = (idx % 2) * half_w + margin
        vy = (idx // 2) * half_h + margin
        draw.text((vx + 5, vy + 5), view_name, fill=(200, 200, 200), font=font_small)

    # Title and stats
    if title:
        draw.text((20, 10), title, fill=(255, 255, 255), font=font)

    stats_text = f"Points: {len(points):,}"
    draw.text((width - 200, 10), stats_text, fill=(255, 255, 255), font=font)

    pil_img.save(output_path)
    print(f'Saved visualization to: {output_path}')
    return True


def main():
    if len(sys.argv) < 3:
        print("Usage: python render_pointcloud.py <input> <output.png> [--title 'Title']")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    title = None
    if '--title' in sys.argv:
        idx = sys.argv.index('--title')
        if idx + 1 < len(sys.argv):
            title = sys.argv[idx + 1]

    # Determine input type
    if os.path.isdir(input_path):
        # COLMAP sparse directory
        points3d_path = os.path.join(input_path, 'points3D.bin')
        if os.path.exists(points3d_path):
            print(f'Reading COLMAP sparse: {input_path}')
            points, colors = read_colmap_points3d_bin(points3d_path)
        else:
            print(f'ERROR: points3D.bin not found in {input_path}')
            sys.exit(1)
    elif input_path.endswith('.ply'):
        print(f'Reading PLY: {input_path}')
        points, colors = read_ply(input_path)
    else:
        print(f'ERROR: Unknown input format: {input_path}')
        sys.exit(1)

    if len(points) == 0:
        print('No points loaded')
        sys.exit(1)

    print(f'Loaded {len(points):,} points')
    render_point_cloud(points, colors, output_path, title=title)


if __name__ == '__main__':
    main()

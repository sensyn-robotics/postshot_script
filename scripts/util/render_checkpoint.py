#!/usr/bin/env python3
"""
Render 3DGS PLY checkpoint to multiple camera view images.

Usage:
    python render_checkpoint.py <ply_file> <output_dir> <checkpoint_number>

Outputs 4 images at different camera angles:
    - checkpoint_{N}_view1.png (Front view)
    - checkpoint_{N}_view2.png (Side view)
    - checkpoint_{N}_view3.png (Top view)
    - checkpoint_{N}_view4.png (Perspective view)
"""

import sys
import struct
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path


def read_ply_splats(filepath):
    """Read 3DGS PLY file with Gaussian splat data."""
    points = []
    colors = []
    scales = []

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
                    prop_type = parts[1]
                    prop_name = parts[2]
                    properties.append((prop_type, prop_name))

        if vertex_count == 0:
            return np.array([]), np.array([]), np.array([])

        # Build property map
        prop_names = [p[1] for p in properties]

        # Find indices for position, color, scale
        x_idx = prop_names.index('x') if 'x' in prop_names else 0
        y_idx = prop_names.index('y') if 'y' in prop_names else 1
        z_idx = prop_names.index('z') if 'z' in prop_names else 2

        # Color can be f_dc_0, f_dc_1, f_dc_2 (spherical harmonics) or red, green, blue
        has_sh = 'f_dc_0' in prop_names
        has_rgb = 'red' in prop_names

        if has_sh:
            r_idx = prop_names.index('f_dc_0')
            g_idx = prop_names.index('f_dc_1')
            b_idx = prop_names.index('f_dc_2')
        elif has_rgb:
            r_idx = prop_names.index('red')
            g_idx = prop_names.index('green')
            b_idx = prop_names.index('blue')
        else:
            r_idx = g_idx = b_idx = -1

        # Scale indices
        has_scale = 'scale_0' in prop_names
        if has_scale:
            scale_idx = prop_names.index('scale_0')
        else:
            scale_idx = -1

        # Calculate byte size per vertex
        byte_sizes = {'float': 4, 'double': 8, 'uchar': 1, 'int': 4, 'uint': 4}
        total_bytes = sum(byte_sizes.get(p[0], 4) for p in properties)

        if is_binary:
            # Read binary data - try to parse as 3DGS format
            try:
                for i in range(vertex_count):
                    # Read all floats (most 3DGS PLY use float for everything)
                    num_floats = len(properties)
                    data = struct.unpack(f'<{num_floats}f', f.read(num_floats * 4))

                    x, y, z = data[x_idx], data[y_idx], data[z_idx]
                    points.append([x, y, z])

                    if r_idx >= 0:
                        if has_sh:
                            # Convert SH coefficients to RGB
                            # SH DC component: color = 0.5 + SH0 * C0 where C0 = 0.28209479
                            C0 = 0.28209479177387814
                            r = int(np.clip((0.5 + data[r_idx] * C0) * 255, 0, 255))
                            g = int(np.clip((0.5 + data[g_idx] * C0) * 255, 0, 255))
                            b = int(np.clip((0.5 + data[b_idx] * C0) * 255, 0, 255))
                        else:
                            r = int(np.clip(data[r_idx], 0, 255))
                            g = int(np.clip(data[g_idx], 0, 255))
                            b = int(np.clip(data[b_idx], 0, 255))
                        colors.append([r, g, b])
                    else:
                        colors.append([128, 128, 128])

                    if scale_idx >= 0:
                        scales.append(data[scale_idx])
                    else:
                        scales.append(1.0)

            except Exception as e:
                print(f"Warning: Error reading binary PLY: {e}")
                # Fallback to simpler reading
                f.seek(0)
                for line in f:
                    if line.startswith(b'end_header'):
                        break
                for _ in range(vertex_count):
                    data = struct.unpack('<3f', f.read(12))
                    points.append([data[0], data[1], data[2]])
                    colors.append([128, 128, 128])
                    scales.append(1.0)
                    # Skip rest of data
                    remaining = total_bytes - 12
                    if remaining > 0:
                        f.read(remaining)
        else:
            # ASCII format
            for _ in range(vertex_count):
                line = f.readline().decode('utf-8', errors='ignore').strip()
                parts = line.split()
                if len(parts) >= 3:
                    x = float(parts[x_idx])
                    y = float(parts[y_idx])
                    z = float(parts[z_idx])
                    points.append([x, y, z])

                    if r_idx >= 0 and len(parts) > max(r_idx, g_idx, b_idx):
                        r = int(float(parts[r_idx]))
                        g = int(float(parts[g_idx]))
                        b = int(float(parts[b_idx]))
                        colors.append([r, g, b])
                    else:
                        colors.append([128, 128, 128])

                    scales.append(1.0)

    return np.array(points), np.array(colors), np.array(scales)


def render_single_view(points, colors, width, height, camera_params):
    """Render point cloud from a single camera view."""
    if len(points) == 0:
        img = np.zeros((height, width, 3), dtype=np.uint8)
        img.fill(30)
        return img

    # Unpack camera parameters
    rotation_angles = camera_params.get('rotation', [0, 0, 0])
    zoom = camera_params.get('zoom', 1.0)
    offset = camera_params.get('offset', [0, 0])

    # Center the points
    center = np.mean(points, axis=0)
    points_centered = points - center

    # Auto-scale
    max_range = np.max(np.abs(points_centered)) * 1.2
    if max_range == 0:
        max_range = 1.0

    # Apply rotations (Euler angles: pitch, yaw, roll)
    pitch, yaw, roll = np.radians(rotation_angles)

    # Rotation matrices
    Rx = np.array([
        [1, 0, 0],
        [0, np.cos(pitch), -np.sin(pitch)],
        [0, np.sin(pitch), np.cos(pitch)]
    ])
    Ry = np.array([
        [np.cos(yaw), 0, np.sin(yaw)],
        [0, 1, 0],
        [-np.sin(yaw), 0, np.cos(yaw)]
    ])
    Rz = np.array([
        [np.cos(roll), -np.sin(roll), 0],
        [np.sin(roll), np.cos(roll), 0],
        [0, 0, 1]
    ])

    R = Rz @ Ry @ Rx
    points_rotated = points_centered @ R.T

    # Perspective projection
    fov = 60  # Field of view in degrees
    f = 1.0 / np.tan(np.radians(fov / 2))

    # Move camera back
    camera_distance = max_range * 2.5 / zoom
    points_cam = points_rotated.copy()
    points_cam[:, 2] += camera_distance

    # Avoid division by zero
    z = points_cam[:, 2].copy()
    z[z < 0.01] = 0.01

    # Project to screen
    x_screen = (points_cam[:, 0] / z * f * 0.4 + 0.5 + offset[0]) * width
    y_screen = (-points_cam[:, 1] / z * f * 0.4 + 0.5 + offset[1]) * height

    # Sort by depth for proper occlusion
    depth_order = np.argsort(-z)

    # Create image
    img = np.zeros((height, width, 3), dtype=np.uint8)
    img.fill(30)  # Dark background

    # Draw points
    for idx in depth_order:
        x, y = int(x_screen[idx]), int(y_screen[idx])
        if 0 <= x < width - 1 and 0 <= y < height - 1:
            c = colors[idx]
            # Draw 2x2 pixel
            img[y:y+2, x:x+2] = c

    return img


def add_text_overlay(img, title, stats_text, view_name):
    """Add text overlay to image."""
    pil_img = Image.fromarray(img)
    draw = ImageDraw.Draw(pil_img)

    try:
        font = ImageFont.truetype("arial.ttf", 24)
        font_small = ImageFont.truetype("arial.ttf", 18)
    except:
        font = ImageFont.load_default()
        font_small = font

    # Draw title
    draw.text((20, 15), title, fill=(255, 255, 255), font=font)

    # Draw view name
    draw.text((20, 50), view_name, fill=(180, 180, 180), font=font_small)

    # Draw stats
    draw.text((20, img.shape[0] - 40), stats_text, fill=(150, 150, 150), font=font_small)

    return np.array(pil_img)


def main():
    if len(sys.argv) < 4:
        print("Usage: python render_checkpoint.py <ply_file> <output_dir> <checkpoint_number>")
        sys.exit(1)

    ply_path = sys.argv[1]
    output_dir = sys.argv[2]
    checkpoint = sys.argv[3]

    # Check input
    if not os.path.exists(ply_path):
        print(f"ERROR: PLY file not found: {ply_path}")
        sys.exit(1)

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Read PLY file
    print(f"Reading PLY: {ply_path}")
    points, colors, scales = read_ply_splats(ply_path)

    if len(points) == 0:
        print("ERROR: No points loaded from PLY")
        sys.exit(1)

    print(f"Loaded {len(points):,} splats")

    # Define 4 camera views
    views = [
        {
            'name': 'Front View',
            'filename': f'checkpoint_{checkpoint}_view1.png',
            'rotation': [0, 0, 0],
            'zoom': 1.0,
            'offset': [0, 0]
        },
        {
            'name': 'Side View (Left)',
            'filename': f'checkpoint_{checkpoint}_view2.png',
            'rotation': [0, 90, 0],
            'zoom': 1.0,
            'offset': [0, 0]
        },
        {
            'name': 'Top View',
            'filename': f'checkpoint_{checkpoint}_view3.png',
            'rotation': [90, 0, 0],
            'zoom': 1.0,
            'offset': [0, 0]
        },
        {
            'name': 'Perspective View',
            'filename': f'checkpoint_{checkpoint}_view4.png',
            'rotation': [30, 45, 0],
            'zoom': 0.8,
            'offset': [0, 0]
        }
    ]

    width, height = 1280, 720
    title = f"Checkpoint {checkpoint}"
    stats_text = f"Splats: {len(points):,}"

    for view in views:
        print(f"  Rendering {view['name']}...")

        camera_params = {
            'rotation': view['rotation'],
            'zoom': view['zoom'],
            'offset': view['offset']
        }

        img = render_single_view(points, colors, width, height, camera_params)
        img = add_text_overlay(img, title, stats_text, view['name'])

        output_path = os.path.join(output_dir, view['filename'])
        Image.fromarray(img).save(output_path)
        print(f"    Saved: {output_path}")

    print(f"\nRendered {len(views)} views for checkpoint {checkpoint}")


if __name__ == '__main__':
    main()

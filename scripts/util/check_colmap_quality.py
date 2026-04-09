#!/usr/bin/env python3
"""Check COLMAP reconstruction quality"""
import sqlite3
import struct
import os
from pathlib import Path

def read_images_bin(path):
    """Read images.bin to get registered image count"""
    images = {}
    with open(path, 'rb') as f:
        num_images = struct.unpack('<Q', f.read(8))[0]
        for _ in range(num_images):
            image_id = struct.unpack('<I', f.read(4))[0]
            qw, qx, qy, qz = struct.unpack('<4d', f.read(32))
            tx, ty, tz = struct.unpack('<3d', f.read(24))
            camera_id = struct.unpack('<I', f.read(4))[0]

            # Read image name
            name = b''
            while True:
                c = f.read(1)
                if c == b'\x00':
                    break
                name += c
            name = name.decode('utf-8')

            # Read points2D
            num_points2D = struct.unpack('<Q', f.read(8))[0]
            f.read(num_points2D * 24)  # Skip point data

            images[image_id] = {'name': name, 'num_points2D': num_points2D}
    return images

def main():
    # Find scene1
    test_data = Path("C:/postshot_test_data")
    scenes = sorted([d for d in test_data.iterdir() if d.is_dir()])
    scene1 = scenes[0]

    print(f"=== COLMAP Quality Analysis ===")
    print(f"Scene: {scene1.name}")
    print()

    # Check database
    db_path = scene1 / "output" / "colmap_output" / "database.db"
    if db_path.exists():
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()

        # Count images
        cursor.execute("SELECT COUNT(*) FROM images")
        total_images = cursor.fetchone()[0]

        # Count keypoints
        cursor.execute("SELECT SUM(rows) FROM keypoints")
        total_keypoints = cursor.fetchone()[0] or 0

        # Count matches
        cursor.execute("SELECT COUNT(*) FROM matches")
        total_match_pairs = cursor.fetchone()[0]

        # Count verified matches (two_view_geometries)
        cursor.execute("SELECT COUNT(*) FROM two_view_geometries WHERE rows > 0")
        verified_pairs = cursor.fetchone()[0]

        conn.close()

        print("--- Database Statistics ---")
        print(f"  Total images in DB: {total_images}")
        print(f"  Total keypoints: {total_keypoints:,}")
        print(f"  Avg keypoints/image: {total_keypoints/total_images:,.0f}" if total_images > 0 else "")
        print(f"  Match pairs attempted: {total_match_pairs}")
        print(f"  Verified match pairs: {verified_pairs}")
        print()

    # Check sparse reconstruction
    sparse_path = scene1 / "output" / "colmap_output" / "sparse" / "0"
    if sparse_path.exists():
        images_bin = sparse_path / "images.bin"
        points3d_bin = sparse_path / "points3D.bin"

        print("--- Sparse Reconstruction ---")

        if images_bin.exists():
            images = read_images_bin(str(images_bin))
            registered = len(images)

            # Count W and Z
            w_count = sum(1 for img in images.values() if 'video_W' in img['name'])
            z_count = sum(1 for img in images.values() if 'video_Z' in img['name'])

            print(f"  Registered images: {registered}")
            print(f"    - Wide (W): {w_count}")
            print(f"    - Zoom (Z): {z_count}")

            if registered < total_images:
                unregistered = total_images - registered
                print(f"  UNREGISTERED: {unregistered} images failed to register!")

        if points3d_bin.exists():
            with open(points3d_bin, 'rb') as f:
                num_points = struct.unpack('<Q', f.read(8))[0]
            print(f"  3D Points: {num_points:,}")

            if num_points < 10000:
                print("  WARNING: Very sparse reconstruction (<10k points)")
                print("  This can cause blurry 3DGS results")
        print()

    # Recommendations
    print("=== Quality Issues & Solutions ===")
    print()

    if 'num_points' in dir() and num_points < 10000:
        print("ISSUE: Sparse COLMAP reconstruction")
        print("  Cause: Insufficient feature matches between images")
        print("  Solutions:")
        print("    1. Use more images (higher FPS extraction)")
        print("    2. Check if W and Z cameras have overlapping views")
        print("    3. Try different COLMAP matcher settings")
        print()

    if 'registered' in dir() and 'total_images' in dir() and registered < total_images * 0.8:
        print("ISSUE: Many images failed to register")
        print("  Cause: Images may be too different or have poor features")
        print("  Solutions:")
        print("    1. Remove outlier images")
        print("    2. Use sequential matcher for video sequences")
        print()

    print("GENERAL RECOMMENDATIONS:")
    print("  1. Increase Postshot training steps: 30k -> 50k-100k")
    print("  2. Try COLMAP with 'high' quality settings")
    print("  3. Ensure W and Z cameras capture same scene area")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Read COLMAP binary files and report statistics.
Based on COLMAP's Python read_model.py
"""

import sys
import os
import struct
import collections

# COLMAP camera models
CAMERA_MODELS = {
    0: "SIMPLE_PINHOLE",
    1: "PINHOLE",
    2: "SIMPLE_RADIAL",
    3: "RADIAL",
    4: "OPENCV",
    5: "OPENCV_FISHEYE",
    6: "FULL_OPENCV",
    7: "FOV",
    8: "SIMPLE_RADIAL_FISHEYE",
    9: "RADIAL_FISHEYE",
    10: "THIN_PRISM_FISHEYE",
}

CameraModel = collections.namedtuple("CameraModel", ["model_id", "model_name", "num_params"])
CAMERA_MODEL_IDS = {
    0: CameraModel(0, "SIMPLE_PINHOLE", 3),
    1: CameraModel(1, "PINHOLE", 4),
    2: CameraModel(2, "SIMPLE_RADIAL", 4),
    3: CameraModel(3, "RADIAL", 5),
    4: CameraModel(4, "OPENCV", 8),
    5: CameraModel(5, "OPENCV_FISHEYE", 8),
    6: CameraModel(6, "FULL_OPENCV", 12),
    7: CameraModel(7, "FOV", 5),
    8: CameraModel(8, "SIMPLE_RADIAL_FISHEYE", 4),
    9: CameraModel(9, "RADIAL_FISHEYE", 5),
    10: CameraModel(10, "THIN_PRISM_FISHEYE", 12),
}


def read_next_bytes(fid, num_bytes, format_char_sequence, endian_character="<"):
    """Read and unpack bytes from a binary file."""
    data = fid.read(num_bytes)
    return struct.unpack(endian_character + format_char_sequence, data)


def read_cameras_binary(path_to_model_file):
    """Read cameras.bin file."""
    cameras = {}
    with open(path_to_model_file, "rb") as fid:
        num_cameras = read_next_bytes(fid, 8, "Q")[0]
        for _ in range(num_cameras):
            camera_properties = read_next_bytes(fid, 24, "iiQQ")
            camera_id = camera_properties[0]
            model_id = camera_properties[1]
            width = camera_properties[2]
            height = camera_properties[3]
            num_params = CAMERA_MODEL_IDS[model_id].num_params
            params = read_next_bytes(fid, 8 * num_params, "d" * num_params)
            cameras[camera_id] = {
                "id": camera_id,
                "model": CAMERA_MODEL_IDS[model_id].model_name,
                "width": width,
                "height": height,
                "params": params,
            }
    return cameras


def read_images_binary(path_to_model_file):
    """Read images.bin file."""
    images = {}
    with open(path_to_model_file, "rb") as fid:
        num_reg_images = read_next_bytes(fid, 8, "Q")[0]
        for _ in range(num_reg_images):
            binary_image_properties = read_next_bytes(fid, 64, "idddddddi")
            image_id = binary_image_properties[0]
            qvec = binary_image_properties[1:5]
            tvec = binary_image_properties[5:8]
            camera_id = binary_image_properties[8]

            image_name = ""
            current_char = read_next_bytes(fid, 1, "c")[0]
            while current_char != b"\x00":
                image_name += current_char.decode("utf-8")
                current_char = read_next_bytes(fid, 1, "c")[0]

            num_points2D = read_next_bytes(fid, 8, "Q")[0]
            x_y_id_s = read_next_bytes(fid, 24 * num_points2D, "ddq" * num_points2D)

            images[image_id] = {
                "id": image_id,
                "qvec": qvec,
                "tvec": tvec,
                "camera_id": camera_id,
                "name": image_name,
                "num_points2D": num_points2D,
                "xys": [(x_y_id_s[i * 3], x_y_id_s[i * 3 + 1]) for i in range(num_points2D)],
                "point3D_ids": [x_y_id_s[i * 3 + 2] for i in range(num_points2D)],
            }
    return images


def read_points3D_binary(path_to_model_file):
    """Read points3D.bin file."""
    points3D = {}
    with open(path_to_model_file, "rb") as fid:
        num_points = read_next_bytes(fid, 8, "Q")[0]
        for _ in range(num_points):
            binary_point_line_properties = read_next_bytes(fid, 43, "QdddBBBd")
            point3D_id = binary_point_line_properties[0]
            xyz = binary_point_line_properties[1:4]
            rgb = binary_point_line_properties[4:7]
            error = binary_point_line_properties[7]
            track_length = read_next_bytes(fid, 8, "Q")[0]
            track_elems = read_next_bytes(fid, 8 * track_length, "ii" * track_length)

            points3D[point3D_id] = {
                "id": point3D_id,
                "xyz": xyz,
                "rgb": rgb,
                "error": error,
                "track_length": track_length,
            }
    return points3D


def analyze_reconstruction(sparse_path):
    """Analyze a COLMAP sparse reconstruction."""
    cameras_path = os.path.join(sparse_path, "cameras.bin")
    images_path = os.path.join(sparse_path, "images.bin")
    points3D_path = os.path.join(sparse_path, "points3D.bin")

    if not all(os.path.exists(p) for p in [cameras_path, images_path, points3D_path]):
        print(f"ERROR: Missing binary files in {sparse_path}")
        return None

    cameras = read_cameras_binary(cameras_path)
    images = read_images_binary(images_path)
    points3D = read_points3D_binary(points3D_path)

    # Analyze results
    print(f"\n=== Reconstruction: {sparse_path} ===")
    print(f"Cameras: {len(cameras)}")
    print(f"Registered images: {len(images)}")
    print(f"3D points: {len(points3D)}")

    # Camera details
    print(f"\nCamera models:")
    for cam_id, cam in cameras.items():
        print(f"  Camera {cam_id}: {cam['model']} ({cam['width']}x{cam['height']})")

    # Image analysis
    w_images = [img for img in images.values() if 'video_W' in img['name'] or '_W' in img['name']]
    z_images = [img for img in images.values() if 'video_Z' in img['name'] or '_Z' in img['name']]

    print(f"\nImage breakdown:")
    print(f"  W images: {len(w_images)}")
    print(f"  Z images: {len(z_images)}")

    if len(images) > 0:
        print(f"\nFirst 10 registered images:")
        for i, (img_id, img) in enumerate(sorted(images.items())[:10]):
            print(f"  {img['name']} (camera {img['camera_id']}, {img['num_points2D']} 2D points)")

    return {
        "cameras": cameras,
        "images": images,
        "points3D": points3D,
        "w_count": len(w_images),
        "z_count": len(z_images),
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python read_colmap_model.py <sparse_path>")
        print("  sparse_path: Path to COLMAP sparse reconstruction folder")
        sys.exit(1)

    sparse_path = sys.argv[1]

    if not os.path.isdir(sparse_path):
        print(f"ERROR: {sparse_path} is not a directory")
        sys.exit(1)

    result = analyze_reconstruction(sparse_path)

    if result:
        print(f"\n=== Summary ===")
        print(f"Total registered: {len(result['images'])} images")
        print(f"W camera: {result['w_count']} images")
        print(f"Z camera: {result['z_count']} images")
        print(f"3D points: {len(result['points3D'])}")


if __name__ == "__main__":
    main()

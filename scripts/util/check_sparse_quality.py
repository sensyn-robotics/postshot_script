#!/usr/bin/env python3
"""Check COLMAP sparse reconstruction quality.

Evaluates fragmentation, registration rate, 3D structure (PCA), and
mean reprojection error. Outputs JSON report.

Usage:
    python check_sparse_quality.py --sparse <sparse_dir> --output <quality.json> [--total-images N]
"""

import argparse
import json
import os
import struct
import sys
from pathlib import Path

import numpy as np


# ---------------------------------------------------------------------------
# COLMAP binary readers (from read_colmap_model.py)
# ---------------------------------------------------------------------------

CAMERA_MODEL_IDS = {
    0: ("SIMPLE_PINHOLE", 3),
    1: ("PINHOLE", 4),
    2: ("SIMPLE_RADIAL", 4),
    3: ("RADIAL", 5),
    4: ("OPENCV", 8),
    5: ("OPENCV_FISHEYE", 8),
    6: ("FULL_OPENCV", 12),
    7: ("FOV", 5),
    8: ("SIMPLE_RADIAL_FISHEYE", 4),
    9: ("RADIAL_FISHEYE", 5),
    10: ("THIN_PRISM_FISHEYE", 12),
}


def _read_next_bytes(fid, num_bytes, fmt, endian="<"):
    data = fid.read(num_bytes)
    return struct.unpack(endian + fmt, data)


def read_images_binary(path):
    """Read images.bin and return dict of image records."""
    images = {}
    with open(path, "rb") as f:
        (num_images,) = _read_next_bytes(f, 8, "Q")
        for _ in range(num_images):
            props = _read_next_bytes(f, 64, "idddddddi")
            image_id = props[0]
            qvec = props[1:5]
            tvec = props[5:8]
            camera_id = props[8]

            name = ""
            ch = _read_next_bytes(f, 1, "c")[0]
            while ch != b"\x00":
                name += ch.decode("utf-8")
                ch = _read_next_bytes(f, 1, "c")[0]

            (num_points2D,) = _read_next_bytes(f, 8, "Q")
            _read_next_bytes(f, 24 * num_points2D, "ddq" * num_points2D)

            images[image_id] = {
                "id": image_id,
                "qvec": qvec,
                "tvec": tvec,
                "camera_id": camera_id,
                "name": name,
            }
    return images


def read_points3D_binary(path):
    """Read points3D.bin and return dict of point records."""
    points = {}
    with open(path, "rb") as f:
        (num_points,) = _read_next_bytes(f, 8, "Q")
        for _ in range(num_points):
            props = _read_next_bytes(f, 43, "QdddBBBd")
            point_id = props[0]
            xyz = props[1:4]
            error = props[7]
            (track_length,) = _read_next_bytes(f, 8, "Q")
            _read_next_bytes(f, 8 * track_length, "ii" * track_length)
            points[point_id] = {"xyz": xyz, "error": error}
    return points


# ---------------------------------------------------------------------------
# Quality checks
# ---------------------------------------------------------------------------

def count_models(sparse_dir):
    """Count numbered subdirectories in sparse/."""
    return len([d for d in Path(sparse_dir).iterdir()
                if d.is_dir() and d.name.isdigit()])


def find_largest_model(sparse_dir):
    """Return path to the largest reconstruction (by images.bin size)."""
    best_path = None
    best_size = 0
    for d in sorted(Path(sparse_dir).iterdir()):
        if not d.is_dir() or not d.name.isdigit():
            continue
        images_bin = d / "images.bin"
        if images_bin.exists():
            sz = images_bin.stat().st_size
            if sz > best_size:
                best_size = sz
                best_path = d
    return str(best_path) if best_path else None


def check_3d_structure(points3D):
    """Check if point cloud is 3D (not planar) using PCA."""
    if len(points3D) < 100:
        return {"is_3d": False, "reason": "too few points",
                "planarity_ratio": 0, "eigenvalues": [], "extent": [],
                "num_points": len(points3D)}

    coords = np.array([p["xyz"] for p in points3D.values()])

    # Extent
    mins = coords.min(axis=0)
    maxs = coords.max(axis=0)
    extent = maxs - mins

    # PCA via covariance matrix
    centered = coords - coords.mean(axis=0)
    cov = np.cov(centered.T)
    eigenvalues = np.sort(np.linalg.eigvalsh(cov))[::-1]  # descending

    # Planarity ratio: smallest / largest eigenvalue
    # Tower = elongated 3D -> ratio should be > 0.01
    # Plane = flat -> ratio ~ 0
    planarity_ratio = float(eigenvalues[2] / eigenvalues[0]) if eigenvalues[0] > 0 else 0

    return {
        "is_3d": planarity_ratio >= 0.01,
        "planarity_ratio": round(planarity_ratio, 6),
        "eigenvalues": [round(float(e), 3) for e in eigenvalues],
        "extent": [round(float(e), 3) for e in extent],
        "num_points": len(points3D),
    }


def check_quality(sparse_dir, total_images=0):
    """Run all quality checks. Returns dict with pass/fail and metrics."""
    results = {"pass": True, "checks": {}, "reasons": []}

    # 1. Count models (fragmentation)
    num_models = count_models(sparse_dir)
    results["checks"]["num_models"] = num_models
    if num_models > 1:
        results["pass"] = False
        results["reasons"].append(f"fragmented: {num_models} models (expected 1)")

    # 2. Find largest model
    largest = find_largest_model(sparse_dir)
    if not largest:
        results["pass"] = False
        results["reasons"].append("no valid reconstruction found")
        results["checks"]["registered_images"] = 0
        results["checks"]["total_images"] = total_images
        return results

    results["checks"]["largest_model"] = os.path.basename(largest)

    # 3. Registration check
    images_path = os.path.join(largest, "images.bin")
    images = read_images_binary(images_path)
    registered = len(images)
    results["checks"]["registered_images"] = registered
    results["checks"]["total_images"] = total_images
    if total_images > 0:
        rate = registered / total_images
        results["checks"]["registration_rate"] = round(rate, 3)
        if rate < 0.85:
            results["pass"] = False
            results["reasons"].append(
                f"low registration: {registered}/{total_images} ({rate:.1%})")

    # 4. 3D structure check (PCA)
    points3D_path = os.path.join(largest, "points3D.bin")
    points3D = read_points3D_binary(points3D_path)
    structure = check_3d_structure(points3D)
    results["checks"]["structure"] = structure
    if not structure["is_3d"]:
        results["pass"] = False
        results["reasons"].append(
            f"planar reconstruction (ratio={structure['planarity_ratio']:.4f})")

    # 5. Mean reprojection error
    if points3D:
        errors = [p["error"] for p in points3D.values()]
        mean_error = float(np.mean(errors))
        results["checks"]["mean_reprojection_error"] = round(mean_error, 3)
        if mean_error > 2.0:
            results["pass"] = False
            results["reasons"].append(
                f"high reprojection error: {mean_error:.3f} px")
    else:
        results["checks"]["mean_reprojection_error"] = None

    return results


def main():
    parser = argparse.ArgumentParser(description="Check COLMAP sparse quality")
    parser.add_argument("--sparse", required=True,
                        help="Path to COLMAP sparse directory")
    parser.add_argument("--output", required=True,
                        help="Path to output quality JSON")
    parser.add_argument("--total-images", type=int, default=0,
                        help="Total number of input images (for registration rate)")
    args = parser.parse_args()

    if not os.path.isdir(args.sparse):
        print(f"ERROR: sparse directory not found: {args.sparse}")
        sys.exit(1)

    results = check_quality(args.sparse, args.total_images)

    # Print summary to stdout
    print(f"\nCOLMAP Quality Check: {'PASS' if results['pass'] else 'FAIL'}")
    print(f"  Models: {results['checks']['num_models']}")
    print(f"  Registered: {results['checks']['registered_images']}"
          f"/{results['checks']['total_images']}")
    if "registration_rate" in results["checks"]:
        print(f"  Registration rate: {results['checks']['registration_rate']:.1%}")
    if "structure" in results["checks"]:
        s = results["checks"]["structure"]
        print(f"  3D structure: {'YES' if s['is_3d'] else 'NO (PLANAR!)'}"
              f" (ratio={s['planarity_ratio']:.4f})")
        print(f"  Points: {s['num_points']}")
    if results["checks"].get("mean_reprojection_error") is not None:
        print(f"  Mean reproj error: {results['checks']['mean_reprojection_error']:.3f} px")
    if results["reasons"]:
        print(f"  Reasons: {'; '.join(results['reasons'])}")

    # Write JSON
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved to: {args.output}")


if __name__ == "__main__":
    main()

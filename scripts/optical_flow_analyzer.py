#!/usr/bin/env python3
"""
optical_flow_analyzer.py - Compute optical flow and select keyframes with target overlap

Uses Farneback optical flow to estimate camera motion between frames.
Selects keyframes such that consecutive selected frames have approximately
the target overlap percentage (~50% by default).

Usage:
    python optical_flow_analyzer.py <images_dir> [options]

Examples:
    python optical_flow_analyzer.py output/images --analyze
    python optical_flow_analyzer.py output/images --select-keyframes --target-overlap 50
    python optical_flow_analyzer.py output/images --select-keyframes --remove-non-keyframes
"""

import argparse
import csv
import os
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np


def compute_optical_flow(img1_path: str, img2_path: str) -> Dict:
    """
    Compute optical flow between two consecutive images.

    Uses Farneback dense optical flow algorithm.

    Args:
        img1_path: Path to first image
        img2_path: Path to second image

    Returns:
        Dictionary with flow statistics:
            - mean_magnitude: Average flow magnitude in pixels
            - max_magnitude: Maximum flow magnitude
            - std_magnitude: Standard deviation of flow magnitude
            - coverage: Percentage of image with significant flow (> 1px)
    """
    img1 = cv2.imread(img1_path, cv2.IMREAD_GRAYSCALE)
    img2 = cv2.imread(img2_path, cv2.IMREAD_GRAYSCALE)

    if img1 is None:
        raise ValueError(f"Could not read image: {img1_path}")
    if img2 is None:
        raise ValueError(f"Could not read image: {img2_path}")

    # Resize for faster processing (keep aspect ratio)
    max_dim = 640
    h, w = img1.shape
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        new_w = int(w * scale)
        new_h = int(h * scale)
        img1 = cv2.resize(img1, (new_w, new_h))
        img2 = cv2.resize(img2, (new_w, new_h))
        # Scale factor to convert back to original image dimensions
        flow_scale = 1.0 / scale
    else:
        flow_scale = 1.0

    # Compute Farneback optical flow
    flow = cv2.calcOpticalFlowFarneback(
        img1, img2,
        None,
        pyr_scale=0.5,
        levels=3,
        winsize=15,
        iterations=3,
        poly_n=5,
        poly_sigma=1.2,
        flags=0
    )

    # Compute flow magnitude
    magnitude = np.sqrt(flow[..., 0]**2 + flow[..., 1]**2)

    # Scale magnitude back to original image dimensions
    magnitude = magnitude * flow_scale

    # Compute statistics
    mean_mag = float(np.mean(magnitude))
    max_mag = float(np.max(magnitude))
    std_mag = float(np.std(magnitude))
    coverage = float(np.sum(magnitude > 1) / magnitude.size * 100)

    return {
        'mean_magnitude': mean_mag,
        'max_magnitude': max_mag,
        'std_magnitude': std_mag,
        'coverage': coverage
    }


def estimate_overlap(flow_magnitude: float, image_width: int, image_height: int = None) -> float:
    """
    Estimate overlap percentage from optical flow magnitude.

    Assumes the flow magnitude represents the average pixel displacement.
    Overlap is approximated as (1 - displacement/image_size) * 100.

    Uses mean of width and height to handle various aspect ratios.

    Args:
        flow_magnitude: Mean flow magnitude in pixels
        image_width: Image width in pixels
        image_height: Image height in pixels (if None, uses width only)

    Returns:
        Estimated overlap percentage (0-100)
    """
    if image_height is not None:
        image_size = (image_width + image_height) / 2
    else:
        image_size = image_width

    displacement_ratio = flow_magnitude / image_size
    overlap = max(0, (1 - displacement_ratio)) * 100
    return overlap


def get_image_files(directory: str, camera: str = None) -> List[Path]:
    """Get sorted image files from directory."""
    extensions = {'.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG'}

    if camera:
        subdir = Path(directory) / f"video_{camera}"
        if subdir.exists():
            images = []
            for ext in extensions:
                images.extend(subdir.glob(f'*{ext}'))
            return sorted(images)

    # Get all images
    images = []
    for ext in extensions:
        images.extend(Path(directory).rglob(f'*{ext}'))

    # Exclude blurred and skipped directories
    images = [img for img in images if 'blurred' not in str(img) and 'skipped' not in str(img)]

    return sorted(images)


def analyze_optical_flow(images_dir: str, output_csv: str = None, camera: str = None) -> List[Dict]:
    """
    Analyze optical flow between all consecutive frame pairs.

    Args:
        images_dir: Directory containing images
        output_csv: Output CSV path (optional)
        camera: Camera to analyze ('W', 'Z', or None for both)

    Returns:
        List of flow analysis results
    """
    results = []

    if camera:
        cameras = [camera]
    else:
        cameras = ['W', 'Z']

    for cam in cameras:
        images = get_image_files(images_dir, cam)

        if len(images) < 2:
            print(f"  Camera {cam}: Not enough images ({len(images)})")
            continue

        print(f"  Camera {cam}: Analyzing {len(images) - 1} frame pairs...")

        # Get image dimensions
        sample_img = cv2.imread(str(images[0]))
        if sample_img is None:
            print(f"  WARNING: Could not read sample image")
            continue
        img_height, img_width = sample_img.shape[:2]

        for i in range(len(images) - 1):
            if (i + 1) % 20 == 0:
                print(f"    Processing pair {i + 1}/{len(images) - 1}...")

            try:
                flow = compute_optical_flow(str(images[i]), str(images[i + 1]))
                overlap = estimate_overlap(flow['mean_magnitude'], img_width, img_height)

                results.append({
                    'camera': cam,
                    'frame1': images[i].name,
                    'frame2': images[i + 1].name,
                    'frame1_path': images[i],
                    'frame2_path': images[i + 1],
                    'mean_flow': flow['mean_magnitude'],
                    'max_flow': flow['max_magnitude'],
                    'estimated_overlap': overlap,
                    'image_width': img_width,
                    'image_height': img_height
                })
            except Exception as e:
                print(f"    WARNING: Could not process pair {i}: {e}")

    # Save CSV if requested
    if output_csv and results:
        with open(output_csv, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['camera', 'frame1', 'frame2', 'mean_flow', 'max_flow', 'estimated_overlap'])

            for r in results:
                writer.writerow([
                    r['camera'],
                    r['frame1'],
                    r['frame2'],
                    f"{r['mean_flow']:.2f}",
                    f"{r['max_flow']:.2f}",
                    f"{r['estimated_overlap']:.1f}"
                ])

        print(f"  Analysis saved to: {output_csv}")

    return results


def select_keyframes(images_dir: str, target_overlap: float = 99.0, camera: str = None) -> Dict:
    """
    Select keyframes such that consecutive keyframes have approximately target overlap.

    Algorithm:
    1. Start with first frame as keyframe
    2. Accumulate flow from last keyframe
    3. When accumulated flow corresponds to (100 - target_overlap)% displacement, mark as keyframe
    4. Reset accumulator, repeat

    Args:
        images_dir: Directory containing images
        target_overlap: Target overlap percentage between consecutive keyframes (default: 99% based on 0.5fps analysis)
        camera: Camera to process ('W', 'Z', or None for both)

    Returns:
        Dictionary with:
            - keyframes: List of keyframe paths
            - non_keyframes: List of non-keyframe paths
            - stats: Selection statistics
    """
    keyframes = []
    non_keyframes = []

    if camera:
        cameras = [camera]
    else:
        cameras = ['W', 'Z']

    # Target displacement as ratio (100% overlap = 0 displacement, 0% overlap = 1.0 displacement)
    target_displacement_ratio = (100 - target_overlap) / 100.0

    for cam in cameras:
        images = get_image_files(images_dir, cam)

        if len(images) < 2:
            print(f"  Camera {cam}: Not enough images ({len(images)})")
            keyframes.extend(images)  # Keep all if too few
            continue

        print(f"  Camera {cam}: Selecting keyframes from {len(images)} images...")

        # Get image dimensions
        sample_img = cv2.imread(str(images[0]))
        if sample_img is None:
            continue
        img_height, img_width = sample_img.shape[:2]

        # Use mean of width and height to handle various aspect ratios
        image_size = (img_width + img_height) / 2

        # Target accumulated flow before selecting next keyframe
        target_accumulated_flow = target_displacement_ratio * image_size

        # Start with first frame as keyframe
        cam_keyframes = [images[0]]
        cam_non_keyframes = []
        accumulated_flow = 0.0
        last_keyframe_idx = 0

        for i in range(len(images) - 1):
            try:
                flow = compute_optical_flow(str(images[i]), str(images[i + 1]))
                accumulated_flow += flow['mean_magnitude']

                if accumulated_flow >= target_accumulated_flow:
                    # Select next frame as keyframe
                    cam_keyframes.append(images[i + 1])
                    accumulated_flow = 0.0
                    last_keyframe_idx = i + 1
                else:
                    # Not a keyframe
                    cam_non_keyframes.append(images[i + 1])

            except Exception as e:
                # On error, keep the frame as keyframe to be safe
                cam_keyframes.append(images[i + 1])
                accumulated_flow = 0.0

        # Always include last frame if not already
        if images[-1] not in cam_keyframes:
            cam_keyframes.append(images[-1])
            if images[-1] in cam_non_keyframes:
                cam_non_keyframes.remove(images[-1])

        print(f"    Selected {len(cam_keyframes)}/{len(images)} keyframes ({100*len(cam_keyframes)/len(images):.1f}%)")

        keyframes.extend(cam_keyframes)
        non_keyframes.extend(cam_non_keyframes)

    return {
        'keyframes': keyframes,
        'non_keyframes': non_keyframes,
        'stats': {
            'total_frames': len(keyframes) + len(non_keyframes),
            'keyframe_count': len(keyframes),
            'target_overlap': target_overlap
        }
    }


def save_keyframes_list(keyframes: List[Path], output_path: str, base_dir: str = None):
    """Save list of keyframe paths to a text file."""
    with open(output_path, 'w', encoding='utf-8') as f:
        for kf in keyframes:
            if base_dir:
                rel_path = kf.relative_to(base_dir)
                f.write(f"{rel_path}\n")
            else:
                f.write(f"{kf}\n")

    print(f"  Keyframes list saved to: {output_path}")


def remove_non_keyframes(images_dir: str, non_keyframes: List[Path], dry_run: bool = True) -> int:
    """
    Move non-keyframes to 'skipped/' subfolder.

    Args:
        images_dir: Base images directory
        non_keyframes: List of non-keyframe paths
        dry_run: If True, only print what would be done

    Returns:
        Number of frames moved/to be moved
    """
    if not non_keyframes:
        print("  No non-keyframes to remove")
        return 0

    skipped_dir = Path(images_dir) / "skipped"

    if dry_run:
        print(f"  DRY RUN: Would move {len(non_keyframes)} non-keyframes to {skipped_dir}")
        for nk in non_keyframes[:5]:
            print(f"    - {nk.name}")
        if len(non_keyframes) > 5:
            print(f"    ... and {len(non_keyframes) - 5} more")
    else:
        # Create skipped directory structure
        for camera in ['video_W', 'video_Z']:
            camera_skipped_dir = skipped_dir / camera
            if not camera_skipped_dir.exists():
                camera_skipped_dir.mkdir(parents=True, exist_ok=True)

        moved = 0
        for nk in non_keyframes:
            if 'video_W' in str(nk):
                dest = skipped_dir / 'video_W' / nk.name
            elif 'video_Z' in str(nk):
                dest = skipped_dir / 'video_Z' / nk.name
            else:
                dest = skipped_dir / nk.name

            try:
                shutil.move(str(nk), str(dest))
                moved += 1
            except Exception as e:
                print(f"  WARNING: Could not move {nk}: {e}")

        print(f"  Moved {moved} non-keyframes to {skipped_dir}")

    return len(non_keyframes)


def main():
    parser = argparse.ArgumentParser(
        description='Compute optical flow and select keyframes with target overlap',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Analyze optical flow only
    python optical_flow_analyzer.py output/images --analyze

    # Select keyframes with 50% target overlap
    python optical_flow_analyzer.py output/images --select-keyframes --target-overlap 50

    # Select keyframes and remove non-keyframes
    python optical_flow_analyzer.py output/images --select-keyframes --remove-non-keyframes

    # Dry run (show what would be removed)
    python optical_flow_analyzer.py output/images --select-keyframes --remove-non-keyframes --dry-run

Flow Interpretation:
    Mean Flow    Interpretation
    ---------    --------------
    < 5 px       Redundant frames (can reduce FPS)
    5-15 px      Good for matching
    15-30 px     High motion (may lose overlap)
    > 30 px      Risk of tracking failure
"""
    )

    parser.add_argument('images_dir', help='Directory containing images (with video_W/video_Z subfolders)')
    parser.add_argument('--analyze', action='store_true', help='Analyze optical flow between consecutive frames')
    parser.add_argument('--select-keyframes', action='store_true', help='Select keyframes with target overlap')
    parser.add_argument('--target-overlap', type=float, default=80.0, help='Target overlap %% between keyframes (default: 80)')
    parser.add_argument('--remove-non-keyframes', action='store_true', help='Remove non-keyframes (move to skipped/)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be removed without actually removing')
    parser.add_argument('--output-csv', help='Output CSV path for flow analysis')
    parser.add_argument('--output-keyframes', help='Output path for keyframes list')
    parser.add_argument('--camera', choices=['W', 'Z'], help='Process only specified camera')

    args = parser.parse_args()

    if not os.path.isdir(args.images_dir):
        print(f"ERROR: Directory not found: {args.images_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"\nOptical Flow Analysis")
    print(f"=====================")
    print(f"Images directory: {args.images_dir}")

    # Analyze optical flow
    if args.analyze:
        output_csv = args.output_csv or os.path.join(args.images_dir, 'optical_flow_analysis.csv')
        results = analyze_optical_flow(args.images_dir, output_csv, args.camera)

        if results:
            # Print statistics
            flows = [r['mean_flow'] for r in results]
            overlaps = [r['estimated_overlap'] for r in results]

            print(f"\nFlow Statistics:")
            print(f"  Mean flow: {np.mean(flows):.2f} px")
            print(f"  Std flow:  {np.std(flows):.2f} px")
            print(f"  Min flow:  {np.min(flows):.2f} px")
            print(f"  Max flow:  {np.max(flows):.2f} px")
            print(f"\nOverlap Statistics:")
            print(f"  Mean overlap: {np.mean(overlaps):.1f}%")
            print(f"  Min overlap:  {np.min(overlaps):.1f}%")
            print(f"  Max overlap:  {np.max(overlaps):.1f}%")

    # Select keyframes
    if args.select_keyframes:
        print(f"\nSelecting keyframes (target overlap: {args.target_overlap}%)...")

        result = select_keyframes(args.images_dir, args.target_overlap, args.camera)

        print(f"\nKeyframe Selection Results:")
        print(f"  Total frames:  {result['stats']['total_frames']}")
        print(f"  Keyframes:     {result['stats']['keyframe_count']}")
        print(f"  Reduction:     {100 * (1 - result['stats']['keyframe_count'] / result['stats']['total_frames']):.1f}%")

        # Save keyframes list
        keyframes_path = args.output_keyframes or os.path.join(args.images_dir, 'keyframes.txt')
        save_keyframes_list(result['keyframes'], keyframes_path, args.images_dir)

        # Remove non-keyframes if requested
        if args.remove_non_keyframes:
            print(f"\nRemoving non-keyframes...")
            remove_non_keyframes(args.images_dir, result['non_keyframes'], dry_run=args.dry_run)

    print(f"\nDone.")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
blur_detector.py - Detect and remove blurred frames using Laplacian Variance

Uses cv2.Laplacian variance method:
- High variance = sharp image
- Low variance = blurred image

Usage:
    python blur_detector.py <images_dir> [options]

Examples:
    python blur_detector.py output/images --analyze
    python blur_detector.py output/images --threshold 100 --remove
    python blur_detector.py output/images --auto-threshold --remove
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


def compute_laplacian_variance(image_path: str) -> float:
    """
    Compute Laplacian variance for blur detection.
    Higher variance = sharper image.

    Args:
        image_path: Path to the image file

    Returns:
        Laplacian variance value (higher = sharper)
    """
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    laplacian = cv2.Laplacian(img, cv2.CV_64F)
    variance = laplacian.var()
    return float(variance)


def get_image_files(directory: str) -> List[Path]:
    """Get all image files from a directory (recursively)."""
    extensions = {'.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG'}
    images = []

    for ext in extensions:
        images.extend(Path(directory).rglob(f'*{ext}'))

    return sorted(images)


def detect_blurred_frames(images_dir: str, threshold: Optional[float] = None) -> Dict:
    """
    Analyze all frames and detect blurred ones.

    Args:
        images_dir: Directory containing images (can have video_W/video_Z subfolders)
        threshold: Blur threshold. If None, auto-detect using mean - 1*std

    Returns:
        Dictionary with:
            - scores: List of (path, camera, laplacian_var, is_blurred)
            - threshold: The threshold used
            - auto_threshold: Whether threshold was auto-detected
            - stats: Statistics (mean, std, min, max)
    """
    images = get_image_files(images_dir)

    if not images:
        raise ValueError(f"No images found in {images_dir}")

    print(f"Analyzing {len(images)} images for blur...")

    # Compute Laplacian variance for all images
    scores = []
    for i, img_path in enumerate(images):
        if (i + 1) % 50 == 0 or i == 0:
            print(f"  Processing {i + 1}/{len(images)}...")

        try:
            variance = compute_laplacian_variance(str(img_path))

            # Determine camera from path
            camera = "unknown"
            if "video_W" in str(img_path):
                camera = "W"
            elif "video_Z" in str(img_path):
                camera = "Z"

            scores.append({
                'path': img_path,
                'camera': camera,
                'laplacian_var': variance,
                'is_blurred': False  # Will be set after threshold determination
            })
        except Exception as e:
            print(f"  WARNING: Could not process {img_path}: {e}")

    if not scores:
        raise ValueError("Could not process any images")

    # Compute statistics
    variances = [s['laplacian_var'] for s in scores]
    stats = {
        'mean': np.mean(variances),
        'std': np.std(variances),
        'min': np.min(variances),
        'max': np.max(variances),
        'count': len(variances)
    }

    # Auto-detect threshold if not provided
    auto_threshold = threshold is None
    if auto_threshold:
        # Use mean - 1*std as cutoff (removes bottom ~16% if normally distributed)
        threshold = stats['mean'] - stats['std']
        threshold = max(threshold, 50)  # Minimum threshold of 50
        print(f"  Auto-detected threshold: {threshold:.2f} (mean - 1*std)")

    # Mark blurred frames
    blurred_count = 0
    for score in scores:
        score['is_blurred'] = score['laplacian_var'] < threshold
        if score['is_blurred']:
            blurred_count += 1

    print(f"  Found {blurred_count}/{len(scores)} blurred frames ({100*blurred_count/len(scores):.1f}%)")

    return {
        'scores': scores,
        'threshold': threshold,
        'auto_threshold': auto_threshold,
        'stats': stats,
        'blurred_count': blurred_count
    }


def save_analysis_csv(scores: List[Dict], output_path: str):
    """Save blur analysis results to CSV."""
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['camera', 'frame', 'laplacian_var', 'is_blurred'])

        for score in scores:
            writer.writerow([
                score['camera'],
                score['path'].name,
                f"{score['laplacian_var']:.2f}",
                str(score['is_blurred'])
            ])

    print(f"  Analysis saved to: {output_path}")


def remove_blurred_frames(images_dir: str, scores: List[Dict], dry_run: bool = True) -> int:
    """
    Move blurred frames to 'blurred/' subfolder.

    Args:
        images_dir: Base images directory
        scores: Analysis scores from detect_blurred_frames
        dry_run: If True, only print what would be done

    Returns:
        Number of frames moved/to be moved
    """
    blurred_dir = Path(images_dir) / "blurred"

    blurred_frames = [s for s in scores if s['is_blurred']]

    if not blurred_frames:
        print("  No blurred frames to remove")
        return 0

    if dry_run:
        print(f"  DRY RUN: Would move {len(blurred_frames)} blurred frames to {blurred_dir}")
        for s in blurred_frames[:5]:
            print(f"    - {s['path'].name} (var={s['laplacian_var']:.2f})")
        if len(blurred_frames) > 5:
            print(f"    ... and {len(blurred_frames) - 5} more")
    else:
        # Create blurred directory structure
        for camera in ['video_W', 'video_Z']:
            camera_blurred_dir = blurred_dir / camera
            if not camera_blurred_dir.exists():
                camera_blurred_dir.mkdir(parents=True, exist_ok=True)

        moved = 0
        for s in blurred_frames:
            src = s['path']

            # Determine destination based on camera
            if s['camera'] == 'W':
                dest = blurred_dir / 'video_W' / src.name
            elif s['camera'] == 'Z':
                dest = blurred_dir / 'video_Z' / src.name
            else:
                dest = blurred_dir / src.name

            try:
                shutil.move(str(src), str(dest))
                moved += 1
            except Exception as e:
                print(f"  WARNING: Could not move {src}: {e}")

        print(f"  Moved {moved} blurred frames to {blurred_dir}")

    return len(blurred_frames)


def limit_frame_count(images_dir: str, max_total: int = 400, dry_run: bool = True) -> int:
    """
    If total frames > max_total, uniformly subsample.
    Preserves temporal distribution by keeping every Nth frame.

    Args:
        images_dir: Directory containing images
        max_total: Maximum total frames to keep
        dry_run: If True, only print what would be done

    Returns:
        Number of frames removed/to be removed
    """
    images = get_image_files(images_dir)

    # Exclude blurred directory
    images = [img for img in images if 'blurred' not in str(img)]

    if len(images) <= max_total:
        print(f"  Frame count ({len(images)}) is within limit ({max_total})")
        return 0

    # Group by camera
    w_images = sorted([img for img in images if 'video_W' in str(img)])
    z_images = sorted([img for img in images if 'video_Z' in str(img)])

    # Calculate how many to keep from each camera (preserve ratio)
    total = len(w_images) + len(z_images)
    w_ratio = len(w_images) / total if total > 0 else 0.5

    w_keep = int(max_total * w_ratio)
    z_keep = max_total - w_keep

    # Select frames uniformly
    def uniform_sample(frames: List[Path], keep: int) -> Tuple[List[Path], List[Path]]:
        if len(frames) <= keep:
            return frames, []

        indices = np.linspace(0, len(frames) - 1, keep, dtype=int)
        keep_set = set(indices)

        to_keep = [frames[i] for i in range(len(frames)) if i in keep_set]
        to_remove = [frames[i] for i in range(len(frames)) if i not in keep_set]

        return to_keep, to_remove

    w_keep_list, w_remove = uniform_sample(w_images, w_keep)
    z_keep_list, z_remove = uniform_sample(z_images, z_keep)

    to_remove = w_remove + z_remove

    print(f"  Limiting frames from {len(images)} to {max_total}")
    print(f"    W: {len(w_images)} -> {len(w_keep_list)}")
    print(f"    Z: {len(z_images)} -> {len(z_keep_list)}")

    if dry_run:
        print(f"  DRY RUN: Would move {len(to_remove)} excess frames to skipped/")
    else:
        skipped_dir = Path(images_dir) / "skipped"

        for camera in ['video_W', 'video_Z']:
            camera_skipped_dir = skipped_dir / camera
            if not camera_skipped_dir.exists():
                camera_skipped_dir.mkdir(parents=True, exist_ok=True)

        moved = 0
        for img_path in to_remove:
            if 'video_W' in str(img_path):
                dest = skipped_dir / 'video_W' / img_path.name
            elif 'video_Z' in str(img_path):
                dest = skipped_dir / 'video_Z' / img_path.name
            else:
                dest = skipped_dir / img_path.name

            try:
                shutil.move(str(img_path), str(dest))
                moved += 1
            except Exception as e:
                print(f"  WARNING: Could not move {img_path}: {e}")

        print(f"  Moved {moved} excess frames to {skipped_dir}")

    return len(to_remove)


def main():
    parser = argparse.ArgumentParser(
        description='Detect and remove blurred frames using Laplacian Variance',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Analyze only (no changes)
    python blur_detector.py output/images --analyze

    # Auto-detect threshold and remove blurred frames
    python blur_detector.py output/images --auto-threshold --remove

    # Use specific threshold
    python blur_detector.py output/images --threshold 100 --remove

    # Dry run (show what would be removed)
    python blur_detector.py output/images --threshold 100 --remove --dry-run
"""
    )

    parser.add_argument('images_dir', help='Directory containing images (with video_W/video_Z subfolders)')
    parser.add_argument('--analyze', action='store_true', help='Only analyze, do not remove')
    parser.add_argument('--threshold', type=float, help='Blur threshold (lower = blurred)')
    parser.add_argument('--auto-threshold', action='store_true', help='Auto-detect threshold using mean - 1*std')
    parser.add_argument('--remove', action='store_true', help='Remove blurred frames (move to blurred/ subfolder)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be removed without actually removing')
    parser.add_argument('--output-csv', help='Output CSV path for analysis (default: blur_analysis.csv in images_dir)')
    parser.add_argument('--max-frames', type=int, default=400, help='Maximum total frames to keep (default: 400)')
    parser.add_argument('--limit-frames', action='store_true', help='Limit total frame count to --max-frames')

    args = parser.parse_args()

    if not os.path.isdir(args.images_dir):
        print(f"ERROR: Directory not found: {args.images_dir}", file=sys.stderr)
        sys.exit(1)

    # Determine threshold
    threshold = args.threshold
    if args.auto_threshold:
        threshold = None  # Will be auto-detected
    elif threshold is None and not args.analyze:
        print("ERROR: Must specify --threshold, --auto-threshold, or --analyze", file=sys.stderr)
        sys.exit(1)

    # Detect blurred frames
    print(f"\nBlur Detection Analysis")
    print(f"=======================")
    print(f"Images directory: {args.images_dir}")

    result = detect_blurred_frames(args.images_dir, threshold)

    # Print statistics
    print(f"\nStatistics:")
    print(f"  Mean Laplacian variance: {result['stats']['mean']:.2f}")
    print(f"  Std Laplacian variance:  {result['stats']['std']:.2f}")
    print(f"  Min Laplacian variance:  {result['stats']['min']:.2f}")
    print(f"  Max Laplacian variance:  {result['stats']['max']:.2f}")
    print(f"  Threshold used:          {result['threshold']:.2f}")
    print(f"  Blurred frames:          {result['blurred_count']}/{result['stats']['count']}")

    # Save CSV
    csv_path = args.output_csv or os.path.join(args.images_dir, 'blur_analysis.csv')
    save_analysis_csv(result['scores'], csv_path)

    # Remove blurred frames if requested
    if args.remove:
        print(f"\nRemoving blurred frames...")
        remove_blurred_frames(args.images_dir, result['scores'], dry_run=args.dry_run)

    # Limit frame count if requested
    if args.limit_frames:
        print(f"\nLimiting frame count to {args.max_frames}...")
        limit_frame_count(args.images_dir, args.max_frames, dry_run=args.dry_run)

    print(f"\nDone.")


if __name__ == '__main__':
    main()

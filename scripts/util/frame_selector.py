#!/usr/bin/env python3
"""
frame_selector.py - Combined blur removal, keyframe selection, and frame limiting

This script provides the complete workflow for intelligent frame selection:
1. Blur detection and removal (Laplacian Variance)
2. Optical flow-based keyframe selection (~50% overlap)
3. Frame count limiting (max 400 frames)

Usage:
    python frame_selector.py <images_dir> [options]

Examples:
    # Full workflow with default settings
    python frame_selector.py output/images --run-all

    # Dry run to see what would happen
    python frame_selector.py output/images --run-all --dry-run

    # Custom settings
    python frame_selector.py output/images --run-all --blur-threshold 100 --target-overlap 50 --max-frames 400
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List

# Import from sibling modules
try:
    from blur_detector import (
        detect_blurred_frames,
        remove_blurred_frames,
        save_analysis_csv as save_blur_csv
    )
    from optical_flow_analyzer import (
        select_keyframes,
        save_keyframes_list,
        remove_non_keyframes,
        analyze_optical_flow
    )
except ImportError:
    # When running as standalone script
    import importlib.util

    script_dir = Path(__file__).parent

    spec = importlib.util.spec_from_file_location("blur_detector", script_dir / "blur_detector.py")
    blur_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(blur_module)

    spec = importlib.util.spec_from_file_location("optical_flow_analyzer", script_dir / "optical_flow_analyzer.py")
    flow_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flow_module)

    detect_blurred_frames = blur_module.detect_blurred_frames
    remove_blurred_frames = blur_module.remove_blurred_frames
    save_blur_csv = blur_module.save_analysis_csv

    select_keyframes = flow_module.select_keyframes
    save_keyframes_list = flow_module.save_keyframes_list
    remove_non_keyframes = flow_module.remove_non_keyframes
    analyze_optical_flow = flow_module.analyze_optical_flow


def count_frames(images_dir: str) -> Dict[str, int]:
    """Count frames in the images directory."""
    extensions = {'.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG'}

    w_dir = Path(images_dir) / "video_W"
    z_dir = Path(images_dir) / "video_Z"

    w_count = 0
    z_count = 0

    if w_dir.exists():
        for ext in extensions:
            w_count += len(list(w_dir.glob(f'*{ext}')))

    if z_dir.exists():
        for ext in extensions:
            z_count += len(list(z_dir.glob(f'*{ext}')))

    return {
        'W': w_count,
        'Z': z_count,
        'total': w_count + z_count
    }


def limit_frame_count(images_dir: str, max_total: int, dry_run: bool = True) -> int:
    """
    Limit total frame count by uniform subsampling.
    This is called after keyframe selection to ensure we don't exceed the max.
    """
    import shutil
    import numpy as np

    extensions = {'.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG'}

    # Get current frames (excluding blurred/skipped)
    w_dir = Path(images_dir) / "video_W"
    z_dir = Path(images_dir) / "video_Z"

    w_images = []
    z_images = []

    if w_dir.exists():
        for ext in extensions:
            w_images.extend(list(w_dir.glob(f'*{ext}')))
        w_images = sorted(w_images)

    if z_dir.exists():
        for ext in extensions:
            z_images.extend(list(z_dir.glob(f'*{ext}')))
        z_images = sorted(z_images)

    total = len(w_images) + len(z_images)

    if total <= max_total:
        print(f"  Frame count ({total}) is within limit ({max_total})")
        return 0

    # Calculate how many to keep from each camera
    w_ratio = len(w_images) / total if total > 0 else 0.5
    w_keep = int(max_total * w_ratio)
    z_keep = max_total - w_keep

    def uniform_sample(frames: List[Path], keep: int):
        if len(frames) <= keep:
            return frames, []
        indices = set(np.linspace(0, len(frames) - 1, keep, dtype=int))
        to_keep = [frames[i] for i in range(len(frames)) if i in indices]
        to_remove = [frames[i] for i in range(len(frames)) if i not in indices]
        return to_keep, to_remove

    _, w_remove = uniform_sample(w_images, w_keep)
    _, z_remove = uniform_sample(z_images, z_keep)

    to_remove = w_remove + z_remove

    print(f"  Limiting frames from {total} to {max_total}")
    print(f"    W: {len(w_images)} -> {len(w_images) - len(w_remove)}")
    print(f"    Z: {len(z_images)} -> {len(z_images) - len(z_remove)}")

    if dry_run:
        print(f"  DRY RUN: Would move {len(to_remove)} excess frames to limited/")
    else:
        limited_dir = Path(images_dir) / "limited"

        for camera in ['video_W', 'video_Z']:
            camera_limited_dir = limited_dir / camera
            if not camera_limited_dir.exists():
                camera_limited_dir.mkdir(parents=True, exist_ok=True)

        moved = 0
        for img_path in to_remove:
            if 'video_W' in str(img_path):
                dest = limited_dir / 'video_W' / img_path.name
            else:
                dest = limited_dir / 'video_Z' / img_path.name

            try:
                shutil.move(str(img_path), str(dest))
                moved += 1
            except Exception as e:
                print(f"  WARNING: Could not move {img_path}: {e}")

        print(f"  Moved {moved} excess frames to {limited_dir}")

    return len(to_remove)


def run_full_pipeline(
    images_dir: str,
    blur_threshold: float = None,
    target_overlap: float = 99.0,  # Based on 0.5fps analysis showing 98.8% overlap
    max_frames: int = 400,
    dry_run: bool = True
) -> Dict:
    """
    Run the complete frame selection pipeline.

    Steps:
    1. Blur detection and removal
    2. Optical flow analysis and keyframe selection
    3. Frame count limiting

    Args:
        images_dir: Directory containing images (video_W/video_Z subfolders)
        blur_threshold: Blur threshold (None for auto-detect)
        target_overlap: Target overlap for keyframe selection
        max_frames: Maximum total frames to keep
        dry_run: If True, only show what would be done

    Returns:
        Summary of operations performed
    """
    results = {
        'initial_frames': count_frames(images_dir),
        'blur_removed': 0,
        'keyframes_selected': 0,
        'frames_limited': 0,
        'final_frames': None
    }

    print(f"\n" + "=" * 60)
    print(f"Frame Selection Pipeline")
    print(f"=" * 60)
    print(f"Images directory: {images_dir}")
    print(f"Initial frame count: {results['initial_frames']['total']} (W: {results['initial_frames']['W']}, Z: {results['initial_frames']['Z']})")
    if dry_run:
        print(f"MODE: DRY RUN (no files will be moved)")
    print(f"=" * 60)

    # Step 1: Blur Detection and Removal
    print(f"\n--- Step 1: Blur Detection ---")
    try:
        blur_result = detect_blurred_frames(images_dir, blur_threshold)

        print(f"  Threshold: {blur_result['threshold']:.2f}")
        print(f"  Blurred frames: {blur_result['blurred_count']}/{blur_result['stats']['count']}")

        # Save blur analysis
        blur_csv = os.path.join(images_dir, 'blur_analysis.csv')
        save_blur_csv(blur_result['scores'], blur_csv)

        # Remove blurred frames
        results['blur_removed'] = remove_blurred_frames(
            images_dir, blur_result['scores'], dry_run=dry_run
        )
    except Exception as e:
        print(f"  ERROR in blur detection: {e}")

    # Step 2: Optical Flow Keyframe Selection
    print(f"\n--- Step 2: Keyframe Selection (target overlap: {target_overlap}%) ---")
    try:
        # Analyze flow first
        flow_csv = os.path.join(images_dir, 'optical_flow_analysis.csv')
        analyze_optical_flow(images_dir, flow_csv)

        # Select keyframes
        keyframe_result = select_keyframes(images_dir, target_overlap)

        print(f"  Total frames (after blur removal): {keyframe_result['stats']['total_frames']}")
        print(f"  Keyframes selected: {keyframe_result['stats']['keyframe_count']}")

        # Save keyframes list
        keyframes_path = os.path.join(images_dir, 'keyframes.txt')
        save_keyframes_list(keyframe_result['keyframes'], keyframes_path, images_dir)

        # Remove non-keyframes
        removed = remove_non_keyframes(
            images_dir, keyframe_result['non_keyframes'], dry_run=dry_run
        )
        results['keyframes_selected'] = keyframe_result['stats']['keyframe_count']
    except Exception as e:
        print(f"  ERROR in keyframe selection: {e}")

    # Step 3: Frame Count Limiting
    print(f"\n--- Step 3: Frame Count Limiting (max: {max_frames}) ---")
    try:
        results['frames_limited'] = limit_frame_count(images_dir, max_frames, dry_run=dry_run)
    except Exception as e:
        print(f"  ERROR in frame limiting: {e}")

    # Final count
    if not dry_run:
        results['final_frames'] = count_frames(images_dir)
    else:
        # Estimate final count
        estimated = results['initial_frames']['total'] - results['blur_removed']
        estimated = min(estimated, results['keyframes_selected']) if results['keyframes_selected'] > 0 else estimated
        estimated = min(estimated, max_frames)
        results['final_frames'] = {'total': estimated, 'W': '~', 'Z': '~'}

    # Summary
    print(f"\n" + "=" * 60)
    print(f"Summary")
    print(f"=" * 60)
    print(f"  Initial frames:    {results['initial_frames']['total']}")
    print(f"  Blurred removed:   {results['blur_removed']}")
    print(f"  Non-keyframes:     {results['initial_frames']['total'] - results['blur_removed'] - results['keyframes_selected'] if results['keyframes_selected'] > 0 else 0}")
    print(f"  Limited:           {results['frames_limited']}")
    if dry_run:
        print(f"  Estimated final:   ~{results['final_frames']['total']}")
    else:
        print(f"  Final frames:      {results['final_frames']['total']} (W: {results['final_frames']['W']}, Z: {results['final_frames']['Z']})")
    print(f"=" * 60)

    return results


def main():
    parser = argparse.ArgumentParser(
        description='Combined blur removal, keyframe selection, and frame limiting',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
The frame selection pipeline:
  1. BLUR DETECTION: Remove blurred frames using Laplacian Variance
  2. KEYFRAME SELECTION: Select frames with ~50% overlap using optical flow
  3. FRAME LIMITING: Ensure total frames don't exceed maximum (default 400)

Removed frames are moved to subfolders (blurred/, skipped/, limited/) and can
be restored by moving them back.

Examples:
    # Full pipeline with default settings (dry run)
    python frame_selector.py output/images --run-all --dry-run

    # Full pipeline (actually move files)
    python frame_selector.py output/images --run-all

    # Custom settings
    python frame_selector.py output/images --run-all --blur-threshold 100 --target-overlap 50 --max-frames 300
"""
    )

    parser.add_argument('images_dir', help='Directory containing images (with video_W/video_Z subfolders)')
    parser.add_argument('--run-all', action='store_true', help='Run complete pipeline')
    parser.add_argument('--blur-threshold', type=float, help='Blur threshold (None for auto-detect)')
    parser.add_argument('--target-overlap', type=float, default=80.0, help='Target overlap %% for keyframe selection (default: 80)')
    parser.add_argument('--max-frames', type=int, default=400, help='Maximum total frames to keep (default: 400)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without moving files')

    # Individual steps
    parser.add_argument('--blur-only', action='store_true', help='Only run blur detection')
    parser.add_argument('--flow-only', action='store_true', help='Only run optical flow analysis')
    parser.add_argument('--keyframes-only', action='store_true', help='Only run keyframe selection')
    parser.add_argument('--limit-only', action='store_true', help='Only run frame limiting')

    args = parser.parse_args()

    if not os.path.isdir(args.images_dir):
        print(f"ERROR: Directory not found: {args.images_dir}", file=sys.stderr)
        sys.exit(1)

    if args.run_all:
        run_full_pipeline(
            args.images_dir,
            blur_threshold=args.blur_threshold,
            target_overlap=args.target_overlap,
            max_frames=args.max_frames,
            dry_run=args.dry_run
        )
    elif args.blur_only:
        print(f"\nBlur Detection")
        print(f"==============")
        result = detect_blurred_frames(args.images_dir, args.blur_threshold)
        blur_csv = os.path.join(args.images_dir, 'blur_analysis.csv')
        save_blur_csv(result['scores'], blur_csv)
        remove_blurred_frames(args.images_dir, result['scores'], dry_run=args.dry_run)
    elif args.flow_only:
        print(f"\nOptical Flow Analysis")
        print(f"=====================")
        flow_csv = os.path.join(args.images_dir, 'optical_flow_analysis.csv')
        analyze_optical_flow(args.images_dir, flow_csv)
    elif args.keyframes_only:
        print(f"\nKeyframe Selection")
        print(f"==================")
        result = select_keyframes(args.images_dir, args.target_overlap)
        keyframes_path = os.path.join(args.images_dir, 'keyframes.txt')
        save_keyframes_list(result['keyframes'], keyframes_path, args.images_dir)
        remove_non_keyframes(args.images_dir, result['non_keyframes'], dry_run=args.dry_run)
    elif args.limit_only:
        print(f"\nFrame Limiting")
        print(f"==============")
        limit_frame_count(args.images_dir, args.max_frames, dry_run=args.dry_run)
    else:
        parser.print_help()
        sys.exit(1)

    print(f"\nDone.")


if __name__ == '__main__':
    main()

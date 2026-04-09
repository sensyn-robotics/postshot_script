#!/usr/bin/env python3
"""
Analyze optical flow and overlap for 0.5fps images.
Saves results to a text file for later reading.
"""

import os
import sys
from pathlib import Path

def main():
    # Find scene1 images
    test_data = Path("C:/postshot_test_data")
    scenes = sorted([d for d in test_data.iterdir() if d.is_dir()])

    if not scenes:
        print("ERROR: No scenes found")
        return 1

    scene1 = scenes[0]
    images_dir = scene1 / "output" / "images"

    if not images_dir.exists():
        print(f"ERROR: Images directory not found: {images_dir}")
        return 1

    print(f"Scene: {scene1.name}")
    print(f"Images: {images_dir}")

    # Try to import opencv
    try:
        import cv2
        import numpy as np
    except ImportError as e:
        print(f"ERROR: Cannot import required modules: {e}")
        print("Please install: pip install opencv-python numpy")

        # Write error to results file
        results_file = scene1 / "output" / "overlap_analysis.txt"
        with open(results_file, 'w') as f:
            f.write("ERROR: Python dependencies not installed\n")
            f.write("Required: opencv-python, numpy\n")
        return 1

    # Analyze W camera
    w_dir = images_dir / "video_W"
    z_dir = images_dir / "video_Z"

    results = []

    for camera_name, camera_dir in [("W", w_dir), ("Z", z_dir)]:
        if not camera_dir.exists():
            continue

        images = sorted([f for f in camera_dir.iterdir() if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

        if len(images) < 2:
            continue

        print(f"\nAnalyzing {camera_name} camera ({len(images)} frames)...")

        flows = []

        for i in range(len(images) - 1):
            img1 = cv2.imread(str(images[i]), cv2.IMREAD_GRAYSCALE)
            img2 = cv2.imread(str(images[i + 1]), cv2.IMREAD_GRAYSCALE)

            if img1 is None or img2 is None:
                continue

            # Compute optical flow
            flow = cv2.calcOpticalFlowFarneback(
                img1, img2, None,
                pyr_scale=0.5, levels=3, winsize=15,
                iterations=3, poly_n=5, poly_sigma=1.2, flags=0
            )

            # Compute magnitude
            magnitude = np.sqrt(flow[..., 0]**2 + flow[..., 1]**2)
            mean_flow = np.mean(magnitude)

            # Compute overlap using (width + height) / 2
            h, w = img1.shape
            image_size = (w + h) / 2
            overlap = max(0, (1 - mean_flow / image_size)) * 100

            flows.append({
                'frame': i,
                'mean_flow': mean_flow,
                'overlap': overlap,
                'width': w,
                'height': h
            })

            if (i + 1) % 20 == 0:
                print(f"  Processed {i + 1}/{len(images) - 1} pairs...")

        if flows:
            avg_flow = sum(f['mean_flow'] for f in flows) / len(flows)
            avg_overlap = sum(f['overlap'] for f in flows) / len(flows)
            min_overlap = min(f['overlap'] for f in flows)
            max_overlap = max(f['overlap'] for f in flows)

            results.append({
                'camera': camera_name,
                'pairs': len(flows),
                'avg_flow': avg_flow,
                'avg_overlap': avg_overlap,
                'min_overlap': min_overlap,
                'max_overlap': max_overlap,
                'image_size': (flows[0]['width'] + flows[0]['height']) / 2
            })

            print(f"  {camera_name}: avg_flow={avg_flow:.2f}px, avg_overlap={avg_overlap:.1f}%")

    # Save results
    results_file = scene1 / "output" / "overlap_analysis.txt"
    with open(results_file, 'w', encoding='utf-8') as f:
        f.write("=== 0.5fps Optical Flow Analysis ===\n\n")

        for r in results:
            f.write(f"Camera {r['camera']}:\n")
            f.write(f"  Frame pairs analyzed: {r['pairs']}\n")
            f.write(f"  Image size (w+h)/2: {r['image_size']:.0f}px\n")
            f.write(f"  Average flow: {r['avg_flow']:.2f}px\n")
            f.write(f"  Average overlap: {r['avg_overlap']:.1f}%\n")
            f.write(f"  Min overlap: {r['min_overlap']:.1f}%\n")
            f.write(f"  Max overlap: {r['max_overlap']:.1f}%\n\n")

        if results:
            overall_avg = sum(r['avg_overlap'] for r in results) / len(results)
            f.write(f"Overall average overlap: {overall_avg:.1f}%\n")
            f.write(f"\nRecommended target overlap: {overall_avg:.0f}%\n")

    print(f"\nResults saved to: {results_file}")

    # Also print summary
    if results:
        overall_avg = sum(r['avg_overlap'] for r in results) / len(results)
        print(f"\n=== SUMMARY ===")
        print(f"Overall average overlap at 0.5fps: {overall_avg:.1f}%")
        print(f"Recommended target overlap: {overall_avg:.0f}%")

    return 0

if __name__ == '__main__':
    sys.exit(main())

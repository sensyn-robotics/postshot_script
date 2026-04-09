#!/usr/bin/env python3
"""
Resize images for COLMAP resolution testing.
"""

import os
import sys
import argparse
from PIL import Image
from pathlib import Path


def resize_images(input_dir, output_dir, scale=0.5, max_dim=None):
    """
    Resize all images in input_dir and save to output_dir.

    Args:
        input_dir: Source directory (with video_W and video_Z subdirs)
        output_dir: Destination directory
        scale: Scale factor (0.5 = half resolution)
        max_dim: Maximum dimension (overrides scale if set)
    """
    input_path = Path(input_dir)
    output_path = Path(output_dir)

    if not input_path.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        return False

    # Create output directory
    output_path.mkdir(parents=True, exist_ok=True)

    # Process each subdirectory
    subdirs = ['video_W', 'video_Z']
    total_processed = 0

    for subdir in subdirs:
        src_dir = input_path / subdir
        dst_dir = output_path / subdir

        if not src_dir.exists():
            print(f"WARNING: Subdirectory not found: {src_dir}")
            continue

        dst_dir.mkdir(parents=True, exist_ok=True)

        # Get all image files
        images = list(src_dir.glob('*.png')) + list(src_dir.glob('*.jpg'))
        print(f"\n{subdir}: Processing {len(images)} images...")

        for i, img_path in enumerate(sorted(images)):
            try:
                with Image.open(img_path) as img:
                    orig_size = img.size

                    # Calculate new size
                    if max_dim:
                        # Scale to max dimension
                        ratio = max_dim / max(orig_size)
                        new_size = (int(orig_size[0] * ratio), int(orig_size[1] * ratio))
                    else:
                        # Scale by factor
                        new_size = (int(orig_size[0] * scale), int(orig_size[1] * scale))

                    # Resize
                    resized = img.resize(new_size, Image.Resampling.LANCZOS)

                    # Save
                    dst_path = dst_dir / img_path.name
                    resized.save(dst_path, quality=95)

                    if i == 0:
                        print(f"  {orig_size[0]}x{orig_size[1]} -> {new_size[0]}x{new_size[1]}")

                    total_processed += 1

            except Exception as e:
                print(f"  ERROR processing {img_path.name}: {e}")

    print(f"\nTotal processed: {total_processed} images")
    print(f"Output directory: {output_dir}")
    return True


def main():
    parser = argparse.ArgumentParser(description='Resize images for COLMAP testing')
    parser.add_argument('input_dir', help='Input images directory')
    parser.add_argument('output_dir', help='Output directory for resized images')
    parser.add_argument('--scale', type=float, default=0.5,
                       help='Scale factor (default: 0.5 = half resolution)')
    parser.add_argument('--max-dim', type=int, default=None,
                       help='Maximum dimension (overrides scale)')

    args = parser.parse_args()

    success = resize_images(
        args.input_dir,
        args.output_dir,
        scale=args.scale,
        max_dim=args.max_dim
    )

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

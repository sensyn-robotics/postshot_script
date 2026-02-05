#!/usr/bin/env python3
"""
Crop center of Wide (W) images to better match Zoom (Z) camera FOV.

The W camera has a wider FOV than Z camera. The center region of W overlaps
with Z's full view. By cropping W images to the center, we can:
1. Match feature scales between W and Z
2. Improve SIFT matching quality
3. Get better cross-camera registration

Usage:
    python crop_wide_images.py <input_dir> <output_dir> [--crop_ratio 0.4]
"""

import os
import sys
import argparse
from pathlib import Path
from PIL import Image


def crop_center(image: Image.Image, crop_ratio: float) -> Image.Image:
    """Crop the center region of an image.

    Args:
        image: PIL Image
        crop_ratio: Ratio of center to keep (0.4 = keep center 40%)

    Returns:
        Cropped PIL Image
    """
    width, height = image.size

    # Calculate crop box
    new_width = int(width * crop_ratio)
    new_height = int(height * crop_ratio)

    left = (width - new_width) // 2
    top = (height - new_height) // 2
    right = left + new_width
    bottom = top + new_height

    return image.crop((left, top, right, bottom))


def process_directory(input_dir: Path, output_dir: Path, crop_ratio: float,
                     resize_to_original: bool = True):
    """Process all images in a directory.

    Args:
        input_dir: Input directory with images
        output_dir: Output directory for cropped images
        crop_ratio: Ratio of center to keep
        resize_to_original: If True, resize cropped image back to original size
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    # Find all image files
    image_extensions = {'.png', '.jpg', '.jpeg', '.PNG', '.JPG', '.JPEG'}
    image_files = [f for f in input_dir.iterdir()
                   if f.is_file() and f.suffix in image_extensions]

    print(f"Processing {len(image_files)} images from {input_dir}")
    print(f"Crop ratio: {crop_ratio} (keeping center {crop_ratio*100:.0f}%)")
    if resize_to_original:
        print("Resizing cropped images back to original dimensions")

    for i, image_path in enumerate(sorted(image_files)):
        # Load image
        img = Image.open(image_path)
        original_size = img.size

        # Crop center
        cropped = crop_center(img, crop_ratio)

        # Optionally resize back to original
        if resize_to_original:
            cropped = cropped.resize(original_size, Image.Resampling.LANCZOS)

        # Save
        output_path = output_dir / image_path.name
        cropped.save(output_path, quality=95)

        if (i + 1) % 20 == 0:
            print(f"  Processed {i + 1}/{len(image_files)} images")

    print(f"Done. Output: {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description='Crop center of Wide camera images to match Zoom FOV'
    )
    parser.add_argument('input_dir', type=str, help='Input directory with W images')
    parser.add_argument('output_dir', type=str, help='Output directory for cropped images')
    parser.add_argument('--crop_ratio', type=float, default=0.4,
                       help='Ratio of center to keep (default: 0.4 = 40%%)')
    parser.add_argument('--no_resize', action='store_true',
                       help='Do not resize cropped images back to original size')

    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    if not input_dir.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    process_directory(
        input_dir,
        output_dir,
        args.crop_ratio,
        resize_to_original=not args.no_resize
    )


if __name__ == '__main__':
    main()

"""
cubemap_decompose.py - Convert equirectangular images to cubemap face images using FFmpeg v360 filter.

Standalone script that decomposes 360 equirectangular frames into 5 perspective
cubemap faces (front, right, back, left, top), excluding the bottom/nadir face.

Usage:
    python cubemap_decompose.py --input_dir <equirect_frames_dir> --output_dir <output_dir> [options]

Options:
    --fov         Field of view in degrees (default: 110)
    --output_size Output image size in pixels, 0=auto from input height (default: 0)
    --faces       Comma-separated list of faces (default: front,right,back,left,top)
    --ffmpeg      Path to FFmpeg executable (default: ffmpeg)

Based on EDGS convert_equirectangular_to_cubemap.py approach using FFmpeg v360=e:rectilinear.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Face definitions: name -> (yaw, pitch) in degrees for FFmpeg v360
FACE_DEFINITIONS = {
    "front": (0, 0),
    "right": (-90, 0),
    "back": (180, 0),
    "left": (90, 0),
    "top": (0, -90),
}

# Numbered prefix for deterministic COLMAP ordering
FACE_DIR_NAMES = {
    "front": "1_front",
    "right": "2_right",
    "back": "3_back",
    "left": "4_left",
    "top": "5_top",
}

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG"}


def get_image_size(image_path: str, ffmpeg_path: str) -> tuple[int, int]:
    """Get image dimensions using ffprobe (bundled with ffmpeg)."""
    ffprobe_path = str(Path(ffmpeg_path).parent / "ffprobe.exe")
    if not os.path.exists(ffprobe_path):
        ffprobe_path = str(Path(ffmpeg_path).parent / "ffprobe")
    if not os.path.exists(ffprobe_path):
        ffprobe_path = "ffprobe"

    cmd = [
        ffprobe_path,
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "csv=p=0:s=x",
        image_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed: {result.stderr}")
    parts = result.stdout.strip().split("x")
    return int(parts[0]), int(parts[1])


def decompose_frame(
    input_path: str,
    output_dir: str,
    face_name: str,
    yaw: float,
    pitch: float,
    fov: int,
    output_size: int,
    ffmpeg_path: str,
    output_filename: str,
) -> bool:
    """Decompose a single equirectangular image into one cubemap face."""
    face_dir_name = FACE_DIR_NAMES[face_name]
    face_output_dir = os.path.join(output_dir, face_dir_name)
    os.makedirs(face_output_dir, exist_ok=True)

    output_path = os.path.join(face_output_dir, output_filename)

    # Skip if output already exists
    if os.path.exists(output_path):
        return True

    # FFmpeg v360 filter: equirectangular to rectilinear (perspective)
    v360_filter = (
        f"v360=e:rectilinear"
        f":h_fov={fov}:v_fov={fov}"
        f":yaw={yaw}:pitch={pitch}"
        f":w={output_size}:h={output_size}"
    )

    cmd = [
        ffmpeg_path,
        "-i", input_path,
        "-vf", v360_filter,
        "-q:v", "2",
        "-y",
        output_path,
    ]

    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        print(f"  ERROR: FFmpeg failed for {output_filename} ({face_name}): {result.stderr}", file=sys.stderr)
        return False

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Convert equirectangular images to cubemap face images"
    )
    parser.add_argument(
        "--input_dir", required=True, help="Directory containing equirectangular PNG images"
    )
    parser.add_argument(
        "--output_dir", required=True, help="Output directory for cubemap face images"
    )
    parser.add_argument(
        "--fov", type=int, default=110, help="Field of view in degrees (default: 110)"
    )
    parser.add_argument(
        "--output_size",
        type=int,
        default=0,
        help="Output image size in pixels, 0=auto from input height (default: 0)",
    )
    parser.add_argument(
        "--faces",
        type=str,
        default="front,right,back,left,top",
        help="Comma-separated list of faces to generate (default: front,right,back,left,top)",
    )
    parser.add_argument(
        "--ffmpeg",
        type=str,
        default="ffmpeg",
        help="Path to FFmpeg executable (default: ffmpeg)",
    )

    args = parser.parse_args()

    input_dir = args.input_dir
    output_dir = args.output_dir
    fov = args.fov
    output_size = args.output_size
    ffmpeg_path = args.ffmpeg
    faces = [f.strip() for f in args.faces.split(",")]

    # Validate faces
    for face in faces:
        if face not in FACE_DEFINITIONS:
            print(f"ERROR: Unknown face '{face}'. Valid faces: {list(FACE_DEFINITIONS.keys())}")
            sys.exit(1)

    # Validate input directory
    if not os.path.isdir(input_dir):
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    # Collect input images
    input_images = sorted(
        [
            f
            for f in os.listdir(input_dir)
            if os.path.isfile(os.path.join(input_dir, f))
            and os.path.splitext(f)[1] in IMAGE_EXTENSIONS
        ]
    )

    if not input_images:
        print(f"ERROR: No images found in {input_dir}")
        sys.exit(1)

    print(f"Found {len(input_images)} equirectangular images")
    print(f"Faces to generate: {faces}")
    print(f"FOV: {fov} degrees")

    # Auto-detect output size from first image if not specified
    if output_size <= 0:
        first_image = os.path.join(input_dir, input_images[0])
        try:
            width, height = get_image_size(first_image, ffmpeg_path)
            output_size = max(height, 1024)
            print(f"Input image size: {width}x{height}")
            print(f"Auto output size: {output_size}px (from input height)")
        except Exception as e:
            print(f"WARNING: Could not detect image size ({e}), using default 1024px")
            output_size = 1024
    else:
        print(f"Output size: {output_size}px")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Process each frame
    total_faces = 0
    failed_faces = 0

    for frame_idx, image_name in enumerate(input_images):
        input_path = os.path.join(input_dir, image_name)

        for face in faces:
            yaw, pitch = FACE_DEFINITIONS[face]
            success = decompose_frame(
                input_path=input_path,
                output_dir=output_dir,
                face_name=face,
                yaw=yaw,
                pitch=pitch,
                fov=fov,
                output_size=output_size,
                ffmpeg_path=ffmpeg_path,
                output_filename=image_name,
            )
            if success:
                total_faces += 1
            else:
                failed_faces += 1

        # Progress reporting
        if (frame_idx + 1) % 10 == 0 or frame_idx == 0 or frame_idx == len(input_images) - 1:
            print(f"  Processed {frame_idx + 1}/{len(input_images)} frames ({total_faces} faces generated)")

    # Summary
    print()
    print(f"Cubemap decomposition complete:")
    print(f"  Input frames: {len(input_images)}")
    print(f"  Faces per frame: {len(faces)}")
    print(f"  Total faces generated: {total_faces}")
    if failed_faces > 0:
        print(f"  Failed faces: {failed_faces}")
        sys.exit(1)

    # List output directories
    for face in faces:
        face_dir = os.path.join(output_dir, FACE_DIR_NAMES[face])
        if os.path.isdir(face_dir):
            count = len([f for f in os.listdir(face_dir) if os.path.splitext(f)[1] in IMAGE_EXTENSIONS])
            print(f"  {FACE_DIR_NAMES[face]}/: {count} images")

    sys.exit(0)


if __name__ == "__main__":
    main()

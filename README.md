# Postshot Script - COLMAP Integration Pipeline

Automated 3D reconstruction pipeline integrating COLMAP SfM and Postshot for processing drone footage.

## Features

- Single command execution for entire pipeline
- Auto-detect input type (video files or image folders)
- Multi-video support with separate camera intrinsics per video
- COLMAP sparse reconstruction with GPU acceleration
- Postshot training and PLY export

## Requirements

- **COLMAP**: sensyn-robotics fork at `C:\Program Files\COLMAP\COLMAP.bat`
- **FFmpeg**: `C:\Program Files\ffmpeg\bin\ffmpeg.exe`
- **Postshot CLI**: `C:\Program Files\Jawset Postshot\bin\postshot-cli.exe`

## Usage

### Basic Usage

```powershell
# Process a directory containing video files
.\scripts\run_pipeline.ps1 "C:\data\project_folder"

# Process a single video file
.\scripts\run_pipeline.ps1 "C:\data\video.mp4"

# Process existing image folder
.\scripts\run_pipeline.ps1 "C:\data\images_folder"
```

### Output Structure

Output is created in the same location as input:

```
input_folder/
├── images/
│   ├── video_W/           # Frames from first video
│   └── video_Z/           # Frames from second video
├── colmap_output/
│   ├── database.db
│   └── sparse/0/
│       ├── cameras.bin
│       ├── images.bin
│       └── points3D.bin
├── scene.psht             # Postshot training output
└── scene.ply              # Point cloud export
```

## Configuration

Edit `config/default_config.json` to customize:

- Tool paths (COLMAP, FFmpeg, Postshot)
- Video extraction settings (FPS, quality)
- COLMAP parameters (feature extraction, matching, mapping)

## Pipeline Stages

1. **Input Detection**: Identifies video files, image folders, or existing COLMAP projects
2. **Frame Extraction**: Extracts frames from videos using FFmpeg (2 FPS default)
3. **COLMAP Processing**:
   - Feature extraction with `ImageReader.single_camera_per_folder=1`
   - Exhaustive matching
   - Sparse reconstruction
4. **Postshot Training**: Trains Gaussian splat model
5. **Export**: Generates PLY point cloud

## Multi-Video Handling

When processing folders with multiple videos (e.g., Wide + Zoom cameras):
- Each video's frames are extracted to separate subfolders
- COLMAP uses `single_camera_per_folder=1` to assign one camera model per video
- All frames are combined in the same reconstruction

## Testing

```powershell
# Run tests on sakaigawa test data
.\tests\run_tests.ps1
```

## License

Internal use only.

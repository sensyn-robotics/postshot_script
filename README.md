# Postshot Script - COLMAP Integration Pipeline

Automated 3D reconstruction pipeline integrating COLMAP SfM and Postshot for processing drone footage.

## Features

- **Single command execution** for entire pipeline
- **Auto-detect input type** (video files, image folders, or existing COLMAP projects)
- **Multi-video support** with separate camera intrinsics per video
- **COLMAP sparse reconstruction** with GPU acceleration
- **Postshot training** and PLY point cloud export
- **Secure credential management** for Postshot CLI

## Requirements

| Tool | Path | Description |
|------|------|-------------|
| **COLMAP** | `C:\Program Files\COLMAP\COLMAP.bat` | sensyn-robotics fork with GPU support |
| **FFmpeg** | `C:\Program Files\ffmpeg\bin\ffmpeg.exe` | Video frame extraction |
| **Postshot CLI** | `C:\Program Files\Jawset Postshot\bin\postshot-cli.exe` | Gaussian splat training |

## Quick Start

```powershell
# Clone the repository
git clone https://github.com/MasahiroOgawa/postshot_script.git
cd postshot_script

# Process a folder containing drone videos
.\scripts\run_pipeline.ps1 "C:\data\my_project"
```

## Usage

### Basic Usage

```powershell
# Process a directory containing video files (most common)
.\scripts\run_pipeline.ps1 "C:\data\project_folder"

# Process a single video file
.\scripts\run_pipeline.ps1 "C:\data\video.mp4"

# Process existing image folder
.\scripts\run_pipeline.ps1 "C:\data\images_folder"

# Use sequential matcher (for video sequences)
.\scripts\run_pipeline.ps1 "C:\data\project_folder" -MatcherType sequential

# Use custom configuration
.\scripts\run_pipeline.ps1 "C:\data\project_folder" -ConfigPath "C:\my_config.json"
```

### Input Types

The pipeline automatically detects the input type:

| Input Type | Description | Action |
|------------|-------------|--------|
| **Video folder** | Directory containing .mp4/.mov files | Extract frames → COLMAP → Postshot |
| **Single video** | Single video file | Extract frames → COLMAP → Postshot |
| **Image folder** | Directory with .jpg/.png images | COLMAP → Postshot |
| **COLMAP project** | Directory with `images/` and `sparse/` | Skip to Postshot |

### Output Structure

Output is created in the same location as input:

```
input_folder/
├── images/
│   ├── video_W/              # Frames from Wide camera video
│   │   ├── frame_00001.jpg
│   │   ├── frame_00002.jpg
│   │   └── ...
│   └── video_Z/              # Frames from Zoom camera video
│       ├── frame_00001.jpg
│       └── ...
├── colmap_output/
│   ├── database.db           # COLMAP feature database
│   └── sparse/
│       └── 0/                # Sparse reconstruction
│           ├── cameras.bin   # Camera intrinsics (1 per video folder)
│           ├── images.bin    # Image poses
│           └── points3D.bin  # 3D points
├── scene.psht                # Postshot training output
└── scene.ply                 # Point cloud export
```

## Configuration

### Default Configuration

Edit `config/default_config.json` to customize settings:

```json
{
  "paths": {
    "colmap_exe": "C:\\Program Files\\COLMAP\\COLMAP.bat",
    "ffmpeg_exe": "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe",
    "postshot_cli": "C:\\Program Files\\Jawset Postshot\\bin\\postshot-cli.exe",
    "temp_directory": "C:\\Postshot_Temp"
  },
  "video_extraction": {
    "fps": 2,
    "output_format": "jpg",
    "quality": 2
  },
  "colmap": {
    "feature_extractor": {
      "ImageReader.single_camera_per_folder": 1,
      "ImageReader.camera_model": "OPENCV",
      "SiftExtraction.use_gpu": 1,
      "SiftExtraction.max_num_features": 8192
    },
    "matcher": {
      "type": "exhaustive",
      "SiftMatching.use_gpu": 1
    },
    "mapper": {
      "Mapper.ba_global_max_num_iterations": 50
    }
  },
  "postshot": {
    "train_iterations": 30000,
    "export_ply": true
  }
}
```

### Key Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `video_extraction.fps` | Frames per second to extract | 2 |
| `video_extraction.quality` | JPEG quality (1=best, 31=worst) | 2 |
| `colmap.feature_extractor.ImageReader.single_camera_per_folder` | Use one camera model per subfolder | 1 (enabled) |
| `colmap.matcher.type` | Matching strategy | exhaustive |

## Pipeline Stages

```
Input (video/images)
       │
       ▼
┌──────────────────┐
│ Frame Extraction │  FFmpeg: extract frames at 2 FPS
│   (if video)     │  Organize into video_W/, video_Z/ subfolders
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Feature Extract  │  COLMAP: SIFT features with GPU
│                  │  single_camera_per_folder=1
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Feature Matching │  COLMAP: exhaustive or sequential
│                  │  matching with GPU
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Sparse Reconstr. │  COLMAP: incremental SfM mapper
│                  │  bundle adjustment
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Postshot Train   │  Train Gaussian splat model
│                  │  30000 iterations default
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ PLY Export       │  Export point cloud
│                  │  scene.ply
└──────────────────┘
```

## Multi-Video Handling

When processing folders with multiple videos (e.g., DJI Wide + Zoom cameras):

1. **Frame Extraction**: Each video's frames are extracted to separate subfolders
   - `DJI_xxx_W.MP4` → `images/video_W/`
   - `DJI_xxx_Z.MP4` → `images/video_Z/`

2. **Camera Intrinsics**: COLMAP uses `single_camera_per_folder=1` to assign one camera model per subfolder
   - Wide camera frames share one set of intrinsics
   - Zoom camera frames share another set of intrinsics

3. **Reconstruction**: All frames are combined in a single sparse reconstruction

## Credential Management

On first run, you'll be prompted for Postshot credentials:
- Email and password are stored encrypted in `%APPDATA%\PostshotScript\postshot_creds.xml`
- Credentials are encrypted using Windows DPAPI (only decryptable by the same user)
- To reset credentials, delete the file and run again

## Testing

```powershell
# Run full test suite on sakaigawa data
.\tests\run_tests.ps1

# Skip processing, only verify existing outputs
.\tests\run_tests.ps1 -SkipProcessing

# Clean previous outputs before testing
.\tests\run_tests.ps1 -CleanupFirst

# Use different test data location
.\tests\run_tests.ps1 -TestDataDir "C:\other\test\data"
```

### Test Data Structure

Expected test data structure:
```
20260121_sakaigawa/
├── ①腕金を両サイド1本ずつ/
│   ├── DJI_xxx_W.MP4
│   └── DJI_xxx_Z.MP4
├── ②腕金1本を真下から/
│   ├── DJI_xxx_W.MP4
│   └── DJI_xxx_Z.MP4
├── ③バーティカル撮影(腕金3本)/
│   └── ...
└── ④腕金周りのパネル撮影/
    └── ...
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| COLMAP not found | Verify path in `default_config.json` |
| FFmpeg not found | Install FFmpeg and update path in config |
| Postshot credential error | Delete `%APPDATA%\PostshotScript\postshot_creds.xml` |
| Japanese path error | Temp directory is set to `C:\Postshot_Temp` to avoid |
| GPU not detected | Check CUDA installation and GPU drivers |

### COLMAP Reconstruction Fails

If COLMAP fails to create a reconstruction:
1. Check that images have sufficient overlap
2. Try reducing `SiftExtraction.max_num_features` for memory issues
3. For video sequences, try `sequential_matcher` instead of `exhaustive_matcher`

## Individual Scripts

Each module can be run independently:

```powershell
# Extract frames from video
.\scripts\video_extractor.ps1 -VideoPath "video.mp4" -OutputDir "frames/"

# Run COLMAP only
.\scripts\colmap_processor.ps1 -ImageDir "images/" -OutputDir "colmap_output/"

# Run Postshot only
.\scripts\postshot_runner.ps1 -InputPath "project/" -OutputPath "scene.psht" -ExportPly
```

## Directory Structure

```
postshot_script/
├── config/
│   └── default_config.json   # Default configuration
├── scripts/
│   ├── run_pipeline.ps1      # Main entry point
│   ├── colmap_processor.ps1  # COLMAP SfM pipeline
│   ├── video_extractor.ps1   # FFmpeg frame extraction
│   └── postshot_runner.ps1   # Postshot CLI wrapper
├── lib/
│   └── config_loader.ps1     # Configuration utilities
├── tests/
│   └── run_tests.ps1         # Test runner
├── .gitignore
└── README.md
```

## License

Internal use only - sensyn-robotics.

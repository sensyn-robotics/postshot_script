# Postshot Script - COLMAP + 3DGS Pipeline

Automated 3D Gaussian Splatting pipeline for processing dual-camera drone footage through COLMAP SfM and Postshot.

## Features

- **7-stage modular pipeline** - each stage runs independently, skips if outputs exist
- **Unified configuration** - single JSON config controls all stages
- **Multi-camera support** - dual video (Wide + Zoom) with per-camera intrinsics
- **Batch processing** - process all scenes in a directory with one command
- **Quality metrics** - SSIM, LPIPS, PSNR evaluation with auto-retry
- **360-degree mode** - optional cubemap decomposition for equirectangular footage

## Requirements

| Tool | Default Path | Description |
|------|-------------|-------------|
| **COLMAP** | `C:\COLMAP\COLMAP.bat` | SfM sparse reconstruction (GPU) |
| **FFmpeg** | `C:\ffmpeg\bin\ffmpeg.exe` | Video frame extraction |
| **Postshot CLI** | `C:\Program Files\Jawset Postshot\bin\postshot-cli.exe` | 3DGS training & export |
| **Python 3.11** | `python` | Blur detection, optical flow, metrics |
| **uv** | - | Python package manager |

### Python Dependencies

Managed via `pyproject.toml` with uv:

```bash
uv sync
```

Key packages: torch (CUDA 12.1), torchvision, opencv-python, lpips, plyfile, numpy, pillow, matplotlib

## Quick Start

```powershell
# Run full pipeline on all scenes
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json

# Run on a single scene
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -ScenePath "C:\path\to\scene"

# Run specific stages (e.g., COLMAP only: stages 3-5)
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -ScenePath "C:\path\to\scene" -StartStage 3 -EndStage 5
```

## Pipeline Stages

| Stage | Script | Description |
|-------|--------|-------------|
| 1 | `01_extract_frames.ps1` | Extract frames from videos using FFmpeg |
| 1b | `01b_cubemap_decompose.ps1` | (Optional) Decompose 360 equirectangular to cubemap |
| 2 | `02_filter_frames.ps1` | Blur detection + keyframe selection via optical flow |
| 3 | `03_colmap_features.ps1` | COLMAP SIFT feature extraction (GPU) |
| 4 | `04_colmap_matching.ps1` | COLMAP feature matching (sequential or exhaustive) |
| 5 | `05_colmap_mapper.ps1` | COLMAP incremental SfM sparse reconstruction |
| 6 | `06_postshot_train.ps1` | Postshot 3DGS training |
| 7 | `07_postshot_export.ps1` | Export to PLY point cloud |

```
Video files ──► Frame Extraction ──► [Filtering] ──► COLMAP Features
                                                          │
                                                          ▼
PLY Export ◄── Postshot Training ◄── COLMAP Mapper ◄── COLMAP Matching
```

Each stage:
- Can be run independently if inputs exist
- Skips automatically if outputs already exist (unless `overwrite_result: true`)
- Controlled by unified `config/pipeline.json`

## Configuration

All settings live in a single JSON config. See `config/pipeline.json` for the primary config.

### Key Settings

| Section | Setting | Default | Description |
|---------|---------|---------|-------------|
| **pipeline** | `overwrite_result` | false | Re-run stages even if outputs exist |
| **pipeline** | `test_data_path` | - | Directory containing scene folders (batch mode) |
| **stage_01** | `fps` | 2 | Frame extraction rate |
| **stage_01** | `target_frames` | 0 | Limit total frames (0 = no limit) |
| **stage_02** | `enabled` | false | Enable blur/keyframe filtering |
| **stage_02** | `target_overlap` | 0.8 | Target overlap between keyframes |
| **stage_02** | `max_frames` | 400 | Max frames after filtering |
| **stage_03** | `camera_model` | SIMPLE_RADIAL | COLMAP camera model |
| **stage_03** | `single_camera` | true | Single camera model for all images |
| **stage_03** | `max_features` | 16384 | Max SIFT features per image |
| **stage_04** | `type` | sequential | Matcher type (sequential/exhaustive) |
| **stage_04** | `sequential_overlap` | 20 | Image overlap for sequential matcher |
| **stage_04** | `sequential_loop` | true | Enable loop closure detection |
| **stage_04** | `guided_matching` | true | Use guided matching |
| **stage_05** | `min_model_size` | 10 | Min images for valid reconstruction |
| **stage_05** | `ba_global_max_iterations` | 100 | Global bundle adjustment iterations |
| **stage_05** | `ba_local_max_iterations` | 25 | Local bundle adjustment iterations |
| **stage_06** | `checkpoints` | [10000, 30000] | Training checkpoint steps |
| **stage_06** | `train_camera` | all | Which camera to train (all/W/Z) |
| **stage_06** | `train_steps_limit` | 0 | Max training steps (0 = unlimited) |
| **stage_06** | `profile` | Splat3 | Postshot training profile |
| **stage_06** | `max_image_size` | 3840 | Max image dimension for training |
| **stage_07** | `format` | ply | Export format |

### Config Variants

| Config | Purpose |
|--------|---------|
| `pipeline.json` | Primary default config |
| `pipeline_tower_scene1_v3.json` | Tower dataset scene 1 |
| `pipeline_scene1_retrain.json` | Scene 1 retrain experiment |
| `pipeline_single.json` | Single-video with quality gates |

## Entry Point Scripts

### run_pipeline_allscene.ps1 (Primary)

Orchestrate all stages for one or all scenes.

```powershell
# All scenes in test_data_path
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json

# Single scene
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -ScenePath "C:\path\to\scene"

# Resume from stage 5
.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json -StartStage 5
```

Parameters:
- `-ConfigPath` (required): Path to config JSON
- `-ScenePath` (optional): Single scene directory. If omitted, processes all scenes in `test_data_path`
- `-StartStage` (default: 1): Start from stage N
- `-EndStage` (default: 7): End at stage N

### run_pipeline_single.ps1

Single-scene pipeline with quality gates and auto-retry.

- Quality thresholds: `min_ssim` (default 0.80), `max_lpips`
- Auto-retry: progressively lowers FPS and image scale

### run_tower_comparison.ps1

Compare sequential vs exhaustive matcher on tower scenes.

## Python Utilities

| Script | Purpose |
|--------|---------|
| `blur_detector.py` | Detect blurred frames (Laplacian variance) |
| `optical_flow_analyzer.py` | Compute optical flow, select keyframes by overlap |
| `frame_selector.py` | Combined blur removal + keyframe selection |
| `compute_lpips.py` | Compute LPIPS, PSNR metrics from PLY renders |
| `check_sparse_quality.py` | Evaluate COLMAP reconstruction quality |
| `render_checkpoint.py` | Render PLY to multi-view images |
| `render_pointcloud.py` | Render COLMAP sparse point cloud |
| `read_colmap_model.py` | Parse and report COLMAP binary model stats |
| `cubemap_decompose.py` | Convert equirectangular to cubemap faces |
| `resize_images.py` | Resize images for resolution testing |

## Output Structure

```
<scene_path>/
└── output/
    ├── images/
    │   ├── video_W/              # Wide camera frames
    │   └── video_Z/              # Zoom camera frames
    ├── colmap/
    │   ├── database.db           # COLMAP feature database
    │   └── sparse/
    │       └── 0/                # Best sparse reconstruction
    │           ├── cameras.bin
    │           ├── images.bin
    │           └── points3D.bin
    ├── postshot/
    │   ├── scene.psht            # Postshot training output
    │   ├── scene.ply             # Exported point cloud
    │   ├── quality.json          # SSIM score
    │   └── lpips.json            # LPIPS/PSNR per-image metrics
    ├── visualizations/           # Rendered preview images
    └── pipeline_config.json      # Config snapshot used for this run
```

## Multi-Camera Handling

When processing folders with dual-camera videos (e.g., DJI Wide + Zoom):

1. **Frame extraction**: Each video extracts to separate subfolder (`video_W/`, `video_Z/`)
2. **Camera intrinsics**: `single_camera=true` assigns one model for all images, or `single_camera_per_folder=true` for per-camera models
3. **Reconstruction**: All frames combined in a single COLMAP sparse reconstruction
4. **Training**: `train_camera` controls which camera images are used for 3DGS training

## Directory Structure

```
postshot_script/
├── config/
│   ├── pipeline.json              # Primary unified config
│   └── [variant configs]          # Experiment-specific configs
├── lib/
│   └── config_loader.ps1          # Config loading utilities
├── scripts/
│   ├── stages/                    # 7 modular stage scripts
│   │   ├── 01_extract_frames.ps1
│   │   ├── 01b_cubemap_decompose.ps1
│   │   ├── 02_filter_frames.ps1
│   │   ├── 03_colmap_features.ps1
│   │   ├── 04_colmap_matching.ps1
│   │   ├── 05_colmap_mapper.ps1
│   │   ├── 06_postshot_train.ps1
│   │   └── 07_postshot_export.ps1
│   ├── run_pipeline_allscene.ps1  # Main pipeline runner
│   ├── run_pipeline_single.ps1    # Single scene with quality gates
│   ├── [Python utilities]         # Analysis and processing scripts
│   └── debug/                     # Diagnostic scripts
├── tests/
│   └── run_tests.ps1
├── pyproject.toml                 # Python dependencies (uv)
├── requirements.txt               # Fallback requirements
└── README.md
```

## Japanese Path Handling

Windows PowerShell has encoding issues with Japanese/Unicode paths. The pipeline handles this by:

- Passing paths as **parameters** (never hardcoded)
- Using **`-LiteralPath`** instead of `-Path`
- Using **`C:\Postshot_Temp`** as temp directory (ASCII-only path)
- Using **junction links** when tools cannot handle Unicode paths

When running from bash, always use the call operator:
```bash
powershell -NoProfile -Command "& '.\scripts\run_pipeline_allscene.ps1' -ConfigPath config\pipeline.json"
```

## Credential Management

On first run, Postshot CLI prompts for credentials:
- Stored encrypted via Windows DPAPI in `%APPDATA%\PostshotScript\postshot_creds.xml`
- Only decryptable by the same Windows user
- Delete the file to reset credentials

## Troubleshooting

| Issue | Solution |
|-------|----------|
| COLMAP not found | Check `paths.colmap` in config |
| No sparse reconstruction | Ensure sufficient image overlap; try exhaustive matcher |
| Postshot credential error | Delete `%APPDATA%\PostshotScript\postshot_creds.xml` |
| Japanese path error | Use `-LiteralPath`; pass paths as parameters |
| Python import error | Run `uv sync` to install dependencies |
| GPU not detected | Check CUDA installation and GPU drivers |

## License

Internal use only - sensyn-robotics.

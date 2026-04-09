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
| **stage_01** | `target_frames` | 600 | Max total frames (0 = no limit) |
| **stage_02** | `enabled` | false | Enable blur/keyframe filtering |
| **stage_03** | `camera_model` | SIMPLE_RADIAL | COLMAP camera model |
| **stage_03** | `single_camera_per_folder` | true | One camera model per subfolder |
| **stage_03** | `max_features` | 8192 | Max SIFT features per image (COLMAP default) |
| **stage_04** | `type` | sequential | Matcher type (sequential/exhaustive) |
| **stage_05** | `filter_degenerate_pairs` | true | Exclude pure-rotation frames via image list |
| **stage_05** | `colmap_timeout_hours` | 12 | Kill COLMAP if exceeds this time |
| **stage_05** | `min_model_size` | 10 | Min images for valid reconstruction (COLMAP default) |
| **stage_06** | `checkpoints` | [10000, 30000] | Training checkpoint steps |
| **stage_06** | `train_camera` | all | Which camera to train (all/W/Z) |
| **stage_06** | `train_steps_limit` | 0 | Max training steps (0 = unlimited) |
| **stage_06** | `profile` | Splat3 | Postshot training profile |
| **stage_07** | `format` | ply | Export format |

Other COLMAP mapper parameters (ba_global_max_iterations, init_min_num_inliers, etc.) use COLMAP defaults unless explicitly set in config.

### Config Variants

| Config | Purpose |
|--------|---------|
| `pipeline.json` | Primary default config |
| `pipeline_single.json` | Single-video with quality gates |
| `pipeline_360.json` | 360-degree equirectangular mode |

## Script Structure

```
run_param_search.ps1                   # Entry point: parameter search
│   (prevents sleep, tries parameter sets, stops on failure)
│
├── run_pipeline_allscene.ps1          # Orchestrator: loops scenes × stages
│   │
│   ├── stages/01_extract_frames.ps1           FFmpeg
│   ├── stages/01b_cubemap_decompose.ps1       (optional 360)
│   │     └── cubemap_decompose.py
│   ├── stages/02_filter_frames.ps1
│   │     ├── blur_detector.py
│   │     └── optical_flow_analyzer.py
│   ├── stages/03_colmap_features.ps1          COLMAP feature_extractor
│   ├── stages/04_colmap_matching.ps1          COLMAP matcher (with timeout)
│   ├── stages/05_colmap_mapper.ps1            COLMAP mapper (with timeout)
│   │     └── check_sparse_quality.py
│   ├── stages/06_postshot_train.ps1           Postshot 3DGS training
│   │     ├── compute_lpips.py
│   │     └── render_checkpoint.py
│   └── stages/07_postshot_export.ps1          PLY export
│
└── (checks registration ≥50%, runs training if all scenes pass)

run_pipeline_single.ps1                # Single scene with quality gates + retry
└── (same stages as above)

run_lpips_all.ps1                      # Standalone: batch LPIPS metrics
└── compute_lpips.py
```

### Entry Points

| Script | Purpose | Usage |
|--------|---------|-------|
| `run_param_search.ps1` | Automated parameter search across all scenes | `.\scripts\run_param_search.ps1 -ConfigPath config\pipeline.json` |
| `run_pipeline_allscene.ps1` | Run pipeline on one or all scenes | `.\scripts\run_pipeline_allscene.ps1 -ConfigPath config\pipeline.json` |
| `run_pipeline_single.ps1` | Single scene with quality gates and auto-retry | `.\scripts\run_pipeline_single.ps1 -ConfigPath config\pipeline_single.json` |

### Python Scripts (called by stages)

| Script | Called by | Purpose |
|--------|----------|---------|
| `blur_detector.py` | Stage 02 | Detect blurred frames (Laplacian variance) |
| `optical_flow_analyzer.py` | Stage 02 | Compute optical flow, select keyframes |
| `frame_selector.py` | Stage 02 | Combined blur removal + keyframe selection |
| `check_sparse_quality.py` | Stage 05 | Evaluate COLMAP reconstruction quality |
| `compute_lpips.py` | Stage 06 | Compute LPIPS, PSNR metrics from PLY renders |
| `render_checkpoint.py` | Stage 06 | Render PLY to multi-view images |
| `cubemap_decompose.py` | Stage 01b | Convert equirectangular to cubemap faces |

### Standalone Utilities (`scripts/util/`)

| Script | Purpose |
|--------|---------|
| `run_lpips_all.ps1` | Batch LPIPS metrics across scenes |
| `create_test_dataset.ps1` | Create small test dataset |
| `analyze_matches.py` | Analyze feature match distribution |
| `analyze_overlap.py` | Analyze frame-to-frame overlap |
| `check_colmap_quality.py` | Check COLMAP reconstruction viability |
| `read_colmap_model.py` | Parse and report COLMAP binary model stats |
| `render_pointcloud.py` | Render COLMAP sparse point cloud |
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
│   ├── pipeline.json              # Primary config (COLMAP defaults + tuning params)
│   ├── default_config.json        # Legacy config (reference only)
│   ├── pipeline_single.json       # Single scene with quality gates
│   └── pipeline_360.json          # 360-degree mode
├── lib/
│   └── config_loader.ps1          # Config loading utilities
├── scripts/
│   ├── stages/                    # 7 modular stage scripts (01-07)
│   ├── run_param_search.ps1       # Parameter search (entry point)
│   ├── run_pipeline_allscene.ps1  # Pipeline orchestrator
│   ├── run_pipeline_single.ps1    # Single scene with quality gates
│   ├── util/                      # All Python utilities + standalone scripts
│   │   (all Python scripts + standalone PS1 utilities)
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

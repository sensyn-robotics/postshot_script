# Claude Code Instructions for postshot_script

## Project Overview
This repository contains PowerShell scripts and Python utilities for processing dual-camera drone footage through COLMAP and Postshot 3DGS pipeline.

## Critical: Encoding Issues with Japanese Paths

### Problem
Windows PowerShell has encoding issues when:
1. Running `.ps1` scripts containing hardcoded Japanese/Unicode characters from bash/cmd
2. The file encoding doesn't match the console's code page

### Solution
**NEVER hardcode Japanese paths in scripts.** Instead:

1. **Use parameters** to pass paths:
   ```powershell
   param(
       [Parameter(Mandatory=$false)]
       [string]$ScenePath
   )
   ```

2. **Dynamically discover directories** using `Get-ChildItem`:
   ```powershell
   $scenes = Get-ChildItem -LiteralPath $TestDataPath -Directory | Sort-Object Name
   ```

3. **Use `-LiteralPath`** instead of `-Path` for paths with special characters:
   ```powershell
   Test-Path -LiteralPath $scenePath  # Correct
   Test-Path $scenePath               # May fail with special chars
   ```

### Running Scripts
When running from command line, pass paths as parameters:
```powershell
.\scripts\run_scene1_02fps.ps1 -ScenePath "C:\postshot_test_data\①腕金を両サイド1本ずつ"
```

Or run from PowerShell directly (not bash) with UTF-8:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
.\scripts\run_all_scenes_optimal.ps1
```

### IMPORTANT: Call operator vs Dot-sourcing
**Always use `&` (call operator), not `.` (dot-source) when running scripts from bash or other contexts:**
```powershell
# CORRECT - use & to call script
& ".\scripts\run_scene1_02fps.ps1"

# WRONG - dot-sourcing can cause parameter scope issues
. .\scripts\run_scene1_02fps.ps1
```

When calling from bash, use:
```bash
powershell -NoProfile -Command "& 'C:\path\to\script.ps1' -Param value"
```

## Project Structure

```
postshot_script/
├── config/                    # Configuration files
│   ├── default_config.json    # Default settings (0.5fps)
│   ├── config_0.2fps.json     # Low FPS for testing
│   └── config_2fps.json       # High FPS for keyframe extraction
├── lib/                       # PowerShell modules
│   └── config_loader.ps1      # Config loading utilities
├── scripts/                   # Main scripts
│   ├── run_pipeline_exhaustive.ps1   # Main pipeline
│   ├── run_scene1_02fps.ps1          # 0.2fps test runner
│   ├── run_all_scenes_optimal.ps1    # All scenes runner
│   ├── blur_detector.py              # Blur detection
│   ├── optical_flow_analyzer.py      # Optical flow analysis
│   └── frame_selector.py             # Combined frame selection
└── requirements.txt           # Python dependencies
```

## Key Scripts

### run_pipeline_exhaustive.ps1
Main pipeline with parameters:
- `-InputPath`: Scene directory (required)
- `-ConfigPath`: Custom config JSON (optional)
- `-OutputDir`: Output directory name (default: "output")
- `-VisualizationIntervalMinutes`: Visualization interval (default: 10)

### Frame Selection Pipeline
The frame selection workflow:
1. Extract frames at higher FPS (2fps) for more candidates
2. `blur_detector.py` - Remove blurred frames (Laplacian Variance)
3. `optical_flow_analyzer.py` - Select keyframes with target overlap (default: 80%)
4. Limit to 400 frames maximum

### Overlap Calculation
Overlap is estimated from optical flow using:
```
image_size = (width + height) / 2  # Handles various aspect ratios
overlap % = (1 - mean_flow / image_size) × 100
```

For 80% target overlap (default):
- 20% displacement needed between keyframes
- For 1920x1080 image: image_size = 1500, target_flow = 300px

### Python Dependencies
```bash
pip install -r requirements.txt
# Requires: numpy, pillow, opencv-python, matplotlib
```

**IMPORTANT:** The Windows Store Python stub (`WindowsApps\python.exe`) may not work correctly.
If visualizations fail, install a proper Python from python.org and ensure it's in PATH:
1. Download from https://www.python.org/downloads/
2. During install, check "Add Python to PATH"
3. Open new terminal and verify: `python --version`
4. Install dependencies: `pip install numpy pillow opencv-python`

## Test Data Location
Default test data path: `C:\postshot_test_data\`

Contains 4 scenes with Japanese names (discovered dynamically, not hardcoded).

## Common Issues

### "Scene not found" error
- Check the path exists
- Use `-LiteralPath` for paths with special characters
- Pass path as parameter instead of relying on hardcoded values

### Visualization directory empty
- Check Python dependencies: `pip install numpy pillow`
- Check `viz_monitor.log` in visualizations directory for errors

### Python errors silently ignored
- Scripts now capture `$LASTEXITCODE` and report Python failures
- Check console output for "ERROR: Python failed" messages

### Empty OutputDir parameter
- Fixed: Scripts now handle empty string `$OutputDir` by defaulting to "output"
- If calling from bash, ensure parameter passing works correctly

## Session Notes (2026-02-04)

### Completed
- Pipeline ran successfully on scene1 with 0.5fps (254 frames total)
- COLMAP exhaustive matching produced 2 reconstructions
- Postshot training completed (30k steps, 3M splats)
- Output files: `output/scene.psht`, `output/scene.ply`, `output/render.mp4`
- Moved 0.2fps output to `output_0.2fps/` directory

### Frame Counts (Scene1)
| Config | W frames | Z frames | Total | Quality |
|--------|----------|----------|-------|---------|
| 0.5fps | 127 | 127 | 254 | Good |
| 0.2fps | 51 | 51 | 102 | Worse |

### Python Setup (RESOLVED)
Python 3.11 was installed via winget with required packages:
- numpy 2.4.2
- pillow 12.1.0
- opencv-python 4.13.0

Python path: `C:\Users\共通パソコンsfmPC⑦\AppData\Local\Programs\Python\Python311\python.exe`
Saved to: `python_path.txt`

### Current State (2026-02-04 Evening) - ALL COMPLETE ✅
| Scene | Status | W Frames | Z Frames | PSHT | PLY |
|-------|--------|----------|----------|------|-----|
| 1 | ✅ Complete | 127 | 127 | 688 MB | 675 MB |
| 2 | ✅ Complete | 156 | 156 | 688 MB | 675 MB |
| 3 | ✅ Complete | 373 | 373 | 691 MB | 675 MB |
| 4 | ✅ Complete | 406 | 406 | 692 MB | 675 MB |

Scene1 also has `output_0.2fps/` with 102 frames (0.2fps test - worse quality than 0.5fps).

### Optical Flow Analysis Results
- **0.5fps average overlap: 98.8%**
- Mean flow: 35.66 px
- This high overlap produces good COLMAP/Postshot results
- Default target overlap updated to 99% in all scripts

### Useful Scripts
- `run_overlap_analysis_safe.ps1` - Analyze optical flow overlap
- `check_all_scenes.ps1` - Check status of all scenes
- `scripts/run_all_scenes.ps1` - Run pipeline on all scenes
- `scripts/run_pipeline_exhaustive.ps1` - Main pipeline script

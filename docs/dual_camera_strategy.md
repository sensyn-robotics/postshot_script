# Dual-Camera Custom Pair Matching Strategy

## Problem Statement

When processing dual-camera footage (Wide + Zoom) through COLMAP:

| Approach | Result |
|----------|--------|
| W-only | Quality not good enough (missing detail from zoom camera) |
| W+Z same-position assumption | Failed because cameras have physical offset |
| W+Z full COLMAP (exhaustive) | Didn't converge due to FOV differences in bundle adjustment |

**Goal**: Run both W and Z through entire COLMAP pipeline, converge in < 9 hours

## Why W+Z COLMAP is Difficult

1. **FOV mismatch**: W is wide-angle (~84deg), Z is telephoto (~15-30deg)
2. **Scale difference**: Same feature appears 3-7x larger in Z vs W
3. **Limited overlap**: W<->Z matching finds few reliable matches
4. **Bundle adjustment**: Struggles to reconcile inconsistent 3D observations

## Solution: Custom Pair Matching

### COLMAP Pipeline Overview

```
1. Feature Extraction  -> finds SIFT features in each image
2. Feature Matching    -> compares image pairs to find shared features  <- CUSTOM PAIRS
3. Mapper              -> builds 3D model using matches
```

### What "Matching" Means

COLMAP compares two images to find the same physical features:
- Example: A corner of the tower appears in both `image_001` and `image_002`
- **Exhaustive matching**: compares ALL image pairs (N^2 = 250,000 for 500 images)
- **Custom pairs**: we specify WHICH pairs to compare

### Custom Pair Matching Strategy

```
W<->W temporal (matching within Wide camera):
  W_001 <-> W_002, W_003, ..., W_011  (10 forward neighbors)
  W_002 <-> W_001, W_003, ..., W_012
  ...
  This captures camera motion continuity

Z<->Z temporal (matching within Zoom camera):
  Z_001 <-> Z_002, Z_003, ..., Z_011
  Z_002 <-> Z_001, Z_003, ..., Z_012
  ...
  Same logic for zoom camera

W<->Z same-timestamp (cross-camera tie):
  W_001 <-> Z_001  (both taken at timestamp T1)
  W_002 <-> Z_002  (both taken at timestamp T2)
  ...
  Connects W and Z models together
```

### Why This Helps Convergence

- Avoids `W_001 <-> Z_250` (far apart, different scale, bad matches)
- Only allows W<->Z pairs that see the exact same scene (same timestamp)
- Bundle adjustment gets cleaner input data
- Much faster than exhaustive (~10,000 pairs vs 250,000)

## Implementation

### match_pairs.txt Format

COLMAP's `matches_importer` expects a text file with one pair per line:

```
video_W/frame_00001.png video_W/frame_00002.png
video_W/frame_00001.png video_W/frame_00003.png
video_W/frame_00001.png video_Z/frame_00001.png
video_Z/frame_00001.png video_Z/frame_00002.png
...
```

Each line contains two image paths (relative to the images root directory).

### Pipeline Stages

1. **Extract frames** from W and Z videos into `images/video_W/` and `images/video_Z/`
2. **Feature extraction** on all images (both W and Z)
3. **Generate match pairs** using `generate_match_pairs.ps1`
4. **Custom pair matching** using COLMAP's `matches_importer`
5. **Mapper** builds unified model with both cameras
6. **Postshot training** on unified model

### Configuration

```json
{
  "colmap": {
    "feature_extractor": {
      "ImageReader.single_camera_per_folder": 1,
      "ImageReader.camera_model": "OPENCV",
      "SiftExtraction.max_num_features": 8192,
      "SiftExtraction.use_gpu": 1
    },
    "matcher": {
      "type": "custom_pairs",
      "temporal_overlap": 10,
      "cross_camera_same_timestamp": true,
      "SiftMatching.use_gpu": 1
    },
    "mapper": {
      "Mapper.ba_global_max_num_iterations": 50,
      "Mapper.ba_global_function_tolerance": 1e-4,
      "Mapper.ba_local_max_num_iterations": 15
    }
  }
}
```

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `temporal_overlap` | 10 | How many neighboring frames to match within each camera |
| `cross_camera_same_timestamp` | true | Whether to match W<->Z at same timestamps |

## Verification

### Check Registered Images

```powershell
# Convert to text format
colmap model_converter --input_path sparse/0 --output_path sparse/0/text --output_type TXT

# Count registered images
Get-Content sparse/0/text/images.txt | Measure-Object -Line

# Check camera count (should be 2: one W, one Z)
Get-Content sparse/0/text/cameras.txt
```

### Success Criteria

1. COLMAP completes without infinite BA loops
2. Both W and Z images appear in `images.bin`
3. Processing time < 9 hours
4. Visual inspection of output PLY shows acceptable quality

## Alternative Strategies

If custom pair matching doesn't work, consider:

### Strategy B: Two-Stage Registration
Build W model first, then register Z images using `image_registrator`.

### Strategy C: Interleaved Naming
Rename images so W and Z alternate: `001_W.png, 001_Z.png, 002_W.png, ...`
Use sequential matcher with overlap=3.

### Strategy D: Optimized Settings Only
Use exhaustive matching with aggressive settings to speed up convergence.

### Strategy E: Low Tolerance (Guaranteed Convergence)
Force BA to converge quickly with loose tolerance (accepts lower quality).

## References

- [COLMAP Documentation](https://colmap.github.io/)
- [COLMAP matches_importer](https://colmap.github.io/cli.html#matches-importer)

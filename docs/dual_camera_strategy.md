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

W<->Z cross-camera (with temporal neighbors):
  W_001 <-> Z_001, Z_002, ..., Z_006  (same + 5 neighbors)
  W_002 <-> Z_001, Z_002, Z_003, ..., Z_007
  ...
  Connects W and Z models with strong overlap
```

**Important**: Cross-camera matching needs temporal neighbors, not just same-timestamp pairs.
Same-timestamp-only matching (W_t <-> Z_t) provides too few connections (~5% of pairs) for
COLMAP to reliably merge Wide and Zoom reconstructions. With temporal neighbors
(CrossCameraTemporalOverlap=5), cross-camera pairs increase to ~35% of total pairs.

### Why This Helps Convergence

- Avoids `W_001 <-> Z_250` (far apart, different scale, bad matches)
- Cross-camera temporal neighbors provide enough matches for model merging
- Bundle adjustment gets cleaner input data
- Much faster than exhaustive (~8,000 pairs vs 250,000)

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
      "SiftExtraction.max_num_features": 8192
    },
    "matcher": {
      "type": "custom_pairs",
      "temporal_overlap": 10,
      "cross_camera_temporal_overlap": 5,
      "cross_camera_same_timestamp": true
    },
    "mapper": {
      "Mapper.ba_global_max_num_iterations": 50,
      "Mapper.ba_global_function_tolerance": 1e-4,
      "Mapper.ba_local_max_num_iterations": 15,
      "Mapper.multiple_models": 1,
      "Mapper.init_min_num_inliers": 50,
      "Mapper.abs_pose_min_num_inliers": 15,
      "Mapper.abs_pose_min_inlier_ratio": 0.15,
      "Mapper.min_model_size": 50
    }
  }
}
```

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `temporal_overlap` | 10 | How many neighboring frames to match within each camera |
| `cross_camera_temporal_overlap` | 5 | W<->Z matching includes timestamps ±5 from each W frame |
| `cross_camera_same_timestamp` | true | Whether to enable cross-camera matching |

### Mapper Parameters for Model Merging

| Parameter | Value | Description |
|-----------|-------|-------------|
| `Mapper.multiple_models` | 1 | Allow multiple models if merging fails |
| `Mapper.init_min_num_inliers` | 50 | Minimum inliers for initial pair (lower = easier init) |
| `Mapper.abs_pose_min_num_inliers` | 15 | Minimum inliers for pose estimation (lower = register more images) |
| `Mapper.abs_pose_min_inlier_ratio` | 0.15 | Minimum inlier ratio for pose (lower = more lenient) |
| `Mapper.min_model_size` | 50 | Discard models with fewer than 50 images |

## Multiple Reconstructions

COLMAP mapper may create multiple reconstruction folders (0, 1, 2, ...) when it cannot
merge all images into a single unified model. This typically happens when:

1. **Insufficient cross-camera connections**: Not enough W<->Z feature matches
2. **Large scene gaps**: Images from different parts of the scene don't connect
3. **Feature matching failures**: Cross-camera scale differences cause poor matches

### Automatic Largest Model Selection

The pipeline automatically selects the largest reconstruction (by number of registered
images) to pass to Postshot. This is determined by the size of `images.bin`:

```powershell
# Get-LargestReconstruction in colmap_processor.ps1
# Finds the reconstruction folder with largest images.bin file
```

### Troubleshooting Multiple Models

If COLMAP creates many separate models:

1. **Increase cross-camera matching**: Set `cross_camera_temporal_overlap` higher (e.g., 10)
2. **Lower mapper thresholds**: Reduce `init_min_num_inliers` and `abs_pose_min_num_inliers`
3. **Check feature quality**: Ensure sufficient features are extracted (8192 recommended)
4. **Verify timestamp alignment**: W and Z frames should be from same recording time

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

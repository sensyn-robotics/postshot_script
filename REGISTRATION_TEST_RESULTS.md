# COLMAP Registration Test Results

**Date:** 2026-02-04 to 2026-02-05
**Scene:** Scene 1 (①腕金を両サイド1本ずつ)

## Problem Statement

COLMAP registered only **2 out of 254 images** (both W, 0 Z) on the full dataset.
This causes blurry 3DGS results because the zoom camera (Z) images are not being used.

## Results Summary (Full Dataset with Improved Settings)

### Before (Original Settings)
- Registered: 2 images (2 W, 0 Z)
- Registration rate: 0.8%

### After (Relaxed Settings)
| Reconstruction | W Images | Z Images | Total | 3D Points |
|----------------|----------|----------|-------|-----------|
| 0 (main) | 127 | 5 | 132 | 58,302 |
| 1 | 19 | 0 | 19 | 9,711 |
| 2 | 0 | 11 | 11 | 1,808 |
| **TOTAL** | **127** | **16** | **162** | - |

**Improvement:** From 2 images to 132 images in main reconstruction
- **All 127 W images now register successfully**
- **5 Z images register with W images in the main reconstruction**
- **Additional 11 Z images form a separate reconstruction**

**Remaining Issue:** The 11 Z images in reconstruction 2 cannot be merged because they lack
sufficient cross-camera matches with the W-dominated reconstruction.

## Root Cause Analysis

### Match Statistics (Full Dataset: 254 images)
- **W-W matches:** 4591 pairs, avg 937.7 matches/pair
- **Z-Z matches:** 1681 pairs, avg 581.6 matches/pair
- **W-Z matches:** 3959 pairs, avg 71.7 matches/pair

**Key Finding:** Cross-camera (W-Z) matches exist but are **13x weaker** than same-camera matches.
This causes COLMAP to build separate models for each camera instead of merging them.

### Why W-Z Matching is Weak
1. **Different focal lengths** - W (wide) and Z (zoom) cameras have very different FOVs
2. **Scale difference** - Same objects appear at different sizes in W vs Z
3. **Limited overlap region** - Only the center of W images overlaps with Z images

## Improved Configuration (config_improved_registration.json)

```json
{
  "colmap": {
    "feature_extractor": {
      "ImageReader.single_camera_per_folder": 1,
      "ImageReader.camera_model": "OPENCV",
      "SiftExtraction.max_num_features": 8192
    },
    "matcher": {
      "type": "exhaustive"
    },
    "mapper": {
      "Mapper.init_min_num_inliers": 15,
      "Mapper.abs_pose_min_num_inliers": 5,
      "Mapper.abs_pose_min_inlier_ratio": 0.05,
      "Mapper.init_max_error": 8,
      "Mapper.min_model_size": 10
    }
  }
}
```

## Test Results Summary (Small Dataset: 30 images = 15 W + 15 Z)

| Test | Total | Registered | W | Z | Time(s) |
|------|-------|------------|---|---|---------|
| baseline | 30 | 16 | 10 | 6 | ~21 |
| very_relaxed | 30 | 18 | 11 | 7 | ~27 |
| simple_radial | 30 | 16 | 10 | 6 | ~19 |
| cross_camera_focus | 30 | 18* | 11 | 7 | ~25 |
| single_camera_all | 30 | 17** | 11 | 6 | ~55 |

*cross_camera_focus created 5 reconstructions; main one has 18 images
**single_camera_all had fragmented reconstructions with many cameras

## Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/create_small_dataset.ps1` | Create 30-image test set (15 W + 15 Z) |
| `scripts/test_colmap_registration.ps1` | Run COLMAP with configurable settings |
| `scripts/run_single_test.ps1` | Quick test runner with predefined configs |
| `scripts/test_full_dataset.ps1` | Test improved settings on full dataset |
| `scripts/read_colmap_model.py` | Analyze COLMAP reconstructions |
| `scripts/analyze_matches.py` | Analyze matching statistics |
| `scripts/resize_images.py` | Resize images for resolution testing |
| `scripts/merge_reconstructions.ps1` | Merge multiple COLMAP models |
| `config/config_improved_registration.json` | Improved config for dual-camera |
| `config/config_test_relaxed.json` | Test relaxed settings |

## Output Locations

- **Small dataset:** `output_test_small/`
- **Improved full run:** `output_improved_registration/`
  - `sparse/0/` - Main reconstruction (132 images: 127 W + 5 Z)
  - `sparse/1/` - Secondary W reconstruction (19 images)
  - `sparse/2/` - Z-only reconstruction (11 images)

## Recommendations

### Immediate Actions
1. **Use the improved configuration** (`config/config_improved_registration.json`)
2. **Use the main reconstruction (sparse/0)** which has 132 images including 5 Z images

### Future Improvements
1. **Image resizing** - Scale down images to reduce scale difference between W and Z
2. **Custom pair matching** - Prioritize same-timestamp W-Z pairs
3. **Multi-camera rig constraints** - Add fixed W-Z pose relationship

## Conclusion

The registration diagnosis identified that weak W-Z feature matches were preventing
cross-camera registration. With relaxed COLMAP settings, registration improved from
2 images to 132 images in the main reconstruction, including 5 Z images being
successfully registered with the 127 W images.

While not all 254 images are in a single reconstruction, the main reconstruction
now contains all W images and some Z images, which should significantly improve
3DGS quality compared to the original W-only result.

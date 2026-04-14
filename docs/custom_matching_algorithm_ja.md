# カスタムマッチングアルゴリズム

## 概要

デュアルカメラ（Wide/Zoom）撮影に対応したCOLMAP用カスタムペアマッチングアルゴリズム。
Wide(W)とZoom(Z)の2つのカメラで同時撮影した映像から、効率的に3D再構成を行うためのマッチングペアを生成する。

## 問題点

### 従来手法の課題
- **Exhaustive Matching**: 全画像ペアをマッチング → 計算量が膨大（O(n²)）
- **Sequential Matching**: 連続フレームのみ → W/Z間の接続が不足し、別々の3Dモデルになる

### 実際に発生した問題
W/Z間のマッチングが不足すると、COLMAPが複数の独立したモデルを生成：
- Reconstruction 0: Wideカメラのみ（253枚）
- Reconstruction 1: Zoomカメラのみ（253枚）
- → 統合された1つのモデルにならない

## アルゴリズム

### 3種類のマッチングペア

```
1. W↔W 時間的ペア
   - 同一カメラ（Wide）内の連続フレーム
   - 各フレームと前後N枚をマッチング（デフォルト: N=10）

2. Z↔Z 時間的ペア
   - 同一カメラ（Zoom）内の連続フレーム
   - 各フレームと前後N枚をマッチング（デフォルト: N=10）

3. W↔Z クロスカメラペア（重要）
   - 異なるカメラ間のマッチング
   - 各Wフレームと同時刻±M枚のZフレームをマッチング
   - 例: W_t → Z_{t-5}, Z_{t-4}, ..., Z_t, ..., Z_{t+4}, Z_{t+5}
```

### パラメータ

| パラメータ | デフォルト値 | 説明 |
|-----------|-------------|------|
| `TemporalOverlap` | 10 | 同一カメラ内の時間的オーバーラップ |
| `CrossCameraTemporalOverlap` | 5 | W↔Z間の時間的オーバーラップ |

### 図解

```
時間軸 →
         t-5  t-4  t-3  t-2  t-1   t   t+1  t+2  t+3  t+4  t+5
Wide:     W    W    W    W    W   [W]   W    W    W    W    W
          ↓    ↓    ↓    ↓    ↓    ↓    ↓    ↓    ↓    ↓    ↓
Zoom:     Z    Z    Z    Z    Z   [Z]   Z    Z    Z    Z    Z

[W] と [Z] が同時刻のフレーム
[W] は時刻 t-5 から t+5 までの全Zフレームとマッチング
```

## 効果

### ペア数の比較（253枚 W + 253枚 Z の場合）

| 手法 | ペア数 | 割合 |
|-----|-------|------|
| Exhaustive | 128,011 | 100% |
| Custom (overlap=0) | 5,287 | 4.1% |
| Custom (overlap=5) | 7,787 | 6.1% |

### W↔Zペアの増加

| CrossCameraTemporalOverlap | W↔Zペア数 | 全ペアに占める割合 |
|---------------------------|----------|------------------|
| 0（同時刻のみ） | 253 | 4.9% |
| 5（±5フレーム） | 2,753 | 35.7% |

## 使用方法

```powershell
.\generate_match_pairs.ps1 `
    -ImagesDir "C:\data\output\images" `
    -OutputPath "C:\data\output\colmap_output\match_pairs.txt" `
    -TemporalOverlap 10 `
    -CrossCameraTemporalOverlap 5
```

## 出力形式

COLMAP custom_matches形式のテキストファイル：
```
video_W/frame_00001.png video_W/frame_00002.png
video_W/frame_00001.png video_W/frame_00003.png
...
video_W/frame_00001.png video_Z/frame_00001.png
video_W/frame_00001.png video_Z/frame_00002.png
...
```

## 注意事項

1. **フレーム番号の同期**: W/Zの`frame_XXXXX.png`の番号が時間的に同期している前提
2. **FOVの違い**: W/Zで視野角が大きく異なる場合、特徴点マッチングが困難な場合あり
3. **Exhaustive推奨**: W/Z間のマッチングが困難な場合は`exhaustive_matcher`の使用を推奨

## 関連ファイル

- `generate_match_pairs.ps1` - マッチングペア生成スクリプト
- `colmap_processor.ps1` - COLMAPマッチング実行
- `run_pipeline_exhaustive.ps1` - Exhaustiveマッチング版パイプライン

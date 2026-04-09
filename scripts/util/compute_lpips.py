"""Compute LPIPS (perceptual quality) for a 3DGS PLY by rendering from training viewpoints.

Reads COLMAP sparse model (cameras.bin, images.bin) for camera intrinsics + poses,
loads the exported PLY (3DGS format), renders images at training viewpoints using gsplat,
and computes LPIPS (AlexNet backbone) between renders and original images.

Usage:
    python scripts/compute_lpips.py \
        --ply output/postshot/scene.ply \
        --sparse output/colmap/sparse/0 \
        --images output/images \
        --output output/postshot/lpips.json \
        --max-images 50
"""

import argparse
import json
import math
import os
import struct
import sys

import numpy as np
import torch


# ─── COLMAP binary reader (embedded) ───────────────────────────────────────

def read_cameras_binary(path):
    """Read cameras.bin → dict of {camera_id: {model, width, height, params}}."""
    cameras = {}
    with open(path, "rb") as f:
        num_cameras = struct.unpack("<Q", f.read(8))[0]
        for _ in range(num_cameras):
            camera_id = struct.unpack("<I", f.read(4))[0]
            model_id = struct.unpack("<i", f.read(4))[0]
            width = struct.unpack("<Q", f.read(8))[0]
            height = struct.unpack("<Q", f.read(8))[0]
            # Number of params per model
            num_params = {0: 3, 1: 4, 2: 4, 3: 5, 4: 4, 5: 5, 6: 8, 7: 12, 8: 4, 9: 5}
            n = num_params.get(model_id, 4)
            params = struct.unpack(f"<{n}d", f.read(8 * n))
            cameras[camera_id] = {
                "model_id": model_id,
                "width": width,
                "height": height,
                "params": list(params),
            }
    return cameras


def read_images_binary(path):
    """Read images.bin → dict of {image_id: {qvec, tvec, camera_id, name}}."""
    images = {}
    with open(path, "rb") as f:
        num_images = struct.unpack("<Q", f.read(8))[0]
        for _ in range(num_images):
            image_id = struct.unpack("<I", f.read(4))[0]
            qvec = struct.unpack("<4d", f.read(32))
            tvec = struct.unpack("<3d", f.read(24))
            camera_id = struct.unpack("<I", f.read(4))[0]
            # Read name (null-terminated string)
            name_chars = []
            while True:
                c = f.read(1)
                if c == b"\x00":
                    break
                name_chars.append(c.decode("utf-8", errors="replace"))
            name = "".join(name_chars)
            # Read 2D points (skip)
            num_points2d = struct.unpack("<Q", f.read(8))[0]
            # Each point2D: x(double), y(double), point3d_id(long long)
            f.read(num_points2d * 24)
            images[image_id] = {
                "qvec": qvec,
                "tvec": tvec,
                "camera_id": camera_id,
                "name": name,
            }
    return images


def qvec_to_rotmat(qvec):
    """Convert COLMAP quaternion (w, x, y, z) to 3x3 rotation matrix."""
    w, x, y, z = qvec
    R = np.array([
        [1 - 2*y*y - 2*z*z, 2*x*y - 2*w*z, 2*x*z + 2*w*y],
        [2*x*y + 2*w*z, 1 - 2*x*x - 2*z*z, 2*y*z - 2*w*x],
        [2*x*z - 2*w*y, 2*y*z + 2*w*x, 1 - 2*x*x - 2*y*y],
    ])
    return R


def get_camera_intrinsics(camera):
    """Extract fx, fy, cx, cy from COLMAP camera params."""
    model_id = camera["model_id"]
    params = camera["params"]
    w, h = camera["width"], camera["height"]

    if model_id == 0:  # SIMPLE_PINHOLE: f, cx, cy
        fx = fy = params[0]
        cx, cy = params[1], params[2]
    elif model_id == 1:  # PINHOLE: fx, fy, cx, cy
        fx, fy = params[0], params[1]
        cx, cy = params[2], params[3]
    elif model_id == 2:  # SIMPLE_RADIAL: f, cx, cy, k
        fx = fy = params[0]
        cx, cy = params[1], params[2]
    elif model_id == 3:  # RADIAL: f, cx, cy, k1, k2
        fx = fy = params[0]
        cx, cy = params[1], params[2]
    elif model_id == 4:  # OPENCV: fx, fy, cx, cy, k1, k2, p1, p2
        fx, fy = params[0], params[1]
        cx, cy = params[2], params[3]
    elif model_id == 8:  # SIMPLE_RADIAL_FISHEYE: f, cx, cy, k
        fx = fy = params[0]
        cx, cy = params[1], params[2]
    else:
        # Fallback: assume first param is f or (fx, fy)
        fx = fy = params[0]
        cx, cy = w / 2.0, h / 2.0

    return fx, fy, cx, cy


# ─── PLY reader for 3DGS ──────────────────────────────────────────────────

def load_ply_3dgs(ply_path):
    """Load a 3DGS PLY file → dict with positions, SH, opacity, scales, rotations."""
    from plyfile import PlyData

    plydata = PlyData.read(ply_path)
    vertex = plydata["vertex"]

    # Positions
    xyz = np.stack([vertex["x"], vertex["y"], vertex["z"]], axis=-1).astype(np.float32)

    # Opacity (stored as raw logit in Postshot PLY)
    opacity = vertex["opacity"].astype(np.float32)

    # Scales (log-space in Postshot PLY)
    scales = np.stack([vertex["scale_0"], vertex["scale_1"], vertex["scale_2"]], axis=-1).astype(np.float32)

    # Rotations (quaternion wxyz)
    rotations = np.stack([
        vertex["rot_0"], vertex["rot_1"], vertex["rot_2"], vertex["rot_3"]
    ], axis=-1).astype(np.float32)

    # SH coefficients - DC term (f_dc_0, f_dc_1, f_dc_2)
    sh_dc = np.stack([vertex["f_dc_0"], vertex["f_dc_1"], vertex["f_dc_2"]], axis=-1).astype(np.float32)

    # Higher order SH coefficients
    sh_rest_names = sorted(
        [p.name for p in vertex.properties if p.name.startswith("f_rest_")],
        key=lambda x: int(x.split("_")[-1]),
    )
    if sh_rest_names:
        sh_rest = np.stack([vertex[n] for n in sh_rest_names], axis=-1).astype(np.float32)
    else:
        sh_rest = np.zeros((xyz.shape[0], 0), dtype=np.float32)

    return {
        "xyz": xyz,
        "opacity": opacity,
        "scales": scales,
        "rotations": rotations,
        "sh_dc": sh_dc,
        "sh_rest": sh_rest,
    }


# ─── Pure PyTorch 3DGS rendering (no CUDA toolkit needed) ────────────────

def eval_sh_dc(sh_dc):
    """Evaluate degree-0 SH (DC term only) → RGB color.

    SH DC coefficient to color: color = sh * C0 + 0.5
    where C0 = 0.28209479177387814
    """
    C0 = 0.28209479177387814
    return sh_dc * C0 + 0.5


def quat_to_rotmat_batch(quats):
    """Convert quaternions (N, 4) wxyz to rotation matrices (N, 3, 3)."""
    w, x, y, z = quats[:, 0], quats[:, 1], quats[:, 2], quats[:, 3]
    R = torch.stack([
        1 - 2*y*y - 2*z*z, 2*x*y - 2*w*z, 2*x*z + 2*w*y,
        2*x*y + 2*w*z, 1 - 2*x*x - 2*z*z, 2*y*z - 2*w*x,
        2*x*z - 2*w*y, 2*y*z + 2*w*x, 1 - 2*x*x - 2*y*y,
    ], dim=-1).reshape(-1, 3, 3)
    return R


def render_gaussians(gaussians, viewmat, K, width, height, device="cuda",
                     render_size=512):
    """Render 3DGS using vectorized 2D gaussian splatting in pure PyTorch.

    Projects 3D gaussians to 2D, computes 2D covariance via EWA splatting,
    and uses a fixed-size kernel with scatter operations for fast rendering.

    Args:
        gaussians: dict from load_ply_3dgs
        viewmat: 4x4 world-to-camera matrix (torch tensor)
        K: 3x3 intrinsics matrix (torch tensor)
        width, height: original image dimensions
        device: cuda or cpu
        render_size: output resolution (default 512)

    Returns:
        rendered image as (render_size, render_size, 3) numpy array in [0, 1]
    """
    rW = rH = render_size
    sx = rW / width
    sy = rH / height

    # Scale intrinsics to render resolution
    sK = K.clone()
    sK[0, 0] *= sx; sK[0, 2] *= sx
    sK[1, 1] *= sy; sK[1, 2] *= sy

    means = torch.from_numpy(gaussians["xyz"]).to(device)
    opacities_logit = torch.from_numpy(gaussians["opacity"]).to(device)
    sh_dc = torch.from_numpy(gaussians["sh_dc"]).to(device)
    scales_log = torch.from_numpy(gaussians["scales"]).to(device)
    rotations_raw = torch.from_numpy(gaussians["rotations"]).to(device)

    # Transform to camera space
    R = viewmat[:3, :3].to(device)
    t = viewmat[:3, 3].to(device)
    means_cam = means @ R.T + t[None]  # (N, 3)

    # Filter: keep only in front of camera
    valid = means_cam[:, 2] > 0.1
    means_cam = means_cam[valid]
    opacities_logit = opacities_logit[valid]
    sh_dc = sh_dc[valid]
    scales_log = scales_log[valid]
    rotations_raw = rotations_raw[valid]

    if means_cam.shape[0] == 0:
        return np.zeros((rH, rW, 3), dtype=np.float32)

    # Project to 2D
    fx, fy, cx, cy = sK[0, 0], sK[1, 1], sK[0, 2], sK[1, 2]
    z = means_cam[:, 2].clamp(min=0.1)
    px = means_cam[:, 0] * fx / z + cx  # float pixel coords
    py = means_cam[:, 1] * fy / z + cy

    # Compute 3D covariance in world space: R_q @ S @ S^T @ R_q^T
    scales = scales_log.exp()  # (N, 3) - Postshot stores log-scale
    quats = rotations_raw / rotations_raw.norm(dim=-1, keepdim=True)
    R_q = quat_to_rotmat_batch(quats)  # (N, 3, 3)

    # M = R_q @ diag(scales)
    M = R_q * scales.unsqueeze(1)  # (N, 3, 3) * (N, 1, 3) broadcast -> (N, 3, 3)
    Sigma_world = M @ M.transpose(1, 2)  # (N, 3, 3)

    # Transform covariance to camera space
    Sigma_cam = R @ Sigma_world @ R.T

    # EWA: Project 3D covariance to 2D using Jacobian of perspective projection
    tx = means_cam[:, 0]
    ty = means_cam[:, 1]
    tz = means_cam[:, 2].clamp(min=0.1)

    J = torch.zeros(means_cam.shape[0], 2, 3, device=device)
    J[:, 0, 0] = fx / tz
    J[:, 0, 2] = -fx * tx / (tz * tz)
    J[:, 1, 1] = fy / tz
    J[:, 1, 2] = -fy * ty / (tz * tz)

    # 2D covariance
    cov2D = J @ Sigma_cam @ J.transpose(1, 2)  # (N, 2, 2)
    cov2D[:, 0, 0] += 0.3  # regularization
    cov2D[:, 1, 1] += 0.3

    # Inverse of 2D covariance
    a = cov2D[:, 0, 0]
    b = cov2D[:, 0, 1]
    c = cov2D[:, 1, 1]
    det = (a * c - b * b).clamp(min=1e-6)
    inv_a = c / det
    inv_b = -b / det
    inv_c = a / det

    # Compute gaussian radius (3-sigma)
    trace = a + c
    discriminant = ((a - c) ** 2 + 4 * b * b).clamp(min=0).sqrt()
    lambda_max = 0.5 * (trace + discriminant)
    radius = (3.0 * lambda_max.clamp(min=0.1).sqrt()).ceil()  # float pixels
    # Cap radius to reasonable value for performance
    MAX_RADIUS = 32
    radius = radius.clamp(max=MAX_RADIUS)

    # Compute colors and opacities
    opacities = opacities_logit.sigmoid()
    colors = eval_sh_dc(sh_dc).clamp(0, 1)  # (N, 3)

    # Filter: keep in-bounds and significant gaussians
    margin = MAX_RADIUS
    in_bounds = (px > -margin) & (px < rW + margin) & (py > -margin) & (py < rH + margin)
    # Also filter low-opacity gaussians for speed
    in_bounds = in_bounds & (opacities > 0.01)

    px = px[in_bounds]
    py = py[in_bounds]
    z = z[in_bounds]
    colors = colors[in_bounds]
    opacities = opacities[in_bounds]
    inv_a = inv_a[in_bounds]
    inv_b = inv_b[in_bounds]
    inv_c = inv_c[in_bounds]
    radius = radius[in_bounds]

    if px.shape[0] == 0:
        return np.zeros((rH, rW, 3), dtype=np.float32)

    # Sort by depth (back to front for simple alpha blending)
    sort_idx = z.argsort(descending=True)
    px = px[sort_idx]
    py = py[sort_idx]
    colors = colors[sort_idx]
    opacities = opacities[sort_idx]
    inv_a = inv_a[sort_idx]
    inv_b = inv_b[sort_idx]
    inv_c = inv_c[sort_idx]
    radius = radius[sort_idx]

    N = px.shape[0]

    # Vectorized splatting with fixed kernel
    # Create kernel offsets: (2K+1)^2 offsets for K = kernel_half
    KERNEL_HALF = 3  # 7x7 kernel per gaussian
    offsets = torch.arange(-KERNEL_HALF, KERNEL_HALF + 1, device=device, dtype=torch.float32)
    dy_grid, dx_grid = torch.meshgrid(offsets, offsets, indexing='ij')
    dx_grid = dx_grid.reshape(-1)  # (K*K,)
    dy_grid = dy_grid.reshape(-1)
    K_size = dx_grid.shape[0]  # 49 for 7x7

    image = torch.zeros(rH, rW, 3, device=device)
    weight_buf = torch.zeros(rH * rW, 1, device=device)

    # Process in batches to manage GPU memory
    BATCH = 200000
    for start in range(0, N, BATCH):
        end = min(start + BATCH, N)
        B = end - start

        b_px = px[start:end]           # (B,)
        b_py = py[start:end]
        b_colors = colors[start:end]   # (B, 3)
        b_opacities = opacities[start:end]  # (B,)
        b_inv_a = inv_a[start:end]
        b_inv_b = inv_b[start:end]
        b_inv_c = inv_c[start:end]
        b_radius = radius[start:end]

        # Scale offsets by radius: each gaussian gets its own scaled kernel
        # For gaussians with radius R, offsets span [-R, R] in R/(KERNEL_HALF) steps
        scale = b_radius / KERNEL_HALF  # (B,)
        # dx, dy for each gaussian at each kernel point: (B, K*K)
        dx = dx_grid.unsqueeze(0) * scale.unsqueeze(1)  # (B, K*K)
        dy = dy_grid.unsqueeze(0) * scale.unsqueeze(1)

        # Evaluate 2D gaussian at each offset
        power = -0.5 * (
            b_inv_a.unsqueeze(1) * dx * dx +
            2 * b_inv_b.unsqueeze(1) * dx * dy +
            b_inv_c.unsqueeze(1) * dy * dy
        )  # (B, K*K)

        gauss_weight = torch.exp(power.clamp(min=-8.0))  # (B, K*K)
        alpha = (b_opacities.unsqueeze(1) * gauss_weight).clamp(max=0.99)  # (B, K*K)

        # Pixel coordinates for each splat point
        splat_x = (b_px.unsqueeze(1) + dx).long()  # (B, K*K)
        splat_y = (b_py.unsqueeze(1) + dy).long()

        # Flatten for scatter
        splat_x_flat = splat_x.reshape(-1)
        splat_y_flat = splat_y.reshape(-1)
        alpha_flat = alpha.reshape(-1)
        # Expand colors to match: (B, K*K, 3)
        colors_expanded = b_colors.unsqueeze(1).expand(-1, K_size, -1).reshape(-1, 3)

        # Filter in-bounds
        valid = (splat_x_flat >= 0) & (splat_x_flat < rW) & \
                (splat_y_flat >= 0) & (splat_y_flat < rH) & \
                (alpha_flat > 0.001)
        splat_x_flat = splat_x_flat[valid]
        splat_y_flat = splat_y_flat[valid]
        alpha_flat = alpha_flat[valid]
        colors_valid = colors_expanded[valid]  # (M, 3)

        if splat_x_flat.shape[0] == 0:
            continue

        # Pixel indices
        pixel_idx = splat_y_flat * rW + splat_x_flat  # (M,)

        # Back-to-front compositing via simple alpha blend using scatter
        # For each pixel: C_new = alpha * color + (1-alpha) * C_old
        # With scatter, we approximate: accumulate weighted colors
        weighted_colors = alpha_flat.unsqueeze(-1) * colors_valid  # (M, 3)

        image_flat = image.reshape(-1, 3)
        # Apply alpha blending: blend new color over existing
        # Since we're going back-to-front, we use: C = alpha*color + (1-alpha)*C_existing
        # With scatter_add this becomes an approximation but works well in practice
        image_flat.scatter_add_(0, pixel_idx.unsqueeze(-1).expand(-1, 3), weighted_colors)

        # Also accumulate alpha weights for normalization
        weight_buf.scatter_add_(
            0, pixel_idx.unsqueeze(-1), alpha_flat.unsqueeze(-1)
        )

    # Normalize by accumulated weight
    weight = weight_buf.clamp(min=1e-6)
    image_flat = image.reshape(-1, 3) / weight
    result = image_flat.reshape(rH, rW, 3).clamp(0, 1).cpu().numpy()
    return result


# ─── LPIPS computation ─────────────────────────────────────────────────────

def compute_lpips_batch(renders, originals, device="cuda"):
    """Compute LPIPS between pairs of images.

    Args:
        renders: list of (H, W, 3) numpy arrays in [0, 1]
        originals: list of (H, W, 3) numpy arrays in [0, 1]
        device: cuda or cpu

    Returns:
        list of per-image LPIPS values
    """
    import lpips

    loss_fn = lpips.LPIPS(net="alex").to(device)
    loss_fn.eval()

    scores = []
    with torch.no_grad():
        for render, original in zip(renders, originals):
            # Resize both to 256x256 (standard LPIPS evaluation practice)
            r = torch.from_numpy(render).permute(2, 0, 1).unsqueeze(0).float().to(device)
            o = torch.from_numpy(original).permute(2, 0, 1).unsqueeze(0).float().to(device)

            # Resize to 256x256
            r = torch.nn.functional.interpolate(r, size=(256, 256), mode="bilinear", align_corners=False)
            o = torch.nn.functional.interpolate(o, size=(256, 256), mode="bilinear", align_corners=False)

            # LPIPS expects [-1, 1] range
            r = r * 2.0 - 1.0
            o = o * 2.0 - 1.0

            score = loss_fn(r, o).item()
            scores.append(score)

    return scores


# ─── Main ──────────────────────────────────────────────────────────────────

def find_image_file(images_dir, image_name):
    """Find image file, searching subdirectories if needed."""
    # Direct path
    direct = os.path.join(images_dir, image_name)
    if os.path.exists(direct):
        return direct

    # Search subdirectories (COLMAP may store as "video_Z/frame_001.png")
    for root, _, files in os.walk(images_dir):
        for f in files:
            full = os.path.join(root, f)
            # Match the relative path from images_dir
            rel = os.path.relpath(full, images_dir).replace("\\", "/")
            if rel == image_name.replace("\\", "/"):
                return full

    return None


def main():
    parser = argparse.ArgumentParser(description="Compute LPIPS for 3DGS PLY")
    parser.add_argument("--ply", required=True, help="Path to 3DGS PLY file")
    parser.add_argument("--sparse", required=True, help="Path to COLMAP sparse model directory")
    parser.add_argument("--images", required=True, help="Path to training images directory")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--max-images", type=int, default=50, help="Max images to evaluate (0=all)")
    parser.add_argument("--device", default="cuda", help="Device (cuda or cpu)")
    args = parser.parse_args()

    device = args.device if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    # Check inputs
    ply_path = args.ply
    sparse_dir = args.sparse
    images_dir = args.images

    if not os.path.exists(ply_path):
        print(f"ERROR: PLY not found: {ply_path}")
        sys.exit(1)

    cameras_bin = os.path.join(sparse_dir, "cameras.bin")
    images_bin = os.path.join(sparse_dir, "images.bin")
    if not os.path.exists(cameras_bin) or not os.path.exists(images_bin):
        print(f"ERROR: COLMAP sparse model not found in: {sparse_dir}")
        sys.exit(1)

    if not os.path.isdir(images_dir):
        print(f"ERROR: Images directory not found: {images_dir}")
        sys.exit(1)

    # Read COLMAP model
    print("Reading COLMAP sparse model...")
    cameras = read_cameras_binary(cameras_bin)
    images = read_images_binary(images_bin)
    print(f"  Cameras: {len(cameras)}, Images: {len(images)}")

    # Load PLY
    print(f"Loading PLY: {ply_path}")
    gaussians = load_ply_3dgs(ply_path)
    print(f"  Gaussians: {gaussians['xyz'].shape[0]:,}")
    print(f"  SH rest dims: {gaussians['sh_rest'].shape[1]}")

    # Select images to evaluate
    image_list = list(images.values())
    if args.max_images > 0 and len(image_list) > args.max_images:
        rng = np.random.RandomState(42)
        indices = rng.choice(len(image_list), size=args.max_images, replace=False)
        image_list = [image_list[i] for i in sorted(indices)]
    print(f"  Evaluating {len(image_list)} images")

    # Render and compute LPIPS
    from PIL import Image

    renders = []
    originals = []
    eval_names = []
    skipped = 0

    for idx, img_data in enumerate(image_list):
        name = img_data["name"]
        cam = cameras[img_data["camera_id"]]
        W, H = cam["width"], cam["height"]

        # Find original image
        img_path = find_image_file(images_dir, name)
        if img_path is None:
            skipped += 1
            continue

        # Read original image
        orig_pil = Image.open(img_path).convert("RGB")
        orig_np = np.array(orig_pil).astype(np.float32) / 255.0

        # Build camera matrices
        fx, fy, cx, cy = get_camera_intrinsics(cam)
        K = torch.tensor([
            [fx, 0, cx],
            [0, fy, cy],
            [0, 0, 1],
        ], dtype=torch.float32)

        # World-to-camera: R | t
        R = qvec_to_rotmat(img_data["qvec"])
        t = np.array(img_data["tvec"])
        viewmat = np.eye(4, dtype=np.float32)
        viewmat[:3, :3] = R
        viewmat[:3, 3] = t
        viewmat = torch.from_numpy(viewmat)

        # Render
        try:
            with torch.no_grad():
                rendered = render_gaussians(gaussians, viewmat, K, W, H, device=device)
        except Exception as e:
            print(f"  WARNING: Render failed for {name}: {e}")
            skipped += 1
            continue

        # Resize original if dimensions don't match
        if orig_np.shape[0] != H or orig_np.shape[1] != W:
            orig_pil_resized = orig_pil.resize((W, H), Image.LANCZOS)
            orig_np = np.array(orig_pil_resized).astype(np.float32) / 255.0

        renders.append(rendered)
        originals.append(orig_np)
        eval_names.append(name)

        if (idx + 1) % 10 == 0 or idx == 0:
            print(f"  Rendered {idx + 1}/{len(image_list)}...")

    if len(renders) == 0:
        print("ERROR: No images could be rendered")
        sys.exit(1)

    if skipped > 0:
        print(f"  Skipped {skipped} images (not found or render failed)")

    # Compute PSNR
    psnr_scores = []
    for render, original in zip(renders, originals):
        # Resize render to match original for fair PSNR comparison
        from PIL import Image as PILImage
        r_pil = PILImage.fromarray((render * 255).clip(0, 255).astype(np.uint8))
        r_resized = r_pil.resize((original.shape[1], original.shape[0]), PILImage.LANCZOS)
        r_np = np.array(r_resized).astype(np.float32) / 255.0
        mse = np.mean((r_np - original) ** 2)
        if mse < 1e-10:
            psnr_scores.append(100.0)
        else:
            psnr_scores.append(float(-10.0 * np.log10(mse)))

    psnr_mean = float(np.mean(psnr_scores))
    print(f"  PSNR mean:  {psnr_mean:.2f} dB")

    # Compute LPIPS
    print(f"Computing LPIPS on {len(renders)} image pairs...")
    lpips_scores = compute_lpips_batch(renders, originals, device=device)

    lpips_mean = float(np.mean(lpips_scores))
    print(f"  LPIPS mean: {lpips_mean:.4f}")
    print(f"  LPIPS min:  {min(lpips_scores):.4f}")
    print(f"  LPIPS max:  {max(lpips_scores):.4f}")

    # Write output
    result = {
        "lpips_mean": round(lpips_mean, 6),
        "psnr_mean": round(psnr_mean, 4),
        "lpips_per_image": [
            {"name": name, "lpips": round(lscore, 6), "psnr": round(pscore, 4)}
            for name, lscore, pscore in zip(eval_names, lpips_scores, psnr_scores)
        ],
        "num_images": len(renders),
        "num_skipped": skipped,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(result, f, indent=2)
    print(f"  Results saved to: {args.output}")


if __name__ == "__main__":
    main()

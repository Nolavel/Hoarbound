#!/usr/bin/env python3
"""Height deltas at fixed world points from capture_snow_surface.gd witness frames.

Usage: python3 tools/runtime/analyze_snow_surface.py <capture_dir> [trail_m]
Writes <capture_dir>/analysis.json and worst-step heat maps. Pixels within
trail_m of Henry's path are left out: his own prints are meant to change.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def decode(path):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0
    coarse = rgb[..., 0] * 4.0
    mid = rgb[..., 1] * 0.25
    fine = rgb[..., 2] * 0.016
    h = mid + np.round((coarse - mid) / 0.25) * 0.25
    h = fine + np.round((h - fine) / 0.016) * 0.016
    ## Background reads black or, through the scene's post stack, white.
    drawn = (rgb.sum(axis=2) > 0.0) & (rgb.min(axis=2) < 0.98)
    return h, drawn


def contact_sheet(cap):
    """First, middle and last frame of the TPS and oblique views, 3 x 2 at 480 px."""
    rows = []
    for view in ("tps", "oblique"):
        frames = sorted((cap / view).glob("*.png"))
        if not frames:
            return None
        picks = [frames[0], frames[len(frames) // 2], frames[-1]]
        rows.append([Image.open(f).convert("RGB").resize((480, 270)) for f in picks])
    walls = [cap / f"wall_{i}_{tag}.png" for i in (0, 1) for tag in ("first", "last")]
    if all(p.exists() for p in walls):
        rows.append([Image.open(p).convert("RGB").resize((480, 270)) for p in walls[:3]])
        rows.append([Image.open(walls[3]).convert("RGB").resize((480, 270))])
    sheet = Image.new("RGB", (480 * 3, 270 * len(rows)))
    for r, row in enumerate(rows):
        for c, img in enumerate(row):
            sheet.paste(img, (c * 480, r * 270))
    return sheet


def world_grid(report, shape):
    w = report["witness"]
    hgt, wid = shape
    size = w["size_m"]
    origin = np.array([w["origin"][0], w["origin"][2]])
    right = np.array([w["right"][0], w["right"][2]])
    up = np.array([w["up"][0], w["up"][2]])
    u = (np.arange(wid) + 0.5) / wid - 0.5
    v = 0.5 - (np.arange(hgt) + 0.5) / hgt
    uu, vv = np.meshgrid(u * size, v * size * hgt / wid)
    return origin[0] + right[0] * uu + up[0] * vv, origin[1] + right[1] * uu + up[1] * vv


def main():
    cap = Path(sys.argv[1])
    trail_m = float(sys.argv[2]) if len(sys.argv) > 2 else 1.5
    report = json.loads((cap / "report.json").read_text())
    frames = sorted((cap / "witness").glob("*.png"))
    h0, d0 = decode(frames[0])
    wx, wz = world_grid(report, h0.shape)
    path = np.array([[f["henry"][0], f["henry"][2]] for f in report["frames"]])
    near_path = np.zeros(h0.shape, bool)
    for a, b in zip(path[:-1], path[1:]):
        ab = b - a
        t = np.clip(((wx - a[0]) * ab[0] + (wz - a[1]) * ab[1]) / max(ab @ ab, 1e-9), 0, 1)
        near_path |= np.hypot(wx - a[0] - t * ab[0], wz - a[1] - t * ab[1]) < trail_m
    steps = []
    prev_h, prev_d = h0, d0
    worst = (0.0, None, None)
    for i, fpath in enumerate(frames[1:], start=1):
        h, d = decode(fpath)
        henry = path[min(i, len(path) - 1)]
        dist = np.maximum(np.abs(wx - henry[0]), np.abs(wz - henry[1]))
        valid = d & prev_d & ~near_path
        dh = np.abs(h - prev_h)
        dh[~valid] = 0.0
        coverage = (d != prev_d) & ~near_path
        row = {"frame": i, "valid_px": int(valid.sum()), "coverage_flips_px": int(coverage.sum())}
        vals = dh[valid]
        if vals.size:
            row.update({
                "max_mm": float(vals.max() * 1000), "p999_mm": float(np.percentile(vals, 99.9) * 1000),
                "over_2mm_px": int((vals > 0.002).sum()), "over_10mm_px": int((vals > 0.010).sum()),
            })
            for lo, hi in [(0, 4), (4, 8), (8, 12), (12, 16), (16, 99)]:
                band = valid & (dist >= lo) & (dist < hi)
                row[f"band_{lo}_{hi}_over_2mm_px"] = int((dh[band] > 0.002).sum())
            if vals.max() > worst[0]:
                worst = (float(vals.max()), i, dh.copy())
        steps.append(row)
        prev_h, prev_d = h, d
    hn, dn = decode(frames[-1])
    total = np.abs(hn - h0)
    both = d0 & dn & ~near_path
    summary = {
        "frames": len(frames),
        "trail_excluded_m": trail_m,
        "step_max_mm": max((s.get("max_mm", 0.0) for s in steps), default=0.0),
        "step_over_2mm_px_total": sum(s.get("over_2mm_px", 0) for s in steps),
        "step_over_10mm_px_total": sum(s.get("over_10mm_px", 0) for s in steps),
        "coverage_flips_px_total": sum(s["coverage_flips_px"] for s in steps),
        "first_to_last_over_2mm_px": int((total[both] > 0.002).sum()),
        "first_to_last_over_10mm_px": int((total[both] > 0.010).sum()),
        "first_to_last_max_mm": float(total[both].max() * 1000) if both.any() else 0.0,
        "first_to_last_coverage_flips_px": int(((d0 != dn) & ~near_path).sum()),
        "valid_px_last": int(both.sum()),
    }
    if worst[1] is not None:
        heat = np.clip(worst[2] / 0.02, 0, 1)
        img = np.zeros(heat.shape + (3,), np.uint8)
        img[..., 0] = (heat * 255).astype(np.uint8)
        img[..., 1] = (near_path * 60).astype(np.uint8)
        img[..., 2] = (d0 * 40).astype(np.uint8)
        Image.fromarray(img).save(cap / "worst_step_heat.png")
        summary["worst_step_frame"] = worst[1]
    heat = np.clip(total * both / 0.02, 0, 1)
    img = np.zeros(heat.shape + (3,), np.uint8)
    img[..., 0] = (heat * 255).astype(np.uint8)
    img[..., 1] = (near_path * 60).astype(np.uint8)
    img[..., 2] = (((d0 != dn) & ~near_path) * 255).astype(np.uint8)
    Image.fromarray(img).save(cap / "first_to_last_heat.png")
    perf_path = cap / "perf.jsonl"
    if perf_path.exists():
        gpu = []
        for line in perf_path.read_text().splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            for view in row.get("viewports", []):
                if view.get("path") == "/root":
                    gpu.append(view.get("gpu_ms", 0.0))
        if gpu:
            ## Lavapipe rasterises on the CPU: only the old/new ratio means anything.
            summary["root_gpu_ms_median"] = float(np.median(gpu))
            summary["root_gpu_samples"] = len(gpu)
    sheet = contact_sheet(cap)
    if sheet is not None:
        sheet.save(cap / "review_sheet.jpg", quality=72)
    (cap / "analysis.json").write_text(json.dumps({"summary": summary, "steps": steps}, indent=1))
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()

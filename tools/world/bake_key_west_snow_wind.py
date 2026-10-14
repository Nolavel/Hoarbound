#!/usr/bin/env python3
"""Bake the Key West city-scale snow field: how wind strips and deposits snow.

For two wind directions (prevailing and storm) every 2 m cell of the city gets
a depth factor from upwind fetch, building shelter, street canyons, corner
speed-up, windward banks with a scoured wall foot, and deposition where the wind
slows. Writes data/world/key_west/snow_wind.png (RGBA8):
  R prevailing depth factor, G storm depth factor, B shelter, A building footprint.
Factor 0..255 maps to 0..FACTOR_MAX times the settled depth.
Run: python3 tools/world/bake_key_west_snow_wind.py  (needs numpy, pillow)
     python3 tools/world/bake_key_west_snow_wind.py --reality  -> snow_wind_reality.png, from the
     Reality buildings that are generated (editor index) and the library's land polygons.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

CITY = Path("data/world/key_west/city_preview.json")
REPORT = Path("data/world/key_west/source_report.json")
OCEAN = Path("data/world/key_west/ocean_connected_mask.png")
OUT = Path("data/world/key_west/snow_wind.png")
REALITY_INDEX = Path("data/world/key_west/reality/editor/editor_index.json")
REALITY_OUT = Path("data/world/key_west/snow_wind_reality.png")
CELL_M = 2.0
# Bake only the city plus a margin; the rest of the island keeps factor 1.
MARGIN_M = 200.0
FACTOR_MAX = 2.5
# Compass bearing the wind blows FROM: winter trades ESE, northers veer ENE.
PREVAILING_FROM_DEG = 112.5
STORM_FROM_DEG = 77.5
FETCH_MAX_M = 300.0
# Open run of wind at which a street counts as fully exposed.
FETCH_FULL_M = 120.0
SHELTER_REACH = 6.0  # lee shadow length in obstacle heights
OBSTACLE_M = 2.0
BANK_REACH_M = 24.0  # windward bank reach in front of a wall
WALL_GAP_M = 2.5  # scoured gap at a windward wall foot


def frame(report: dict) -> tuple[float, float]:
    step = float(report["preview_resolution_m"])
    return int(report["width"]) * step, int(report["height"]) * step


def rasterise(city: dict, w: int, h: int, x0: float, z0: float) -> np.ndarray:
    img = Image.new("F", (w, h), 0.0)
    draw = ImageDraw.Draw(img)
    for b in city["buildings"]:
        pts = [((p[0] - x0) / CELL_M, (p[1] - z0) / CELL_M) for p in b["footprint"]]
        if len(pts) >= 3:
            draw.polygon(pts, fill=float(max(b.get("height", 4.0), 3.0)))
    return np.asarray(img, dtype=np.float32)


def water(w: int, h: int, x0: float, z0: float, width_m: float, height_m: float) -> np.ndarray:
    """Ocean mask (whole frame) resampled onto the cropped bake grid."""
    mask = np.asarray(Image.open(OCEAN).convert("L")) > 127
    mh, mw = mask.shape
    xs = ((x0 + (np.arange(w) + 0.5) * CELL_M + width_m * 0.5) / width_m * mw).astype(int).clip(0, mw - 1)
    zs = ((z0 + (np.arange(h) + 0.5) * CELL_M + height_m * 0.5) / height_m * mh).astype(int).clip(0, mh - 1)
    return mask[np.ix_(zs, xs)]


def shifted(a: np.ndarray, dx: int, dz: int, fill: float) -> np.ndarray:
    """a sampled at (x + dx, z + dz), out of range -> fill."""
    out = np.full_like(a, fill)
    h, w = a.shape
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    zs, zd = (slice(dz, h), slice(0, h - dz)) if dz >= 0 else (slice(0, h + dz), slice(-dz, h))
    out[zd, xd] = a[zs, xs]
    return out


def field(height: np.ndarray, sea: np.ndarray, from_deg: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    # Local frame: +x east, +z south. Upwind unit vector points toward the source.
    b = math.radians(from_deg)
    up = np.array([math.sin(b), -math.cos(b)])
    side = np.array([-up[1], up[0]])
    steps = int(FETCH_MAX_M / CELL_M)
    blocked = height > OBSTACLE_M
    fetch = np.full(height.shape, FETCH_MAX_M, dtype=np.float32)
    shelter = np.zeros(height.shape, dtype=np.float32)
    seen = np.zeros(height.shape, dtype=bool)
    for s in range(1, steps + 1):
        dx, dz = round(up[0] * s), round(up[1] * s)
        hit = shifted(height, dx, dz, 0.0)
        dist = s * CELL_M
        newly = (hit > OBSTACLE_M) & ~seen
        fetch[newly] = dist
        seen |= hit > OBSTACLE_M
        # Lee shadow: an obstacle h tall shelters about SHELTER_REACH * h downwind.
        shelter = np.maximum(shelter, np.clip(hit * SHELTER_REACH / dist - 0.5, 0.0, 1.0))
    exposure = np.clip(fetch / FETCH_FULL_M, 0.0, 1.0)
    # Canyon: walls close on both flanks while the street runs with the wind.
    walls = np.zeros(height.shape, dtype=np.float32)
    for sign in (1, -1):
        near = np.zeros(height.shape, dtype=bool)
        for s in range(1, int(16.0 / CELL_M) + 1):
            near |= shifted(height, round(side[0] * s * sign), round(side[1] * s * sign), 0.0) > OBSTACLE_M
        walls += near
    canyon = (walls >= 2) * exposure
    # Corners: a wall on one flank only, with the wind already running free,
    # speeds the flow round the building edge and strips the ground there.
    flank = np.zeros(height.shape, dtype=np.float32)
    for sign in (1, -1):
        close = np.zeros(height.shape, dtype=bool)
        for s in range(1, int(4.0 / CELL_M) + 1):
            close |= shifted(height, round(side[0] * s * sign), round(side[1] * s * sign), 0.0) > OBSTACLE_M
        flank += close
    corner = (flank == 1) * np.clip(exposure * 2.0, 0.0, 1.0) * ~blocked
    # Windward wall: a bank builds in front of it, with a scoured gap at its foot.
    bank = np.zeros(height.shape, dtype=np.float32)
    gap = np.zeros(height.shape, dtype=bool)
    reached = np.zeros(height.shape, dtype=bool)
    for s in range(1, int(BANK_REACH_M / CELL_M) + 1):
        ahead = shifted(height, -round(up[0] * s), -round(up[1] * s), 0.0)
        dist = s * CELL_M
        newly = (ahead > OBSTACLE_M) & ~reached & ~blocked
        reached |= ahead > OBSTACLE_M
        gap |= newly & (dist <= WALL_GAP_M)
        bank = np.where(newly & (dist > WALL_GAP_M), np.clip(1.0 - dist / (1.5 * ahead + 2.0), 0.0, 1.0), bank)
    # Coast: open water upwind strips the shore.
    coast = np.zeros(height.shape, dtype=np.float32)
    for s in range(1, steps + 1, 4):
        coast = np.maximum(coast, shifted(sea.astype(np.float32), round(up[0] * s), round(up[1] * s), 0.0) * (1.0 - s / steps))
    erosion = np.clip(0.6 * exposure + 0.4 * canyon + 0.3 * coast + 0.35 * corner, 0.0, 1.0) * (1.0 - shelter)
    # Deposition where the wind slows: exposure drops going downwind.
    lag = round(12.0 / CELL_M)
    upwind_exposure = shifted(exposure, round(up[0] * lag), round(up[1] * lag), 1.0)
    deposit = np.clip((upwind_exposure - exposure) * 2.0, 0.0, 1.0)
    factor = 0.45 + 0.9 * (1.0 - erosion) + 0.7 * shelter * (1.0 - blocked) + 0.6 * deposit + 0.6 * bank
    factor = np.where(gap, factor * 0.6, factor)
    factor[blocked] = 1.0
    factor[sea] = 0.0
    return np.clip(factor, 0.0, FACTOR_MAX), shelter, exposure


def blur(a: np.ndarray, r: float) -> np.ndarray:
    """Two box passes per axis, close to a Gaussian of radius r cells."""
    k = max(1, int(round(r)))
    out = a.astype(np.float32)
    for axis in (0, 1):
        for _ in range(2):
            pad = np.pad(out, [(k, k) if ax == axis else (0, 0) for ax in (0, 1)], mode="edge")
            c = np.cumsum(pad, axis=axis, dtype=np.float64)
            c = np.insert(c, 0, 0.0, axis=axis)
            n = out.shape[axis]
            hi = np.take(c, np.arange(2 * k + 1, n + 2 * k + 1), axis=axis)
            lo = np.take(c, np.arange(0, n), axis=axis)
            out = ((hi - lo) / (2 * k + 1)).astype(np.float32)
    return out


def reality_city() -> dict:
    """Generated Reality buildings as the legacy city shape: footprint (local x, z) and height above ground."""
    doc = json.loads(REALITY_INDEX.read_text())
    return {"buildings": [{"footprint": list(zip(b["ring"][0::2], b["ring"][1::2])), "height": b["h"]}
                          for b in doc["buildings"] if b["generated"] and len(b["ring"]) >= 6]}


def reality_sea(w: int, h: int, x0: float, z0: float) -> np.ndarray:
    """Cells outside every library land polygon."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from reality import frame as rframe
    from reality import library
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    geoms, _ = library.read_layer("land")
    for g in geoms:
        local = rframe.to_local(g)
        for poly in getattr(local, "geoms", [local]):
            if poly.geom_type != "Polygon":
                continue  # land points and lines carry no area
            draw.polygon([((x - x0) / CELL_M, (z - z0) / CELL_M) for x, z in poly.exterior.coords], fill=255)
            for ring in poly.interiors:
                draw.polygon([((x - x0) / CELL_M, (z - z0) / CELL_M) for x, z in ring.coords], fill=0)
    return np.asarray(img) < 128


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reality", action="store_true", help="bake from the Reality buildings into snow_wind_reality.png")
    reality = parser.parse_args().reality
    city = reality_city() if reality else json.loads(CITY.read_text())
    out = REALITY_OUT if reality else OUT
    xs = [p[0] for b in city["buildings"] for p in b["footprint"]]
    zs = [p[1] for b in city["buildings"] for p in b["footprint"]]
    x0 = math.floor((min(xs) - MARGIN_M) / CELL_M) * CELL_M
    z0 = math.floor((min(zs) - MARGIN_M) / CELL_M) * CELL_M
    w = int((max(xs) + MARGIN_M - x0) / CELL_M)
    h = int((max(zs) + MARGIN_M - z0) / CELL_M)
    height = rasterise(city, w, h, x0, z0)
    if reality:
        sea = reality_sea(w, h, x0, z0)
    else:
        width_m, height_m = frame(json.loads(REPORT.read_text()))
        sea = water(w, h, x0, z0, width_m, height_m)
    prev, shelter, exposure = field(height, sea, PREVAILING_FROM_DEG)
    storm, _, _ = field(height, sea, STORM_FROM_DEG)
    to8 = lambda a, top: np.clip(a / top * 255.0 + 0.5, 0, 255).astype(np.uint8)
    rgba = np.dstack([
        to8(blur(prev, 1.5), FACTOR_MAX), to8(blur(storm, 1.5), FACTOR_MAX),
        to8(blur(shelter, 1.5), 1.0), to8((height > 0.0).astype(np.float32), 1.0),
    ])
    Image.fromarray(rgba, mode="RGBA").save(out, optimize=True)
    meta = {"cell_m": CELL_M, "origin": [x0, z0], "size": [w, h], "factor_max": FACTOR_MAX,
            "prevailing_from_deg": PREVAILING_FROM_DEG, "storm_from_deg": STORM_FROM_DEG}
    out.with_suffix(".json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"wrote {out} {w}x{h}, mean factor {prev[~sea].mean():.2f}")


if __name__ == "__main__":
    main()

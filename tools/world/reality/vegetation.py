"""Frozen-out vegetation for the editor export: shrub stems and tree trunks kept off the roads.

Stems stand only where the data puts low vegetation: inside mapped scrub / wetland / mangrove /
garden areas, denser on cells the 2019 lidar measures 0.3-2.5 m above ground. Lidar trees are
crown centres; a crown over a street put the trunk in the carriageway, so trunks move to the edge.
"""
from __future__ import annotations

import hashlib
import json
import math

import numpy as np
import shapely
import shapely.ops

from . import frame, library

ROAD_DEFAULT_WIDTH_M = 4.0  # editor_export: ribbon width when a road has no width tag


def _rng(fid: str) -> np.random.Generator:
    """Per-feature generator: the same feature always yields the same stems."""
    return np.random.default_rng(int.from_bytes(hashlib.blake2b(fid.encode(), digest_size=8).digest(), "little"))


class Clearance:
    """Road ribbons (as drawn) and building outlines, in projected metres."""

    def __init__(self, road_margin_m: float) -> None:
        geoms, cols = library.read_layer("roads")
        polys = []
        for g, attrs_json in zip(geoms, cols["attrs_json"]):
            if g is None or g.geom_type not in ("LineString", "MultiLineString"):
                continue
            width = float(json.loads(attrs_json).get("width_m") or ROAD_DEFAULT_WIDTH_M)
            polys.append(g.buffer(width / 2 + road_margin_m, cap_style="flat"))
        self.roads = shapely.STRtree(polys)
        self._road_polys = polys
        bgeoms, _ = library.read_layer("buildings")
        self._buildings = [g for g in bgeoms if g is not None]
        self.buildings = shapely.STRtree(self._buildings)

    def blocked(self, xy: np.ndarray) -> np.ndarray:
        """True where a point lies on a road ribbon or inside a building."""
        pts = shapely.points(xy)
        out = np.zeros(len(pts), bool)
        for tree in (self.roads, self.buildings):
            idx = tree.query(pts, predicate="within")
            out[idx[0]] = True
        return out

    def off_road(self, x: float, y: float, step_m: float) -> tuple[float, float, float]:
        """Moves a point on a road to the nearest road edge plus step_m; (x, y, moved metres)."""
        p = shapely.Point(x, y)
        hits = self.roads.query(p, predicate="within")
        if not len(hits):
            return x, y, 0.0
        local = shapely.union_all([self._road_polys[i] for i in self.roads.query(p.buffer(30.0))])
        edge = shapely.ops.nearest_points(local.boundary, p)[0]
        d = np.array([edge.x - x, edge.y - y])
        n = float(np.linalg.norm(d))
        if n < 1e-6:
            return x, y, 0.0
        q = np.array([edge.x, edge.y]) + d / n * step_m
        if local.contains(shapely.Point(*q)) or len(self.buildings.query(shapely.Point(*q), predicate="within")):
            return x, y, 0.0
        return float(q[0]), float(q[1]), round(n + step_m, 2)


def stem_points(s, clearance: Clearance, g, cls: str, fid: str, cfg: dict) -> dict | None:
    """Stem clumps inside a vegetation polygon: kind 'stems', local x/z, ground y, scale."""
    density = cfg["density_per_100m2"].get(cls)
    if not density or g.is_empty:
        return None
    grid = float(cfg["grid_m"])
    b = g.bounds
    xs = np.arange(b[0] + grid / 2, b[2], grid)
    ys = np.arange(b[1] + grid / 2, b[3], grid)
    if not len(xs) or not len(ys):
        return None
    gx, gy = np.meshgrid(xs, ys)
    gx, gy = gx.ravel(), gy.ravel()
    rng = _rng(fid)
    jitter = (rng.random((len(gx), 2)) - 0.5) * grid
    roll = rng.random(len(gx))
    size = rng.random(len(gx))
    gx, gy = gx + jitter[:, 0], gy + jitter[:, 1]
    keep = shapely.contains_xy(g, gx, gy)
    gx, gy, roll, size = gx[keep], gy[keep], roll[keep], size[keep]
    if not len(gx):
        return None
    free = ~clearance.blocked(np.column_stack([gx, gy]))
    gx, gy, roll, size = gx[free], gy[free], roll[free], size[free]
    if not len(gx):
        return None
    low = _low_vegetation(s, gx, gy, cfg["low_vegetation_band_m"])
    per_cell = density * grid * grid / 100.0
    p_keep = np.where(low, per_cell, per_cell * float(cfg["bare_cell_share"]))
    keep = roll < p_keep
    gx, gy, low, roll, size = gx[keep], gy[keep], low[keep], roll[keep], size[keep]
    cap = int(cfg["max_clumps_per_feature"])
    if len(gx) > cap:
        order = np.argsort(roll)[:cap]
        gx, gy, low, size = gx[order], gy[order], low[order], size[order]
    if not len(gx):
        return None
    ground = s.ground_at(np.column_stack([gx, gy]))
    oe, on = frame.origin()
    ## Lidar-measured shrub cells carry taller stems than the sparse clumps between them.
    scale = np.round(0.7 + 0.6 * size + np.where(low, 0.3, 0.0), 2).tolist()
    return {"kind": "stems", "p": np.round(np.column_stack([gx - oe, on - gy]), 2).ravel().tolist(),
            "y": [round(float(v), 2) for v in ground], "s": scale,
            "lidar_low_vegetation_share": round(float(low.mean()), 3)}


def _low_vegetation(s, gx: np.ndarray, gy: np.ndarray, band: list) -> np.ndarray:
    """2019 DSM minus lidar ground within the band (shrub height) at each point."""
    win = s.dsm.window(float(gx.min()) - 1, float(gy.min()) - 1, float(gx.max()) + 1, float(gy.max()) + 1)
    if win is None:
        return np.zeros(len(gx), bool)
    dsm, ground, t, *_ = win
    cols = np.clip(((gx - t.c) / t.a).astype(int), 0, dsm.shape[1] - 1)
    rows = np.clip(((gy - t.f) / t.e).astype(int), 0, dsm.shape[0] - 1)
    h = dsm[rows, cols] - ground[rows, cols]
    return np.isfinite(h) & (h >= band[0]) & (h <= band[1])


def split_points(mesh: dict) -> dict[str, dict]:
    """Stem clumps grouped by the chunk each one stands in."""
    out: dict[str, dict] = {}
    p, y, sc = mesh["p"], mesh["y"], mesh["s"]
    for k in range(len(y)):
        cid = frame.chunk_of_local(p[2 * k], p[2 * k + 1])
        piece = out.setdefault(cid, {"kind": "stems", "p": [], "y": [], "s": [],
                                     "lidar_low_vegetation_share": mesh["lidar_low_vegetation_share"]})
        piece["p"] += p[2 * k:2 * k + 2]
        piece["y"].append(y[k])
        piece["s"].append(sc[k])
    return out

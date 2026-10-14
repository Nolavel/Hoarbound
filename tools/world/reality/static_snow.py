"""Static snow caps on roofs: offline winter dressing, separate from the dynamic snow Henry deforms.

Depth per roof face = settled depth x Cs (slope) x Ce (shelter) x unbalanced factor (ASCE 7-16, see
config generation.json "static_snow"). The cap sits on the roof faces that hold snow; along its open
edges a lip runs past the eave and droops, longest on lee edges (cornices), short on windward ones.
"""
from __future__ import annotations

import itertools
import json
import math

import numpy as np
from PIL import Image

from . import config, paths

LIP_SHADE = (1.0, 0.93, 0.97, 0.9)  # vertex shade down the lip: thin strata where the layers show


class WindField:
    """The baked city wind field (RGBA: prevailing, storm, shelter, footprint) in the local frame."""

    def __init__(self, png_rel: str):
        png = paths.ROOT / png_rel
        meta = json.loads(png.with_suffix(".json").read_text())
        self.rgba = np.asarray(Image.open(png).convert("RGBA"))
        self.origin = np.array(meta["origin"], float)
        self.cell = float(meta["cell_m"])
        b = math.radians(float(meta["prevailing_from_deg"]))
        self.upwind = np.array([math.sin(b), -math.cos(b)])  # local x east, z south, towards the source

    def shelter(self, x: float, z: float) -> float:
        i = int((z - self.origin[1]) / self.cell)
        j = int((x - self.origin[0]) / self.cell)
        h, w = self.rgba.shape[:2]
        if not (0 <= i < h and 0 <= j < w):
            return 0.0
        return float(self.rgba[i, j, 2]) / 255.0


def settings() -> dict:
    return config.load("generation.json")["static_snow"]


def slope_factor(slope_deg: float, cfg: dict) -> float:
    """ASCE 7 cold-roof Cs: 1 up to slope_full_deg, falling linearly to 0 at slope_zero_deg."""
    lo, hi = cfg["slope_full_deg"], cfg["slope_zero_deg"]
    return float(np.clip((hi - slope_deg) / (hi - lo), 0.0, 1.0))


def roof_cap(mesh: dict, wind: WindField, cfg: dict) -> dict | None:
    """Cap mesh {"v": xyz..., "i": ..., "c": shade...} in the export frame, or None when nothing holds snow."""
    v = np.asarray(mesh.get("roof_v", []), float).reshape(-1, 3)
    tris = np.asarray(mesh.get("roof_i", []), int).reshape(-1, 3)
    if not len(tris):
        return None
    a, b, c = v[tris[:, 0]], v[tris[:, 1]], v[tris[:, 2]]
    n = np.cross(b - a, c - a)
    area = np.linalg.norm(n, axis=1) * 0.5
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    n[n[:, 1] < 0] *= -1.0  # roof triangles may wind either way; snow lies on the up side
    slope = np.degrees(np.arccos(np.clip(n[:, 1], -1.0, 1.0)))
    centre = (a + b + c) / 3.0
    horiz = n[:, [0, 2]]
    hlen = np.linalg.norm(horiz, axis=1)
    facing = np.where(hlen > 1e-6, (horiz @ wind.upwind) / np.maximum(hlen, 1e-9), 0.0) * np.clip(np.sin(np.radians(slope)) / math.sin(math.radians(45)), 0.0, 1.0)
    depth = np.zeros(len(tris))
    for k in range(len(tris)):
        cs = slope_factor(slope[k], cfg)
        if cs <= 0.0 or area[k] < 1e-4:
            continue
        ce = cfg["exposure_open"] + (cfg["exposure_sheltered"] - cfg["exposure_open"]) * wind.shelter(centre[k, 0], centre[k, 2])
        f = facing[k]
        unbalanced = 1.0 - (1.0 - cfg["windward_keep"]) * f if f > 0 else 1.0 - cfg["leeward_gain"] * f
        depth[k] = cfg["settled_depth_m"] * cs * ce * unbalanced
    keep = depth > 0.005
    if not keep.any():
        return None
    # Per-vertex depth: area-weighted mean of the snow-holding faces around it.
    vd = np.zeros(len(v))
    vw = np.zeros(len(v))
    for k in np.flatnonzero(keep):
        for idx in tris[k]:
            vd[idx] += depth[k] * area[k]
            vw[idx] += area[k]
    vd = np.where(vw > 0, vd / np.maximum(vw, 1e-9), 0.0)
    out_v, out_c, out_i = [], [], []

    def add(p, shade):
        out_v.append(p)
        out_c.append(shade)
        return len(out_v) - 1

    top = {}
    for k in np.flatnonzero(keep):
        ids = []
        for idx in tris[k]:
            if idx not in top:
                top[idx] = add(v[idx] + (0.0, vd[idx], 0.0), 1.0)
            ids.append(top[idx])
        out_i.extend(_up(ids, out_v))
    # Open edges of the snow-holding faces get the eave lip, between the outline's real corners.
    edges: dict[tuple[int, int], int] = {}
    count: dict[tuple[int, int], int] = {}
    for k in np.flatnonzero(keep):
        t = tris[k]
        for e0, e1, opp in ((t[0], t[1], t[2]), (t[1], t[2], t[0]), (t[2], t[0], t[1])):
            key = (min(e0, e1), max(e0, e1))
            count[key] = count.get(key, 0) + 1
            edges[key] = opp
    for run in _chains([e for e, c in count.items() if c == 1]):
        at: dict[int, int] = {}
        for k, vid in enumerate(run[:-1]):
            at.setdefault(vid, k)  # a closed loop repeats its first vertex at the end
        corners = _corners(run, v, vd)
        sides = []
        for e0, e1 in itertools.pairwise(corners):
            first = run[at[e0] + 1]  # the merged stretch's first real edge says which side the roof is on
            sides.append(_outward(v[e0], v[e1], v[edges[(min(e0, first), max(e0, first))]]))
        _lip_strip(corners, sides, run[0] == run[-1], v, vd, wind, cfg, add, out_v, out_i)
    flat = np.round(np.asarray(out_v), 3).ravel().tolist()
    return {"v": flat, "i": [int(x) for x in out_i], "c": [round(x, 3) for x in out_c],
            "depth_m": [round(float(depth[keep].min()), 3), round(float(depth[keep].max()), 3)]}


CORNER_DEG = 3.0  # boundary vertices where the outline turns less than this are not lip corners
CORNER_RISE_M = 0.02  # nor where the cap top stays this close to the straight run


def _chains(boundary: list[tuple[int, int]]) -> list[list[int]]:
    """Boundary edges as vertex runs; caller merges straight stretches (see _corners)."""
    nbr: dict[int, list[int]] = {}
    for a, b in boundary:
        nbr.setdefault(a, []).append(b)
        nbr.setdefault(b, []).append(a)
    seen: set[tuple[int, int]] = set()
    out = []
    for a, b in boundary:
        if (a, b) in seen or (b, a) in seen:
            continue
        run = [a, b]
        seen.add((a, b))
        while True:
            nxt = [n for n in nbr[run[-1]] if (run[-1], n) not in seen and (n, run[-1]) not in seen]
            if len(nbr[run[-1]]) != 2 or not nxt:
                break
            seen.add((run[-1], nxt[0]))
            run.append(nxt[0])
            if nxt[0] == run[0]:
                break
        out.append(run)
    return out


def _outward(p0, p1, q) -> np.ndarray:
    """Horizontal unit normal of edge p0-p1 pointing away from the roof face whose third vertex is q."""
    d2 = np.array([p1[2] - p0[2], -(p1[0] - p0[0])])
    d2 /= max(float(np.linalg.norm(d2)), 1e-9)
    return -d2 if d2 @ ((p0 + p1)[[0, 2]] * 0.5 - q[[0, 2]]) < 0 else d2


def _lip_strip(corners, sides, closed, v, vd, wind, cfg, add, out_v, out_i) -> None:
    """Eave lip along a run of corners; neighbouring stretches share a mitred corner, so no gap opens."""
    n = len(corners)
    outs = []
    for k in range(n):
        prev = sides[k - 1] if k > 0 else (sides[-1] if closed else None)
        nxt = sides[k] if k < len(sides) else (sides[0] if closed else None)
        both = [s for s in (prev, nxt) if s is not None]
        m = np.sum(both, axis=0)
        m /= max(float(np.linalg.norm(m)), 1e-9)
        stretch = min(1.0 / max(float(m @ both[0]), 0.5), 2.0)  # miter length, capped at sharp corners
        outs.append((m, stretch))
    rows = []
    for vid, (m, stretch) in zip(corners, outs):
        p, d = v[vid], vd[vid]
        lee = float(np.clip(-(m @ wind.upwind), 0.0, 1.0))
        out = np.array([m[0], 0.0, m[1]]) * stretch
        reach = d * (cfg["eave_over_depth"] + (cfg["cornice_over_depth"] - cfg["eave_over_depth"]) * lee)
        droop = d * cfg["droop_over_depth"] * (0.35 + 0.65 * lee)
        rows.append([p + (0.0, d, 0.0), p + out * reach * 0.75 + (0.0, d * 0.55, 0.0),
                     p + out * reach + (0.0, d * 0.1 - droop * 0.6, 0.0), p + out * reach * 0.45 + (0.0, -droop, 0.0)])
    for k in range(n - 1):
        side = np.array([sides[k][0], 0.0, sides[k][1]])
        for s in range(len(rows[0]) - 1):
            ids = [add(rows[k][s], LIP_SHADE[s]), add(rows[k + 1][s], LIP_SHADE[s]),
                   add(rows[k + 1][s + 1], LIP_SHADE[s + 1]), add(rows[k][s + 1], LIP_SHADE[s + 1])]
            out_i.extend(_facing([ids[0], ids[1], ids[2]], out_v, side))
            out_i.extend(_facing([ids[0], ids[2], ids[3]], out_v, side))


def _corners(run: list[int], v: np.ndarray, vd: np.ndarray) -> list[int]:
    """The run with straight-through vertices dropped (turn under CORNER_DEG, top within CORNER_RISE_M)."""
    keep = [run[0]]
    for k in range(1, len(run) - 1):
        a, b, c = v[keep[-1]], v[run[k]], v[run[k + 1]]
        u, w = (b - a)[[0, 2]], (c - b)[[0, 2]]
        if np.linalg.norm(u) < 1e-6 or np.linalg.norm(w) < 1e-6:
            continue
        turn = math.degrees(math.acos(np.clip(u @ w / (np.linalg.norm(u) * np.linalg.norm(w)), -1.0, 1.0)))
        ta, tb, tc = a[1] + vd[keep[-1]], b[1] + vd[run[k]], c[1] + vd[run[k + 1]]
        t = np.linalg.norm(u) / (np.linalg.norm(u) + np.linalg.norm(w))
        if turn >= CORNER_DEG or abs(tb - (ta + (tc - ta) * t)) >= CORNER_RISE_M:
            keep.append(run[k])
    keep.append(run[-1])
    return keep


def _up(ids: list[int], verts: list) -> list[int]:
    return _facing(ids, verts, np.array([0.0, 1.0, 0.0]))


def _facing(ids: list[int], verts: list, want: np.ndarray) -> list[int]:
    """Triangle ids ordered so Godot shows the face from `want` (clockwise front faces)."""
    a, b, c = (np.asarray(verts[i]) for i in ids)
    n = np.cross(b - a, c - a)
    return [ids[0], ids[2], ids[1]] if n @ want > 0 else list(ids)

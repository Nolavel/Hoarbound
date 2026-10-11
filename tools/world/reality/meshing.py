"""Measured surfaces for the editor generator: roofs, decks, pole heights, terrain tiles.

All heights are NAVD88 metres sampled from the 2019 lidar DSM (0.5 m) and the 2016
DEM (1 m). Nothing here invents shape: a roof is the measured top surface inside the
real footprint (median-filtered, clamped against canopy), or a flat cap when the
measured relief says it is flat or when there is no lidar coverage.
"""
from __future__ import annotations

import numpy as np
import shapely
import shapely.ops
import triangle
from scipy import ndimage

from . import frame, lidar

FLAT_RELIEF_M = 0.6
MIN_WALL_M = 2.2


def fill_dem_voids(dem: np.ndarray, ceiling: float) -> tuple[np.ndarray, np.ndarray]:
    """DEM 6366 voids are unsurveyed water (sea beyond coverage, dredged basins): nearest valid
    depth (GDAL FillNodata-style), clamped to MLLW so a void never surfaces as land."""
    void = ~np.isfinite(dem)
    if not void.any():
        return dem, void
    idx = ndimage.distance_transform_edt(void, return_distances=False, return_indices=True)
    filled = dem[idx[0], idx[1]]
    filled[void] = np.minimum(filled[void], ceiling)
    return filled.astype(np.float32), void


class Surfaces:
    def __init__(self) -> None:
        self.dem = lidar.DemCrop()
        self.dsm = lidar.LidarGrids("noaa_lidar_9081")
        self.ground, self.void = fill_dem_voids(self.dem.data, frame.frame()["vertical"]["tidal_datums_navd88_m"]["MLLW"])

    def ground_at(self, xy: np.ndarray) -> np.ndarray:
        t = self.dem.transform
        cols = np.clip(((xy[:, 0] - t.c) / t.a).astype(int), 0, self.ground.shape[1] - 1)
        rows = np.clip(((xy[:, 1] - t.f) / t.e).astype(int), 0, self.ground.shape[0] - 1)
        return self.ground[rows, cols]

    def dsm_window(self, geom, pad: float = 3.0):
        b = geom.bounds
        win = self.dsm.window(b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad)
        if win is None:
            return None
        dsm, _, transform, minx, maxy, ncol, nrow = win
        if np.isfinite(dsm).sum() < 4:
            return None
        filled = np.where(np.isfinite(dsm), dsm, np.nanmedian(dsm))
        return ndimage.median_filter(filled, size=3), np.isfinite(dsm), transform

    @staticmethod
    def _sample(grid, transform, xy: np.ndarray) -> np.ndarray:
        cols = np.clip(((xy[:, 0] - transform.c) / transform.a).astype(int), 0, grid.shape[1] - 1)
        rows = np.clip(((xy[:, 1] - transform.f) / transform.e).astype(int), 0, grid.shape[0] - 1)
        return grid[rows, cols]


def _ring_points(ring, spacing: float) -> np.ndarray:
    line = shapely.segmentize(shapely.LinearRing(ring.coords), spacing)
    return np.asarray(line.coords)[:-1, :2]

ROOF_MODELS = ("flat", "gable_major", "gable_minor", "hip", "shed")
MODEL_PENALTY_M = 0.05
MAX_MODEL_RMSE_M = 0.45


def _axes(poly):
    """Oriented-envelope frame: centre, unit long axis, half-lengths (U long, V short)."""
    env = shapely.oriented_envelope(poly)
    c = np.asarray(env.exterior.coords)[:4]
    e0, e1 = c[1] - c[0], c[2] - c[1]
    if np.linalg.norm(e0) < np.linalg.norm(e1):
        e0, e1 = e1, e0
    u = e0 / max(np.linalg.norm(e0), 1e-9)
    centre = c.mean(axis=0)
    return centre, u, np.linalg.norm(e0) / 2.0, np.linalg.norm(e1) / 2.0


def _uv(xy, centre, u):
    d = xy - centre
    v_axis = np.array([-u[1], u[0]])
    return d @ u, d @ v_axis


def _design(kind: str, uu, vv, U, V):
    one = np.ones_like(uu)
    if kind == "flat":
        return np.column_stack([one])
    if kind == "gable_major":
        return np.column_stack([one, -np.abs(vv)])
    if kind == "gable_minor":
        return np.column_stack([one, -np.abs(uu)])
    if kind == "hip":
        return np.column_stack([one, -np.maximum(np.abs(vv), np.abs(uu) - max(U - V, 0.0))])
    return np.column_stack([one, vv])


def fit_roof_model(xy: np.ndarray, z: np.ndarray, poly) -> dict | None:
    """Robust (trimmed) least squares over measured DSM cells; picks the simplest adequate model."""
    if len(z) < 8:
        return None
    centre, u, U, V = _axes(poly)
    uu, vv = _uv(xy, centre, u)
    best = None
    for kind in ROOF_MODELS:
        A = _design(kind, uu, vv, U, V)
        keep = np.ones(len(z), bool)
        coef = None
        for _ in range(4):
            if keep.sum() < A.shape[1] + 4:
                break
            coef, *_ = np.linalg.lstsq(A[keep], z[keep], rcond=None)
            res = z - A @ coef
            keep = res < 0.6
            keep &= res > -1.5
        if coef is None or keep.sum() < 0.5 * len(z):
            continue
        rmse = float(np.sqrt(np.mean((z[keep] - A[keep] @ coef) ** 2)))
        if kind in ("gable_major", "gable_minor", "hip") and not (0.15 <= coef[1] <= 1.5):
            continue
        if kind == "shed" and not (0.05 <= abs(coef[1]) <= 1.2):
            continue
        score = float(np.mean(np.minimum(np.abs(z - A @ coef), 1.0))) + MODEL_PENALTY_M * (A.shape[1] - 1)
        if best is None or score < best["score"]:
            best = {"type": kind, "coef": [float(c) for c in coef], "rmse": round(rmse, 3), "score": score,
                    "inlier_share": round(float(keep.mean()), 3), "truncated_l1": round(score - MODEL_PENALTY_M * (A.shape[1] - 1), 3), "centre": centre.tolist(), "u": u.tolist(),
                    "U": round(float(U), 2), "V": round(float(V), 2), "slope_deg": round(float(np.degrees(np.arctan(abs(coef[1])))), 1) if len(coef) > 1 else 0.0}
    if best is None or best["rmse"] > MAX_MODEL_RMSE_M:
        return None
    return best


def eval_roof_model(m: dict, xy: np.ndarray) -> np.ndarray:
    uu, vv = _uv(xy, np.asarray(m["centre"]), np.asarray(m["u"]))
    return _design(m["type"], uu, vv, m["U"], m["V"]) @ np.asarray(m["coef"])



def building_shell(s: Surfaces, poly, base_y: float, height: float | None, height_is_authoritative: bool,
                   roof_relief: float | None, spacing: float, flat_top: float | None = None) -> dict:
    """Walls follow the roof edge; the roof is a model fitted to measured lidar cells
    (flat / gable / hip / shed), or a flat cap when no lidar exists or no model fits."""
    poly = shapely.make_valid(poly)
    if poly.geom_type != "Polygon":
        poly = max(getattr(poly, "geoms", [poly]), key=lambda g: g.area if g.geom_type == "Polygon" else 0)
        if poly.geom_type != "Polygon":
            return {}
    rings = [poly.exterior, *poly.interiors]
    ring_pts = [_ring_points(r, spacing) for r in rings]
    top_known = height is not None
    cap = base_y + (height if top_known else 3.0)
    flat_cap = base_y + flat_top if (flat_top is not None and not height_is_authoritative) else cap
    roof_source = "flat_cap_placeholder" if not top_known else "flat_cap_measured_height"
    model = None
    win = s.dsm_window(poly) if (roof_relief is not None and roof_relief >= FLAT_RELIEF_M) else None
    if win is not None:
        grid, valid, transform = win
        inner = poly.buffer(-0.5)
        if not inner.is_empty:
            rows, cols = np.nonzero(valid)
            xs = transform.c + (cols + 0.5) * transform.a
            ys = transform.f + (rows + 0.5) * transform.e
            ok = shapely.contains_xy(inner, xs, ys)
            model = fit_roof_model(np.column_stack([xs[ok], ys[ok]]), grid[rows[ok], cols[ok]], poly)
        if model is None:
            roof_source = "flat_cap_complex_roof_unresolved"
    extra = [np.zeros((0, 2))]
    if model and model["type"] != "flat":
        b = poly.buffer(-0.6)
        if not b.is_empty:
            minx, miny, maxx, maxy = b.bounds
            gx, gy = np.meshgrid(np.arange(minx, maxx, spacing), np.arange(miny, maxy, spacing))
            cand = np.column_stack([gx.ravel(), gy.ravel()])
            if len(cand):
                extra.append(cand[shapely.contains_xy(b, cand[:, 0], cand[:, 1])])
            c, u = np.asarray(model["centre"]), np.asarray(model["u"])
            v_axis = np.array([-u[1], u[0]])
            t = np.arange(-model["U"] - model["V"], model["U"] + model["V"], spacing / 2.0)
            ridge = c + np.outer(t, u) if model["type"] in ("gable_major", "hip") else c + np.outer(t, v_axis)
            extra.append(ridge[shapely.contains_xy(b, ridge[:, 0], ridge[:, 1])])
    verts = np.vstack(ring_pts + extra)
    segs, start = [], 0
    for rp in ring_pts:
        n = len(rp)
        segs.extend([[start + k, start + (k + 1) % n] for k in range(n)])
        start += n
    holes = [shapely.Polygon(r).representative_point().coords[0] for r in poly.interiors]
    tri_in = {"vertices": verts, "segments": np.array(segs)}
    if holes:
        tri_in["holes"] = np.array(holes)
    try:
        t = triangle.triangulate(tri_in, "pQ")
    except Exception:
        return {}
    tv, ti = t["vertices"], t["triangles"]
    if model is not None:
        z = eval_roof_model(model, tv)
        upper = cap if height_is_authoritative else np.inf
        z = np.clip(z, base_y + MIN_WALL_M, max(upper, base_y + MIN_WALL_M))
        roof_source = f"lidar_model_{model['type']}"
    else:
        z = np.full(len(tv), flat_cap)
    n_ring = sum(len(rp) for rp in ring_pts)
    tops, k = [], 0
    for rp in ring_pts:
        tops.append(np.round(z[k:k + len(rp)], 2).tolist())
        k += len(rp)
    oe, on = frame.origin()
    lx, lz = tv[:, 0] - oe, on - tv[:, 1]
    roof_v = np.round(np.column_stack([lx, z, lz]), 2).ravel().tolist()
    rings_local = [np.round(np.column_stack([rp[:, 0] - oe, on - rp[:, 1]]), 2).ravel().tolist() for rp in ring_pts]
    out = {"rings": rings_local, "ring_top_y": tops, "base_y": round(base_y, 2), "roof_v": roof_v,
           "roof_i": ti.astype(int).ravel().tolist(), "roof_source": roof_source, "ring_vertex_count": n_ring}
    if model is not None:
        out["roof_model"] = {k2: model[k2] for k2 in ("type", "rmse", "truncated_l1", "inlier_share", "slope_deg")}
    # Collision proxy: the source outline (not the densified render ring) capped at the median eave.
    col = np.asarray(poly.exterior.simplify(0.1).coords)[:-1, :2]
    out["collision"] = {"ring": np.round(np.column_stack([col[:, 0] - oe, on - col[:, 1]]), 2).ravel().tolist(),
                        "top_y": round(float(np.median(z[:len(ring_pts[0])])), 2)}
    return out


def deck_height(s: Surfaces, geom, fallback: float) -> tuple[float, str]:
    """Median lidar top surface over a pier / deck footprint (measured)."""
    area = geom if geom.geom_type in ("Polygon", "MultiPolygon") else geom.buffer(0.6)
    win = s.dsm_window(area, pad=1.0)
    if win is None:
        return fallback, "inferred_ground_plus_1m"
    grid, valid, transform = win
    from rasterio.features import rasterize
    mask = rasterize([(area, 1)], out_shape=grid.shape, transform=transform, fill=0, dtype="uint8").astype(bool) & valid
    if mask.sum() < 3:
        return fallback, "inferred_ground_plus_1m"
    return round(float(np.median(grid[mask])), 2), "lidar_dsm_2019_median"


DECK_SAMPLE_M = 1.0
DECK_DISC_M = 0.75
DECK_RAMP_MAX = 0.125  # 1:8, the steepest deck run-out from an abutment at grade


def deck_profile(s: Surfaces, line, abutments: bool) -> tuple[np.ndarray, list[float], str]:
    """Deck top along a line: lowest 2019 DSM cell within 0.75 m of the axis every 1 m (canopy
    sits above a deck), never below ground; bridges also rise from both abutments at most 1:8."""
    xy = np.asarray(shapely.segmentize(line, DECK_SAMPLE_M).coords)[:, :2]
    ground = s.ground_at(xy)
    top = ground + 0.05
    src = "dem_ground"
    win = s.dsm_window(line.buffer(2.0), pad=1.0)
    if win is not None:
        grid, valid, transform = win
        reach = int(np.ceil(DECK_DISC_M / abs(transform.a)))
        lows = []
        for x, y in xy:
            col = int((x - transform.c) / transform.a)
            row = int((y - transform.f) / transform.e)
            r0, c0 = max(0, row - reach), max(0, col - reach)
            cells = grid[r0:row + reach + 1, c0:col + reach + 1][valid[r0:row + reach + 1, c0:col + reach + 1]]
            lows.append(float(cells.min()) if len(cells) else np.nan)
        lows = np.asarray(lows)
        top = np.where(np.isfinite(lows), np.maximum(lows, ground + 0.05), ground + 0.05)
        src = "lidar_dsm_2019_min_0.75m"
    if abutments and len(xy) > 1:
        d = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(xy, axis=0).T))])
        cap = np.minimum(ground[0] + DECK_RAMP_MAX * d, ground[-1] + DECK_RAMP_MAX * (d[-1] - d))
        top = np.maximum(np.minimum(top, cap), ground + 0.05)
        src += "_abutments_1:8"
    if len(top) >= 5:
        top = np.maximum(ndimage.median_filter(top, size=5, mode="nearest"), ground + 0.05)
    return xy, [round(float(v), 2) for v in top], src


def pole_top(s: Surfaces, x: float, y: float, ground: float) -> tuple[float, str]:
    win = s.dsm.window(x - 1.0, y - 1.0, x + 1.0, y + 1.0)
    if win is None:
        return 9.0, "inferred_9m"
    dsm = win[0]
    if not np.isfinite(dsm).any():
        return 9.0, "inferred_9m"
    h = float(np.nanmax(dsm)) - ground
    if 4.0 <= h <= 30.0:
        return round(h, 2), "lidar_dsm_2019_max_1m"
    return 9.0, "inferred_9m"


def terrain_tile(s: Surfaces, cx: int, cz: int, size: float, step: float) -> tuple[np.ndarray, float]:
    """(n x n) NAVD88 heights on the chunk grid (row = +z south, col = +x east) and the DEM-void share."""
    n = int(round(size / step)) + 1
    oe, on = frame.origin()
    xs = cx * size + np.arange(n) * step
    zs = cz * size + np.arange(n) * step
    gx, gz = np.meshgrid(xs, zs)
    xy = np.column_stack([gx.ravel() + oe, on - gz.ravel()])
    t = s.dem.transform
    cols = np.clip(((xy[:, 0] - t.c) / t.a).astype(int), 0, s.void.shape[1] - 1)
    rows = np.clip(((xy[:, 1] - t.f) / t.e).astype(int), 0, s.void.shape[0] - 1)
    return s.ground_at(xy).reshape(n, n).astype(np.float32), float(s.void[rows, cols].mean())

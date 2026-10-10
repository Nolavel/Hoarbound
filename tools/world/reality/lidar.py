"""Measured attributes from the NOAA lidar grids (raw_cache/<source>/grids/*.npz) and the DEM crop.

The point clouds classify only ground (2) and noise (7); buildings and vegetation are
both class 1. Heights are therefore 'top of non-ground returns inside a footprint minus
same-epoch ground around it', and trees are canopy-height local maxima outside footprints.
"""
from __future__ import annotations

from collections import OrderedDict
from pathlib import Path

import numpy as np
import rasterio
import shapely
import shapely.geometry
from rasterio.features import rasterize
from rasterio.transform import Affine
from scipy import ndimage

from . import paths

TILE_M = 500.0


class DemCrop:
    """The 1 m DEM 6366 crop of the library extent (NAVD88 metres)."""

    def __init__(self) -> None:
        self.path = paths.RAW / "noaa_dem_6366" / "dem_6366_extent_1m.tif"
        with rasterio.open(self.path) as src:
            self.data = src.read(1)
            self.transform = src.transform
            self.nodata = src.nodata
            self.crs = src.crs
        self.data = np.where(self.data == self.nodata, np.nan, self.data).astype(np.float32)

    def window(self, minx: float, maxy: float, ncol: int, nrow: int, cell: float) -> np.ndarray:
        """DEM resampled (nearest) onto a grid with origin (minx, maxy) and the given cell size."""
        inv = ~self.transform
        xs = minx + (np.arange(ncol) + 0.5) * cell
        ys = maxy - (np.arange(nrow) + 0.5) * cell
        cols = np.floor((xs - self.transform.c) / self.transform.a).astype(int)
        rows = np.floor((ys - self.transform.f) / self.transform.e).astype(int)
        del inv
        out = np.full((nrow, ncol), np.nan, dtype=np.float32)
        cv = (cols >= 0) & (cols < self.data.shape[1])
        rv = (rows >= 0) & (rows < self.data.shape[0])
        out[np.ix_(rv, cv)] = self.data[np.ix_(rows[rv], cols[cv])]
        return out


class LidarGrids:
    def __init__(self, source_id: str, cache: int = 24) -> None:
        self.source_id = source_id
        self.dir = paths.RAW / source_id / "grids"
        self.tiles: dict[tuple[int, int], Path] = {}
        self.cell = None
        self.dates: dict[tuple[int, int], str] = {}
        for p in sorted(self.dir.glob("*.npz")):
            with np.load(p) as z:
                ox, oy = z["origin"]
                self.cell = float(z["cell"])
            key = (int(round(ox / TILE_M)), int(round(oy / TILE_M)))
            self.tiles[key] = p
            self.dates[key] = p.name[:8]
        self._lru: OrderedDict = OrderedDict()
        self._cache = cache

    def _tile(self, key):
        if key in self._lru:
            self._lru.move_to_end(key)
            return self._lru[key]
        p = self.tiles.get(key)
        data = None
        if p is not None:
            with np.load(p) as z:
                data = (z["dsm"], z["ground"], z["nonground_count"])
        self._lru[key] = data
        if len(self._lru) > self._cache:
            self._lru.popitem(last=False)
        return data

    def date_at(self, x: float, y: float) -> str | None:
        key = (int(np.floor(x / TILE_M)), int(np.ceil(y / TILE_M)))
        d = self.dates.get(key)
        return f"{d[:4]}-{d[4:6]}-{d[6:8]}" if d else None

    def window(self, minx: float, miny: float, maxx: float, maxy: float):
        c = self.cell
        minx = np.floor(minx / c) * c
        maxy = np.ceil(maxy / c) * c
        ncol = int(np.ceil((maxx - minx) / c))
        nrow = int(np.ceil((maxy - miny) / c))
        dsm = np.full((nrow, ncol), np.nan, np.float32)
        ground = np.full((nrow, ncol), np.nan, np.float32)
        tx0, tx1 = int(np.floor(minx / TILE_M)), int(np.floor((minx + ncol * c - 1e-6) / TILE_M))
        ty0, ty1 = int(np.ceil((maxy - nrow * c + 1e-6) / TILE_M)), int(np.ceil(maxy / TILE_M))
        covered = False
        for tx in range(tx0, tx1 + 1):
            for ty in range(ty0, ty1 + 1):
                t = self._tile((tx, ty))
                if t is None:
                    continue
                covered = True
                tdsm, tground, _ = t
                ox, oy = tx * TILE_M, ty * TILE_M
                c0 = int(round((ox - minx) / c))
                r0 = int(round((maxy - oy) / c))
                tr0, tc0 = max(0, -r0), max(0, -c0)
                wr0, wc0 = max(0, r0), max(0, c0)
                h = min(tdsm.shape[0] - tr0, nrow - wr0)
                w = min(tdsm.shape[1] - tc0, ncol - wc0)
                if h > 0 and w > 0:
                    dsm[wr0:wr0 + h, wc0:wc0 + w] = tdsm[tr0:tr0 + h, tc0:tc0 + w]
                    ground[wr0:wr0 + h, wc0:wc0 + w] = tground[tr0:tr0 + h, tc0:tc0 + w]
        transform = Affine(c, 0, minx, 0, -c, maxy)
        return (dsm, ground, transform, minx, maxy, ncol, nrow) if covered else None


def _mask(geom, shape, transform) -> np.ndarray:
    return rasterize([(geom, 1)], out_shape=shape, transform=transform, fill=0, dtype="uint8").astype(bool)


def footprint_stats(grids: LidarGrids, dem: DemCrop, geom, q: dict) -> dict | None:
    b = geom.bounds
    win = grids.window(b[0] - 8, b[1] - 8, b[2] + 8, b[3] + 8)
    if win is None:
        return None
    dsm, ground, transform, minx, maxy, ncol, nrow = win
    inside = _mask(geom, dsm.shape, transform)
    if inside.sum() == 0:
        inside = _mask(geom.buffer(grids.cell * 0.5), dsm.shape, transform)
    ring = _mask(geom.buffer(6.0), dsm.shape, transform) & ~_mask(geom.buffer(1.5), dsm.shape, transform)
    vals = dsm[inside]
    finite = vals[np.isfinite(vals)]
    n_in = int(inside.sum())
    if n_in == 0:
        return None
    coverage = len(finite) / n_in
    g_ring = ground[ring]
    g_ring = g_ring[np.isfinite(g_ring)]
    ground_method = "lidar_ground_ring_median"
    if len(g_ring) >= 3:
        g0 = float(np.median(g_ring))
    else:
        dw = dem.window(minx, maxy, ncol, nrow, grids.cell)[ring]
        dw = dw[np.isfinite(dw)]
        if len(dw) == 0:
            return None
        g0 = float(np.median(dw))
        ground_method = "dem6366_ring_median"
    out = {"cells": n_in, "coverage": round(coverage, 3), "ground_m": round(g0, 2), "ground_method": ground_method}
    if len(finite) < q["min_cells"] or coverage < q["min_coverage"]:
        out["usable"] = False
        return out
    p10, p50, p90, p95 = np.percentile(finite, [10, 50, 90, 95])
    out.update({
        "usable": True,
        "height_p95_m": round(float(p95 - g0), 2),
        "height_p50_m": round(float(p50 - g0), 2),
        "roof_relief_m": round(float(p90 - p10), 2),
        "lidar_support": round(float(np.mean(np.where(np.isfinite(vals), vals - g0, 0.0) > 2.0)), 3),
    })
    return out


def detect_trees(grids: LidarGrids, dem: DemCrop, building_union, params: dict, land_mask) -> tuple[list[dict], list]:
    """Individual crowns as canopy-height local maxima; dense continuous canopy returned as polygons instead.

    CHM = 2019 DSM - 2016 bare-earth DEM, Gaussian-smoothed (sigma 1 m). Peaks need a
    height-dependent window (radius 1.5 + 0.25 h m), rough canopy (DSM std >= 0.3 m in
    2.5 m: excludes flat roofs, boats, trucks) and land (DEM >= -0.3 m).
    """
    trees: list[dict] = []
    dense: list = []
    c = grids.cell
    for key in sorted(grids.tiles):
        tx, ty = key
        minx, maxy = tx * TILE_M, ty * TILE_M
        tile_box = shapely.box(minx, maxy - TILE_M, minx + TILE_M, maxy)
        if not land_mask.intersects(tile_box):
            continue
        t = grids._tile(key)
        if t is None:
            continue
        dsm = t[0]
        nrow, ncol = dsm.shape
        transform = Affine(c, 0, minx, 0, -c, maxy)
        ground = dem.window(minx, maxy, ncol, nrow, c)
        chm = dsm - ground
        blocked = np.zeros(dsm.shape, bool)
        local_b = building_union.intersection(tile_box.buffer(5))
        if not local_b.is_empty:
            blocked = _mask(local_b.buffer(params["exclude_building_buffer_m"]), dsm.shape, transform)
        land_local = land_mask.intersection(tile_box)
        on_land = _mask(land_local.buffer(5.0), dsm.shape, transform) if not land_local.is_empty else np.zeros(dsm.shape, bool)
        canopy = np.isfinite(chm) & (chm >= 2.0) & ~blocked & on_land & (np.nan_to_num(ground, nan=-9.0) >= params["min_ground_m"])
        open_cells = max(3, int(round(params["opening_m"] / c)) | 1)
        canopy = ndimage.binary_opening(canopy, structure=np.ones((open_cells, open_cells), bool))
        if not canopy.any():
            continue
        filled = np.where(np.isfinite(dsm), dsm, 0.0).astype(np.float32)
        mean = ndimage.uniform_filter(filled, size=5)
        rough = np.sqrt(np.maximum(ndimage.uniform_filter(filled * filled, size=5) - mean * mean, 0.0))
        smooth = ndimage.gaussian_filter(np.where(canopy, chm, 0.0).astype(np.float32), sigma=1.0 / c)
        labels, _ = ndimage.label(canopy)
        sizes = np.bincount(labels.ravel()) * c * c
        big = sizes > params["dense_canopy_area_m2"]
        big[0] = False
        dense_mask = big[labels]
        if dense_mask.any():
            for geom, _ in rasterio_shapes(dense_mask.astype(np.uint8), dense_mask, transform):
                dense.append(geom)
        peak = np.zeros(dsm.shape, bool)
        for h0, h1 in ((params["min_height_m"], 6.0), (6.0, 10.0), (10.0, 15.0), (15.0, params["max_height_m"])):
            radius = 1.5 + 0.25 * (h0 + h1) / 2.0
            size = int(round(2 * radius / c)) | 1
            band = (smooth >= h0) & (smooth < h1)
            peak |= band & (smooth == ndimage.maximum_filter(smooth, size=size))
        peak &= canopy & ~dense_mask & (rough >= params["min_roughness_m"])
        rr, cc = np.nonzero(peak)
        for r, col in zip(rr, cc):
            h = float(chm[r, col])
            if not (params["min_height_m"] <= h <= params["max_height_m"]):
                continue
            win = int(round((1.5 + 0.25 * h) / c))
            r0, r1 = max(0, r - win), min(nrow, r + win + 1)
            c0, c1 = max(0, col - win), min(ncol, col + win + 1)
            crown = (chm[r0:r1, c0:c1] >= 0.5 * h) & canopy[r0:r1, c0:c1]
            area = float(crown.sum()) * c * c
            if area < params["min_crown_area_m2"]:
                continue
            x = minx + (col + 0.5) * c
            y = maxy - (r + 0.5) * c
            if not (minx <= x < minx + TILE_M and maxy - TILE_M < y <= maxy):
                continue  # tile files overlap their neighbours; each peak belongs to one nominal tile
            conf = 0.45 + (0.15 if area >= 12.0 else 0.0) + (0.1 if 4.0 <= h <= 20.0 else 0.0) + (0.05 if rough[r, col] >= 0.6 else 0.0)
            trees.append({"x": x, "y": y, "height_m": round(h, 2), "crown_radius_m": round(float(np.sqrt(area / np.pi)), 2),
                          "ground_m": round(float(ground[r, col]), 2), "confidence": round(min(conf, 0.75), 2),
                          "roughness_m": round(float(rough[r, col]), 2), "date": grids.date_at(x, y)})
    merged = shapely.union_all(dense) if dense else shapely.Polygon()
    parts = [g for g in getattr(merged, "geoms", [merged]) if not g.is_empty and g.area >= params["dense_canopy_area_m2"]]
    return trees, parts


def rasterio_shapes(mask, valid, transform):
    from rasterio.features import shapes
    for geom, val in shapes(mask, mask=valid, transform=transform):
        yield shapely.geometry.shape(geom), val


def alignment_offset(grids: LidarGrids, dem: DemCrop, footprints: list, area_box, max_shift_m: float = 3.0) -> dict:
    """Systematic offset between vector footprints and the lidar elevated-surface mask (cross-correlation)."""
    minx, miny, maxx, maxy = area_box.bounds
    win = grids.window(minx, miny, maxx, maxy)
    if win is None:
        return {"status": "no_lidar"}
    dsm, _, transform, wx, wy, ncol, nrow = win
    ground = dem.window(wx, wy, ncol, nrow, grids.cell)
    elevated = np.isfinite(dsm) & ((dsm - ground) > 2.5)
    fp = rasterize([(g, 1) for g in footprints if g.intersects(area_box)], out_shape=dsm.shape, transform=transform, fill=0, dtype="uint8").astype(bool)
    k = int(round(max_shift_m / grids.cell))
    best = None
    scores = {}
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            shifted = np.roll(np.roll(fp, dy, axis=0), dx, axis=1)
            inter = np.logical_and(shifted, elevated).sum()
            union = np.logical_or(shifted, elevated & ndimage.binary_dilation(fp, iterations=k)).sum()
            iou = inter / max(union, 1)
            scores[(dx, dy)] = iou
            if best is None or iou > best[0]:
                best = (iou, dx, dy)
    iou0 = scores[(0, 0)]
    _, dx, dy = best
    return {"status": "ok", "footprints": len([g for g in footprints if g.intersects(area_box)]),
            "best_shift_east_m": round(dx * grids.cell, 2), "best_shift_north_m": round(-dy * grids.cell, 2),
            "iou_at_zero": round(float(iou0), 4), "iou_at_best": round(float(best[0]), 4),
            "cell_m": grids.cell, "window_projected": [round(v, 1) for v in area_box.bounds]}

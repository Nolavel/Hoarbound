"""The authoritative WGS84 -> UTM 17N -> Hoarbound local transform (config/frame.json)."""
from __future__ import annotations

import json
import math
from functools import lru_cache

import numpy as np
import shapely
from pyproj import Transformer

from . import paths


@lru_cache(maxsize=1)
def frame() -> dict:
    return json.loads((paths.CONFIG / "frame.json").read_text(encoding="utf-8"))


def origin() -> tuple[float, float]:
    o = frame()["local_origin_projected"]
    return float(o["easting"]), float(o["northing"])


def chunk_size() -> float:
    return float(frame()["chunking"]["chunk_size_m"])


@lru_cache(maxsize=8)
def _transformer(src: str, dst: str) -> Transformer:
    return Transformer.from_crs(src, dst, always_xy=True)


def to_projected(geom, src_crs: str = "EPSG:4326"):
    """Projects a shapely geometry from src_crs to the frame's projected CRS."""
    dst = frame()["projected_crs"]
    if src_crs == dst:
        return geom
    tr = _transformer(src_crs, dst)

    def fn(coords: np.ndarray) -> np.ndarray:
        x, y = tr.transform(coords[:, 0], coords[:, 1])
        return np.column_stack([x, y])

    return shapely.transform(geom, fn)


def to_lonlat(geom, src_crs: str | None = None):
    src = src_crs or frame()["projected_crs"]
    tr = _transformer(src, "EPSG:4326")

    def fn(coords: np.ndarray) -> np.ndarray:
        x, y = tr.transform(coords[:, 0], coords[:, 1])
        return np.column_stack([x, y])

    return shapely.transform(geom, fn)


def projected_to_local(e: float, n: float) -> tuple[float, float]:
    oe, on = origin()
    return e - oe, on - n


def local_to_projected(x: float, z: float) -> tuple[float, float]:
    oe, on = origin()
    return x + oe, on - z


def to_local(geom):
    """Projected (UTM) geometry -> local X/Z metres (z grows south)."""
    oe, on = origin()
    return shapely.transform(geom, lambda c: np.column_stack([c[:, 0] - oe, on - c[:, 1]]))


def chunk_of_local(x: float, z: float) -> str:
    size = chunk_size()
    return f"{math.floor(x / size)}:{math.floor(z / size)}"


def representative_point(geom):
    """Deterministic anchor used for chunk assignment."""
    if geom.geom_type in ("LineString", "MultiLineString"):
        return geom.interpolate(0.5, normalized=True)
    if geom.geom_type == "Point":
        return geom
    return geom.point_on_surface()


def chunk_of_projected_geom(geom) -> str:
    p = representative_point(geom)
    x, z = projected_to_local(p.x, p.y)
    return chunk_of_local(x, z)

"""Scope decisions against the derived extent: keep, keep as context outline, or exclude."""
from __future__ import annotations

import numpy as np
import pyogrio
import shapely
from shapely.strtree import STRtree

from . import frame, paths

OUTLINE_FAMILIES = {"land", "coastline", "water", "terrain_coverage"}


class Zones:
    def __init__(self) -> None:
        path = paths.RAW / "extent" / "extent_zones.gpkg"
        meta, _, geom, fields = pyogrio.raw.read(path, layer="zones")
        self.zone = {str(n): g for n, g in zip(fields[0], shapely.from_wkb(geom))}
        meta, _, geom, fields = pyogrio.raw.read(path, layer="land_in_scope")
        self.scope_land = list(shapely.from_wkb(geom))
        self.scope_names = [str(n) for n in fields[1]]
        self.rect = self.zone["library_extent"]
        self.boca = self.zone.get("boca_chica_silhouette", shapely.Polygon())
        self.context_land = self.zone.get("context_land", shapely.Polygon())
        self.crossing = self.zone.get("crossing", shapely.Polygon()).buffer(25.0)
        self.boca_side = shapely.union_all([self.boca, self.context_land]).buffer(1.0)
        self.scope_union = shapely.union_all(self.scope_land)
        self.tree = STRtree(self.scope_land)
        shapely.prepare(self.rect)
        shapely.prepare(self.boca_side)
        shapely.prepare(self.crossing)
        shapely.prepare(self.scope_union)

    def classify(self, geom, family: str) -> tuple[str | None, str | None]:
        """Returns (zone, exclusion_reason). Exactly one of them is None."""
        if geom is None or geom.is_empty:
            return None, "empty_geometry"
        if not self.rect.intersects(geom):
            return None, "outside_extent"
        inside = geom if self.rect.contains(geom) else geom.intersection(self.rect)
        rep = frame.representative_point(inside if not inside.is_empty else geom)
        if self.crossing.intersects(geom) and family not in OUTLINE_FAMILIES:
            return "crossing", None
        on_scope = self.scope_union.contains(rep)
        if on_scope:
            idx = self.tree.query(rep, predicate="intersects")
            names = self.scope_names[int(idx[0])] if len(idx) else ""
            core = any(n in names for n in ("Key West", "Stock Island", "Fleming Key", "Sunset Key", "Thompson Island"))
            return ("core" if core else "adjacent"), None
        boca_side = self.boca_side.contains(rep) or (
            self.boca_side.distance(rep) < 150.0 and self.boca_side.distance(rep) < self.scope_union.distance(rep))
        if boca_side:
            if family in OUTLINE_FAMILIES:
                return "boca_chica_silhouette", None
            return None, "boca_chica_out_of_scope"
        return "water", None

    def scope_of(self, zone: str) -> str:
        return "context_silhouette" if zone == "boca_chica_silhouette" else "reality"


def lidar_land_mask():
    return shapely.union_all(Zones().scope_land)


def chunk(geom) -> str:
    return frame.chunk_of_projected_geom(geom)


def to_array(geoms) -> np.ndarray:
    return np.array(geoms, dtype=object)

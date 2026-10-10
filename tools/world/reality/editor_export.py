"""Library -> per-chunk editor interchange (derived/editor level) for the Godot editor generator.

One JSON per 512 m chunk under data/world/key_west/reality/derived/editor_chunks/ (git-ignored,
regenerable). Coordinates are Hoarbound local metres (x east, z south); every feature carries
the metadata contract the generated node must keep (docs/world/KEY_WEST_REALITY_LIBRARY.md §8).
"""
from __future__ import annotations

import json
import sqlite3
from collections import Counter, defaultdict

import numpy as np
import shapely

from . import PIPELINE_VERSION, frame, library, overrides, paths, receipts, regen

FAMILIES = ("buildings", "building_parts", "roads", "bridges", "coastal_structures", "barriers", "power", "utilities",
            "street_furniture", "transit", "airport", "trees", "vegetation_areas", "water", "land_use")
GROUP = {"buildings": "Buildings", "building_parts": "Buildings", "roads": "Roads", "bridges": "Coastal", "coastal_structures": "Coastal",
         "barriers": "Barriers", "power": "Infrastructure", "utilities": "Infrastructure", "street_furniture": "Infrastructure",
         "transit": "Infrastructure", "airport": "Roads", "trees": "Vegetation", "vegetation_areas": "Vegetation", "water": "Coastal",
         "land_use": "LandUse"}
KEEP_ATTRS = {"height_m", "roof_median_height_m", "roof_relief_m", "roof_form", "roof_shape", "roof_direction_deg", "levels",
              "ground_elevation_m", "min_height_m", "width_m", "flags", "osm:lanes", "osm:oneway", "surface_rules", "crown_radius_m",
              "building_use", "occupancy_class", "address", "name", "osm:height", "osm:material", "floating"}
OUT = paths.REALITY / "derived" / "editor_chunks"


def _local(geom):
    g = frame.to_local(geom)
    return shapely.set_precision(g, 0.01)


def _coords(g) -> dict:
    t = g.geom_type
    if t == "Point":
        return {"type": "point", "p": [round(g.x, 2), round(g.y, 2)]}
    if t == "LineString":
        return {"type": "line", "p": np.round(np.asarray(g.coords)[:, :2], 2).ravel().tolist()}
    if t == "Polygon":
        return {"type": "polygon", "rings": [np.round(np.asarray(r.coords)[:, :2], 2).ravel().tolist() for r in [g.exterior, *g.interiors]]}
    return {"type": "multi", "parts": [_coords(p) for p in g.geoms]}


class _Ground:
    """NAVD88 ground under local coordinates from the DEM 6366 crop (nearest 1 m pixel)."""

    def __init__(self) -> None:
        from .lidar import DemCrop
        self.dem = DemCrop()
        self.oe, self.on = frame.origin()

    def at(self, xz: np.ndarray) -> list[float]:
        t = self.dem.transform
        cols = np.clip(((xz[:, 0] + self.oe - t.c) / t.a).astype(int), 0, self.dem.data.shape[1] - 1)
        rows = np.clip(((self.on - xz[:, 1] - t.f) / t.e).astype(int), 0, self.dem.data.shape[0] - 1)
        return np.round(np.nan_to_num(self.dem.data[rows, cols], nan=0.0), 2).tolist()


def _ground_for(g, ground: _Ground):
    if g.geom_type == "Point":
        return ground.at(np.array([[g.x, g.y]]))
    if g.geom_type == "LineString":
        return ground.at(np.asarray(g.coords)[:, :2])
    if g.geom_type == "Polygon":
        return ground.at(np.asarray(g.exterior.coords)[:, :2])
    return None


def run(chunks: list[str] | None = None) -> dict:
    ground = _Ground()
    con = sqlite3.connect(paths.LIBRARY)
    epoch = dict(con.execute("SELECT feature_id, observed_at FROM feature_index").fetchall())
    hashes = dict(con.execute("SELECT feature_id, geometry_hash FROM feature_index").fetchall())
    con.close()
    ov = overrides.load()
    override_state = defaultdict(list)
    for o in ov["features"]:
        if o.get("target_feature_id"):
            override_state[o["target_feature_id"]].append({"override_id": o["override_id"], "type": o["override_type"],
                                                           "status": o.get("status"), "params": json.loads(o["params_json"]),
                                                           "geometry": _coords(_local(o["geometry"])) if not o["geometry"].is_empty else None})
    plan = regen.plan(hashes, ov["assets"], PIPELINE_VERSION)
    bad = regen.violations(plan)
    if bad:
        raise SystemExit("refusing to export: " + "; ".join(bad[:5]))
    per_chunk = defaultdict(list)
    for fam in FAMILIES:
        geoms, cols = library.read_layer(fam)
        for i, g in enumerate(geoms):
            cid = cols["chunk_id"][i]
            if chunks and cid not in chunks:
                continue
            fid = cols["feature_id"][i]
            attrs = {k: v for k, v in json.loads(cols["attrs_json"][i]).items() if k in KEEP_ATTRS}
            p = plan.get(fid, {"action": "generate"})
            lg = _local(g)
            per_chunk[cid].append({
                "feature_id": fid, "family": fam, "group": GROUP[fam], "class": cols["class"][i], "subclass": cols["subclass"][i],
                "name": cols["name"][i], "node_name": library.node_name(fid), "geometry": _coords(lg),
                "ground_y": _ground_for(lg, ground), "ground_y_source": "noaa_dem_6366 nearest 1 m (NAVD88)",
                "attrs": attrs, "meta": {
                    "feature_id": fid, "feature_class": cols["class"][i], "source_geometry_hash": cols["geometry_hash"][i],
                    "source_dataset": cols["geometry_source"][i], "source_record": cols["geometry_record"][i],
                    "source_epoch": cols["source_epoch"][i], "observed_at": epoch.get(fid), "reconstruction_class": cols["reconstruction_class"][i],
                    "confidence": float(cols["confidence"][i]), "scope": cols["scope"][i],
                    "override_state": "overridden" if fid in override_state else "reality",
                    "authoring_state": (p.get("asset") or {}).get("authoring_state", "generated"),
                    "asset_revision": (p.get("asset") or {}).get("asset_revision"),
                },
                "overrides": override_state.get(fid, []), "regen_action": p["action"],
            })
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = receipts.now_utc()
    for cid, feats in sorted(per_chunk.items()):
        cx, cz = (int(v) for v in cid.split(":"))
        size = frame.chunk_size()
        doc = {"schema": "kw_reality.editor_chunk.v1", "chunk_id": cid, "origin_local": [cx * size, cz * size], "size_m": size,
               "generator_version": PIPELINE_VERSION, "exported_at": stamp, "library": paths.rel(paths.LIBRARY),
               "frame": "x east, z south, y NAVD88 metres (config/frame.json)", "features": sorted(feats, key=lambda f: f["feature_id"])}
        (OUT / f"chunk_{cx}_{cz}.json").write_text(json.dumps(doc, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    summary = {"chunks": len(per_chunk), "features": sum(len(v) for v in per_chunk.values()),
               "actions": dict(Counter(p["action"] for p in plan.values()))}
    print(json.dumps(summary))
    return summary

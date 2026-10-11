"""Derives the authoritative library extent from data (rules in config/extent_rules.json).

Writes config/extent.json (committed) and raw_cache/extent/extent_zones.gpkg
(zones + in-scope land, consumed by acquisition and normalization).
"""
from __future__ import annotations

import json
import math

import numpy as np
import pyarrow.parquet as pq
import shapely
from shapely import wkb
from shapely.geometry import box

from . import config, frame, paths, receipts
from .acquire import OVERTURE_RELEASE


def _read(theme: str, typ: str) -> list[dict]:
    path = paths.RAW / "overture" / OVERTURE_RELEASE / f"{theme}__{typ}.parquet"
    return pq.read_table(path).to_pylist()


def _name(row: dict) -> str | None:
    return (row.get("names") or {}).get("primary")


def _polys(geom):
    return geom.geom_type in ("Polygon", "MultiPolygon")


def derive() -> dict:
    rules = config.extent_rules()
    fr = frame.frame()
    land_rows = _read("base", "land")
    # Coastline-derived land polygons carry the geometry; island/islet polygons carry names.
    land = [(r["id"], frame.to_projected(wkb.loads(r["geometry"]))) for r in land_rows
            if r["subtype"] == "land" and r["class"] == "land"]
    land = [(i, g) for i, g in land if _polys(g)]
    named = [(_name(r), frame.to_projected(wkb.loads(r["geometry"]))) for r in land_rows
             if r["class"] in ("island", "islet") and _name(r)]
    named = [(n, g) for n, g in named if _polys(g)]

    def names_of(g) -> list[str]:
        return sorted({n for n, ng in named if ng.intersects(g) and ng.intersection(g).area > 0.05 * g.area})

    land_names = [names_of(g) for _, g in land]
    division = [r for r in _read("divisions", "division_area")
                if _name(r) == rules["core"]["division_locality"] and r["subtype"] == "locality"]
    if not division:
        raise SystemExit("extent: Key West locality polygon not found in Overture divisions")
    city = frame.to_projected(wkb.loads(division[0]["geometry"]))
    ctx_names = set(rules["context_landmasses"]["names"])
    context = {i for i, n in enumerate(land_names) if ctx_names & set(n)}
    core = {i for i, (_, g) in enumerate(land) if g.intersects(city) or set(rules["core"]["named_islands"]) & set(land_names[i])}
    core -= context
    core_geom = shapely.union_all([land[i][1] for i in core])
    context_geom = shapely.union_all([land[i][1] for i in context])

    adj_rule = rules["adjacent_islands"]
    adjacent = []
    gaps = []
    for i, (_, g) in enumerate(land):
        if i in core or i in context:
            continue
        dc = core_geom.distance(g)
        dx = context_geom.distance(g)
        if dc <= adj_rule["max_gap_m"] and (not adj_rule["must_be_closer_to_core_than_to_context"] or dc < dx):
            adjacent.append(i)
            gaps.append(dc)
    rejected = sorted(core_geom.distance(land[i][1]) for i in range(len(land))
                      if i not in core and i not in context and i not in adjacent and core_geom.distance(land[i][1]) <= adj_rule["max_gap_m"])
    in_scope = sorted(core | set(adjacent))
    scope_geom = shapely.union_all([land[i][1] for i in in_scope])

    # Crossings: the named bridge kept whole, plus an approach on the far side.
    bridges = [r for r in _read("base", "infrastructure") if r["subtype"] == "bridge" and _name(r) in rules["crossings"]["bridge_names"]]
    bridge_geom = shapely.union_all([frame.to_projected(wkb.loads(r["geometry"])) for r in bridges]) if bridges else shapely.Point()
    far_landing = bridge_geom.intersection(context_geom.buffer(5.0)) if not bridge_geom.is_empty else shapely.Point()
    approach = far_landing.buffer(rules["crossings"]["far_side_approach_m"]) if not far_landing.is_empty else shapely.Point()

    margin = float(rules["water_margin_m"])
    hull = shapely.union_all([scope_geom.buffer(margin), bridge_geom.buffer(margin), approach])
    minx, miny, maxx, maxy = hull.bounds
    if rules.get("contain_legacy_runtime_crop"):
        lp = fr["legacy_runtime_crop"]["projected"]
        minx, miny = min(minx, lp["min_e"]), min(miny, lp["min_n"])
        maxx, maxy = max(maxx, lp["max_e"]), max(maxy, lp["max_n"])

    size = frame.chunk_size()
    oe, on = frame.origin()

    def snap(bounds):
        x0, z0 = math.floor((bounds[0] - oe) / size) * size, math.floor((on - bounds[3]) / size) * size
        x1, z1 = math.ceil((bounds[2] - oe) / size) * size, math.ceil((on - bounds[1]) / size) * size
        return (x0 + oe, on - z1, x1 + oe, on - z0)

    rect = snap((minx, miny, maxx, maxy)) if rules.get("snap_to_chunk_grid") else (minx, miny, maxx, maxy)
    grown = []
    if rules.get("never_cut_land"):
        for _ in range(20):
            r = box(*rect)
            cut = [i for i, (_, g) in enumerate(land) if i not in context and g.intersects(r) and not r.contains(g)]
            if not cut:
                break
            u = shapely.union_all([r] + [land[i][1] for i in cut])
            grown.extend(land[i][0] for i in cut)
            rect = snap(u.bounds)
    r = box(*rect)
    silhouette = context_geom.intersection(r)
    outside_scope_land = [land[i][1] for i in range(len(land)) if i not in in_scope and i not in context and r.intersects(land[i][1])]
    legacy = fr["legacy_runtime_crop"]["projected"]
    legacy_box = box(legacy["min_e"], legacy["min_n"], legacy["max_e"], legacy["max_n"])
    north_ne = r.difference(legacy_box)

    lonlat = frame.to_lonlat(r).bounds
    x0, z0 = frame.projected_to_local(rect[0], rect[3])
    x1, z1 = frame.projected_to_local(rect[2], rect[1])
    result = {
        "schema": "kw_reality.extent.v1",
        "generated_at": receipts.now_utc(),
        "generator": "tools/world/reality/extent.py",
        "inputs": {"overture_release": OVERTURE_RELEASE, "rules": "config/extent_rules.json"},
        "projected_crs": fr["projected_crs"],
        "projected_bounds": {"min_e": rect[0], "min_n": rect[1], "max_e": rect[2], "max_n": rect[3]},
        "lonlat_bounds": {"west": round(lonlat[0], 6), "south": round(lonlat[1], 6), "east": round(lonlat[2], 6), "north": round(lonlat[3], 6)},
        "local_bounds": {"min_x": x0, "max_x": x1, "min_z": z0, "max_z": z1},
        "size_m": {"x": rect[2] - rect[0], "z": rect[3] - rect[1]},
        "chunks": {"x": [int(x0 // size), int(x1 // size) - 1], "z": [int(z0 // size), int(z1 // size) - 1],
                   "count": int(((x1 - x0) // size) * ((z1 - z0) // size))},
        "core_islands": sorted({n for i in core for n in land_names[i]}),
        "adjacent_islands": {"count": len(adjacent), "named": sorted({n for i in adjacent for n in land_names[i]}),
                             "max_gap_m": round(max(gaps), 1) if gaps else 0.0,
                             "nearest_context_side_islet_gap_m": round(rejected[0], 1) if rejected else None},
        "context_landmasses": {"names": sorted(ctx_names), "role": rules["context_landmasses"]["role"],
                               "silhouette_area_km2": round(silhouette.area / 1e6, 3)},
        "crossings": {"bridges": [{"name": _name(b), "overture_id": b["id"], "osm": [s["record_id"] for s in b["sources"]]} for b in bridges],
                      "bridge_length_m": round(bridge_geom.length, 1) if bridge_geom.geom_type.endswith("LineString") else None,
                      "bridge_bounds_projected": [round(v, 1) for v in bridge_geom.bounds] if not bridge_geom.is_empty else None},
        "grown_to_avoid_cutting_land": grown,
        "in_scope_land_km2": round(scope_geom.area / 1e6, 3),
        "outside_scope_land_inside_rect": {"count": len(outside_scope_land), "area_km2": round(sum(g.area for g in outside_scope_land) / 1e6, 3),
                                           "note": "Boca-Chica-side or offshore islets that fall inside the rectangle; kept as context land (outline only)."},
        "growth_vs_legacy_crop": {"legacy_area_km2": round(legacy_box.area / 1e6, 2), "new_area_km2": round(r.area / 1e6, 2),
                                  "added_north_m": rect[3] - legacy["max_n"], "added_east_m": rect[2] - legacy["max_e"],
                                  "added_south_m": legacy["min_n"] - rect[1], "added_west_m": legacy["min_e"] - rect[0]},
    }
    (paths.CONFIG / "extent.json").write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    _write_zones(r, scope_geom, silhouette, outside_scope_land, bridge_geom, approach, legacy_box, north_ne, land, in_scope, context, land_names)
    print(json.dumps({k: result[k] for k in ("lonlat_bounds", "local_bounds", "size_m", "adjacent_islands", "growth_vs_legacy_crop")}, indent=1))
    return result


def _write_zones(rect, scope, silhouette, outside, bridge, approach, legacy_box, north_ne, land, in_scope, context, land_names) -> None:
    import pyogrio

    out = paths.RAW / "extent" / "extent_zones.gpkg"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    crs = frame.frame()["projected_crs"]
    zones = [("library_extent", rect), ("in_scope_land", scope), ("boca_chica_silhouette", silhouette),
             ("context_land", shapely.union_all(outside) if outside else shapely.Polygon()), ("crossing", bridge),
             ("far_side_approach", approach), ("legacy_runtime_crop", legacy_box), ("added_vs_legacy", north_ne)]
    zones = [(n, g) for n, g in zones if not g.is_empty]
    pyogrio.raw.write(out, shapely.to_wkb(np.array([g for _, g in zones], dtype=object)),
                      [np.array([n for n, _ in zones], dtype=object)], ["zone"], layer="zones",
                      driver="GPKG", crs=crs, geometry_type="Unknown")
    ids = [land[i][0] for i in in_scope]
    pyogrio.raw.write(out, shapely.to_wkb(np.array([land[i][1] for i in in_scope], dtype=object)),
                      [np.array(ids, dtype=object), np.array(["/".join(land_names[i]) for i in in_scope], dtype=object)],
                      ["overture_id", "names"], layer="land_in_scope", driver="GPKG", crs=crs, geometry_type="Unknown", append=True)

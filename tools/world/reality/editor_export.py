"""Library -> per-chunk editor interchange (derived/editor level) for the Godot editor generator.

data/world/key_west/reality/derived/editor_chunks/chunk_<cx>_<cz>.json + terrain_<cx>_<cz>.f32
(git-ignored, regenerable). Coordinates: local metres x east, z south, y NAVD88. Every feature
carries the node metadata contract (docs/world/KEY_WEST_REALITY_LIBRARY.md §10) and, where it
is drawn, mesh-ready geometry whose every height says where it came from.
"""
from __future__ import annotations

import json
import sqlite3
import time
from collections import Counter, defaultdict

import numpy as np
import shapely

from . import PIPELINE_VERSION, config, frame, library, meshing, overrides, paths, receipts, regen

EXPORT_VERSION = "kw_reality.editor_chunk.v2"
FAMILIES = ("buildings", "building_parts", "roads", "bridges", "coastal_structures", "barriers", "power", "utilities",
            "street_furniture", "transit", "airport", "trees", "vegetation_areas", "water", "land_use")
GROUP = {"buildings": "Buildings", "building_parts": "Buildings", "roads": "Roads", "bridges": "Coastal", "coastal_structures": "Coastal",
         "barriers": "Barriers", "power": "Infrastructure", "utilities": "Infrastructure", "street_furniture": "Infrastructure",
         "transit": "Infrastructure", "airport": "Roads", "trees": "Vegetation", "vegetation_areas": "Vegetation", "water": "Coastal",
         "land_use": "LandUse"}
KEEP_ATTRS = {"height_m", "roof_median_height_m", "roof_relief_m", "roof_form", "roof_shape", "levels", "ground_elevation_m", "width_m",
              "flags", "osm:lanes", "osm:oneway", "crown_radius_m", "building_use", "occupancy_class", "address", "name", "year_built",
              "construction", "osm:height", "osm:material", "osm:floating", "historic_status"}
AIRPORT_WIDTH = {"runway": 45.0, "taxiway": 18.0, "taxilane": 10.0, "stopway": 45.0}
AIRPORT_PAVED = ("apron", "runway", "taxiway", "taxilane", "stopway", "helipad")  # aerodrome boundaries are not pavement
SEVER_HALF_WIDTH_M = 30.0  # remove_span lines run along the deck; cut the full deck width
OUT = paths.REALITY / "derived" / "editor_chunks"


def _xz(coords) -> list[float]:
    """Projected coordinate array -> flat local [x0, z0, x1, z1, ...]."""
    oe, on = frame.origin()
    a = np.asarray(coords)[:, :2]
    return np.round(np.column_stack([a[:, 0] - oe, on - a[:, 1]]), 2).ravel().tolist()


def _parts(g):
    return list(g.geoms) if hasattr(g, "geoms") else [g]


def _selected(con, name: str) -> dict[str, tuple]:
    rows = con.execute("""SELECT fi.feature_id, a.value_json, p.reconstruction_class, p.method FROM attribute_store a
        JOIN feature_index fi ON fi.fid = a.fid JOIN attribute_name n ON n.name_id = a.name_id JOIN provenance p ON p.prov_id = a.prov_id
        WHERE n.name = ? AND a.selected = 1""", (name,)).fetchall()
    return {r[0]: (json.loads(r[1]), r[2], r[3]) for r in rows}


def corridors(ov_features: list[dict]) -> list[dict]:
    by_id = {o["override_id"]: o for o in ov_features}
    out = []
    for c in config.load("generation.json")["priority_corridors"]:
        a, b = by_id[c["from_override"]], by_id[c["to_override"]]
        pa = a["geometry"].representative_point() if a["geometry"].geom_type != "Point" else a["geometry"]
        pb = b["geometry"].representative_point() if b["geometry"].geom_type != "Point" else b["geometry"]
        ax, az = json.loads(a["params_json"]).get("anchor_local_xz") or frame.projected_to_local(pa.x, pa.y)
        bx, bz = json.loads(b["params_json"]).get("anchor_local_xz") or frame.projected_to_local(pb.x, pb.y)
        line = shapely.LineString([frame.local_to_projected(ax, az), frame.local_to_projected(bx, bz)])
        out.append({"name": c["name"], "area": line.buffer(c["buffer_m"]), "line": line, "anchors": [[ax, az], [bx, bz]]})
    return out


def corridor_chunks(corr: list[dict]) -> list[str]:
    size = frame.chunk_size()
    ids = set()
    for c in corr:
        minx, miny, maxx, maxy = c["area"].bounds
        x0, z0 = frame.projected_to_local(minx, maxy)
        x1, z1 = frame.projected_to_local(maxx, miny)
        for cx in range(int(np.floor(x0 / size)), int(np.floor(x1 / size)) + 1):
            for cz in range(int(np.floor(z0 / size)), int(np.floor(z1 / size)) + 1):
                ids.add(f"{cx}:{cz}")
    return sorted(ids)


def run(chunks: list[str] | None = None, route_only: bool = False) -> dict:
    t0 = time.time()
    gen = config.load("generation.json")
    library.ensure()
    con = sqlite3.connect(paths.LIBRARY)
    epoch = dict(con.execute("SELECT feature_id, observed_at FROM feature_index").fetchall())
    hashes = dict(con.execute("SELECT feature_id, geometry_hash FROM feature_index").fetchall())
    sel = {n: _selected(con, n) for n in ("height_m", "roof_median_height_m", "roof_relief_m", "ground_elevation_m")}
    con.close()
    ov = overrides.load()
    corr = corridors(ov["features"])
    route_chunks = set(corridor_chunks(corr))
    if route_only:
        chunks = sorted(route_chunks)
    override_state = defaultdict(list)
    removed = defaultdict(list)
    for o in ov["features"]:
        tgt = o.get("target_feature_id")
        if not tgt:
            continue
        params = json.loads(o["params_json"])
        override_state[tgt].append({"override_id": o["override_id"], "type": o["override_type"], "status": o.get("status"), "params": params})
        if o["override_type"] == "remove_span":
            removed[tgt].append(o["geometry"])
    severed = [o["geometry"] for o in ov["features"] if o["override_type"] == "remove_span"]
    severed_area = shapely.union_all([g.buffer(SEVER_HALF_WIDTH_M, cap_style="flat") for g in severed]) if severed else shapely.Polygon()
    customs = [o for o in ov["features"] if o["override_type"] == "custom_structure"]
    plan = regen.plan(hashes, ov["assets"], PIPELINE_VERSION)
    bad = regen.violations(plan)
    if bad:
        raise SystemExit("refusing to export: " + "; ".join(bad[:5]))
    s = meshing.Surfaces()
    heights = gen["inferred_heights_m"]
    per_chunk = defaultdict(list)
    wires = defaultdict(list)
    poles: dict[str, tuple] = {}
    stats = Counter()

    ext = config.extent()["chunks"]
    extent_chunks = {f"{x}:{z}" for x in range(ext["x"][0], ext["x"][1] + 1) for z in range(ext["z"][0], ext["z"][1] + 1)}

    def in_corridor(g) -> bool:
        return any(c["area"].intersects(g) for c in corr)

    for fam in FAMILIES:
        geoms, cols = library.read_layer(fam)
        for i, g in enumerate(geoms):
            cid = cols["chunk_id"][i]
            fid = cols["feature_id"][i]
            if chunks and cid not in chunks and fam != "power":
                continue
            attrs = {k: v for k, v in json.loads(cols["attrs_json"][i]).items() if k in KEEP_ATTRS}
            p = plan.get(fid, {"action": "generate"})
            hot = in_corridor(g)
            mesh, sources = _mesh_for(fam, cols["class"][i], cols["subclass"][i], g, fid, attrs, sel, s, gen, heights, hot,
                                      removed.get(fid, []), severed_area, stats)
            if fam == "power" and g.geom_type == "Point":
                poles[fid] = (g.x, g.y, mesh.get("base_y", 0.0), mesh.get("top_y", 9.0))
            if chunks and cid not in chunks:
                continue
            if cid not in extent_chunks:
                stats["outside_extent_chunk_not_exported"] += 1
                continue
            ovs = override_state.get(fid, [])
            role = next((o["params"].get("role") for o in ovs if o["type"] == "landmark_role"), None)
            per_chunk[cid].append({
                "feature_id": fid, "family": fam, "group": GROUP[fam], "class": cols["class"][i], "subclass": cols["subclass"][i],
                "name": cols["name"][i], "node_name": library.node_name(fid), "attrs": attrs, "mesh": mesh, "height_sources": sources,
                "fidelity": "corridor" if hot else "default",
                "meta": {
                    "feature_id": fid, "feature_class": cols["class"][i], "source_geometry_hash": cols["geometry_hash"][i],
                    "source_dataset": cols["geometry_source"][i], "source_record": cols["geometry_record"][i],
                    "source_epoch": cols["source_epoch"][i], "observed_at": epoch.get(fid), "reconstruction_class": cols["reconstruction_class"][i],
                    "confidence": float(cols["confidence"][i]), "scope": cols["scope"][i],
                    "override_state": "overridden" if ovs else "reality", "landmark_role": role,
                    "authoring_state": (p.get("asset") or {}).get("authoring_state", "generated"),
                    "asset_revision": (p.get("asset") or {}).get("asset_revision"),
                    "authored_scene": (p.get("asset") or {}).get("godot_scene"),
                    "asset_origin_local": (p.get("asset") or {}).get("origin_local"),
                },
                "overrides": ovs, "regen_action": p["action"],
            })
            stats[f"{fam}"] += 1
    # Wires only between two measured supports (real topology edges); open ends are not drawn.
    tg, tc = library.read_layer("utility_topology")
    oe, on = frame.origin()
    for geom, a, b, via, eid in zip(tg, tc["from_feature_id"], tc["to_feature_id"], tc["via_feature_id"], tc["edge_id"]):
        if not (a and b and a in poles and b in poles):
            stats["wire_open_end_skipped"] += 1
            continue
        pa, pb = poles[a], poles[b]
        mid = shapely.Point((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
        cid = frame.chunk_of_projected_geom(mid)
        if chunks and cid not in chunks:
            continue
        wires[cid].append({"edge_id": eid, "from": a, "to": b, "line": via,
                           "a": [round(pa[0] - oe, 2), round(pa[2] + pa[3] - 0.4, 2), round(on - pa[1], 2)],
                           "b": [round(pb[0] - oe, 2), round(pb[2] + pb[3] - 0.4, 2), round(on - pb[1], 2)]})
        stats["wires"] += 1
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = receipts.now_utc()
    size = frame.chunk_size()
    written = sorted(set(per_chunk) | set(chunks or []))
    if not chunks:
        written = sorted(extent_chunks)
        keep = {f"{kind}_{c.replace(':', '_')}.{ext_}" for c in written for kind, ext_ in (("chunk", "json"), ("terrain", "f32"))}
        for stale in [*OUT.glob("chunk_*.json"), *OUT.glob("terrain_*.f32")]:
            if stale.name not in keep:
                stale.unlink()
    for cid in written:
        cx, cz = (int(v) for v in cid.split(":"))
        hot = cid in route_chunks
        step = gen["terrain_step_m"]["corridor" if hot else "default"]
        tile, void = meshing.terrain_tile(s, cx, cz, size, step)
        stats["terrain_tiles_with_dem_void"] += int(void > 0)
        tname = f"terrain_{cx}_{cz}.f32"
        tile.astype("<f4").tofile(OUT / tname)
        custom = []
        for o in customs:
            pt = o["geometry"]
            if frame.chunk_of_projected_geom(pt) == cid:
                x, z = frame.projected_to_local(pt.x, pt.y)
                custom.append({"override_id": o["override_id"], "local_xz": [round(x, 2), round(z, 2)], "params": json.loads(o["params_json"])})
        doc = {"schema": EXPORT_VERSION, "chunk_id": cid, "origin_local": [cx * size, cz * size], "size_m": size,
               "fidelity": "corridor" if hot else "default", "generator_version": PIPELINE_VERSION, "exported_at": stamp,
               "library": paths.rel(paths.LIBRARY), "library_sha256": json.loads(library.MANIFEST.read_text())["gpkg"]["sha256"] if library.MANIFEST.exists() else None,
               "frame": "x east, z south, y NAVD88 metres (config/frame.json); MSL = -0.265",
               "terrain": {"file": tname, "n": int(tile.shape[0]), "step_m": step, "source": "noaa_dem_6366 1 m, nearest", "recon": "measured",
                           "dem_void_share": round(void, 4), "void_fill": "nearest_valid_depth_clamped_to_mllw (inferred)"},
               "corridors": [c["name"] for c in corr if shapely.box(*_chunk_box(cx, cz, size)).intersects(c["area"])],
               "anchors": [{"name": c["name"], "points": c["anchors"]} for c in corr],
               "custom_structures": custom, "wires": wires.get(cid, []),
               "features": sorted(per_chunk.get(cid, []), key=lambda f: f["feature_id"])}
        (OUT / f"chunk_{cx}_{cz}.json").write_text(json.dumps(doc, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    manifest = {"schema": "kw_reality.editor_export_manifest.v1", "exported_at": stamp, "export_version": EXPORT_VERSION,
                "route_chunks": sorted(route_chunks), "chunks": written, "stats": dict(stats), "seconds": round(time.time() - t0, 1)}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ("route_chunks", "stats", "seconds")}))
    return manifest


def _chunk_box(cx: int, cz: int, size: float):
    e0, n1 = frame.local_to_projected(cx * size, cz * size)
    e1, n0 = frame.local_to_projected((cx + 1) * size, (cz + 1) * size)
    return (e0, n0, e1, n1)


def _mesh_for(fam, cls, sub, g, fid, attrs, sel, s, gen, heights, hot, removed_parts, severed_area, stats) -> tuple[dict, dict]:
    """Mesh-ready geometry + where each height came from."""
    oe, on = frame.origin()
    spacing = gen["roof_sample_spacing_m"]["corridor" if hot else "default"]
    if fam == "buildings" and g.geom_type in ("Polygon", "MultiPolygon"):
        poly = max(_parts(g), key=lambda q: q.area)
        ground = sel["ground_elevation_m"].get(fid)
        base = float(ground[0]) if ground else float(np.median(s.ground_at(np.asarray(poly.exterior.coords)[:, :2])))
        h = sel["height_m"].get(fid)
        relief = sel["roof_relief_m"].get(fid)
        median = sel["roof_median_height_m"].get(fid)
        shell = meshing.building_shell(s, poly, base, float(h[0]) if h else None, bool(h and h[1] == "authoritative"),
                                       float(relief[0]) if relief else None, spacing, float(median[0]) if median else None)
        if not shell:
            stats["building_shell_failed"] += 1
            return {"kind": "marker", "p": _xz([poly.representative_point().coords[0]])}, {}
        stats[f"roof_{shell['roof_source']}"] += 1
        return {"kind": "building", **shell}, {"base": "lidar_ground_ring" if ground else "dem_6366", "top": h[2] if h else "placeholder_3m",
                                               "top_class": h[1] if h else "procedural", "roof": shell["roof_source"]}
    if fam in ("roads", "airport") and g.geom_type in ("LineString", "MultiLineString"):
        geom = g
        for r in removed_parts:
            geom = geom.difference(r.buffer(0.5))
        width = float(attrs.get("width_m") or AIRPORT_WIDTH.get(cls, 4.0))
        bridge = "bridge" in (attrs.get("flags") or [])
        parts = []
        for part in _parts(geom):
            if part.is_empty or part.length < 0.5:
                continue
            if bridge:
                xy, ys, src = meshing.deck_profile(s, part, abutments=True)
            else:
                xy = np.asarray(part.coords)[:, :2]
                ys, src = [round(float(v) + 0.05, 2) for v in s.ground_at(xy)], "dem_6366_plus_5cm"
            parts.append({"p": _xz(xy), "y": ys})
        if removed_parts:
            stats["road_spans_removed_by_override"] += 1
        return {"kind": "ribbon", "width": width, "parts": parts}, {"y": "lidar_deck" if bridge else "dem_6366",
                                                                     "width": "tag" if attrs.get("width_m") and fam == "roads" else "class_table"}
    if fam == "airport" and cls not in AIRPORT_PAVED and g.geom_type in ("Polygon", "MultiPolygon"):
        return {"kind": "marker", "p": _xz([g.representative_point().coords[0]])}, {}
    if fam in ("coastal_structures", "bridges", "airport", "transit") and g.geom_type in ("Polygon", "MultiPolygon"):
        geom = g.difference(severed_area) if fam == "bridges" and not severed_area.is_empty and g.intersects(severed_area) else g
        if fam == "bridges" and geom is not g:
            stats["bridge_outline_cut_by_override"] += 1
        polys = [q for q in _parts(geom) if q.geom_type == "Polygon" and q.area > 0.5]
        if not polys:
            return {"kind": "none"}, {}
        ground = float(np.median(s.ground_at(np.asarray(polys[0].exterior.coords)[:, :2])))
        if fam in ("airport", "transit"):
            top, src = ground + 0.03, "dem_6366"
        else:
            top, src = meshing.deck_height(s, geom, ground + 1.0)
        return {"kind": "slab", "top_y": top, "thickness": 0.4 if fam != "transit" else 0.03,
                "polys": [{"rings": [_xz(r.coords) for r in [q.exterior, *q.interiors]]} for q in polys]}, {"top": src}
    if fam in ("coastal_structures", "bridges") and g.geom_type in ("LineString", "MultiLineString"):
        geom = g.difference(severed_area) if fam == "bridges" and not severed_area.is_empty and g.intersects(severed_area) else g
        if geom is not g:
            stats["bridge_line_cut_by_override"] += 1
        parts = []
        for part in [q for q in _parts(geom) if q.geom_type == "LineString" and q.length >= 0.5]:
            xy, ys, src = meshing.deck_profile(s, part, abutments=fam == "bridges")
            parts.append({"p": _xz(xy), "y": ys})
        if not parts:
            return {"kind": "none"}, {}
        return {"kind": "ribbon", "width": gen["pier_width_m_when_line"], "parts": parts}, {"y": "lidar_deck", "width": "inferred"}
    if fam == "barriers" and g.geom_type in ("LineString", "MultiLineString", "Polygon"):
        line = g.exterior if g.geom_type == "Polygon" else g
        h = attrs.get("osm:height")
        try:
            hv, hsrc = float(str(h).split()[0]), "osm_height_tag"
        except (TypeError, ValueError):
            hv, hsrc = heights.get(cls, 1.5), "inferred_class_default"
        parts = [{"p": _xz(part.coords), "y": [round(float(v), 2) for v in s.ground_at(np.asarray(part.coords)[:, :2])]} for part in _parts(line)]
        return {"kind": "wall", "height": hv, "thickness": 0.6 if cls == "hedge" else 0.2, "parts": parts}, {"height": hsrc}
    if fam == "power" and g.geom_type == "Point":
        ground = float(s.ground_at(np.array([[g.x, g.y]]))[0])
        top, src = meshing.pole_top(s, g.x, g.y, ground)
        return {"kind": "pole", "p": _xz([(g.x, g.y)]), "base_y": round(ground, 2), "top_y": top}, {"top": src}
    if fam == "trees" and g.geom_type == "Point":
        ground = float(s.ground_at(np.array([[g.x, g.y]]))[0])
        return {"kind": "tree", "p": _xz([(g.x, g.y)]), "base_y": round(ground, 2),
                "height": float(attrs.get("height_m") or 6.0), "crown_radius": float(attrs.get("crown_radius_m") or 2.5)}, \
            {"height": "lidar_chm" if attrs.get("height_m") else "inferred_6m"}
    if fam == "vegetation_areas" and cls == "lidar_canopy_dense" and g.geom_type == "Polygon":
        ground = float(np.median(s.ground_at(np.asarray(g.exterior.coords)[:, :2])))
        top, src = meshing.deck_height(s, g, ground + 5.0)
        return {"kind": "canopy_mass", "top_y": top, "base_y": round(ground, 2),
                "polys": [{"rings": [_xz(r.coords) for r in [g.exterior, *g.interiors]]}]}, {"top": src}
    if fam == "water" and g.geom_type == "Polygon" and g.area < 5e5 and cls in ("swimming_pool", "pond", "water", "canal", "basin", "reservoir"):
        ground = float(np.median(s.ground_at(np.asarray(g.exterior.coords)[:, :2])))
        level, src = (ground - 0.3, "dem_rim_minus_0.3") if cls == "swimming_pool" else (-0.265, "msl_navd88_8724580")
        return {"kind": "water", "top_y": round(level, 2), "polys": [{"rings": [_xz(r.coords) for r in [g.exterior, *g.interiors]]}]}, {"level": src}
    if fam in ("street_furniture", "utilities") and g.geom_type == "Point":
        ground = float(s.ground_at(np.array([[g.x, g.y]]))[0])
        return {"kind": "prop", "p": _xz([(g.x, g.y)]), "base_y": round(ground, 2), "height": heights.get(cls, 1.0)}, \
            {"height": "inferred_class_default" if cls in heights else "inferred_1m"}
    rp = frame.representative_point(g)
    ground = float(s.ground_at(np.array([[rp.x, rp.y]]))[0])
    return {"kind": "marker", "p": _xz([(rp.x, rp.y)]), "base_y": round(ground, 2)}, {}

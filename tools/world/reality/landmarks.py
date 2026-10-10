"""First Exit landmarks measured from lidar and documentary facts, written as glTF (Godot + Blender).

  landmarks            measure, write assets/world/key_west/landmarks/*.glb + data/.../landmarks/*.json,
                       register them in authoring/asset_manifest.json (never over artist work)

Nothing here is invented: every element names the measurement or record it comes from, and
whatever the sources cannot tell (openings, floor plan, emplacement detail) is left out.
"""
from __future__ import annotations

import hashlib
import json
import struct

import numpy as np
import pyogrio
import shapely
import shapely.affinity
import triangle
from scipy import ndimage

from . import PIPELINE_VERSION, frame, lidar, meshing, paths, receipts
from .assets import MANIFEST, _current_hash

LANDMARK_VERSION = "kw_landmark.1"
ASSET_DIR = paths.ROOT / "assets/world/key_west/landmarks"
SPEC_DIR = paths.REALITY / "landmarks"
ROOF_BAND_M = (4.3, 5.2)  # 727: flat roof plane above ground, separates roof from canopy
NOTCH_ROOF_MIN_M = 1.0  # roof run-out beyond an edge that counts as a roofed notch, not an eave
MATERIALS = {"masonry_stucco": (0.86, 0.83, 0.76, 1.0), "roof_membrane": (0.55, 0.55, 0.53, 1.0),
             "fort_brick": (0.62, 0.45, 0.36, 1.0)}


def run() -> dict:
    s = meshing.Surfaces()
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    SPEC_DIR.mkdir(parents=True, exist_ok=True)
    out = {}
    for name, fn in (("kw_727_fort_st", _shelter_727), ("kw_fort_zachary_taylor", _fort_taylor)):
        spec, nodes = fn(s)
        if not _may_write(spec["feature_id"]):
            out[name] = "skipped: artist-owned asset in manifest"
            continue
        glb = ASSET_DIR / f"{name}.glb"
        _write_glb(glb, nodes)
        spec.update({"landmark_version": LANDMARK_VERSION, "pipeline_version": PIPELINE_VERSION, "built_at": receipts.now_utc(),
                     "asset": paths.rel(glb), "asset_sha256": hashlib.sha256(glb.read_bytes()).hexdigest(),
                     "triangles": int(sum(len(sf["i"]) // 3 for n in nodes for sf in n["surfaces"]))})
        (SPEC_DIR / f"{name}.json").write_text(json.dumps(spec, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        _register(spec, f"res://{paths.rel(glb)}")
        out[name] = {"triangles": spec["triangles"], "bytes": glb.stat().st_size}
    print(json.dumps(out, indent=1))
    return out


def _library_polygon(fid: str):
    meta, _, geoms, _ = pyogrio.raw.read(paths.LIBRARY, layer="buildings", where=f"feature_id='{fid}'")
    if not len(geoms):
        raise SystemExit(f"{fid} missing from the library")
    return shapely.from_wkb(geoms[0])


def _origin(poly, ground_y: float) -> tuple[np.ndarray, list[float]]:
    c = poly.centroid
    lx, lz = frame.projected_to_local(c.x, c.y)
    return np.array([c.x, c.y]), [round(lx, 3), round(ground_y, 3), round(lz, 3)]


def _shelter_727(s: meshing.Surfaces):
    """Walls = OSM roof trace inset by the eave width that reproduces the official floor area."""
    fid = "kw:building:osm:w339414849"
    facts = _facts(fid)
    fp = shapely.orient_polygons(_library_polygon(fid))
    ground = float(np.median(s.ground_at(np.asarray(fp.exterior.coords)[:, :2])))
    ring_ground = float(facts.get("ground_elevation_m", ground))
    roof_rel, roof_n, epochs = _roof_plane(fp, ring_ground)
    floor_area = float(facts["floor_area_m2"])
    eave = _inset_for_area(fp, floor_area)
    walls = fp.buffer(-eave, join_style="mitre")
    edges = _edge_runouts(fp, ring_ground)
    notch = [e for e in edges if e["runout_m"] is not None and e["runout_m"] >= NOTCH_ROOF_MIN_M]
    roof = shapely.union_all([fp] + [_edge_strip(fp, e["i"], e["runout_m"]) for e in notch])
    roof = shapely.orient_polygons(roof.buffer(0))
    centre, origin = _origin(fp, ring_ground)
    top = roof_rel
    fascia = 0.3  # presentation thickness of the roof slab edge (inferred)
    floor = 0.15  # slab-on-grade finish above the ring ground (inferred)
    wall_mesh = _prism(walls, centre, -0.3, top - fascia)
    roof_mesh = _prism(roof, centre, top - fascia, top)
    floor_mesh = _cap(walls.buffer(-0.01), centre, floor, up=True)
    spec = {
        "landmark": "727 Fort Street (First Exit primary shelter) - measured massing", "presentation": "measured_massing",
        "feature_id": fid,
        "override_id": "kw_override:first_exit:shelter:727_fort_st", "origin_local": origin,
        "frame": "glTF/Godot local metres: +x east, +y up (NAVD88 - origin y), +z south",
        "elements": {
            "roof_top_navd88_m": {"value": round(ring_ground + top, 3), "recon": "measured",
                                  "method": "median of 2019 DSM roof-band cells minus lidar ground ring", "above_ground_m": round(top, 3),
                                  "cells": roof_n, "epochs": epochs},
            "roof_outline": {"recon": "cross_verified", "method": "OSM trace (roof incl. eaves) + lidar roof run-out at notch edges",
                             "area_m2": round(roof.area, 1), "notch_roofs": notch},
            "walls": {"recon": "cross_verified", "inset_m": round(eave, 3), "area_m2": round(walls.area, 1),
                      "method": "OSM trace inset until the area equals the City record (3,693 sq ft)",
                      "check_lidar_eave_runouts_m": [e["runout_m"] for e in edges if e not in notch]},
            "floor_above_ground_m": {"value": floor, "recon": "inferred", "note": "finished floor not in any reachable record"},
            "roof_fascia_m": {"value": fascia, "recon": "inferred"},
            "openings": {"recon": "unresolved", "note": "doors/windows only from the Legistar plan attachments (not delivered)"},
        },
        "conflicts": [{
            "attribute": "height", "documentary": {"value_m": 6.86, "source": "city_kw_legistar_20_6136", "text": "existing height 22 ft 6 in"},
            "measured": {"value_m": round(top, 2), "sources": ["noaa_lidar_9081 2019", "noaa_lidar_6246 2016"]},
            "resolution": "geometry follows the two lidar epochs (flat roof, no parapet); the record's height datum is unstated. "
                          "Proposed 26 ft 4 in (2020) may describe a later state - needs post-2020 evidence."}],
        "ground_ring_navd88_m": round(ring_ground, 3),
    }
    nodes = [{"name": "Walls-col", "surfaces": [dict(wall_mesh, material="masonry_stucco")]},
             {"name": "Roof-col", "surfaces": [dict(roof_mesh, material="roof_membrane")]},
             {"name": "Floor", "surfaces": [dict(floor_mesh, material="masonry_stucco")]}]
    return spec, nodes


def _fort_taylor(s: meshing.Surfaces):
    """2.5D measured surface of the surviving fort fronts (exterior massing only, 0.5 m)."""
    fid = "kw:building:osm:w524088621"
    poly = shapely.orient_polygons(_library_polygon(fid))
    g19, g16 = lidar.LidarGrids("noaa_lidar_9081"), lidar.LidarGrids("noaa_lidar_6246")
    b = poly.buffer(3).bounds
    d19, _, _, minx, maxy, ncol, nrow = g19.window(*b)
    c = g19.cell
    ys, xs = np.mgrid[0:nrow, 0:ncol]
    X, Y = minx + (xs + 0.5) * c, maxy - (ys + 0.5) * c
    d16, _, _, mx6, my6, nc6, nr6 = g16.window(*b)
    v16 = d16[np.clip(((my6 - Y) / g16.cell).astype(int), 0, nr6 - 1), np.clip(((X - mx6) / g16.cell).astype(int), 0, nc6 - 1)]
    gap = ~np.isfinite(d19)
    surf = np.where(gap, v16, d19)
    surf = np.where(np.isfinite(surf), surf, np.nanmedian(surf))
    surf = ndimage.median_filter(surf, size=3)
    inner = poly.buffer(-0.4)
    ins = shapely.contains_xy(inner, X, Y)
    diff = (surf - v16)[ins & np.isfinite(v16)]
    boundary = meshing._ring_points(poly.exterior, c)
    # Edge heights come from the nearest interior cell, so the wall top is not mixed with the moat.
    _, (ri, ci) = ndimage.distance_transform_edt(~ins, return_indices=True)
    bcol = np.clip(((boundary[:, 0] - minx) / c).astype(int), 0, ncol - 1)
    brow = np.clip(((maxy - boundary[:, 1]) / c).astype(int), 0, nrow - 1)
    btop = surf[ri[brow, bcol], ci[brow, bcol]]
    ipts = np.column_stack([X[ins], Y[ins]])
    itop = surf[ins]
    verts = np.vstack([boundary, ipts])
    n = len(boundary)
    t = triangle.triangulate({"vertices": verts, "segments": np.array([[k, (k + 1) % n] for k in range(n)])}, "pQ")
    tv, ti = np.asarray(t["vertices"]), np.asarray(t["triangles"])
    heights = np.concatenate([btop, itop])
    if len(tv) != len(verts):
        heights = np.concatenate([heights, surf[np.clip(((maxy - tv[len(verts):, 1]) / c).astype(int), 0, nrow - 1),
                                                np.clip(((tv[len(verts):, 0] - minx) / c).astype(int), 0, ncol - 1)]])
    base = s.ground_at(boundary)
    ground0 = float(np.median(base))
    centre, origin = _origin(poly, ground0)
    top_mesh = _surface(tv, heights, ti, centre, ground0)
    skirt = _skirt(boundary, btop, base - 0.3, centre, ground0)
    spec = {
        "landmark": "Fort Zachary Taylor fronts - measured exterior surface (landmark proxy for the First Exit start)",
        "presentation": "measured_exterior_proxy",
        "not": "a reconstruction of Battery Osceola: no separate battery outline exists in any reachable source",
        "feature_id": fid,
        "override_id": "kw_override:first_exit:start:battery_osceola", "origin_local": origin,
        "frame": "glTF/Godot local metres: +x east, +y up (NAVD88 - origin y), +z south",
        "elements": {
            "surface": {"recon": "measured", "method": "2019 DSM 0.5 m, 3x3 median; gaps from 2016 DSM 1 m",
                        "cells": int(ins.sum()), "gap_share_2019": round(float(gap[ins].mean()), 4),
                        "height_navd88_m": [round(float(np.percentile(itop, q)), 2) for q in (5, 50, 95)],
                        "check_vs_2016": {"median_m": round(float(np.median(diff)), 3),
                                          "mad_m": round(float(np.median(np.abs(diff - np.median(diff)))), 3)}},
            "outline": {"recon": "derived", "method": "OSM w524088621 (Fort Zachary Taylor) as conflated in the library"},
            "skirt": {"recon": "measured", "method": "outline dropped to DEM 6366 ground (voids: MLLW-clamped fill) - 0.3 m"},
            "battery_osceola": {"recon": "unresolved", "note": "no separate footprint in any reachable source; the start anchor "
                                "sits on the measured south-front mass; no emplacement detail is modelled"},
        },
    }
    nodes = [{"name": "FortSurface-col", "surfaces": [dict(top_mesh, material="fort_brick")]},
             {"name": "FortWalls-col", "surfaces": [dict(skirt, material="fort_brick")]}]
    return spec, nodes


def _facts(fid: str) -> dict:
    import sqlite3
    con = sqlite3.connect(paths.LIBRARY)
    rows = con.execute("SELECT name, value_json FROM attribute WHERE feature_id = ? AND selected = 1", (fid,)).fetchall()
    con.close()
    return {k: json.loads(v) for k, v in rows}


def _local_grid(fp, pad: float):
    g = lidar.LidarGrids("noaa_lidar_9081")
    b = fp.buffer(pad).bounds
    dsm, _, _, minx, maxy, ncol, nrow = g.window(*b)
    ys, xs = np.mgrid[0:nrow, 0:ncol]
    return dsm, minx + (xs + 0.5) * g.cell, maxy - (ys + 0.5) * g.cell, minx, maxy, g.cell


def _roof_plane(fp, ground: float) -> tuple[float, int, dict]:
    epochs = {}
    for sid in ("noaa_lidar_9081", "noaa_lidar_6246"):
        g = lidar.LidarGrids(sid)
        b = fp.bounds
        dsm, _, _, minx, maxy, ncol, nrow = g.window(*b)
        ys, xs = np.mgrid[0:nrow, 0:ncol]
        ok = shapely.contains_xy(fp.buffer(-0.5), minx + (xs + 0.5) * g.cell, maxy - (ys + 0.5) * g.cell)
        nd = dsm[ok] - ground
        band = nd[(nd > ROOF_BAND_M[0]) & (nd < ROOF_BAND_M[1])]
        epochs[sid] = {"median_m": round(float(np.median(band)), 3), "p05_p95_m": [round(float(np.percentile(band, q)), 3) for q in (5, 95)],
                       "cells": int(band.size), "canopy_share": round(float((nd >= ROOF_BAND_M[1]).mean()), 3)}
    primary = epochs["noaa_lidar_9081"]
    return primary["median_m"], primary["cells"], epochs


def _inset_for_area(fp, area: float) -> float:
    lo, hi = 0.0, 2.0
    for _ in range(50):
        mid = (lo + hi) / 2
        if fp.buffer(-mid, join_style="mitre").area > area:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _edge_runouts(fp, ground: float) -> list[dict]:
    """Per-edge distance the lidar roof plane runs past the traced outline (median of 9 profiles)."""
    dsm, X, Y, minx, maxy, c = _local_grid(fp, 8)
    nd = dsm - ground
    co = np.asarray(fp.exterior.coords)
    out = []
    for i in range(len(co) - 1):
        a, b = co[i], co[i + 1]
        length = float(np.linalg.norm(b - a))
        t = (b - a) / length
        n = np.array([t[1], -t[0]])  # outward for a counter-clockwise exterior
        offs = []
        for f in np.linspace(0.15, 0.85, 9):
            d = np.arange(-2.0, 3.01, 0.1)
            pts = a + t * length * f + np.outer(d, n)
            h = nd[np.clip(((maxy - pts[:, 1]) / c).astype(int), 0, nd.shape[0] - 1), np.clip(((pts[:, 0] - minx) / c).astype(int), 0, nd.shape[1] - 1)]
            roof = (h > ROOF_BAND_M[0]) & (h < ROOF_BAND_M[1])
            if not roof[d < 0].any():
                continue
            k = 0
            while k < len(d) and (d[k] < 0 or roof[k]):
                k += 1
            if k < len(d) and h[k] < ROOF_BAND_M[0]:
                offs.append(float(d[k - 1]))
        out.append({"i": i, "length_m": round(length, 2), "runout_m": round(float(np.median(offs)), 2) if len(offs) >= 3 else None,
                    "profiles": len(offs)})
    return out


def _edge_strip(fp, i: int, depth: float):
    co = np.asarray(fp.exterior.coords)
    a, b = co[i], co[i + 1]
    t = (b - a) / np.linalg.norm(b - a)
    n = np.array([t[1], -t[0]])
    return shapely.Polygon([a, b, b + n * depth, a + n * depth]).difference(fp)


def _tri_polygon(poly) -> tuple[np.ndarray, np.ndarray]:
    rings = [poly.exterior, *poly.interiors]
    pts, segs, start = [], [], 0
    for r in rings:
        p = np.asarray(r.coords)[:-1, :2]
        pts.append(p)
        segs.extend([[start + k, start + (k + 1) % len(p)] for k in range(len(p))])
        start += len(p)
    tri = {"vertices": np.vstack(pts), "segments": np.array(segs)}
    if poly.interiors:
        tri["holes"] = np.array([shapely.Polygon(r).representative_point().coords[0] for r in poly.interiors])
    t = triangle.triangulate(tri, "pQ")
    return np.asarray(t["vertices"]), np.asarray(t["triangles"])


def _to_local(xy: np.ndarray, centre: np.ndarray) -> np.ndarray:
    """Projected (E, N) -> landmark-local (x east, z south)."""
    return np.column_stack([xy[:, 0] - centre[0], -(xy[:, 1] - centre[1])])


def _mesh(tris: list[np.ndarray]) -> dict:
    """Flat-shaded triangles (each a 3x3 array, counter-clockwise seen from outside)."""
    if not tris:
        return {"p": np.zeros((0, 3), np.float32), "n": np.zeros((0, 3), np.float32), "i": np.zeros(0, np.uint32)}
    t = np.asarray(tris, np.float32)
    nrm = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    return {"p": t.reshape(-1, 3), "n": np.repeat(nrm, 3, axis=0), "i": np.arange(len(t) * 3, dtype=np.uint32)}


def _cap_tris(poly, centre, y: float, up: bool) -> list[np.ndarray]:
    v, idx = _tri_polygon(poly)
    lv = _to_local(v, centre)
    out = []
    for a, b, c in idx:
        tri = np.array([[lv[k, 0], y, lv[k, 1]] for k in (a, b, c)])
        n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
        if (n[1] > 0) != up:
            tri = tri[[0, 2, 1]]
        out.append(tri)
    return out


def _cap(poly, centre, y: float, up: bool) -> dict:
    return _mesh(_cap_tris(poly, centre, y, up))


def _side_tris(poly, centre, y0: float, y1: float) -> list[np.ndarray]:
    out = []
    for ring, outer in [(poly.exterior, True)] + [(r, False) for r in poly.interiors]:
        p = _to_local(np.asarray(ring.coords)[:, :2], centre)
        for k in range(len(p) - 1):
            a, b = p[k], p[k + 1]
            q = [np.array([a[0], y0, a[1]]), np.array([b[0], y0, b[1]]), np.array([b[0], y1, b[1]]), np.array([a[0], y1, a[1]])]
            mid = (a + b) / 2
            nrm = np.cross(q[1] - q[0], q[3] - q[0])
            probe = mid + np.array([nrm[0], nrm[2]]) * 0.01 / max(np.linalg.norm(nrm), 1e-9)
            inside = shapely.contains_xy(poly, probe[0] + centre[0], -probe[1] + centre[1])
            if inside:
                q = q[::-1]
            out += [np.array([q[0], q[1], q[2]]), np.array([q[0], q[2], q[3]])]
    return out


def _prism(poly, centre, y0: float, y1: float) -> dict:
    return _mesh(_side_tris(poly, centre, y0, y1) + _cap_tris(poly, centre, y1, True) + _cap_tris(poly, centre, y0, False))


def _surface(v: np.ndarray, h: np.ndarray, idx: np.ndarray, centre, y0: float) -> dict:
    """Indexed heightfield with area-weighted vertex normals (shared vertices keep the asset small)."""
    lv = _to_local(v, centre)
    p = np.column_stack([lv[:, 0], h - y0, lv[:, 1]]).astype(np.float32)
    idx = np.asarray(idx, np.int64)
    fn = np.cross(p[idx[:, 1]] - p[idx[:, 0]], p[idx[:, 2]] - p[idx[:, 0]])
    flip = fn[:, 1] < 0
    idx[flip] = idx[flip][:, [0, 2, 1]]
    fn[flip] = -fn[flip]
    vn = np.zeros_like(p)
    for k in range(3):
        np.add.at(vn, idx[:, k], fn)
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-9)
    return {"p": p, "n": vn.astype(np.float32), "i": idx.ravel().astype(np.uint32)}


def _skirt(ring: np.ndarray, top: np.ndarray, bottom: np.ndarray, centre, y0: float) -> dict:
    lv = _to_local(ring, centre)
    poly = shapely.Polygon(ring)
    out = []
    m = len(ring)
    for k in range(m):
        j = (k + 1) % m
        q = [np.array([lv[k, 0], bottom[k] - y0, lv[k, 1]]), np.array([lv[j, 0], bottom[j] - y0, lv[j, 1]]),
             np.array([lv[j, 0], top[j] - y0, lv[j, 1]]), np.array([lv[k, 0], top[k] - y0, lv[k, 1]])]
        nrm = np.cross(q[1] - q[0], q[3] - q[0])
        mid = (ring[k] + ring[j]) / 2
        probe = mid + np.array([nrm[0], -nrm[2]]) * 0.01 / max(np.linalg.norm(nrm), 1e-9)
        if shapely.contains_xy(poly, probe[0], probe[1]):
            q = q[::-1]
        out += [np.array([q[0], q[1], q[2]]), np.array([q[0], q[2], q[3]])]
    return _mesh(out)


def _write_glb(path, nodes: list[dict]) -> None:
    """Minimal glTF 2.0 binary: one mesh per node, one primitive per surface, PBR base colours."""
    names = sorted({sf["material"] for n in nodes for sf in n["surfaces"]})
    blob, views, accessors, meshes = bytearray(), [], [], []

    def add(arr: np.ndarray, target: int, comp: int, typ: str, minmax: bool = False) -> int:
        while len(blob) % 4:
            blob.append(0)
        data = arr.tobytes()
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            acc["min"] = arr.min(axis=0).tolist()
            acc["max"] = arr.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    for n in nodes:
        prims = []
        for sf in n["surfaces"]:
            if not len(sf["i"]):
                continue
            pos = add(np.ascontiguousarray(sf["p"], np.float32), 34962, 5126, "VEC3", True)
            nrm = add(np.ascontiguousarray(sf["n"], np.float32), 34962, 5126, "VEC3")
            ind = add(np.ascontiguousarray(sf["i"], np.uint32), 34963, 5125, "SCALAR")
            prims.append({"attributes": {"POSITION": pos, "NORMAL": nrm}, "indices": ind, "material": names.index(sf["material"])})
        meshes.append({"name": n["name"], "primitives": prims})
    gltf = {"asset": {"version": "2.0", "generator": f"hoarbound {LANDMARK_VERSION}"}, "scene": 0,
            "scenes": [{"nodes": list(range(len(nodes)))}],
            "nodes": [{"name": n["name"], "mesh": k} for k, n in enumerate(nodes)], "meshes": meshes,
            "materials": [{"name": m, "pbrMetallicRoughness": {"baseColorFactor": list(MATERIALS[m]), "metallicFactor": 0.0,
                                                                "roughnessFactor": 0.9}} for m in names],
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def _may_write(fid: str) -> bool:
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return not any(a["feature_id"] == fid and a.get("authoring_state") in ("artist_modified", "artist_locked", "needs_rebase")
                   for a in doc["assets"])


def _register(spec: dict, scene: str) -> None:
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    fid = spec["feature_id"]
    rec = next((a for a in doc["assets"] if a["feature_id"] == fid), None)
    if rec is None:
        rec = {"feature_id": fid, "asset_id": f"kw_asset:landmark:{fid.split(':')[-1]}", "asset_revision": 0}
        doc["assets"].append(rec)
    changed = rec.get("asset_sha256") != spec["asset_sha256"]
    rec.update({"authoring_state": "generated", "kind": "landmark", "godot_scene": scene, "origin_local": spec["origin_local"],
                "source_geometry_hash": _current_hash(fid), "last_generator_version": PIPELINE_VERSION,
                "asset_sha256": spec["asset_sha256"], "landmark_spec": paths.rel(SPEC_DIR / (scene.rsplit("/", 1)[-1][:-4] + ".json"))})
    if changed:
        rec["asset_revision"] = int(rec.get("asset_revision") or 0) + 1
        rec["updated_at"] = spec["built_at"]
    doc["assets"] = sorted(doc["assets"], key=lambda a: (a["feature_id"], a.get("asset_id") or ""))
    MANIFEST.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

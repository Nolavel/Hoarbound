"""Hoarbound game overrides and the authoring (Blender/Godot asset) manifest.

Both are hand-authored, version-controlled files that the library build only COPIES
into the GeoPackage. Rebuilding reality never edits or deletes them.
  overrides/*.geojson           game_override features (EPSG:32617 coordinates)
  authoring/asset_manifest.json generated/authored asset records per feature_id
"""
from __future__ import annotations

import json

import shapely.geometry

from . import paths

AUTHORING_STATES = ("generated", "artist_modified", "artist_locked", "deprecated", "needs_rebase")


def load() -> dict:
    feats = []
    for path in sorted(paths.OVERRIDES.glob("*.geojson")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        if doc.get("crs_name") not in (None, "EPSG:32617"):
            raise SystemExit(f"{path}: overrides must use EPSG:32617 coordinates")
        for f in doc["features"]:
            props = dict(f["properties"])
            props["geometry"] = shapely.geometry.shape(f["geometry"]) if f.get("geometry") else shapely.Point()
            props["params_json"] = json.dumps(props.pop("params", {}), ensure_ascii=False, sort_keys=True)
            props["source_file"] = paths.rel(path)
            feats.append(props)
    manifest = paths.AUTHORING / "asset_manifest.json"
    assets = json.loads(manifest.read_text(encoding="utf-8"))["assets"] if manifest.exists() else []
    for a in assets:
        if a.get("authoring_state") not in AUTHORING_STATES:
            raise SystemExit(f"asset_manifest: invalid authoring_state {a.get('authoring_state')!r} for {a.get('feature_id')}")
    return {"features": feats, "assets": assets}


def init_bridge_override(gap_length_m: float = 120.0) -> None:
    """Writes overrides/boca_chica_channel_bridge.geojson once, from real geometry; refuses to overwrite.

    The gap is the gap-length window with the deepest mean channel bed under the real bridge
    axis (DEM 6366 bed averaged across the full bridge outline, 40 m kept at each abutment). Length is a provisional authoring choice.
    """
    import numpy as np
    import shapely
    from shapely.ops import substring

    from . import library, lidar, receipts

    out = paths.OVERRIDES / "boca_chica_channel_bridge.geojson"
    if out.exists():
        raise SystemExit(f"{out} exists; it is authored data. Edit it by hand or delete it deliberately.")
    geoms, cols = library.read_layer("bridges")
    bridge = [(g, cols["feature_id"][i]) for i, g in enumerate(geoms) if cols["name"][i] == "Boca Chica Channel Bridge"]
    if not bridge:
        raise SystemExit("Boca Chica Channel Bridge not in library")
    outline, outline_id = max(bridge, key=lambda b: b[0].area)
    rgeoms, rcols = library.read_layer("roads")
    decks = [(g, rcols["feature_id"][i], rcols["class"][i]) for i, g in enumerate(rgeoms)
             if "bridge" in (rcols["flags"][i] or "") and g.intersects(outline.buffer(2.0))]
    axis = max(decks, key=lambda d: d[0].intersection(outline.buffer(2.0)).length)[0].intersection(outline.buffer(2.0))
    axis = max(getattr(axis, "geoms", [axis]), key=lambda g: g.length)
    if axis.coords[0][0] > axis.coords[-1][0]:
        axis = shapely.LineString(list(axis.coords)[::-1])
    dem = lidar.DemCrop()
    inv = ~dem.transform
    s = np.arange(0.0, axis.length, 2.0)
    z = []
    for d in s:
        p0, p1 = axis.interpolate(max(0.0, d - 1.0)), axis.interpolate(min(axis.length, d + 1.0))
        tx, ty = p1.x - p0.x, p1.y - p0.y
        n = np.hypot(tx, ty) or 1.0
        nx, ny = -ty / n, tx / n
        p = axis.interpolate(d)
        vals = []
        for off in np.arange(-30.0, 30.1, 2.0):
            q = shapely.Point(p.x + nx * off, p.y + ny * off)
            if outline.contains(q):
                col, row = inv * (q.x, q.y)
                vals.append(float(dem.data[int(row), int(col)]))
        z.append(float(np.nanmean(vals)) if vals else np.nan)
    z = np.array(z)
    keep = 40.0
    starts = np.arange(keep, axis.length - keep - gap_length_m, 2.0)
    means = [float(np.nanmean(z[(s >= a0) & (s <= a0 + gap_length_m)])) for a0 in starts]
    a = float(starts[int(np.argmin(means))])
    b = a + gap_length_m
    deepest = (a + b) / 2
    feats = [{
        "type": "Feature",
        "geometry": shapely.geometry.mapping(outline),
        "properties": {"override_id": "kw_override:bridge:boca_chica_channel:state", "target_feature_id": outline_id,
                       "override_type": "bridge_state", "status": "provisional_author_review", "author": "Claude (Technical Director) for author review",
                       "created": receipts.now_utc()[:10],
                       "reason": "Hoarbound world rule: the US-1 link Stock Island -> Boca Chica is severed. Reality layer keeps the intact bridge.",
                       "params": {"state": "severed", "reality_preserved": True, "deck_length_m": round(axis.length, 1),
                                  "piers_and_abutments": "real positions not in any reachable source (FDOT plans / NOAA ENC needed); generator must not invent them as reality"}},
    }]
    for g, fid, cls in decks:
        cut = substring(axis, a, b).buffer(30.0, cap_style="flat")
        removed = g.intersection(cut)
        if removed.is_empty:
            continue
        feats.append({"type": "Feature", "geometry": shapely.geometry.mapping(removed),
                      "properties": {"override_id": f"kw_override:bridge:boca_chica_channel:gap:{fid.split(':')[-1]}", "target_feature_id": fid,
                                     "override_type": "remove_span", "status": "provisional_author_review",
                                     "author": "Claude (Technical Director) for author review", "created": receipts.now_utc()[:10],
                                     "reason": f"Severed {cls} deck over the deepest part of Boca Chica Channel.",
                                     "params": {"removed_interval_along_axis_m": [round(a, 1), round(b, 1)], "axis_length_m": round(axis.length, 1),
                                                "measured_from": "west (Stock Island) end of the bridge deck",
                                                "gap_length_m": round(b - a, 1), "gap_placement_reason": f"deepest mean bed {min(means):.2f} m NAVD88 over {gap_length_m:.0f} m window; abutments ({keep:.0f} m) kept"}}})
    for name, d in (("west", a), ("east", b)):
        p = axis.interpolate(d)
        feats.append({"type": "Feature", "geometry": shapely.geometry.mapping(p),
                      "properties": {"override_id": f"kw_override:bridge:boca_chica_channel:severed_end:{name}", "target_feature_id": outline_id,
                                     "override_type": "severed_end", "status": "provisional_author_review",
                                     "author": "Claude (Technical Director) for author review", "created": receipts.now_utc()[:10],
                                     "reason": "Broken deck edge for the generator (collision end, rubble anchor).",
                                     "params": {"along_axis_m": round(d, 1), "deck_side": "Stock Island" if name == "west" else "Boca Chica"}}})
    doc = {"type": "FeatureCollection", "crs_name": "EPSG:32617", "layer": "game_override",
           "description": "Hoarbound game override - NOT reality. Boca Chica Channel Bridge (US-1) is severed in the game world. Source truth stays intact in the bridges/roads layers.",
           "profile_along_axis_m": {"step_m": 2.0, "min_navd88_m": round(float(np.nanmin(z)), 2), "gap_centre_m": deepest,
                                    "bed_profile_every_20m": [None if np.isnan(v) else round(float(v), 2) for v in z[::10]]},
           "features": feats}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out} gap {a:.0f}..{b:.0f} m of {axis.length:.0f} m")

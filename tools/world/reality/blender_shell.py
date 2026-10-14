"""Building shell for Blender: the measured outline extruded to the measured height, alone.

Blender cannot read Godot scenes, so the shell is written from the library as glTF (Blender
imports it natively) with a sidecar of sizes and placement. Origin: footprint centroid on the
ground; metres; +Y up, x east, z south (Blender's importer turns it Z-up). No neighbours.

  blender-shell --feature-id kw:building:osm:w339414849
"""
from __future__ import annotations

import itertools
import json

import numpy as np
import shapely
from shapely.geometry.polygon import orient

from . import frame, library, paths
from .landmarks import _write_glb

OUT_DIR = paths.AUTHORING / "blender"
RETURN_DIR = "assets/world/key_west/buildings"
SCHEMA = "kw_reality.blender_shell.v1"
SHELL_MATERIALS = {"shell": (0.72, 0.72, 0.74, 1.0)}
LEVEL_M = 3.0  # storey height used only when a building has no measured height (inferred)


def stem_of(asset_id: str) -> str:
    """'kw_asset:building:osm_w1' -> 'building_osm_w1' (a file name on every OS)."""
    return asset_id.removeprefix("kw_asset:").replace(":", "_")


def asset_id_for(feature_id: str) -> str:
    manifest = json.loads((paths.AUTHORING / "asset_manifest.json").read_text(encoding="utf-8"))
    rec = next((a for a in manifest["assets"] if a["feature_id"] == feature_id), None)
    return rec["asset_id"] if rec else "kw_asset:building:" + "_".join(feature_id.split(":")[2:])


def sidecar_of(asset_id: str) -> dict | None:
    path = OUT_DIR / stem_of(asset_id) / "shell.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def run(feature_id: str) -> dict:
    geoms, cols = library.read_layer("buildings")
    i = next((k for k, f in enumerate(cols["feature_id"]) if f == feature_id), None)
    if i is None:
        raise SystemExit(f"{feature_id} is not a building in the Reality Library")
    attrs = json.loads(cols["attrs_json"][i])
    local = frame.to_local(geoms[i])
    poly = orient(max(local.geoms, key=lambda p: p.area) if local.geom_type == "MultiPolygon" else local, 1.0)
    c = poly.centroid
    ground = float(attrs.get("ground_elevation_m") or 0.0)
    measured = attrs.get("height_m")
    height = float(measured) if measured else LEVEL_M * float(attrs.get("levels") or 1)
    shape = shapely.affinity.translate(poly, -c.x, -c.y)
    asset_id = asset_id_for(feature_id)
    stem = stem_of(asset_id)
    sizes = {"height_m": round(height, 2), "height_source": "measured" if measured else "levels x 3 m (inferred)",
             "roof_median_height_m": attrs.get("roof_median_height_m"), "roof_relief_m": attrs.get("roof_relief_m"),
             "roof_form": attrs.get("roof_form") or attrs.get("roof_shape"), "levels": attrs.get("levels"),
             "footprint_area_m2": round(poly.area, 2),
             "bounds_m": [round(v, 2) for v in (shape.bounds[2] - shape.bounds[0], height, shape.bounds[3] - shape.bounds[1])]}
    doc = {"schema": SCHEMA, "feature_id": feature_id, "asset_id": asset_id, "stem": stem,
           "source_geometry_hash": cols["geometry_hash"][i], "address": attrs.get("address"), "name": cols["name"][i],
           "origin_local": [round(c.x, 3), round(ground, 3), round(c.y, 3)], "yaw_deg": 0.0,
           "axes": "metres; +Y up, x east, z south; origin = footprint centroid on the ground",
           "sizes": sizes,
           "footprint": {"exterior": [[round(x, 3), round(z, 3)] for x, z in list(shape.exterior.coords)[:-1]],
                         "holes": [[[round(x, 3), round(z, 3)] for x, z in list(r.coords)[:-1]] for r in shape.interiors]},
           "return": {"model": f"{RETURN_DIR}/{stem}.glb",
                      "register": f"python3 tools/world/key_west_reality.py asset --feature-id {feature_id} --asset-id {asset_id} "
                                  f"--state artist_modified --scene res://{RETURN_DIR}/{stem}.glb"}}
    out = OUT_DIR / stem
    out.mkdir(parents=True, exist_ok=True)
    extras = {k: doc[k] for k in ("feature_id", "asset_id", "source_geometry_hash", "origin_local")}
    _write_glb(out / "shell.glb", [{"name": stem + "_shell", "extras": extras, "surfaces": [_prism(shape, height)]}],
               SCHEMA, SHELL_MATERIALS)
    (out / "shell.json").write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"shell": paths.rel(out / "shell.glb"), "sizes": sizes, "return": doc["return"]}, indent=1))
    return doc


def _prism(shape, height: float) -> dict:
    """Flat-shaded closed prism (walls around the outline and every courtyard, roof, floor)."""
    p, n = [], []

    def tri(a, b, c, want):
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        nrm = np.cross(b - a, c - a)
        if np.dot(nrm, want) < 0:
            b, c = c, b
            nrm = -nrm
        nrm = nrm / (np.linalg.norm(nrm) or 1.0)
        p.extend([a, b, c])
        n.extend([nrm, nrm, nrm])

    for ring in [shape.exterior, *shape.interiors]:
        pts = list(ring.coords)
        for (x0, z0), (x1, z1) in itertools.pairwise(pts):
            out = np.array([z1 - z0, 0.0, -(x1 - x0)])  # CCW outline, CW holes: points away from the solid
            a, b, c, d = (x0, 0.0, z0), (x1, 0.0, z1), (x1, height, z1), (x0, height, z0)
            tri(a, b, c, out)
            tri(a, c, d, out)
    for t in shapely.constrained_delaunay_triangles(shape).geoms:
        (x0, z0), (x1, z1), (x2, z2) = list(t.exterior.coords)[:3]
        tri((x0, height, z0), (x1, height, z1), (x2, height, z2), (0.0, 1.0, 0.0))
        tri((x0, 0.0, z0), (x1, 0.0, z1), (x2, 0.0, z2), (0.0, -1.0, 0.0))
    return {"material": "shell", "p": np.asarray(p, np.float32), "n": np.asarray(n, np.float32),
            "i": np.arange(len(p), dtype=np.uint32)}

"""727 Fort Street exterior as built after the 2020 permit (Legistar 20-6136, sheets A2.01 and A1.03).

Plan frame of the landmark spec: u along the long facade (u = -13.26 is the left end of the SW elevation),
v towards Fort Street, y up from the landmark ground. Only dressing on the existing game outline: the
outline, the door and the windows stay the game's. A part that would cover a game opening is deferred
to the outline step and listed by deferred(). Each part names the sheet or record its numbers come from.
"""
from __future__ import annotations

import json
import math
import struct

import numpy as np
import shapely

FT = 0.3048
## Colours as sRGB 0-255. Paints from the A2.01 schedule, values from the Sherwin-Williams colour list.
WALL_PAINT = (227, 201, 161)  # SW 7691 (sold as Biltmore Buff, now Pale Yellow): walls, parapet
CANOPY_STEEL = (98, 63, 69)  # SW 0072 Deep Maroon: steel canopy, rods, exterior doors and frames
WOOD_TILE = (92, 64, 47)  # "wood pattern" porcelain slats: colour not scheduled, estimated from the 2025 panorama
SIGN_RED = (150, 32, 32)  # sign letters: estimated from the 2025 panorama
MATERIALS = {"wall_paint": WALL_PAINT, "canopy_steel": CANOPY_STEEL, "wood_tile": WOOD_TILE, "sign_red": SIGN_RED}

CANOPY_Y = 10.5 * FT  # A2.01 front elevation: underside of the canopy 10'-6" over ground (scaled)
CANOPY_DEPTH = 5.0 * FT  # A1.03 plan: line of canopy 5'-0" past the walls
CANOPY_SIDE = 4.9 * FT  # A1.03 / A2.01: the canopy runs 4'-11" past each side of the projection
CANOPY_T = 0.15  # steel structure depth: not dimensioned, inferred
ROD_FROM_Y = 12.6 * FT  # A2.01: tie rods leave the projection wall about 12'-7" over ground (scaled)
ROD_AT_FT = (1.4, 8.7, 16.1, 23.5, 30.9)  # A2.01: rods, feet from the projection's left corner (scaled)
PARAPET_TOP = 16.0 * FT + 2.0 * 0.0254  # A2.01: T.O. new parapet 16'-2"
PARAPET_T = 0.2  # not dimensioned, inferred
PLANTER_H = 2.0 * FT  # A2.01: planters about 2 ft tall (scaled)
PLANTER_FRONT_D = 1.9 * FT  # A1.03: planter strip along the projection front (scaled)
PLANTER_SIDE_D = 1.5 * FT  # A1.03: planter strips along the main walls and the projection's east side (scaled)
STRIP_PROUD = 0.03  # porcelain slats on the wall face
## A2.01: accent strips, feet from the facade's left end (left group) and from it (right group), scaled.
STRIPS_LEFT_FT = ((9.67, 12.96), (14.67, 18.03), (19.67, 23.09))
STRIPS_RIGHT_FT = ((57.04, 60.33), (61.97, 65.26), (66.91, 70.2))
PROJECTION_FT = (24.1, 56.1)  # A2.01: projection between these feet; 24'-6" from the left end per A1.02
SIGN_TEXT = "KEY WEST HEALTH CENTER"  # as built (2025 panorama); A2.01 drew a CHI sign "as per signage permit"
SIGN_Y = 4.35  # centre of the A2.01 sign band (12'-8" to 16'-2"), scaled
SIGN_CAP_H = 0.4  # letter height: estimated from the 2025 panorama


def _outline(spec: dict) -> dict:
    """Corners of the game outline the dressing hangs on (spec interior.outline_uv)."""
    o = spec["interior"]["outline_uv"]
    return {"proj_u0": o[4][0], "proj_u1": o[3][0], "proj_v": max(o[3][1], o[4][1]),
            "west_v": o[5][1], "east_v": o[1][1], "west_u": o[6][0], "east_u": o[0][0]}


def _openings_on(spec: dict, v: float) -> list[tuple[float, float]]:
    """u ranges of the game openings in the wall line v that face Fort Street."""
    out = []
    for o in spec["interior"]["openings"]:
        if o["outward_uv"] == [0, 1] and abs(o["centre_uv"][1] - v) < 0.2:
            out.append((o["centre_uv"][0] - o["width_m"] / 2, o["centre_uv"][0] + o["width_m"] / 2))
    return out


def _box(name, material, u0, y0, v0, u1, y1, v1, source, collision=False) -> dict:
    return {"name": name, "kind": "box", "material": material, "collision": collision, "source": source,
            "box": [[round(min(u0, u1), 4), round(min(y0, y1), 4), round(min(v0, v1), 4)],
                    [round(max(u0, u1), 4), round(max(y0, y1), 4), round(max(v0, v1), 4)]]}


def _strips(spec: dict, g: dict) -> list[dict]:
    left = [(g["proj_u0"] - (PROJECTION_FT[0] - a) * FT, g["proj_u0"] - (PROJECTION_FT[0] - b) * FT) for a, b in STRIPS_LEFT_FT]
    right = [(g["proj_u1"] + (a - PROJECTION_FT[1]) * FT, g["proj_u1"] + (b - PROJECTION_FT[1]) * FT) for a, b in STRIPS_RIGHT_FT]
    out = []
    for side, v, spans in (("W", g["west_v"], left), ("E", g["east_v"], right)):
        for k, (u0, u1) in enumerate(spans, 1):
            p = _box(f"AccentStrip{side}{k}", "wood_tile", u0, PLANTER_H, v, u1, PARAPET_TOP, v + STRIP_PROUD,
                     "A2.01 vertical accent strips, wood-pattern porcelain 6x36 in slats")
            p["covers_opening"] = any(u0 < b and u1 > a for a, b in _openings_on(spec, v))
            out.append(p)
    return out


def _all(spec: dict, roof_outline) -> list[dict]:
    g = _outline(spec)
    u0, u1, fv = g["proj_u0"], g["proj_u1"], g["proj_v"]
    top = CANOPY_Y + CANOPY_T
    parts = [
        _box("CanopyFront", "canopy_steel", u0 - CANOPY_SIDE, CANOPY_Y, fv, u1 + CANOPY_SIDE, top, fv + CANOPY_DEPTH,
             "A2.01 steel canopy; A1.03 line of canopy", True),
        _box("CanopyWest", "canopy_steel", u0 - CANOPY_SIDE, CANOPY_Y, g["west_v"], u0, top, fv, "A1.03 line of canopy, west side", True),
        _box("CanopyEast", "canopy_steel", u1, CANOPY_Y, g["east_v"], u1 + CANOPY_SIDE, top, fv, "A1.03 line of canopy, east side", True),
        _box("PlanterFront", "wood_tile", u0, 0.0, fv, u1, PLANTER_H, fv + PLANTER_FRONT_D, "A1.03 concrete planters; A2.01 wrap", True),
        _box("PlanterWest", "wood_tile", g["west_u"], 0.0, g["west_v"], u0 - CANOPY_SIDE, PLANTER_H, g["west_v"] + PLANTER_SIDE_D,
             "A1.03 concrete planters (west front, up to the entrance)", True),
        _box("PlanterProjectionEast", "wood_tile", u1, 0.0, g["east_v"], u1 + PLANTER_SIDE_D, PLANTER_H, fv,
             "A1.03 concrete planters along the projection's east side", True),
    ]
    ramp = spec["interior"]["entry_ramp"]
    gap = (ramp["to_uv"][0] - 1.3, ramp["to_uv"][0] + 1.3)  # keep the game's MainDoor and ramp free
    for name, a, b in (("PlanterEastA", u1 + PLANTER_SIDE_D, gap[0]), ("PlanterEastB", gap[1], g["east_u"])):
        if b - a > 0.5:
            parts.append(_box(name, "wood_tile", a, 0.0, g["east_v"], b, PLANTER_H, g["east_v"] + PLANTER_SIDE_D,
                              "A1.03 concrete planters (east front), gap at the game door", True))
    for k, at in enumerate(ROD_AT_FT, 1):
        u = u0 + at * FT
        parts.append({"name": f"CanopyRod{k}", "kind": "rod", "material": "canopy_steel", "collision": False,
                      "from": [round(u, 4), round(ROD_FROM_Y, 4), round(fv, 4)], "to": [round(u, 4), round(top, 4), round(fv + CANOPY_DEPTH, 4)],
                      "radius": 0.03, "source": "A2.01 canopy tie rods"})
    ring = roof_outline.difference(roof_outline.buffer(-PARAPET_T, join_style="mitre"))
    roof_top = spec["elements"]["roof_top_navd88_m"]["above_ground_m"]
    parts.append({"name": "Parapet", "kind": "prism", "material": "wall_paint", "collision": False, "source": "A2.01 T.O. new parapet 16'-2\"",
                  "polygon_uv": [list(map(lambda c: [round(c[0], 4), round(c[1], 4)], r.coords)) for r in [ring.exterior, *ring.interiors]],
                  "bottom_y": round(roof_top, 4), "top_y": round(PARAPET_TOP, 4)})
    parts.append({"name": "Sign", "kind": "text", "material": "sign_red", "collision": False, "text": SIGN_TEXT,
                  "centre": [round((u0 + u1) / 2, 4), SIGN_Y, round(fv + 0.02, 4)], "cap_h": SIGN_CAP_H,
                  "source": "built sign per the 2025 panorama (visual); A2.01 sign band"})
    return parts + _strips(spec, g)


def parts(spec: dict, roof_outline) -> list[dict]:
    """Exterior parts on the game outline, without those that would cover a game opening."""
    return [p for p in _all(spec, roof_outline) if not p.get("covers_opening")]


def deferred(spec: dict, roof_outline=None) -> list[dict]:
    """Parts the outline step must place: they would cover a game opening today."""
    roof = roof_outline if roof_outline is not None else shapely.Polygon(spec["interior"]["outline_uv"]).buffer(0.45, join_style="mitre")
    return [p for p in _all(spec, roof) if p.get("covers_opening")]


def roof_outline_from_glb(glb_path: str, yaw_rad: float) -> shapely.Polygon:
    """Outline of the shell's Roof-col mesh in the plan frame (Godot Basis(UP, yaw) maps plan to local)."""
    data = open(glb_path, "rb").read()
    n = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + n])
    blob = data[28 + n:]
    node = next(x for x in gltf["nodes"] if x.get("name") == "Roof-col")
    prim = gltf["meshes"][node["mesh"]]["primitives"][0]

    def read(index: int, width: int, dtype: str) -> np.ndarray:
        acc = gltf["accessors"][index]
        view = gltf["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return np.frombuffer(blob[start:start + acc["count"] * width * np.dtype(dtype).itemsize], dtype=dtype).reshape(-1, width)
    pos = read(prim["attributes"]["POSITION"], 3, "<f4")
    kind = {5123: "<u2", 5125: "<u4"}[gltf["accessors"][prim["indices"]]["componentType"]]
    tri = read(prim["indices"], 1, kind).reshape(-1, 3)
    cs, sn = math.cos(-yaw_rad), math.sin(-yaw_rad)
    u = pos[:, 0] * cs + pos[:, 2] * sn
    v = -pos[:, 0] * sn + pos[:, 2] * cs
    polys = [shapely.Polygon([(u[i], v[i]) for i in t]) for t in tri]
    return shapely.union_all([p.buffer(0.001) for p in polys if p.area > 1e-6]).buffer(-0.001)


def linear(srgb: tuple) -> list[float]:
    """sRGB 0-255 -> linear 0-1 (glTF baseColorFactor)."""
    return [round(c / 255 / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4, 4) for c in srgb]


def paint_shell(glb_path: str, material: str = "masonry_stucco") -> list[float]:
    """Sets the shell's exterior wall material to SW 7691; other buffers stay byte-identical. Returns the factor."""
    from .landmark_glass_frost import _read_glb, _write_glb
    gltf, blob = _read_glb(glb_path)
    factor = linear(WALL_PAINT) + [1.0]
    mat = next(m for m in gltf["materials"] if m.get("name") == material)
    mat.setdefault("pbrMetallicRoughness", {})["baseColorFactor"] = factor
    _write_glb(glb_path, gltf, blob)
    return factor


def apply(spec_path, shell_glb, exterior_glb, manifest_path) -> dict:
    """Paints the shell, then records both assets in the landmark spec and the authoring manifest."""
    import datetime
    import hashlib
    factor = paint_shell(str(shell_glb))
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    sha = {p: hashlib.sha256(open(p, "rb").read()).hexdigest() for p in (str(shell_glb), str(exterior_glb))}
    spec = json.loads(open(spec_path, encoding="utf-8").read())
    roof = roof_outline_from_glb(str(shell_glb), spec["interior"]["plan_yaw_rad"])
    spec["asset_sha256"] = sha[str(shell_glb)]
    spec["exterior"] = {"tool": "tools/blender/build_727_exterior.py (parts: tools/world/reality/facade_727.py)",
                        "asset": "assets/world/key_west/landmarks/kw_727_exterior.glb", "asset_sha256": sha[str(exterior_glb)],
                        "record": "Legistar 20-6136 permit set 2020, sheets A2.01 (elevations, paint schedule) and A1.03 (plan)",
                        "wall_paint": {"material": "masonry_stucco", "sw": "SW 7691", "srgb": list(WALL_PAINT), "linear": factor},
                        "parts": [p["name"] for p in parts(spec, roof)], "deferred": [p["name"] for p in deferred(spec, roof)],
                        "unchanged": "outline, door and windows stay the game's until the outline step", "built_at": stamp}
    open(spec_path, "w", encoding="utf-8").write(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
    manifest = json.loads(open(manifest_path, encoding="utf-8").read())
    rec = next(a for a in manifest["assets"] if a["feature_id"] == spec["feature_id"])
    rec.update({"asset_sha256": sha[str(shell_glb)], "updated_at": stamp, "asset_revision": int(rec.get("asset_revision") or 0) + 1,
                "authored_by": "tools/world/reality/facade_727.py (wall paint SW 7691; other buffers unchanged)"})
    open(manifest_path, "w", encoding="utf-8").write(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    return spec["exterior"]

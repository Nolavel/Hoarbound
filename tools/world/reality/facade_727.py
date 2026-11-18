"""727 Fort Street exterior as built after the 2020 permit (Legistar 20-6136, sheets A2.01 and A1.03).

Hangs on the spec's permit layout (interior.layout.faces: outer wall faces in the plan frame, u along the
long facade, v towards Fort Street, y up from the landmark ground) and on its openings, so the dressing
and the walls share one outline. Each part names the sheet or record its numbers come from.
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
WOOD_TILE = (114, 72, 51)  # "wood pattern" porcelain slats: sampled from the A2.01 material swatch
SIGN_RED = (150, 32, 32)  # sign letters: estimated from the 2025 panorama
DOOR_PAINT = (236, 226, 200)  # service doors as built: cream, not the scheduled SW 0072 (2025 Street View, visual)
EQUIPMENT_GREY = (150, 152, 150)  # electric service and roof units: estimated
MATERIALS = {"wall_paint": WALL_PAINT, "canopy_steel": CANOPY_STEEL, "wood_tile": WOOD_TILE, "sign_red": SIGN_RED,
             "door_paint": DOOR_PAINT, "equipment_grey": EQUIPMENT_GREY}

CANOPY_Y = 10.5 * FT  # A2.01 front elevation: underside of the canopy 10'-6" over ground (scaled)
CANOPY_DEPTH = 5.0 * FT  # A1.03 plan: line of canopy 5'-0" past the walls
CANOPY_SIDE = 4.9 * FT  # A1.03 / A2.01: the canopy runs 4'-11" past each side of the wing
CANOPY_T = 0.15  # steel structure depth: not dimensioned, inferred
ROD_FROM_Y = 12.6 * FT  # A2.01: tie rods leave the wing wall about 12'-7" over ground (scaled)
ROD_AT_FT = (1.4, 8.7, 16.1, 23.5, 30.9)  # A2.01: rods, feet from the wing's west corner (scaled)
PARAPET_TOP = 16.0 * FT + 2.0 * 0.0254  # A2.01: T.O. new parapet 16'-2"
PARAPET_T = 0.2  # not dimensioned, inferred
PLANTER_H = 2.0 * FT  # A2.01: planters about 2 ft tall (scaled)
PLANTER_FRONT_D = 1.9 * FT  # A1.03: planter strip along the wing front (scaled)
PLANTER_SIDE_D = 1.5 * FT  # A1.03: planter strips along the main front and the wing's east side (scaled)
STRIP_W = 3.33 * FT  # A2.01: each wood-pattern band is about 3'-4" wide and frames one narrow window
STRIP_PROUD = 0.03  # porcelain slats on the wall face
ROD_SIDE_FT = (1.5, 8.7, 15.8)  # A2.01 NW/SE: side canopy rods, feet from the main front corner (scaled)
## A2.01 side elevations, metres along each end of the main block (scaled; NW from the back corner, SE from the front one).
END_BANDS = {"NW": ((3.68, 5.33), (6.57, 7.56), (8.12, 9.11), (9.67, 10.66)),
             "SE": ((0.33, 1.33), (1.89, 2.87), (3.44, 4.42), (5.66, 8.34))}  # the last SE one is the door panel
SERVICE_DOOR = {"NW": (3.90, 4.91), "SE": (6.08, 7.08)}  # door leaves; both scale to about 7'-0" high
SERVICE_DOOR_H = 7.0 * FT
SERVICE_CANOPY = {"NW": ((3.63, 5.37), 2.46), "SE": ((5.61, 8.39), 2.50)}  # span along the end, underside over ground
SERVICE_CANOPY_DEPTH = 0.9  # not drawn in plan: inferred from the 2025 Street View (visual)
ELECTRIC_SERVICE = ((7.36, 8.06), (1.24, 2.27))  # A2.01 SE "relocated el. service": along the end, over ground
EQUIPMENT_PROUD = 0.25  # inferred
DOOR_PROUD = 0.04  # leaf and frame over the wall face
## A2.01 back elevation: three 6" PVC leaders (metres from the SE end) under a fibreglass collecting gutter.
DRAIN_LEADERS = (0.21, 13.23, 26.17)
GUTTER_Y = (3.99, 4.41)
GUTTER_D = 0.2  # inferred
## A2.01 back elevation: two roof units behind the parapet (dashed), metres from the SE end; 1.23 m square, top 1 m over it.
ROOF_UNITS = (7.31, 19.80)
ROOF_UNIT_W = 1.23
SIGN_TEXT = "KEY WEST HEALTH CENTER"  # as built (2025 panorama); A2.01 drew a CHI sign "as per signage permit"
SIGN_Y = 4.35  # centre of the A2.01 sign band (12'-8" to 16'-2"), scaled
SIGN_CAP_H = 0.4  # letter height: estimated from the 2025 panorama
COVER_REACH = 0.4  # a part this close in front of an opening blocks it


def _box(name, material, u0, y0, v0, u1, y1, v1, source, collision=False) -> dict:
    return {"name": name, "kind": "box", "material": material, "collision": collision, "source": source,
            "box": [[round(min(u0, u1), 4), round(min(y0, y1), 4), round(min(v0, v1), 4)],
                    [round(max(u0, u1), 4), round(max(y0, y1), 4), round(max(v0, v1), 4)]]}


def _faces(spec: dict) -> dict:
    return spec["interior"]["layout"]["faces"]


def _strips(spec: dict) -> list[dict]:
    """A2.01 bands on the main front, centred on the narrow windows and cut around them.

    A2.01 scales the west bands onto the A1.02 windows; the east bands scale 0.3-0.5 m off, so both follow the windows.
    """
    f = _faces(spec)["F"]
    src = "A2.01 vertical accent band, wood-pattern porcelain 6x36 in slats, framing a narrow window"
    out = []
    for o in spec["interior"]["openings"]:
        if not o["name"].startswith("NarrowWindow"):
            continue
        cu, hw, n = o["centre_uv"][0], o["width_m"] / 2, o["name"].removeprefix("NarrowWindow")
        u0, u1 = cu - STRIP_W / 2, cu + STRIP_W / 2
        for tag, a, b, y0, y1 in (("L", u0, cu - hw, PLANTER_H, PARAPET_TOP), ("R", cu + hw, u1, PLANTER_H, PARAPET_TOP),
                                  ("B", cu - hw, cu + hw, PLANTER_H, o["y0"]), ("T", cu - hw, cu + hw, o["y1"], PARAPET_TOP)):
            out.append(_box(f"AccentStrip{n}{tag}", "wood_tile", a, y0, f, b, y1, f + STRIP_PROUD, src))
    return out


def parts(spec: dict, roof_outline) -> list[dict]:
    """Exterior parts: canopy and rods, planters, parapet, sign and accent bands."""
    g = _faces(spec)
    w0, w1, f, p = g["PW"], g["PE"], g["F"], g["P"]
    top = CANOPY_Y + CANOPY_T
    out = [
        _box("CanopyFront", "canopy_steel", w0 - CANOPY_SIDE, CANOPY_Y, p, w1 + CANOPY_SIDE, top, p + CANOPY_DEPTH,
             "A2.01 steel canopy; A1.03 line of canopy", True),
        _box("CanopyWest", "canopy_steel", w0 - CANOPY_SIDE, CANOPY_Y, f, w0, top, p, "A1.03 line of canopy over the NW entrance", True),
        _box("CanopyEast", "canopy_steel", w1, CANOPY_Y, f, w1 + CANOPY_SIDE, top, p, "A1.03 line of canopy, wing's east side", True),
        _box("PlanterFront", "wood_tile", w0, 0.0, p, w1, PLANTER_H, p + PLANTER_FRONT_D, "A1.03 concrete planters; A2.01 wrap", True),
        _box("PlanterWest", "wood_tile", g["W"], 0.0, f, w0 - CANOPY_SIDE, PLANTER_H, f + PLANTER_SIDE_D,
             "A1.03 concrete planters (main front, up to the entrance walk)", True),
        _box("PlanterWingEast", "wood_tile", w1, 0.0, f, w1 + PLANTER_SIDE_D, PLANTER_H, p, "A1.03 concrete planters along the wing's east side", True),
        _box("PlanterEast", "wood_tile", w1 + PLANTER_SIDE_D, 0.0, f, g["E"], PLANTER_H, f + PLANTER_SIDE_D,
             "A1.03 concrete planters (main front, east of the wing)", True),
    ]
    for k, at in enumerate(ROD_AT_FT, 1):
        u = w0 + at * FT
        out.append({"name": f"CanopyRod{k}", "kind": "rod", "material": "canopy_steel", "collision": False,
                    "from": [round(u, 4), round(ROD_FROM_Y, 4), round(p, 4)], "to": [round(u, 4), round(top, 4), round(p + CANOPY_DEPTH, 4)],
                    "radius": 0.03, "source": "A2.01 canopy tie rods"})
    ring = roof_outline.difference(roof_outline.buffer(-PARAPET_T, join_style="mitre"))
    roof_top = spec["elements"]["roof_top_navd88_m"]["above_ground_m"]
    out.append({"name": "Parapet", "kind": "prism", "material": "wall_paint", "collision": False, "source": "A2.01 T.O. new parapet 16'-2\"",
                "polygon_uv": [list(map(lambda c: [round(c[0], 4), round(c[1], 4)], r.coords)) for r in [ring.exterior, *ring.interiors]],
                "bottom_y": round(roof_top, 4), "top_y": round(PARAPET_TOP, 4)})
    out.append({"name": "Sign", "kind": "text", "material": "sign_red", "collision": False, "text": SIGN_TEXT,
                "centre": [round((w0 + w1) / 2, 4), SIGN_Y, round(p + 0.02, 4)], "cap_h": SIGN_CAP_H,
                "source": "built sign per the 2025 panorama (visual); A2.01 sign band"})
    return out + _strips(spec) + _side_rods(spec) + _ends(spec) + _back(spec, roof_top)


def _side_rods(spec: dict) -> list[dict]:
    """A2.01 NW/SE: three tie rods on each side canopy, wing wall to the canopy's outer edge."""
    g = _faces(spec)
    top = CANOPY_Y + CANOPY_T
    out = []
    for side, wall, edge in (("W", g["PW"], g["PW"] - CANOPY_SIDE), ("E", g["PE"], g["PE"] + CANOPY_SIDE)):
        for k, at in enumerate(ROD_SIDE_FT, 1):
            v = g["F"] + at * FT
            out.append({"name": f"CanopyRod{side}{k}", "kind": "rod", "material": "canopy_steel", "collision": False,
                        "from": [round(wall, 4), round(ROD_FROM_Y, 4), round(v, 4)], "to": [round(edge, 4), round(top, 4), round(v, 4)],
                        "radius": 0.03, "source": "A2.01 side elevations, canopy tie rods"})
    return out


def _ends(spec: dict) -> list[dict]:
    """Both ends of the main block (A2.01 NW and SE): bands cut around a closed service door, its canopy, the SE meters.

    The doors stay shut walls in the game (owner 2026-11-18); a matching leaf on the inside face keeps the two views agreeing.
    """
    g, lines, floor = _faces(spec), spec["interior"]["layout"]["lines"], spec["interior"]["floor_y"]
    out = []
    for end, face, inner, out_dir, to_v in (("NW", g["W"], lines["W"], -1.0, lambda d: g["B"] + d),
                                            ("SE", g["E"], lines["E"], 1.0, lambda d: g["F"] - d)):
        span = lambda a, b: sorted((to_v(a), to_v(b)))
        d0, d1 = SERVICE_DOOR[end]
        door_v = span(d0, d1)
        skin = (face, face + out_dir * STRIP_PROUD)
        for k, (a, b) in enumerate(END_BANDS[end], 1):
            v0, v1 = span(a, b)
            src = f"A2.01 {end} side elevation, wood-pattern band"
            if v0 < door_v[1] and v1 > door_v[0]:
                pieces = ((v0, door_v[0], 0.0), (door_v[1], v1, 0.0), (door_v[0], door_v[1], SERVICE_DOOR_H))
                for tag, (pa, pb, y0) in zip("LRT", pieces):
                    out.append(_box(f"EndBand{end}{k}{tag}", "wood_tile", skin[0], y0, pa, skin[1], PARAPET_TOP, pb, src))
            else:
                out.append(_box(f"EndBand{end}{k}", "wood_tile", skin[0], 0.0, v0, skin[1], PARAPET_TOP, v1, src))
        src = f"A2.01 {end} side elevation, service door (closed in the game)"
        out.append(_box(f"ServiceDoor{end}", "door_paint", face, 0.0, door_v[0], face + out_dir * DOOR_PROUD, SERVICE_DOOR_H, door_v[1], src))
        out.append(_box(f"ServiceDoor{end}Inside", "door_paint", inner, floor, door_v[0], inner - out_dir * DOOR_PROUD,
                        floor + SERVICE_DOOR_H, door_v[1], "inside face of the closed service door (game)"))
        (c0, c1), under = SERVICE_CANOPY[end]
        cv0, cv1 = span(c0, c1)
        tip = face + out_dir * SERVICE_CANOPY_DEPTH
        out.append(_box(f"ServiceCanopy{end}", "canopy_steel", face, under, cv0, tip, under + 0.12, cv1,
                        f"A2.01 {end}: steel canopy over the service door; depth from the 2025 Street View"))
        for k, v in enumerate((cv0 + 0.15, cv1 - 0.15), 1):
            out.append({"name": f"ServiceCanopy{end}Rod{k}", "kind": "rod", "material": "canopy_steel", "collision": False,
                        "from": [round(face, 4), round(under + 0.7, 4), round(v, 4)], "to": [round(tip, 4), round(under + 0.12, 4), round(v, 4)],
                        "radius": 0.02, "source": "service canopy hangers, 2025 Street View (visual)"})
    (e0, e1), (ey0, ey1) = ELECTRIC_SERVICE
    ev = sorted((g["F"] - e0, g["F"] - e1))
    out.append(_box("ElectricServiceSE", "equipment_grey", g["E"] + STRIP_PROUD, ey0, ev[0], g["E"] + EQUIPMENT_PROUD, ey1, ev[1],
                    "A2.01 SE: relocated electric service; meters in the 2025 Street View"))
    return out


def _back(spec: dict, roof_top: float) -> list[dict]:
    """A2.01 back elevation: gutter under the parapet, three PVC leaders, two roof units behind the parapet."""
    g = _faces(spec)
    b, e = g["B"], g["E"]
    out = [_box("BackGutter", "wall_paint", g["W"], GUTTER_Y[0], b - GUTTER_D, e, GUTTER_Y[1], b,
                "A2.01 back elevation: fibreglass collecting gutter; depth inferred")]
    for k, at in enumerate(DRAIN_LEADERS, 1):
        u = e - at
        out.append({"name": f"DrainLeader{k}", "kind": "rod", "material": "wall_paint", "collision": False,
                    "from": [round(u, 4), 0.0, round(b - 0.1, 4)], "to": [round(u, 4), GUTTER_Y[0], round(b - 0.1, 4)],
                    "radius": 0.076, "source": "A2.01 back elevation: 6 in PVC drain leader"})
    mid = (b + g["F"]) / 2
    for k, at in enumerate(ROOF_UNITS, 1):
        u, h = e - at, ROOF_UNIT_W / 2
        out.append(_box(f"RoofUnit{k}", "equipment_grey", u - h, roof_top, mid - h, u + h, PARAPET_TOP + 1.0, mid + h,
                        "A2.01 back elevation: roof unit (position along the block); across the roof inferred mid-depth"))
    return out


def covered(spec: dict, part_list: list[dict]) -> list[tuple[str, str]]:
    """(part, opening) pairs where a box stands in front of an opening; the build refuses any."""
    hits = []
    for o in spec["interior"]["openings"]:
        if o["kind"] not in ("door", "window"):
            continue
        (cu, cv), (du, dv), hw = o["centre_uv"], o["outward_uv"], o["width_m"] / 2
        if du == 0 and dv == 0:
            continue
        ## Footprint just outside the opening: along the wall +-hw, outward from the wall face up to COVER_REACH.
        if dv:
            (a, b), (c, d) = (cu - hw, cu + hw), sorted((cv + 0.15 * dv, cv + (0.15 + COVER_REACH) * dv))
        else:
            (a, b), (c, d) = sorted((cu + 0.15 * du, cu + (0.15 + COVER_REACH) * du)), (cv - hw, cv + hw)
        reach = shapely.box(a, c, b, d)
        for p in part_list:
            if p["kind"] != "box":
                continue
            (u0, y0, v0), (u1, y1, v1) = p["box"]
            if y0 < o["y1"] - 1e-3 and y1 > o["y0"] + 1e-3 and shapely.box(u0, v0, u1, v1).intersection(reach).area > 1e-4:
                hits.append((p["name"], o["name"]))
    return hits


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
                        "parts": [p["name"] for p in parts(spec, roof)], "built_at": stamp}
    open(spec_path, "w", encoding="utf-8").write(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
    manifest = json.loads(open(manifest_path, encoding="utf-8").read())
    rec = next(a for a in manifest["assets"] if a["feature_id"] == spec["feature_id"])
    rec.update({"asset_sha256": sha[str(shell_glb)], "updated_at": stamp, "asset_revision": int(rec.get("asset_revision") or 0) + 1,
                "authored_by": "tools/world/reality/facade_727.py (wall paint SW 7691; other buffers unchanged)"})
    open(manifest_path, "w", encoding="utf-8").write(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    return spec["exterior"]

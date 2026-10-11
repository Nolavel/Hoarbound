"""727 Fort Street as an enterable shelter: hollow measured walls, openings and a clinic plan.

Only the outer form is measured (landmarks._shelter_727). Openings, partitions and furniture
are game-invented (no floor plan is reachable) and are flagged as such in the spec. Door and
window openings follow the First Exit hut standard (door 1.5 x 2.25 m, window 2.0 x 1.1 m).

Plan frame: metres from the landmark origin, u along the long facade, v towards Fort Street.
In Godot a node at the landmark origin with Basis(UP, plan_yaw_rad) maps plan (u, v) to (x, z).
"""
from __future__ import annotations

import math

import numpy as np
import shapely
import shapely.affinity

from . import frame

WALL_T = 0.25  # exterior wall (inferred masonry)
PART_T = 0.12  # interior stud partition (inferred)
FLOOR_ABOVE_GROUND_M = 0.1  # finished floor over the highest DEM ground inside the walls (inferred)
CEILING_CLEAR_M = 3.0  # suspended ceiling height above the floor (inferred)
DOOR = (1.5, 2.25)  # First Exit hut door standard: HingedDoor.opening_size
WINDOW = (2.0, 1.1, 0.8)  # hut window standard: width, height, sill above the floor
RAMP_RUN_M = 2.4  # Henry has no step-up; entries are ramps (hut EntryRamp), here about 1:7

## Corridor between v = -1.6 and v = 0.2; rooms south of it, wing and side rooms north of it.
ROOMS = [
    ("dental", "Dental operatory", (-12.95, -6.56, -7.0, -1.6)),
    ("exam_1", "Exam room 1", (-7.0, -6.56, -2.0, -1.6)),
    ("exam_2", "Exam room 2", (-2.0, -6.56, 3.0, -1.6)),
    ("pharmacy", "Lab / pharmacy", (3.0, -6.56, 8.3, -1.6)),
    ("storage", "Storage", (8.3, -6.56, 13.66, -1.6)),
    ("corridor", "Corridor", (-12.95, -1.6, 13.66, 0.2)),
    ("restroom_w", "Restroom", (-12.95, 0.2, -9.3, 2.96)),
    ("restroom_e", "Restroom", (-9.3, 0.2, -5.64, 2.96)),
    ("waiting", "Waiting room (heated shelter)", (-5.64, 0.2, 3.46, 10.07)),
    ("lobby", "Entry lobby / reception (heated shelter)", (3.46, 0.2, 9.0, 2.96)),
    ("office", "Office", (9.0, 0.2, 13.66, 2.96)),
]
HEATED = ("waiting", "lobby")
PARTITIONS = [  # (axis, at, from, to): a wall line in plan, clipped to the interior
    ("v", -1.6, -12.95, 13.66), ("v", 0.2, -12.95, 13.66),
    ("u", -7.0, -6.56, -1.6), ("u", -2.0, -6.56, -1.6), ("u", 3.0, -6.56, -1.6), ("u", 8.3, -6.56, -1.6),
    ("u", -9.3, 0.2, 2.96), ("u", -5.64, 0.2, 2.96), ("u", 3.46, 0.2, 2.96), ("u", 9.0, 0.2, 2.96),
]
## Openings: (name, kind, axis of the wall, wall line, centre along it, outward (du, dv), room).
OPENINGS = [
    ("MainDoor", "door", "v", 3.08, 6.23, (0, 1), "lobby"),
    ("LobbyArch", "arch", "u", 3.46, 1.6, (1, 0), "waiting"),
    ("WaitingDoor", "doorway", "v", 0.2, -1.0, (0, -1), "waiting"),
    ("RestroomWDoor", "doorway", "v", 0.2, -11.1, (0, -1), "restroom_w"),
    ("RestroomEDoor", "doorway", "v", 0.2, -7.5, (0, -1), "restroom_e"),
    ("OfficeDoor", "doorway", "v", 0.2, 11.3, (0, -1), "office"),
    ("DentalDoor", "doorway", "v", -1.6, -10.0, (0, 1), "dental"),
    ("Exam1Door", "doorway", "v", -1.6, -4.5, (0, 1), "exam_1"),
    ("Exam2Door", "doorway", "v", -1.6, 0.5, (0, 1), "exam_2"),
    ("PharmacyDoor", "doorway", "v", -1.6, 5.6, (0, 1), "pharmacy"),
    ("StorageDoor", "doorway", "v", -1.6, 11.0, (0, 1), "storage"),
    ("FrontWindow1", "window", "v", 10.2, -3.0, (0, 1), "waiting"),
    ("FrontWindow2", "window", "v", 10.2, 1.0, (0, 1), "waiting"),
    ("SideWindowWest", "window", "u", -5.77, 7.0, (-1, 0), "waiting"),
    ("SideWindowEast", "window", "u", 3.58, 7.0, (1, 0), "waiting"),
    ("DentalWindow", "window", "v", -6.68, -10.0, (0, -1), "dental"),
    ("DentalWestWindow", "window", "u", -13.1, -4.0, (-1, 0), "dental"),
    ("Exam1Window", "window", "v", -6.68, -4.5, (0, -1), "exam_1"),
    ("Exam2Window", "window", "v", -6.68, 0.5, (0, -1), "exam_2"),
    ("PharmacyWindow", "window", "v", -6.68, 5.6, (0, -1), "pharmacy"),
    ("StorageWindow", "window", "v", -6.68, 11.0, (0, -1), "storage"),
    ("StorageEastWindow", "window", "u", 13.79, -4.0, (1, 0), "storage"),
    ("OfficeEastWindow", "window", "u", 13.79, 1.6, (1, 0), "office"),
    ("OfficeFrontWindow", "window", "v", 3.08, 11.6, (0, 1), "office"),
    ("RestroomWindow", "window", "u", -13.1, 1.6, (-1, 0), "restroom_w"),
]
## Furniture: (node, kind, room, centre (u, v), yaw_deg, size (w, h, d) for game boxes or None).
## Hut kinds reuse the First Exit hut nodes; the rest are plain clinic boxes (game-invented).
FURNITURE = [
    ("Stove", "hut_stove", "waiting", (-1.2, 6.4), 0, None),
    ("Mattress", "hut_mattress", "waiting", (-4.4, 7.6), 0, None),
    ("RestCrate", "hut_rest_crate", "waiting", (0.9, 4.6), 0, None),
    ("Cabinet", "hut_cabinet", "waiting", (2.9, 8.8), 0, None),
    ("ToolBench", "hut_tool_bench", "storage", (10.6, -5.6), 0, None),
    ("SupplyBench", "hut_supply_bench", "storage", (12.6, -3.0), 90, None),
    ("ReceptionCounter", "counter", "lobby", (8.15, 1.6), 0, (0.6, 1.05, 2.2)),
    ("WaitingBenchWest", "bench", "waiting", (-5.1, 4.2), 0, (0.5, 0.45, 2.4)),
    ("WaitingBenchFront", "bench", "waiting", (-1.0, 9.6), 90, (0.5, 0.45, 2.4)),
    ("ExamTable1", "exam_table", "exam_1", (-4.5, -5.4), 90, (0.7, 0.8, 1.9)),
    ("ExamTable2", "exam_table", "exam_2", (0.5, -5.4), 90, (0.7, 0.8, 1.9)),
    ("ExamDesk1", "desk", "exam_1", (-6.3, -3.0), 0, (0.6, 0.75, 1.2)),
    ("ExamDesk2", "desk", "exam_2", (-1.3, -3.0), 0, (0.6, 0.75, 1.2)),
    ("DentalChair", "dental_chair", "dental", (-10.0, -4.6), 90, (0.8, 0.9, 1.9)),
    ("DentalCart", "cart", "dental", (-8.2, -5.6), 0, (0.5, 0.9, 0.6)),
    ("PharmacyShelf", "shelf", "pharmacy", (5.6, -6.2), 90, (0.4, 2.0, 3.6)),
    ("LabCounter", "counter", "pharmacy", (7.85, -4.1), 0, (0.6, 0.95, 2.4)),
    ("StorageShelf", "shelf", "storage", (13.25, -5.6), 0, (0.45, 2.0, 1.6)),
    ("OfficeDesk", "desk", "office", (11.3, 2.2), 90, (0.7, 0.75, 1.5)),
    ("ToiletW", "toilet", "restroom_w", (-12.4, 2.3), 0, (0.45, 0.8, 0.7)),
    ("SinkW", "sink", "restroom_w", (-9.8, 2.5), 0, (0.5, 0.85, 0.45)),
    ("ToiletE", "toilet", "restroom_e", (-6.2, 2.3), 0, (0.45, 0.8, 0.7)),
    ("SinkE", "sink", "restroom_e", (-8.8, 2.5), 0, (0.5, 0.85, 0.45)),
]
GAME_INVENTED = ("no floor plan, door or window record is reachable (Legistar plan attachments not delivered); "
                 "layout follows a small community health centre (CHI Key West clinic programme: medical, dental, "
                 "pharmacy) and the hut standards")


class Plan:
    """Plan frame of the 727 walls: origin = landmark origin, u along the longest wall edge."""

    def __init__(self, walls_projected, origin_local: list[float]):
        self.c = np.array([origin_local[0], origin_local[2]])
        wl = frame.to_local(walls_projected)
        co = np.asarray(wl.exterior.coords)[:, :2]
        edges = co[1:] - co[:-1]
        k = int(np.argmax(np.linalg.norm(edges, axis=1)))
        self.theta = math.atan2(edges[k][1], edges[k][0])
        uv = self.to_plan(wl)
        if uv.bounds[3] < -uv.bounds[1]:  # the Fort Street wing must lie on +v
            self.theta += math.pi
        self.walls = self.to_plan(wl)

    def to_plan(self, geom_local):
        moved = shapely.affinity.translate(geom_local, -self.c[0], -self.c[1])
        return shapely.affinity.rotate(moved, -self.theta, origin=(0, 0), use_radians=True)

    def to_projected(self, geom_plan):
        g = shapely.affinity.rotate(geom_plan, self.theta, origin=(0, 0), use_radians=True)
        g = shapely.affinity.translate(g, self.c[0], self.c[1])
        oe, on = frame.origin()
        return shapely.transform(g, lambda p: np.column_stack([p[:, 0] + oe, on - p[:, 1]]))

    def to_local_xz(self, u: float, v: float) -> tuple[float, float]:
        """Plan point -> landmark-local x/z (relative to the origin)."""
        cs, sn = math.cos(self.theta), math.sin(self.theta)
        return u * cs - v * sn, u * sn + v * cs

    def godot_yaw(self) -> float:
        """Basis(UP, yaw) * Vector3(u, 0, v) == Vector3(x, 0, z) of to_local_xz."""
        return -self.theta


def _rect(u0: float, v0: float, u1: float, v1: float):
    return shapely.box(min(u0, u1), min(v0, v1), max(u0, u1), max(v0, v1))


def _line_rect(axis: str, at: float, a: float, b: float, half: float):
    return _rect(a, at - half, b, at + half) if axis == "v" else _rect(at - half, a, at + half, b)


def _opening_rect(o) -> shapely.Polygon:
    name, kind, axis, at, along, _, _ = o
    width = WINDOW[0] if kind == "window" else (2.2 if kind == "arch" else DOOR[0])
    return _line_rect(axis, at, along - width / 2, along + width / 2, 0.45) if axis == "v" else \
        _rect(at - 0.45, along - width / 2, at + 0.45, along + width / 2)


def _opening_y(kind: str, floor: float) -> tuple[float, float]:
    if kind == "window":
        return floor + WINDOW[2], floor + WINDOW[2] + WINDOW[1]
    return floor, floor + DOOR[1]


def floor_height(plan: Plan, origin_y: float, ground_at) -> float:
    """Floor above the origin: the DEM under the slab rises up to ~0.6 m over the ground ring."""
    inner = plan.walls.buffer(-WALL_T, join_style="mitre")
    b = inner.bounds
    us, vs = np.meshgrid(np.arange(b[0], b[2], 0.5), np.arange(b[1], b[3], 0.5))
    pts = shapely.points(us.ravel(), vs.ravel())
    pts = pts[shapely.contains(inner, pts)]
    proj = np.asarray([plan.to_projected(p).coords[0] for p in pts])
    return round(float(np.max(ground_at(proj))) - origin_y + FLOOR_ABOVE_GROUND_M, 2)


def build(plan: Plan, wall_top: float, origin_y: float, ground_at) -> tuple[dict, list[dict]]:
    """Returns (interior spec, glTF node list). ground_at(projected Nx2) -> NAVD88 heights."""
    floor = floor_height(plan, origin_y, ground_at)
    ceiling = floor + CEILING_CLEAR_M
    inner = plan.walls.buffer(-WALL_T, join_style="mitre")
    shell = plan.walls.difference(inner)
    strips = shapely.union_all([_line_rect(a, at, lo, hi, PART_T / 2) for a, at, lo, hi in PARTITIONS])
    parts = strips.intersection(inner)
    ext_open = [o for o in OPENINGS if o[1] in ("door", "window")]
    int_open = [o for o in OPENINGS if o[1] not in ("door", "window")]
    for o in OPENINGS:
        target = shell if o in ext_open else parts
        if not _opening_rect(o).intersects(target):
            raise SystemExit(f"727 opening {o[0]} misses its wall")
    shell_tris = _walls_with_openings(plan, shell, ext_open, -0.3, wall_top, floor)
    part_tris = _walls_with_openings(plan, parts, int_open, floor, ceiling, floor)
    glass = []
    for o in ext_open:
        if o[1] == "window":
            y0, y1 = _opening_y("window", floor)
            pane = _opening_rect(o).intersection(shell).centroid
            glass += _box_tris(plan, pane.x, pane.y, (0.02, y1 - y0, WINDOW[0]) if o[2] == "u" else (WINDOW[0], y1 - y0, 0.02), y0)
    door = next(o for o in OPENINGS if o[0] == "MainDoor")
    sill = _opening_rect(door).intersection(shell).centroid
    du, dv = door[5]
    out_edge = (sill.x + du * WALL_T / 2, sill.y + dv * WALL_T / 2)
    foot = (out_edge[0] + du * RAMP_RUN_M, out_edge[1] + dv * RAMP_RUN_M)
    foot_proj = np.asarray(plan.to_projected(shapely.Point(foot)).coords)[:, :2]
    foot_y = float(ground_at(foot_proj)[0])
    ramp_tris = _ramp(plan, out_edge, foot, door, foot_y - origin_y, floor)
    nodes = [
        {"name": "Walls-col", "surfaces": [_mesh_dict(shell_tris, "masonry_stucco")]},
        {"name": "Partitions-col", "surfaces": [_mesh_dict(part_tris, "interior_plaster")]},
        {"name": "Floor-col", "surfaces": [_mesh_dict(_prism_tris(plan, inner, -0.3, floor), "floor_vinyl")]},
        {"name": "Ceiling-col", "surfaces": [_mesh_dict(_cap(plan, inner, ceiling, up=False), "ceiling_tile")]},
        {"name": "EntryRamp-col", "surfaces": [_mesh_dict(ramp_tris, "masonry_stucco")]},
        {"name": "Glass", "surfaces": [_mesh_dict(glass, "window_glass")]},
    ]
    spec = {
        "recon": "game_invented", "note": GAME_INVENTED,
        "plan_yaw_rad": round(plan.godot_yaw(), 6), "plan_frame": "u along the long facade, v towards Fort Street",
        "floor_y": floor, "floor_method": "max DEM ground inside the walls + %.2f m" % FLOOR_ABOVE_GROUND_M,
        "ceiling_y": round(ceiling, 3), "wall_thickness_m": WALL_T, "partition_thickness_m": PART_T,
        "door_standard": {"width_m": DOOR[0], "height_m": DOOR[1], "source": "First Exit hut HingedDoor.opening_size"},
        "window_standard": {"width_m": WINDOW[0], "height_m": WINDOW[1], "sill_m": WINDOW[2], "source": "First Exit hut breach windows"},
        "rooms": [{"id": rid, "name": label, "rect_uv": [round(x, 3) for x in r], "heated": rid in HEATED,
                   "area_m2": round(_rect(*r).intersection(inner).area, 1)} for rid, label, r in ROOMS],
        "openings": [_opening_spec(o, shell if o in ext_open else parts, floor) for o in OPENINGS],
        "entry_ramp": {"from_uv": [round(foot[0], 3), round(foot[1], 3)], "to_uv": [round(out_edge[0], 3), round(out_edge[1], 3)],
                       "foot_y_navd88": round(foot_y, 3), "top_y": floor},
        "furniture": [{"node": n, "kind": k, "room": r, "uv": list(p), "yaw_deg": y, "size": list(s) if s else None}
                      for n, k, r, p, y, s in FURNITURE],
        "outline_uv": [[round(x, 3), round(y, 3)] for x, y in plan.walls.exterior.coords[:-1]],
    }
    for f in spec["furniture"]:
        if not _rect(*next(r for rid, _, r in ROOMS if rid == f["room"])).buffer(0.01).contains(shapely.Point(f["uv"])):
            raise SystemExit(f"727 furniture {f['node']} is outside room {f['room']}")
    return spec, nodes


def _opening_spec(o, wall, floor: float) -> dict:
    name, kind, axis, at, along, out, room = o
    c = _opening_rect(o).intersection(wall).centroid
    y0, y1 = _opening_y(kind, floor)
    width = WINDOW[0] if kind == "window" else (2.2 if kind == "arch" else DOOR[0])
    return {"name": name, "kind": kind, "room": room, "centre_uv": [round(c.x, 3), round(c.y, 3)], "outward_uv": list(out),
            "width_m": width, "y0": round(y0, 3), "y1": round(y1, 3)}


def _walls_with_openings(plan: Plan, wall, openings, y0: float, y1: float, floor: float) -> list[np.ndarray]:
    holes = shapely.union_all([_opening_rect(o) for o in openings]) if openings else shapely.Polygon()
    tris = _prism_tris(plan, wall.difference(holes), y0, y1)
    for o in openings:
        piece = _opening_rect(o).intersection(wall)
        oy0, oy1 = _opening_y(o[1], floor)
        if oy0 > y0 + 1e-3:
            tris += _prism_tris(plan, piece, y0, oy0)
        if oy1 < y1 - 1e-3:
            tris += _prism_tris(plan, piece, oy1, y1)
    return tris


def _polys(geom) -> list:
    if geom.is_empty:
        return []
    if geom.geom_type == "Polygon":
        return [geom]
    return [g for g in getattr(geom, "geoms", []) if g.geom_type == "Polygon" and g.area > 1e-4]


def _prism_tris(plan: Plan, geom, y0: float, y1: float) -> list[np.ndarray]:
    from .landmarks import _side_tris, _cap_tris
    out = []
    for poly in _polys(geom):
        p = shapely.orient_polygons(plan.to_projected(poly))
        centre = _proj_centre(plan)
        out += _side_tris(p, centre, y0, y1) + _cap_tris(p, centre, y1, True) + _cap_tris(p, centre, y0, False)
    return out


def _cap(plan: Plan, geom, y: float, up: bool) -> list[np.ndarray]:
    from .landmarks import _cap_tris
    return [t for poly in _polys(geom) for t in _cap_tris(shapely.orient_polygons(plan.to_projected(poly)), _proj_centre(plan), y, up)]


def _box_tris(plan: Plan, u: float, v: float, size: tuple[float, float, float], y0: float) -> list[np.ndarray]:
    w, h, d = size
    return _prism_tris(plan, _rect(u - w / 2, v - d / 2, u + w / 2, v + d / 2), y0, y0 + h)


def _ramp(plan: Plan, top: tuple[float, float], foot: tuple[float, float], door, foot_rel_y: float,
          floor: float) -> list[np.ndarray]:
    """Sloped slab from the ground at the foot up to the floor at the door sill."""
    du, dv = door[5]
    side = np.array([-dv, du]) * (DOOR[0] / 2 + 0.1)
    corners = [np.array(foot) - side, np.array(foot) + side, np.array(top) + side, np.array(top) - side]
    pts = []
    for (u, v), y in zip(corners, [foot_rel_y, foot_rel_y, floor, floor]):
        x, z = plan.to_local_xz(u, v)
        pts.append(np.array([x, y, z]))
    base = [np.array([p[0], min(foot_rel_y, floor) - 0.3, p[2]]) for p in pts]
    mid = np.mean(pts + base, axis=0)
    tris = [_facing(np.array([pts[0], pts[1], pts[2]]), np.array([0.0, 1.0, 0.0])),
            _facing(np.array([pts[0], pts[2], pts[3]]), np.array([0.0, 1.0, 0.0]))]
    for k in range(4):
        j = (k + 1) % 4
        for t in (np.array([base[k], base[j], pts[j]]), np.array([base[k], pts[j], pts[k]])):
            tris.append(_facing(t, t.mean(axis=0) - mid))
    return tris


def _facing(t: np.ndarray, out: np.ndarray) -> np.ndarray:
    """Winds a triangle so its normal points along out (collision faces are one-sided)."""
    n = np.cross(t[1] - t[0], t[2] - t[0])
    return t if float(np.dot(n, out)) > 0 else t[[0, 2, 1]]


def _proj_centre(plan: Plan) -> np.ndarray:
    oe, on = frame.origin()
    return np.array([plan.c[0] + oe, on - plan.c[1]])


def _mesh_dict(tris: list[np.ndarray], material: str) -> dict:
    from .landmarks import _mesh
    return dict(_mesh(tris), material=material)

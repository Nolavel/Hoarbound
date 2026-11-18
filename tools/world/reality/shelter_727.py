"""727 Fort Street as an enterable shelter: the permit-set walls, openings and a game clinic plan.

Walls, the entrance and the windows follow the 2020 permit set of Legistar 20-6136: the exterior outline
scaled from sheet A1.02 (area 342.4 m2 against the City record 343.1 m2), the openings from the A2.01
elevations. The outline is placed in the plan frame by best overlap with the measured OSM/lidar walls.
Rooms, partitions and furniture stay game-invented (owner 2026-11-18: game function over the clinic plan);
they hang on named layout lines, so a change of the outline moves them with their walls.

Plan frame: metres from the landmark origin, u along the long facade, v towards Fort Street.
In Godot a node at the landmark origin with Basis(UP, plan_yaw_rad) maps plan (u, v) to (x, z).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import shapely
import shapely.affinity

from . import frame

WALL_T = 0.25  # exterior wall (inferred masonry)
PART_T = 0.12  # interior stud partition (inferred)
FLOOR_ABOVE_GROUND_M = 0.1  # finished floor over the highest DEM ground inside the walls (inferred)
CEILING_CLEAR_M = 3.0  # suspended ceiling height above the floor (inferred)
DOOR = (1.5, 2.25)  # First Exit hut door standard: HingedDoor.opening_size
RAMP_RUN_M = 2.4  # Henry has no step-up; entries are ramps (hut EntryRamp), here about 1:7

## Exterior outline, A1.02 existing floor plan scaled by its bar (the printed dimensions are interior).
MAIN_L = 26.46  # main block along u
MAIN_D = 10.96  # main block along v
PROJ_W = 9.95  # Fort Street wing along u
PROJ_D = 5.27  # Fort Street wing past the main front
PROJ_LEFT = 7.50  # main block's west end to the wing's west face
## A2.01 elevations, metres along the main block from its west end (u = a + x) and over the ground.
WINDOW_Y = (1.06, 2.60)  # sill and head of every window
FRONT_GROUPS = ((7.70, 10.16), (11.24, 13.69), (14.79, 17.25))  # three storefront groups on the wing front
NARROW_WEST = ((3.25, 3.82), (4.80, 5.37), (6.33, 6.91))  # narrow windows on the main front, west of the wing
NARROW_EAST = ((17.92, 18.49), (19.47, 20.04), (21.00, 21.58))  # and east of it
SIDE_WINDOW = (2.63, 2.47)  # wing's SE side: centre back from the wing front, width (A2.01 SE elevation)
ENTRANCE_FROM_MAIN_FRONT = 2.78  # storefront entrance on the wing's NW side, centre past the main front (A2.01 NW)
## A2.01 NW: the entrance is an 8'-0" x 8'-0" double storefront door. The leaf towards Fort Street opens (hinged on
## its outer jamb); the other leaf is fixed glass.
STOREFRONT = (8.0 * 0.3048, 8.0 * 0.3048)


@dataclass(frozen=True)
class Layout:
    """The permit outline at plan offset (a, front): a is the main block's west face, front its Fort Street face."""
    a: float
    front: float

    def outline(self) -> shapely.Polygon:
        a, f, w0, w1 = self.a, self.front, self.a + PROJ_LEFT, self.a + PROJ_LEFT + PROJ_W
        return shapely.orient_polygons(shapely.Polygon([(a, f - MAIN_D), (a + MAIN_L, f - MAIN_D), (a + MAIN_L, f), (w1, f),
                                                        (w1, f + PROJ_D), (w0, f + PROJ_D), (w0, f), (a, f)]))

    def faces(self) -> dict[str, float]:
        """Outer wall faces, same keys as lines()."""
        a, f = self.a, self.front
        return {"W": a, "E": a + MAIN_L, "B": f - MAIN_D, "F": f, "PW": a + PROJ_LEFT, "PE": a + PROJ_LEFT + PROJ_W, "P": f + PROJ_D}

    def lines(self) -> dict[str, float]:
        """Inner wall faces: W/E main ends, B back, F main front, PW/PE wing sides, P wing front."""
        a, f = self.a, self.front
        return {"W": a + WALL_T, "E": a + MAIN_L - WALL_T, "B": f - MAIN_D + WALL_T, "F": f - WALL_T,
                "PW": a + PROJ_LEFT + WALL_T, "PE": a + PROJ_LEFT + PROJ_W - WALL_T, "P": f + PROJ_D - WALL_T}


def fit_layout(walls_plan) -> Layout:
    """The permit outline placed by best overlap (2 cm steps) with the measured walls in the plan frame."""
    best = None
    b = walls_plan.bounds
    for a in np.arange(b[0] - 0.8, b[0] + 0.8, 0.02):
        for f in np.arange(b[1] + MAIN_D - 1.2, b[1] + MAIN_D + 1.2, 0.02):
            p = Layout(round(float(a), 2), round(float(f), 2)).outline()
            iou = p.intersection(walls_plan).area / p.union(walls_plan).area
            if best is None or iou > best[0]:
                best = (iou, Layout(round(float(a), 2), round(float(f), 2)))
    return best[1]


def _at(x, lines: dict) -> float:
    return lines[x] if isinstance(x, str) else float(x)


## Game rooms: corridor between v = -1.6 and 0.2, rooms behind it, the wing and side rooms in front.
## Coordinates are plan metres or layout line names (Layout.lines).
ROOMS = [
    ("dental", "Dental operatory", ("W", "B", -7.0, -1.6)),
    ("exam_1", "Exam room 1", (-7.0, "B", -2.0, -1.6)),
    ("exam_2", "Exam room 2", (-2.0, "B", 3.0, -1.6)),
    ("pharmacy", "Lab / pharmacy", (3.0, "B", 8.3, -1.6)),
    ("storage", "Storage", (8.3, "B", "E", -1.6)),
    ("corridor", "Corridor", ("W", -1.6, "E", 0.2)),
    ("restroom_w", "Restroom", ("W", 0.2, -9.3, "F")),
    ("restroom_e", "Restroom", (-9.3, 0.2, "PW", "F")),
    ("waiting", "Waiting room (heated shelter)", ("PW", 0.2, "PE", "P")),
    ("lobby", "Lobby / reception (heated shelter)", ("PE", 0.2, 9.0, "F")),
    ("office", "Office", (9.0, 0.2, "E", "F")),
]
HEATED = ("waiting", "lobby")
PARTITIONS = [  # (axis, at, from, to): a wall line in plan, clipped to the interior
    ("v", -1.6, "W", "E"), ("v", 0.2, "W", "E"),
    ("u", -7.0, "B", -1.6), ("u", -2.0, "B", -1.6), ("u", 3.0, "B", -1.6), ("u", 8.3, "B", -1.6),
    ("u", -9.3, 0.2, "F"), ("u", "PW", 0.2, "F"), ("u", "PE", 0.2, "F"), ("u", 9.0, 0.2, "F"),
]
## Interior openings: (name, kind, axis, wall line, centre along it, outward (du, dv), room).
INTERIOR_OPENINGS = [
    ("LobbyArch", "arch", "u", "PE", 1.6, (1, 0), "waiting"),
    ("WaitingDoor", "doorway", "v", 0.2, -1.0, (0, -1), "waiting"),
    ("RestroomWDoor", "doorway", "v", 0.2, -11.1, (0, -1), "restroom_w"),
    ("RestroomEDoor", "doorway", "v", 0.2, -7.5, (0, -1), "restroom_e"),
    ("OfficeDoor", "doorway", "v", 0.2, 11.3, (0, -1), "office"),
    ("DentalDoor", "doorway", "v", -1.6, -10.0, (0, 1), "dental"),
    ("Exam1Door", "doorway", "v", -1.6, -4.5, (0, 1), "exam_1"),
    ("Exam2Door", "doorway", "v", -1.6, 0.5, (0, 1), "exam_2"),
    ("PharmacyDoor", "doorway", "v", -1.6, 5.6, (0, 1), "pharmacy"),
    ("StorageDoor", "doorway", "v", -1.6, 11.0, (0, 1), "storage"),
]
## Furniture: (node, kind, room, (room edge u0|u1, offset), (room edge v0|v1, offset), yaw_deg, size (w, h, d) or None).
## Offsets keep each piece at its wall when the outline changes. Hut kinds reuse the First Exit hut nodes.
FURNITURE = [
    ("Stove", "hut_stove", "waiting", ("u0", 4.44), ("v1", -3.67), 0, None),
    ("Mattress", "hut_mattress", "waiting", ("u0", 1.24), ("v1", -2.47), 0, None),
    ("RestCrate", "hut_rest_crate", "waiting", ("u1", -2.56), ("v0", 4.4), 0, None),
    ("Cabinet", "hut_cabinet", "waiting", ("u0", 0.56), ("v1", -0.75), 180, None),  # west wall, between the entrance and the front
    ("ToolBench", "hut_tool_bench", "storage", ("u0", 2.3), ("v0", 0.96), 0, None),
    ("SupplyBench", "hut_supply_bench", "storage", ("u1", -1.06), ("v1", -1.4), 90, None),
    ("ReceptionCounter", "counter", "lobby", ("u1", -0.85), ("v0", 1.4), 0, (0.6, 1.05, 2.2)),
    ("WaitingBenchWest", "bench", "waiting", ("u0", 0.54), ("v0", 4.0), 0, (0.5, 0.45, 2.4)),
    ("WaitingBenchFront", "bench", "waiting", ("u1", -4.46), ("v1", -0.47), 90, (0.5, 0.45, 2.4)),
    ("ExamTable1", "exam_table", "exam_1", ("u0", 2.5), ("v0", 1.16), 90, (0.7, 0.8, 1.9)),
    ("ExamTable2", "exam_table", "exam_2", ("u0", 2.5), ("v0", 1.16), 90, (0.7, 0.8, 1.9)),
    ("ExamDesk1", "desk", "exam_1", ("u0", 0.7), ("v1", -1.4), 0, (0.6, 0.75, 1.2)),
    ("ExamDesk2", "desk", "exam_2", ("u0", 0.7), ("v1", -1.4), 0, (0.6, 0.75, 1.2)),
    ("DentalChair", "dental_chair", "dental", ("u0", 2.95), ("v0", 1.96), 90, (0.8, 0.9, 1.9)),
    ("DentalCart", "cart", "dental", ("u1", -1.2), ("v0", 0.96), 0, (0.5, 0.9, 0.6)),
    ("PharmacyShelf", "shelf", "pharmacy", ("u0", 2.6), ("v0", 0.36), 90, (0.4, 2.0, 3.6)),
    ("LabCounter", "counter", "pharmacy", ("u1", -0.45), ("v0", 2.46), 0, (0.6, 0.95, 2.4)),
    ("StorageShelf", "shelf", "storage", ("u1", -0.41), ("v0", 0.96), 0, (0.45, 2.0, 1.6)),
    ("OfficeDesk", "desk", "office", ("u0", 2.3), ("v1", -0.76), 90, (0.7, 0.75, 1.5)),
    ("ToiletW", "toilet", "restroom_w", ("u0", 0.55), ("v1", -0.66), 0, (0.45, 0.8, 0.7)),
    ("SinkW", "sink", "restroom_w", ("u1", -0.5), ("v1", -0.46), 0, (0.5, 0.85, 0.45)),
    ("ToiletE", "toilet", "restroom_e", ("u1", -0.56), ("v1", -0.66), 0, (0.45, 0.8, 0.7)),
    ("SinkE", "sink", "restroom_e", ("u0", 0.5), ("v1", -0.46), 0, (0.5, 0.85, 0.45)),
    ## Searchable furniture (FurnitureKit), its back 1 cm off the wall it stands on (the chest 14 cm, room for its lid).
    ("KitchenCupboard", "kitchen_cupboard", "waiting", ("u0", 2.04), ("v0", 0.245), 0, None),
    ("Dresser", "dresser", "waiting", ("u0", 0.295), ("v0", 1.4), 90, None),
    ("Chest", "chest", "waiting", ("u1", -0.365), ("v0", 4.2), -90, None),
    ## On the corridor wall of the waiting room, beside the lobby arch, read from the stove.
    ("WallThermometer", "wall_thermometer", "waiting", ("u1", -0.86), ("v0", 0.062), 0, None),
]
MOUNT_H = {"WallThermometer": 1.7}  # wall fixtures: height of the mount above the floor
GAME_INVENTED = ("rooms, partitions and furniture are game-invented (owner 2026-11-18: game function over the clinic plan); "
                 "walls, the entrance and the windows follow the 2020 permit set (Legistar 20-6136, A1.02 and A2.01)")


@dataclass(frozen=True)
class Opening:
    """A door, window, arch or doorway: the wall line it cuts (axis u or v at `at`) and its span along it."""
    name: str
    kind: str
    axis: str
    at: float
    along: float
    outward: tuple
    room: str
    width: float
    y0: float | None = None  # over the landmark ground; None: from the floor (doors, arches, doorways)
    y1: float | None = None
    height: float | None = None  # from the floor, when y0 is None; None: the door standard


def rooms(lay: Layout) -> list[tuple[str, str, tuple]]:
    """(id, label, (u0, v0, u1, v1)) in plan metres."""
    lines = lay.lines()
    return [(rid, label, tuple(round(_at(x, lines), 3) for x in r)) for rid, label, r in ROOMS]


def partitions(lay: Layout) -> list[tuple]:
    lines = lay.lines()
    return [(axis, _at(at, lines), _at(a, lines), _at(b, lines)) for axis, at, a, b in PARTITIONS]


def openings(lay: Layout) -> list[Opening]:
    """Exterior openings from the 2020 permit set, then the game's interior ones."""
    a, f = lay.a, lay.front
    wing_w, wing_e, wing_f = a + PROJ_LEFT, a + PROJ_LEFT + PROJ_W, f + PROJ_D
    mid = WALL_T / 2
    sw, sh = STOREFRONT
    entrance = f + ENTRANCE_FROM_MAIN_FRONT
    out = [Opening("MainDoor", "door", "u", wing_w + mid, entrance + sw / 4, (-1, 0), "waiting", sw / 2, height=sh),
           Opening("EntranceFixedLeaf", "window", "u", wing_w + mid, entrance - sw / 4, (-1, 0), "waiting", sw / 2, height=sh)]
    for k, (x0, x1) in enumerate(FRONT_GROUPS, 1):
        out.append(Opening(f"FrontWindow{k}", "window", "v", wing_f - mid, a + (x0 + x1) / 2, (0, 1), "waiting", x1 - x0, *WINDOW_Y))
    out.append(Opening("SideWindowEast", "window", "u", wing_e - mid, wing_f - SIDE_WINDOW[0], (1, 0), "waiting", SIDE_WINDOW[1], *WINDOW_Y))
    rooms_by_u = [("restroom_w", "restroom_e", -9.3), ("lobby", "office", 9.0)]
    for side, spans, (low, high, split) in (("W", NARROW_WEST, rooms_by_u[0]), ("E", NARROW_EAST, rooms_by_u[1])):
        for k, (x0, x1) in enumerate(spans, 1):
            u = a + (x0 + x1) / 2
            out.append(Opening(f"NarrowWindow{side}{k}", "window", "v", f - mid, u, (0, 1), low if u < split else high, x1 - x0, *WINDOW_Y))
    lines = lay.lines()
    for name, kind, axis, at, along, outward, room in INTERIOR_OPENINGS:
        out.append(Opening(name, kind, axis, _at(at, lines), along, outward, room, 2.2 if kind == "arch" else DOOR[0]))
    return out


def opening(name: str, lay: Layout) -> Opening:
    return next(o for o in openings(lay) if o.name == name)


def furniture(lay: Layout) -> list[dict]:
    """Furniture in plan metres, each piece placed from the room edge it is anchored to."""
    rects = {rid: r for rid, _, r in rooms(lay)}
    out = []
    for node, kind, room, (eu, du), (ev, dv), yaw, size in FURNITURE:
        u0, v0, u1, v1 = rects[room]
        u = (u0 if eu == "u0" else u1) + du
        v = (v0 if ev == "v0" else v1) + dv
        item = {"node": node, "kind": kind, "room": room, "uv": [round(u, 3), round(v, 3)], "yaw_deg": yaw,
                "size": list(size) if size else None}
        if node in MOUNT_H:
            item["h"] = MOUNT_H[node]
        out.append(item)
    return out


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
        self.measured = self.to_plan(wl)
        self.layout = fit_layout(self.measured)
        self.walls = self.layout.outline()

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


def _opening_rect(o: Opening) -> shapely.Polygon:
    """The opening's cut through its wall line (0.45 m either side covers any wall thickness)."""
    lo, hi = o.along - o.width / 2, o.along + o.width / 2
    return _line_rect(o.axis, o.at, lo, hi, 0.45) if o.axis == "v" else _rect(o.at - 0.45, lo, o.at + 0.45, hi)


def _opening_y(o: Opening, floor: float) -> tuple[float, float]:
    """Sill and head over the landmark ground: windows as drawn, doors and passages from the floor."""
    if o.y0 is not None:
        return o.y0, o.y1
    return floor, floor + (o.height or DOOR[1])


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
    lay = plan.layout
    floor = floor_height(plan, origin_y, ground_at)
    ceiling = floor + CEILING_CLEAR_M
    inner = plan.walls.buffer(-WALL_T, join_style="mitre")
    shell = plan.walls.difference(inner)
    strips = shapely.union_all([_line_rect(a, at, lo, hi, PART_T / 2) for a, at, lo, hi in partitions(lay)])
    parts = strips.intersection(inner)
    all_open = openings(lay)
    ext_open = [o for o in all_open if o.kind in ("door", "window")]
    int_open = [o for o in all_open if o.kind not in ("door", "window")]
    for o in all_open:
        if not _opening_rect(o).intersects(shell if o in ext_open else parts):
            raise SystemExit(f"727 opening {o.name} misses its wall")
    shell_tris = _walls_with_openings(plan, shell, ext_open, -0.3, wall_top, floor)
    part_tris = _walls_with_openings(plan, parts, int_open, floor, ceiling, floor)
    glass = []
    for o in ext_open:
        if o.kind == "window":
            y0, y1 = _opening_y(o, floor)
            pane = _opening_rect(o).intersection(shell).centroid
            glass += _box_tris(plan, pane.x, pane.y, (0.02, y1 - y0, o.width) if o.axis == "u" else (o.width, y1 - y0, 0.02), y0)
    door = opening("MainDoor", lay)
    du, dv = door.outward
    ## The ramp serves the whole storefront, centred on it, not on the opening leaf.
    out_edge = (door.at + du * WALL_T / 2, lay.front + ENTRANCE_FROM_MAIN_FRONT)
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
    room_rects = rooms(lay)
    spec = {
        "recon": "permit_set_walls_and_openings_game_rooms", "note": GAME_INVENTED,
        "plan_yaw_rad": round(plan.godot_yaw(), 6), "plan_frame": "u along the long facade, v towards Fort Street",
        "layout": {"a": lay.a, "front": lay.front, "lines": {k: round(v, 3) for k, v in lay.lines().items()},
                   "faces": {k: round(v, 3) for k, v in lay.faces().items()},
                   "fit": "permit outline placed by best overlap with the measured walls",
                   "fit_iou": round(plan.walls.intersection(plan.measured).area / plan.walls.union(plan.measured).area, 3)},
        "floor_y": floor, "floor_method": "max DEM ground inside the walls + %.2f m" % FLOOR_ABOVE_GROUND_M,
        "ceiling_y": round(ceiling, 3), "wall_thickness_m": WALL_T, "partition_thickness_m": PART_T,
        "door_standard": {"width_m": DOOR[0], "height_m": DOOR[1], "source": "First Exit hut HingedDoor.opening_size (interior doors)"},
        "entrance": {"storefront_m": [round(STOREFRONT[0], 3), round(STOREFRONT[1], 3)], "active_leaf": "MainDoor",
                     "fixed_leaf": "EntranceFixedLeaf", "hinge": "outer jamb, towards Fort Street",
                     "source": "A2.01 NW elevation, double storefront door 8'-0\" x 8'-0\", dark bronze anodized"},
        "window_source": "A2.01 elevations (2020 permit): sill %.2f m, head %.2f m over the ground" % WINDOW_Y,
        "rooms": [{"id": rid, "name": label, "rect_uv": list(r), "heated": rid in HEATED,
                   "area_m2": round(_rect(*r).intersection(inner).area, 1)} for rid, label, r in room_rects],
        "openings": [_opening_spec(o, shell if o in ext_open else parts, floor) for o in all_open],
        "entry_ramp": {"from_uv": [round(foot[0], 3), round(foot[1], 3)], "to_uv": [round(out_edge[0], 3), round(out_edge[1], 3)],
                       "foot_y_navd88": round(foot_y, 3), "top_y": floor},
        "furniture": furniture(lay),
        "outline_uv": [[round(x, 3), round(y, 3)] for x, y in plan.walls.exterior.coords[:-1]],
    }
    rects = {rid: r for rid, _, r in room_rects}
    for f in spec["furniture"]:
        if not _rect(*rects[f["room"]]).buffer(0.01).contains(shapely.Point(f["uv"])):
            raise SystemExit(f"727 furniture {f['node']} is outside room {f['room']}")
    return spec, nodes


def _opening_spec(o: Opening, wall, floor: float) -> dict:
    c = _opening_rect(o).intersection(wall).centroid
    y0, y1 = _opening_y(o, floor)
    return {"name": o.name, "kind": o.kind, "room": o.room, "centre_uv": [round(c.x, 3), round(c.y, 3)], "outward_uv": list(o.outward),
            "width_m": round(o.width, 3), "y0": round(y0, 3), "y1": round(y1, 3)}


def _walls_with_openings(plan: Plan, wall, openings, y0: float, y1: float, floor: float) -> list[np.ndarray]:
    holes = shapely.union_all([_opening_rect(o) for o in openings]) if openings else shapely.Polygon()
    tris = _prism_tris(plan, wall.difference(holes), y0, y1)
    for o in openings:
        piece = _opening_rect(o).intersection(wall)
        oy0, oy1 = _opening_y(o, floor)
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
    du, dv = door.outward
    side = np.array([-dv, du]) * (STOREFRONT[0] / 2 + 0.1)
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

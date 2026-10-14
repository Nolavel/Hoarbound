"""First Exit gameplay sites on the Reality world (game-authored, derived from measured data).

  python3 tools/world/key_west_reality.py first-exit-sites

Writes data/world/key_west/reality/overrides/first_exit_gameplay.json for
scripts/world/key_west_reality_first_exit.gd. Nothing here is historical: the bunker door,
vent and loot are game objects. Where they go is read from the data: the door sits on the
fort's courtyard face fitted from the 2019 DSM; loot lies beside real buildings, the nearest
bus stop and the open-sea shore, never on a road or inside a footprint.
"""
from __future__ import annotations

import json

import numpy as np
import shapely
import shapely.ops

from . import frame, library, meshing, paths, receipts, vegetation

OUT = paths.OVERRIDES / "first_exit_gameplay.json"
LANDMARK_727 = "kw:building:osm:w339414849"
FORT = "kw:building:osm:w524088621"
## Owner start anchor (issue #211): the door is placed on the face nearest this x.
START_X = -4052.73
FACE_SEARCH_Z = (1900.0, 1935.0)
FACE_FIT_HALF_M = 14.0
FACE_RISE_M = 2.0
FACE_MAX_RMS_M = 0.6
## First Exit bunker template: block 9 x 6 x 7 m centred on the portal, door on its +Z face,
## wing walls 2 m out. The block's front stands this far proud of the measured face.
BLOCK_HALF_DEPTH_M = 3.5
PROUD_M = 0.3
WING_M = 2.0
SPAWN_PAST_WINGS_M = 1.5
VENT_BEHIND_M = 1.5
VENT_SIDE_M = 4.0
PICKUP_LIFT_M = 0.35
WALL_GAP_M = 0.9
PICKUP_CLEAR_M = 0.5
SHORE_BAND_M = (0.3, 1.2)
OPEN_SEA_PROBE_M = 60.0
MSL_Y = -0.265
## 727 interior sockets (game-authored, plan u/v metres, h above the finished floor). A pickup's
## origin is the bottom of its visual, so h is the surface it rests on (bench tops 0.80 m). Board
## stacks (1.7 m planks along local x) turn 90 degrees to lie along the storage room's west wall.
SHELTER_SOCKETS = {
    "BoardsShelterInside": ("storage", 8.6, -5.6, 0.0, 90), "BoardsShelterTest1": ("storage", 8.95, -5.6, 0.0, 90),
    "BoardsShelterTest2": ("storage", 9.3, -5.6, 0.0, 90), "BoardsShelterTest3": ("storage", 8.6, -3.4, 0.0, 90),
    "BoardsShelterTest4": ("storage", 8.95, -3.4, 0.0, 90), "BoardsShelterTest5": ("storage", 9.3, -3.4, 0.0, 90),
    "BoardsShelterTest6": ("storage", 9.65, -3.4, 0.0, 90),
    "HammerShelter": ("storage", 9.95, -5.6, 0.80, 0), "NailsShelter": ("storage", 10.35, -5.6, 0.80, 0),
    "LighterShelterTest": ("storage", 10.75, -5.6, 0.80, 0), "KnifeShelterTest": ("storage", 11.1, -5.6, 0.80, 0),
    "AxeShelterTest": ("storage", 11.4, -5.6, 0.80, 0),
    "StewShelterTest": ("storage", 12.6, -3.6, 0.80, 0), "FlaskShelterTest": ("storage", 12.6, -3.0, 0.80, 0),
    "PineappleShelterTest": ("storage", 12.6, -2.4, 0.80, 0),
    "FirewoodShelter": ("lobby", 4.3, 2.3, 0.0, 0), "RoadFlareShelterTest": ("lobby", 8.15, 1.2, 1.05, 0),
    "BedrollShelterTest": ("office", 12.9, 1.0, 0.0, 0),
}
## Hut furniture that is not in the spec's sized list: (u, v, half_u, half_v, top) in plan space.
HUT_TOPS = {"ToolBench": (0.95, 0.325, 0.80), "SupplyBench": (0.325, 0.95, 0.80)}
## Outside the office front facade (plan v = 3.08), clear of the entry ramp at u = 6.23.
SHELTER_YARD = {"BoardsShelterYard": (8.8, 4.7), "FirewoodShelterYard": (9.8, 4.7)}
SOCKET_MARGIN_M = 0.25


def run() -> dict:
    s = meshing.Surfaces()
    oe, on = frame.origin()
    clear = vegetation.Clearance(0.3)
    geoms, cols = library.read_layer("buildings")
    fids = list(cols["feature_id"])
    local = [frame.to_local(g) if g is not None else None for g in geoms]
    by_id = {fid: g for fid, g in zip(fids, local)}
    houses = [(fid, g) for fid, g in zip(fids, local) if g is not None and fid not in (FORT, LANDMARK_727)]
    solid = shapely.STRtree([g for g in local if g is not None])

    def ground(x: float, z: float) -> float:
        return float(s.ground_at(np.array([[x + oe, on - z]]))[0])

    def free(x: float, z: float) -> bool:
        pt = np.array([[x + oe, on - z]])
        return not clear.blocked(pt)[0] and not len(solid.query(shapely.Point(x, z).buffer(PICKUP_CLEAR_M), predicate="intersects"))

    def beside(g, toward: tuple[float, float], gap: float = WALL_GAP_M) -> tuple[float, float] | None:
        """Free ground just outside the wall, on the wall stretch nearest `toward` that has room."""
        ring = g.exterior
        ref = shapely.Point(*toward)
        walls = sorted((ring.interpolate(k).distance(ref), k) for k in np.arange(0.0, ring.length, 0.5))
        for _, k in walls:
            a, b = ring.interpolate(k), ring.interpolate(min(k + 0.25, ring.length))
            d = np.array([b.y - a.y, a.x - b.x])
            d /= max(np.linalg.norm(d), 1e-6)
            if g.contains(shapely.Point(a.x + d[0] * 0.2, a.y + d[1] * 0.2)):
                d = -d
            for step in (gap, gap + 0.6):
                q = (a.x + d[0] * step, a.y + d[1] * step)
                if free(*q):
                    return q
        return None

    def site(point, pred, k: int = 0) -> tuple[str, object, tuple[float, float]]:
        """k-th building (by distance to point) matching pred that has free ground beside it."""
        p = shapely.Point(*point)
        ranked = sorted((g.distance(p), fid, g) for fid, g in houses if pred(fid, g) and g.distance(p) < 400.0)
        found = []
        for _, fid, g in ranked:
            q = beside(g, point)
            if q is not None:
                found.append((fid, g, q))
                if len(found) > k:
                    return found[k]
        raise SystemExit(f"fewer than {k + 1} usable buildings near {point}")

    face = _fit_face(s, oe, on)
    door = np.array([START_X, face["a"] + face["b"] * START_X])
    n = np.array([face["b"], -1.0])
    n /= np.linalg.norm(n)
    t = np.array([n[1], -n[0]])
    door_y = float(np.median([ground(*(door + n * k)) for k in (1.0, 2.0, 3.0, 4.0, 5.0, 6.0)]))
    portal = door + n * (PROUD_M - BLOCK_HALF_DEPTH_M)
    spawn = door + n * (PROUD_M + WING_M + SPAWN_PAST_WINGS_M)
    vent = door - n * VENT_BEHIND_M + t * VENT_SIDE_M
    vent_top = _dsm_at(s, oe, on, vent)
    yaw = float(np.arctan2(n[0], n[1]))
    fort = by_id[FORT]
    shelter = by_id[LANDMARK_727]
    sc = shelter.centroid
    sxz = (sc.x, sc.y)
    pickups: dict[str, dict] = {}

    def put(name: str, xz: tuple[float, float], site: str, fid: str, why: str) -> None:
        if not free(*xz):
            raise SystemExit(f"{name}: {xz} is on a road or inside a building")
        pickups[name] = {"xz": [round(xz[0], 2), round(xz[1], 2)], "y": round(ground(*xz) + PICKUP_LIFT_M, 2),
                         "site": site, "feature_id": fid, "reason": why}

    in_fort = lambda f, h: fort.convex_hull.contains(h.centroid)
    fid, g, q = site(tuple(door), in_fort)
    put("BoardsFort1", q, "fort_building", fid, "nearest building inside the fort with free ground beside it (template: fort store)")
    along = next((p for p in (_along_wall(g, q, m) for m in (2.0, -2.0, 1.0, -1.0)) if free(*p)), q)
    put("TinderFort", along, "fort_building", fid, "same wall, 2 m along (template keeps the pair together)")
    fid, g, q = site(tuple(door), lambda f, h: 8.0 <= h.area <= 60.0 and not in_fort(f, h))
    put("StewPatrolHut", q, "small_building_near_fort", fid, "hut-sized building (8-60 m2) nearest the bunker outside the fort")
    stop_xz, stop_id = _nearest_stop(sxz)
    road_side = np.array(stop_xz) - np.array(sxz)
    road_side /= np.linalg.norm(road_side)
    put("FirewoodBusStop", _first_free(free, stop_xz, -road_side), "bus_stop", stop_id, "mapped bus stop nearest 727, on its footway side")
    shore = _shore_point(s, oe, on, door, fort, free)
    put("StewBeachWreck", shore, "open_sea_shore", "noaa_dem_6366", "shore cell (0.3-1.2 m NAVD88) nearest the bunker with open sea 60 m out")
    house = lambda f, h: h.area > 40.0
    small = lambda f, h: h.area < 30.0
    fid, g, q = site(sxz, house, 0)
    put("BoardsNextDoor", q, "neighbour_building", fid, "building nearest 727 (template: next door)")
    fid, g, q = site(sxz, small, 0)
    put("FirewoodShelterOutbuilding", q, "outbuilding", fid, "outbuilding-sized building (<30 m2) nearest 727")
    along = next((p for p in (_along_wall(g, q, m) for m in (1.2, -1.2, 0.6, -0.6)) if free(*p)), q)
    put("BoardsShelterOutbuilding", along, "outbuilding", fid, "same outbuilding, 1.2 m along")
    fid, g, q = site(sxz, small, 1)
    put("FirewoodShedN1", q, "shed", fid, "second outbuilding-sized building nearest 727 (template: shed)")
    fid, g, q = site(sxz, house, 2)
    put("TinderCollapsedN3", q, "house", fid, "third building nearest 727 (template: collapsed house N3)")
    spec = json.loads((paths.REALITY / "landmarks" / "kw_727_fort_st.json").read_text(encoding="utf-8"))
    sockets = _shelter_sockets(spec["interior"])
    o = spec["origin_local"]
    yaw7 = float(spec["interior"]["plan_yaw_rad"])
    for name, (u, v) in SHELTER_YARD.items():
        x = o[0] + u * np.cos(yaw7) + v * np.sin(yaw7)
        z = o[2] - u * np.sin(yaw7) + v * np.cos(yaw7)
        put(name, (x, z), "727_yard", LANDMARK_727, "outside the 727 office front, beside the entry ramp")
    doc = {"schema": "kw_reality.first_exit_gameplay.v1", "built_at": receipts.now_utc(),
           "recon": "game_authored_override",
           "note": "Game objects on measured geometry. Battery Osceola has no separate footprint in any reachable "
                   "source; the bunker door is not a historical opening.",
           "frame": "local metres x east, z south, y NAVD88",
           "bunker": {"portal_xz": _r(portal), "door_xz": _r(door), "ground_y": round(door_y, 2), "yaw_rad": round(yaw, 4),
                      "face_fit": {"source": "noaa_lidar_9081 2019 DSM, courtyard face, DSM within FACE_RISE_M of the floor", "a": face["a"], "b": face["b"],
                                   "rms_m": face["rms"], "samples": face["samples"]}},
           "vent": {"xz": _r(vent), "base_y": round(vent_top, 2), "source": "DSM top of the casemate terrace behind the door"},
           "spawn": {"xz": _r(spawn), "y": round(ground(*spawn) + 0.15, 2), "yaw_rad": round(yaw, 4),
                     "source": "past the bunker wing walls, facing out of the door"},
           "pickups": pickups,
           "shelter_sockets": sockets}
    OUT.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"door": doc["bunker"]["door_xz"], "face_rms_m": face["rms"], "pickups": len(pickups)}))
    return doc


def _shelter_sockets(interior: dict) -> dict:
    """Validates the interior sockets: inside their room, and on top of any furniture they overlap."""
    rooms = {r["id"]: r["rect_uv"] for r in interior["rooms"]}
    boxes = []
    for f in interior["furniture"]:
        u, v = f["uv"]
        if f["node"] in HUT_TOPS:
            hu, hv, top = HUT_TOPS[f["node"]]
        elif f["size"]:
            sx, sy, sz = f["size"]
            swap = int(round(float(f["yaw_deg"]))) % 180 == 90
            hu, hv, top = (sz if swap else sx) / 2, (sx if swap else sz) / 2, sy
        else:
            continue
        boxes.append((f["node"], u - hu, v - hv, u + hu, v + hv, top))
    out = {}
    for name, (room, u, v, h, yaw) in SHELTER_SOCKETS.items():
        r = rooms[room]
        if not (r[0] + SOCKET_MARGIN_M <= u <= r[2] - SOCKET_MARGIN_M and r[1] + SOCKET_MARGIN_M <= v <= r[3] - SOCKET_MARGIN_M):
            raise SystemExit(f"socket {name} is outside room {room}")
        on = None
        for node, u0, v0, u1, v1, top in boxes:
            if u0 - 0.15 <= u <= u1 + 0.15 and v0 - 0.15 <= v <= v1 + 0.15:
                if not (u0 <= u <= u1 and v0 <= v <= v1 and top <= h <= top + 0.3):
                    raise SystemExit(f"socket {name} collides with {node}")
                on = node
        out[name] = {"room": room, "uv": [u, v], "h": h, "yaw_deg": yaw, "on": on}
    return out


def _r(p) -> list[float]:
    return [round(float(p[0]), 2), round(float(p[1]), 2)]


def _dsm_window(s, oe, on, x0, z0, x1, z1):
    dsm, _, t, *_ = s.dsm.window(x0 + oe, on - z1, x1 + oe, on - z0)
    return dsm, t


def _dsm_at(s, oe, on, p) -> float:
    dsm, t = _dsm_window(s, oe, on, p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2)
    return float(np.nanmedian(dsm))


def _fit_face(s, oe, on) -> dict:
    """Least-squares line z = a + b x through the courtyard edge of the south front.

    Each column is walked north from inside the mass; the face is where the DSM drops to
    within FACE_RISE_M of the courtyard floor (5th percentile of the column)."""
    z0, z1 = FACE_SEARCH_Z
    dsm, t = _dsm_window(s, oe, on, START_X - FACE_FIT_HALF_M - 1, z0, START_X + FACE_FIT_HALF_M + 1, z1)
    xs, zs = [], []
    for x in np.arange(START_X - FACE_FIT_HALF_M, START_X + FACE_FIT_HALF_M, 0.5):
        c = int((x + oe - t.c) / t.a)
        prof = [(z, dsm[int((on - z - t.f) / t.e), c]) for z in np.arange(z1 - 0.5, z0 + 0.5, -0.25)]
        floor = np.nanpercentile([h for _, h in prof], 5)
        for z, h in prof:
            if np.isfinite(h) and h < floor + FACE_RISE_M:
                xs.append(x)
                zs.append(z + 0.125)
                break
    xs, zs = np.array(xs), np.array(zs)
    keep = np.ones(len(xs), bool)
    for _ in range(3):
        b, a = np.polyfit(xs[keep], zs[keep], 1)
        res = np.abs(zs - (a + b * xs))
        keep = res < max(3.0 * np.median(res[keep]), 0.5)
    rms = float(np.sqrt(np.mean(res[keep] ** 2)))
    if rms > FACE_MAX_RMS_M:
        raise SystemExit(f"fort face fit rms {rms:.2f} m")
    return {"a": round(float(a), 3), "b": round(float(b), 4), "rms": round(rms, 2), "samples": int(keep.sum()),
            "rejected": int((~keep).sum())}


def _along_wall(g, q, metres: float) -> tuple[float, float]:
    ring = g.exterior
    d = ring.project(shapely.Point(*q))
    p = ring.interpolate((d + metres) % ring.length)
    base = ring.interpolate(d)
    off = np.array(q) - np.array([base.x, base.y])
    return (p.x + off[0], p.y + off[1])


def _first_free(free, origin, direction) -> tuple[float, float]:
    for step in np.arange(1.0, 8.0, 0.5):
        q = (origin[0] + direction[0] * step, origin[1] + direction[1] * step)
        if free(*q):
            return q
    raise SystemExit(f"no free ground near {origin}")


def _nearest_stop(xz) -> tuple[tuple[float, float], str]:
    geoms, cols = library.read_layer("street_furniture")
    best = None
    for g, fid, cls in zip(geoms, cols["feature_id"], cols["class"]):
        if g is None or cls != "stop":
            continue
        p = frame.to_local(g)
        d = p.distance(shapely.Point(*xz))
        if best is None or d < best[0]:
            best = (d, (p.x, p.y), fid)
    return best[1], best[2]


def _shore_point(s, oe, on, door, fort, free) -> tuple[float, float]:
    """Nearest dry shore cell to the door facing open sea: every sample of a 60 m seaward probe
    is measured water (below MSL and not a filled DEM void), which rules out the fort moat."""
    xs = np.arange(door[0] - 400, door[0] + 400, 2.0)
    zs = np.arange(door[1] - 400, door[1] + 400, 2.0)
    gx, gz = np.meshgrid(xs, zs)
    pts = np.column_stack([gx.ravel() + oe, on - gz.ravel()])
    g = s.ground_at(pts).reshape(gx.shape)
    lo, hi = SHORE_BAND_M

    def wet(x: np.ndarray, z: np.ndarray) -> np.ndarray:
        q = np.column_stack([x + oe, on - z])
        t = s.dem.transform
        cols = np.clip(((q[:, 0] - t.c) / t.a).astype(int), 0, s.void.shape[1] - 1)
        rows = np.clip(((q[:, 1] - t.f) / t.e).astype(int), 0, s.void.shape[0] - 1)
        return (s.ground_at(q) < MSL_Y) & ~s.void[rows, cols]

    order = np.argsort(np.hypot(gx - door[0], gz - door[1]), axis=None)
    for k in order:
        r, c = np.unravel_index(k, gx.shape)
        if not (lo <= g[r, c] <= hi) or fort.convex_hull.buffer(10.0).contains(shapely.Point(gx[r, c], gz[r, c])):
            continue
        for ang in np.arange(0.0, 2 * np.pi, np.pi / 8):
            d = np.array([np.cos(ang), np.sin(ang)])
            steps = np.arange(4.0, OPEN_SEA_PROBE_M + 0.1, 4.0)
            if wet(gx[r, c] + d[0] * steps, gz[r, c] + d[1] * steps).all():
                q = (float(gx[r, c] - d[0] * 3.0), float(gz[r, c] - d[1] * 3.0))
                if free(*q):
                    return q
    raise SystemExit("no open-sea shore within 400 m of the bunker")

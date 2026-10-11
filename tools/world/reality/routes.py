"""Walkable test routes over the Reality Library (game data, not reality).

  python3 tools/world/key_west_reality.py route-gate

Writes data/world/key_west/reality/routes/first_exit_gate.json: waypoints in local metres for
tools/runtime/gate_key_west_reality.gd. Legs are least-cost paths on a 2 m grid: buildings,
water and the 727 walls block, mapped roads are cheaper than yards, so Henry walks streets.
"""
from __future__ import annotations

import json

import numpy as np
import pyogrio
import shapely
import shapely.ops
from scipy import ndimage, sparse
from scipy.sparse.csgraph import dijkstra

from . import frame, library, meshing, paths, receipts

OUT = paths.REALITY / "routes" / "first_exit_gate.json"
CELL_M = 2.0
PAD_M = 160.0
MSL_Y = -0.265
COST_ROAD = 1.0
COST_OPEN = 2.5
BUILDING_CLEARANCE_M = 0.8
LANDMARK_727 = "kw:building:osm:w339414849"
## Owner-decided start (issue #211) and the Old Town loop as street crossings, in walking order.
LEGS = [("727_fort_st_entrance", None), ("fort_x_petronia", ("Fort Street", "Petronia Street")),
        ("petronia_x_duval", ("Petronia Street", "Duval Street")), ("duval_x_front", ("Duval Street", "Front Street")),
        ("front_x_whitehead", ("Front Street", "Whitehead Street")), ("whitehead_x_petronia", ("Whitehead Street", "Petronia Street")),
        ("727_fort_st_return", None)]


def run() -> dict:
    s = meshing.Surfaces()
    lm = json.loads((paths.REALITY / "landmarks" / "kw_727_fort_st.json").read_text(encoding="utf-8"))
    spawn = _spawn_point()
    streets = _streets()
    goals = [("battery_osceola_start", spawn)]
    entrance = _entrance(streets["Fort Street"])
    for name, cross in LEGS:
        goals.append((name, entrance if cross is None else _crossing(streets[cross[0]], streets[cross[1]])))
    xs = [p[0] for _, p in goals]
    zs = [p[1] for _, p in goals]
    x0, z0 = min(xs) - PAD_M, min(zs) - PAD_M
    nx, nz = int((max(xs) + PAD_M - x0) / CELL_M) + 1, int((max(zs) + PAD_M - z0) / CELL_M) + 1
    cost = _cost_grid(s, x0, z0, nx, nz)
    graph = _graph(cost)
    points, legs = [], []
    for (a_name, a), (b_name, b) in zip(goals, goals[1:]):
        path = _shortest(graph, cost, a, b, x0, z0, nx)
        if path is None:
            raise SystemExit(f"no walkable path {a_name} -> {b_name}")
        simplified = shapely.LineString(path).simplify(1.0)
        pts = [[round(x, 2), round(z, 2)] for x, z in simplified.coords]
        legs.append({"from": a_name, "to": b_name, "length_m": round(simplified.length, 1), "first_point": len(points)})
        points.extend(pts if not points else pts[1:])
    doc = {"schema": "kw_reality.gate_route.v1", "built_at": receipts.now_utc(), "kind": "game_test_route (not reality)",
           "frame": "local metres x east, z south", "cell_m": CELL_M, "spawn_local": [round(spawn[0], 2), round(spawn[1], 2)],
           "goals": [{"name": n, "xz": [round(p[0], 2), round(p[1], 2)]} for n, p in goals],
           "legs": legs, "length_m": round(sum(leg["length_m"] for leg in legs), 1), "points": points,
           "landmark_727_roof_navd88_m": lm["elements"]["roof_top_navd88_m"]["value"]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"length_m": doc["length_m"], "legs": [(leg["to"], leg["length_m"]) for leg in legs], "points": len(points)}))
    return doc


def _spawn_point() -> tuple[float, float]:
    text = (paths.ROOT / "scenes/world/key_west/key_west_reality_content.tscn").read_text(encoding="utf-8")
    nums = text.split("Transform3D(")[1].split(")")[0].split(",")
    return float(nums[9]), float(nums[11])


def _streets() -> dict:
    geoms, cols = library.read_layer("roads")
    out: dict[str, list] = {}
    for g, name in zip(geoms, cols["name"]):
        if name:
            out.setdefault(name, []).append(frame.to_local(g))
    return {k: shapely.union_all(v) for k, v in out.items()}


def _crossing(a, b) -> tuple[float, float]:
    inter = a.intersection(b)
    if inter.is_empty:
        p, q = shapely.ops.nearest_points(a, b)
        return ((p.x + q.x) / 2, (p.y + q.y) / 2)
    c = inter.centroid
    return (c.x, c.y)


def _entrance(fort_street) -> tuple[float, float]:
    """Point 2.5 m outside the 727 wall that faces Fort Street (no opening is modelled)."""
    meta, _, geoms, _ = pyogrio.raw.read(paths.LIBRARY, layer="buildings", where=f"feature_id='{LANDMARK_727}'")
    fp = frame.to_local(shapely.from_wkb(geoms[0]))
    p_wall, _ = shapely.ops.nearest_points(fp.exterior, fort_street)
    c = fp.centroid
    d = np.array([p_wall.x - c.x, p_wall.y - c.y])
    d /= np.linalg.norm(d)
    return (p_wall.x + d[0] * 2.5, p_wall.y + d[1] * 2.5)


def _cost_grid(s: meshing.Surfaces, x0: float, z0: float, nx: int, nz: int) -> np.ndarray:
    gx, gz = np.meshgrid(x0 + (np.arange(nx) + 0.5) * CELL_M, z0 + (np.arange(nz) + 0.5) * CELL_M)
    oe, on = frame.origin()
    ground = s.ground_at(np.column_stack([gx.ravel() + oe, on - gz.ravel()])).reshape(nz, nx)
    cost = np.full((nz, nx), COST_OPEN)
    box = shapely.box(x0, z0, x0 + nx * CELL_M, z0 + nz * CELL_M)
    roads, _ = library.read_layer("roads")
    road_mask = shapely.contains_xy(shapely.union_all([frame.to_local(g).buffer(3.0) for g in roads]).intersection(box), gx, gz)
    cost[road_mask] = COST_ROAD
    bgeoms, _ = library.read_layer("buildings")
    blocks = [frame.to_local(g).buffer(BUILDING_CLEARANCE_M) for g in bgeoms]
    blocks = [b for b in blocks if b.intersects(box)]
    blocked = shapely.contains_xy(shapely.union_all(blocks), gx, gz) | (ground < MSL_Y)
    cost[blocked] = np.inf
    return cost


def _graph(cost: np.ndarray):
    """8-connected grid graph; edge weight = mean cell cost times step length."""
    nz, nx = cost.shape
    flat = cost.ravel()
    rows, cols, vals = [], [], []
    for dz, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        i, j = np.mgrid[0:nz - dz, max(0, -dx):nx - max(0, dx)]
        src = (i * nx + j).ravel()
        dst = src + dz * nx + dx
        w = (flat[src] + flat[dst]) * 0.5 * CELL_M * (np.sqrt(2.0) if dz and dx else 1.0)
        ok = np.isfinite(w)
        rows.append(src[ok]); cols.append(dst[ok]); vals.append(w[ok])
    r, c, v = np.concatenate(rows), np.concatenate(cols), np.concatenate(vals)
    return sparse.csr_matrix((np.concatenate([v, v]), (np.concatenate([r, c]), np.concatenate([c, r]))), shape=(nz * nx, nz * nx))


def _cell(p, x0, z0, nx, cost):
    i, j = int((p[1] - z0) / CELL_M), int((p[0] - x0) / CELL_M)
    if not np.isfinite(cost[i, j]):
        free = np.isfinite(cost)
        _, (ri, rj) = ndimage.distance_transform_edt(~free, return_indices=True)
        i, j = ri[i, j], rj[i, j]
    return i * nx + j


def _shortest(graph, cost, a, b, x0, z0, nx):
    s, t = _cell(a, x0, z0, nx, cost), _cell(b, x0, z0, nx, cost)
    dist, pred = dijkstra(graph, indices=s, return_predecessors=True)
    if not np.isfinite(dist[t]):
        return None
    out, k = [], t
    while k != s and k >= 0:
        out.append(k)
        k = pred[k]
    out.append(s)
    out.reverse()
    return [(x0 + (k % nx + 0.5) * CELL_M, z0 + (k // nx + 0.5) * CELL_M) for k in out]

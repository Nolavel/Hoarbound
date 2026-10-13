"""Traversal check of the generated Reality world: no generated collider sits on a walkable way.

  python3 tools/world/key_west_reality.py traversal-check

Generated colliders are building prisms (collision outline, courtyards open), solid slabs
(parking, piers, breakwaters; bridge decks are the way itself) and the terrain; walls, fences, trees and stems have
none. Every mapped road, path and footway (bridges and ferries excepted) is sampled every
SAMPLE_M along its centreline; a sample is blocked inside a building prism, or inside a slab
whose top stands more than STEP_M above the way and whose underside is below HEADROOM_M. Writes reports/traversal.json.
"""
from __future__ import annotations

import json

import numpy as np
import shapely

from . import paths, receipts

OUT = paths.REALITY / "reports" / "traversal.json"
SAMPLE_M = 2.0
## Henry steps up this much without a ramp (CharacterBody snap; the 727 entry needed a ramp).
STEP_M = 0.35
## A slab Henry's capsule (2 m) passes under is a roof over the way, not a block.
HEADROOM_M = 2.0
## Outline contact is not a block: a way may graze a wall within this distance.
GRAZE_M = 0.3
NOT_WALKED = {"ferry_route", "rail_unknown"}


def run() -> dict:
    prisms, slabs, ways = [], [], []
    for path in sorted((paths.REALITY / "derived" / "editor_chunks").glob("chunk_*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        for ft in doc["features"]:
            m = ft.get("mesh") or {}
            kind = m.get("kind")
            if kind == "building" and m.get("collision", {}).get("ring"):
                col = m["collision"]
                shell = np.asarray(col["ring"]).reshape(-1, 2)
                holes = [np.asarray(h).reshape(-1, 2) for h in col.get("holes", []) if len(h) >= 6]
                poly = shapely.Polygon(shell, holes).buffer(0)
                if not poly.is_empty:
                    prisms.append((poly.buffer(-GRAZE_M), ft["feature_id"], (ft.get("meta") or {}).get("source_dataset", "")))
            elif kind == "slab" and ft["family"] != "bridges":
                for p in m["polys"]:
                    rings = [np.asarray(r).reshape(-1, 2) for r in p["rings"]]
                    poly = shapely.Polygon(rings[0], rings[1:]).buffer(0)
                    if not poly.is_empty:
                        slabs.append((poly.buffer(-GRAZE_M), float(m["top_y"]), float(m.get("thickness", 0.0)), ft["feature_id"]))
            elif kind == "ribbon" and ft["family"] == "roads" and ft["class"] not in NOT_WALKED:
                if "bridge" in (ft.get("attrs") or {}).get("flags", []):
                    continue
                for part in m["parts"]:
                    ways.append((np.asarray(part["p"]).reshape(-1, 2), np.asarray(part["y"]), ft["feature_id"], ft["class"]))
    prism_tree = shapely.STRtree([p for p, _, _ in prisms])
    slab_tree = shapely.STRtree([p for p, _, _, _ in slabs])
    samples, blocked = 0, []
    for pts, ys, fid, cls in ways:
        line = shapely.LineString(pts)
        if line.length <= 0.0:
            continue
        d = np.arange(0.0, line.length + 1e-6, SAMPLE_M)
        sp = shapely.line_interpolate_point(line, d)
        seg = np.searchsorted(np.cumsum(np.r_[0.0, np.hypot(*np.diff(pts, axis=0).T)]), d, side="right") - 1
        seg = np.clip(seg, 0, len(ys) - 2)
        cum = np.cumsum(np.r_[0.0, np.hypot(*np.diff(pts, axis=0).T)])
        t = np.clip((d - cum[seg]) / np.maximum(cum[seg + 1] - cum[seg], 1e-6), 0.0, 1.0)
        way_y = ys[seg] * (1 - t) + ys[seg + 1] * t
        samples += len(sp)
        hit_p = prism_tree.query(sp, predicate="within")
        for i, j in zip(*hit_p):
            blocked.append({"way": fid, "class": cls, "at": [round(sp[i].x, 1), round(sp[i].y, 1)], "by": prisms[j][1], "kind": "building"})
        hit_s = slab_tree.query(sp, predicate="within")
        for i, j in zip(*hit_s):
            rise = slabs[j][1] - way_y[i]
            underside = rise - slabs[j][2]
            if rise > STEP_M and underside < HEADROOM_M:
                blocked.append({"way": fid, "class": cls, "at": [round(sp[i].x, 1), round(sp[i].y, 1)], "by": slabs[j][3],
                                "kind": "slab", "rise_m": round(float(rise), 2)})
    conflicts = _building_conflicts(blocked, prisms, ways)
    slab_blocks: dict[str, int] = {}
    for b in blocked:
        if b["kind"] == "slab":
            slab_blocks[b["by"]] = slab_blocks.get(b["by"], 0) + 1
    passes = [c for c in conflicts if c["kind"] == "passes_through"]
    doc = {"schema": "kw_reality.traversal.v2", "built_at": receipts.now_utc(), "sample_m": SAMPLE_M, "step_m": STEP_M,
           "headroom_m": HEADROOM_M, "ways": len(ways), "samples": samples, "blocked_samples": len(blocked),
           "blocked_share": round(len(blocked) / max(samples, 1), 5),
           "slab_blocks": dict(sorted(slab_blocks.items(), key=lambda kv: -kv[1])),
           "building_conflicts": {"note": "a mapped way inside a building footprint: 'enters' ends inside it (drive "
                                          "into a garage, path to a door); 'passes_through' leaves on the far side. "
                                          "Source conflicts, reported for an author decision; geometry is unchanged.",
                                  "enters": len(conflicts) - len(passes), "passes_through": len(passes),
                                  "passes_over_6m": sum(1 for c in passes if c["inside_m"] > 6.0),
                                  "list": sorted(conflicts, key=lambda c: -c["inside_m"])}}
    OUT.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: doc[k] for k in ("ways", "samples", "blocked_samples", "blocked_share")}
                     | {"slab_blocks": len(doc["slab_blocks"]), "passes_through": len(passes)}))
    return doc


def _building_conflicts(blocked: list, prisms: list, ways: list) -> list:
    """One row per (way, building) the samples found: how far the way runs inside, and whether it ends there."""
    pairs = {(b["way"], b["by"]) for b in blocked if b["kind"] == "building"}
    polys = {fid: (poly, src) for poly, fid, src in prisms}
    lines: dict[str, list] = {}
    cls_of: dict[str, str] = {}
    for pts, _, fid, cls in ways:
        lines.setdefault(fid, []).append(pts)
        cls_of[fid] = cls
    out = []
    for way, bid in pairs:
        poly, src = polys[bid]
        inside, ends_inside = 0.0, False
        for pts in lines[way]:
            line = shapely.LineString(pts)
            inside += line.intersection(poly).length
            ends_inside = ends_inside or poly.contains(shapely.Point(pts[0])) or poly.contains(shapely.Point(pts[-1]))
        out.append({"way": way, "class": cls_of[way], "building": bid, "building_source": src,
                    "inside_m": round(inside, 1), "kind": "enters" if ends_inside else "passes_through"})
    return out

"""Search index for the Godot Reality editor dock: buildings with address, size and footprint.

Read-only view of the library in the local frame (x east, z south). Addresses come from the
building's own attribute, else from an address point inside its footprint.
"""
from __future__ import annotations

import json
import re

import shapely

from . import frame, library, paths, traversal

OUT = paths.REALITY / "editor" / "editor_index.json"
SCHEMA = "kw_reality.editor_index.v1"
FOOTPRINT_TOLERANCE_M = 0.25  # simplification of the stored outline; search and picking only
NEAR_ADDRESS_M = 6.0  # an address point this close to an unaddressed footprint names it (inferred)
CITY_TAIL = re.compile(r"\s+KEY WEST(\s+FL)?(\s+\d{5})?$")
NUMBER_HEAD = re.compile(r"^(\d+[A-Z]?(?:-\d+[A-Z]?)?)\s+(.+)$")


def split_address(text: str) -> tuple[str, str]:
    """'1400 KENNEDY DR KEY WEST 33040' -> ('1400', 'KENNEDY DR')."""
    s = CITY_TAIL.sub("", " ".join(str(text).upper().split()))
    m = NUMBER_HEAD.match(s)
    return (m.group(1), m.group(2)) if m else ("", s)


def run() -> dict:
    removed = set(json.loads(traversal.REMOVED_OUT.read_text(encoding="utf-8"))["buildings"]) if traversal.REMOVED_OUT.exists() else set()
    pts, pcols = library.read_layer("addresses")
    point_addr = []
    for g, attrs in zip(pts, pcols["attrs_json"]):
        a = json.loads(attrs)
        if a.get("number") and a.get("street"):
            point_addr.append((g, str(a["number"]).upper(), " ".join(str(a["street"]).upper().split())))
    tree = shapely.STRtree([p[0] for p in point_addr])

    geoms, cols = library.read_layer("buildings")
    out, sources = [], {"attribute": 0, "point_inside": 0, "point_near": 0}
    for i, g in enumerate(geoms):
        if g is None or g.is_empty:
            continue
        attrs = json.loads(cols["attrs_json"][i])
        number, street = split_address(attrs["address"]) if attrs.get("address") else ("", "")
        src = "attribute" if number or street else ""
        if not src:
            hits = [point_addr[k] for k in tree.query(g, predicate="contains")]
            src = "point_inside" if hits else ""
            if not hits:
                hits = [point_addr[k] for k in tree.query(g, predicate="dwithin", distance=NEAR_ADDRESS_M)]
                hits.sort(key=lambda h: h[0].distance(g))
                src = "point_near" if hits else ""
            if hits:
                _, number, street = hits[0]
        if src:
            sources[src] += 1
        local = frame.to_local(g).simplify(FOOTPRINT_TOLERANCE_M)
        poly = max(local.geoms, key=lambda p: p.area) if local.geom_type == "MultiPolygon" else local
        c = poly.representative_point()
        fid = cols["feature_id"][i]
        out.append({
            "id": fid, "name": cols["name"][i] or attrs.get("name") or "", "number": number, "street": street,
            "chunk": cols["chunk_id"][i], "c": [round(c.x, 1), round(c.y, 1)],
            "y": round(float(attrs.get("ground_elevation_m", 0.0) or 0.0), 2),
            "h": round(float(attrs.get("height_m", 0.0) or 0.0), 2), "levels": attrs.get("levels"),
            "use": attrs.get("primary_occupancy") or attrs.get("building_use_group") or "",
            "addr_src": src, "generated": fid not in removed,
            "ring": [v for xy in list(poly.exterior.coords)[:-1] for v in (round(xy[0], 1), round(xy[1], 1))],
        })
    out.sort(key=lambda b: b["id"])
    doc = {"schema": SCHEMA, "frame": "local metres, x east, z south (config/frame.json)", "library_sha256":
           json.loads(library.MANIFEST.read_text())["gpkg"]["sha256"] if library.MANIFEST.exists() else None,
           "counts": {"buildings": len(out), "address_sources": sources,
                      "not_generated": sum(not b["generated"] for b in out)},
           "buildings": out}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(json.dumps(doc["counts"]))
    return doc

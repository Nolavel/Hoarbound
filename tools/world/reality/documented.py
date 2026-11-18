"""Documented buildings: real buildings taken from public planning records (config/documented_buildings.json).

Used when no survey source has a building yet (built after the OSM, lidar and imagery epochs).
Geometry is the approved plan georeferenced to street centrelines, flagged as designed, not surveyed;
a survey that disagrees wins. Heights come from the elevation sheets, stored above the sidewalk.
"""
from __future__ import annotations

import numpy as np
import shapely

from . import config, ids
from .model import Attr, Feature

CONFIG = "documented_buildings.json"


def load() -> dict:
    return config.load(CONFIG)


def georeference(plan_px: list, georef: dict) -> shapely.Polygon:
    """Sheet pixels -> EPSG:32617: origin pixel to origin point, sheet y along down_axis, sheet x to its right."""
    down = np.asarray(georef["down_axis_en"], float)
    down /= np.linalg.norm(down)
    right = np.array([-down[1], down[0]])  # sheet x: 90 degrees anticlockwise of sheet y in E/N, the east side of Fort St
    px = np.asarray(plan_px, float) - np.asarray(georef["origin_px"], float)
    en = np.asarray(georef["origin_en"], float) + georef["metres_per_px"] * (np.outer(px[:, 1], down) + np.outer(px[:, 0], right))
    return shapely.orient_polygons(shapely.Polygon(en))


def roof(mass: dict, heights: dict) -> dict:
    """Documented roof above the sidewalk: eave, flat top and the slope between them."""
    lift = heights["crown_to_sidewalk_m"]
    return {"form": mass["roof"]["form"], "eave_m": round(mass["eave_above_crown_m"] - lift, 2),
            "top_m": round(mass["top_above_crown_m"] - lift, 2), "pitch": mass["roof"]["pitch"]}


def features(idreg: ids.IdRegistry) -> list[Feature]:
    """One library feature per documented mass, with the record's provenance on geometry and attributes."""
    doc = load()
    out = []
    for b in doc["buildings"]:
        for m in b["masses"]:
            native = f"{b['key']}_{m['key']}"
            fid = idreg.claim(ids.make("buildings", "doc", native), ids.make("buildings", "doc", native))
            f = Feature(feature_id=fid, family="buildings", cls="building", geom=georeference(m["plan_px"], doc["georef"]),
                        geometry_source=b["source_id"], geometry_record=m["geometry_record"],
                        geometry_method=b["geometry_method"], geometry_recon=b["reconstruction_class"],
                        geometry_confidence=b["confidence"], geometry_accuracy_m=b["geometry_accuracy_m"],
                        name=m["name"], valid_from=b["valid_from"], flags=set(b["flags"]))
            r = roof(m, doc["heights"])

            def fact(name, value, note=None):
                return Attr(name, value, b["source_id"], "documentary_record", b["reconstruction_class"], b["confidence"],
                            m["geometry_record"], "m" if name.endswith("_m") else None, note=note, selected=True)
            f.add(fact("height_m", r["top_m"], "35 ft cap over the crown of Fort St, stored above the sidewalk"),
                  fact("levels", m["levels"]), fact("roof_documented", r, m["roof"].get("pitch_note")),
                  fact("roof_material", m["roof"]["material"]), fact("address", b["address"]),
                  fact("construction", b["construction"]), fact("as_designed_note", m.get("note")))
            out.append(f)
    return out

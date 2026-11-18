"""Documented buildings: real buildings taken from public planning records (config/documented_buildings.json).

Used when no survey source has a building yet (built after the OSM, lidar and imagery epochs).
Geometry is the approved plan georeferenced to street centrelines, flagged as designed, not surveyed;
a survey that disagrees wins. Heights come from the elevation sheets, or from lidar for masses that
already stood in 2019. A record may close older library features it replaces (valid_to).
"""
from __future__ import annotations

import numpy as np
import shapely

from . import config, ids
from .model import Attr, Feature, Link

CONFIG = "documented_buildings.json"
LIDAR_HEIGHTS = "lidar_2019"


def load() -> dict:
    return config.load(CONFIG)


def _axes(georef: dict) -> tuple[np.ndarray, np.ndarray]:
    """Unit E/N vectors of sheet +y (down) and sheet +x (right); either one may be given."""
    if "down_axis_en" in georef:
        down = np.asarray(georef["down_axis_en"], float)
        down /= np.linalg.norm(down)
        return down, np.array([-down[1], down[0]])
    right = np.asarray(georef["right_axis_en"], float)
    right /= np.linalg.norm(right)
    return np.array([right[1], -right[0]]), right


def georeference(plan_px: list, georef: dict) -> shapely.Polygon:
    """Sheet pixels -> EPSG:32617: the origin pixel lands on the origin point, scaled by metres_per_px."""
    down, right = _axes(georef)
    px = np.asarray(plan_px, float) - np.asarray(georef["origin_px"], float)
    en = np.asarray(georef["origin_en"], float) + georef["metres_per_px"] * (np.outer(px[:, 1], down) + np.outer(px[:, 0], right))
    return shapely.orient_polygons(shapely.Polygon(en))


def roof(mass: dict, heights: dict) -> dict:
    """Documented roof above the base (sidewalk or lowest grade): eave, top and, for a hip, its pitch."""
    lift = heights["datum_to_base_m"]
    out = {"form": mass["roof"]["form"], "eave_m": round(mass["eave_above_datum_m"] - lift, 2),
           "top_m": round(mass["top_above_datum_m"] - lift, 2)}
    if "pitch" in mass["roof"]:
        out["pitch"] = mass["roof"]["pitch"]
    return out


def lidar_masses(features: list[Feature]) -> list[str]:
    """Ids of documented masses whose heights and roofs come from the 2019 lidar (they predate it)."""
    return [f.feature_id for f in features if "heights_from_lidar_2019" in f.flags]


def supersessions() -> list[dict]:
    """Older library features each record replaces: feature_id, valid_to, reason, source_id."""
    return [dict(s, source_id=b["source_id"]) for b in load()["buildings"] for s in b.get("supersedes", [])]


def features(idreg: ids.IdRegistry) -> list[Feature]:
    """One library feature per documented mass, with the record's provenance on geometry and attributes."""
    out = []
    for b in load()["buildings"]:
        for m in b["masses"]:
            out.append(_feature(b, m, idreg))
    return out


def _feature(b: dict, m: dict, idreg: ids.IdRegistry) -> Feature:
    native = f"{b['key']}_{m['key']}"
    fid = idreg.claim(ids.make("buildings", "doc", native), ids.make("buildings", "doc", native))
    geom = georeference(m["plan_px"], b["georef"])
    if "minus_px" in m:
        geom = shapely.orient_polygons(geom.difference(georeference(m["minus_px"], b["georef"])))
    lidar = m.get("heights") == LIDAR_HEIGHTS
    flags = set(m.get("flags", b["flags"])) | ({"heights_from_lidar_2019"} if lidar else set())
    conf = m.get("confidence", b["confidence"])
    f = Feature(feature_id=fid, family="buildings", cls="building", geom=geom, geometry_source=b["source_id"],
                geometry_record=m["geometry_record"], geometry_method=b["geometry_method"],
                geometry_recon=b["reconstruction_class"], geometry_confidence=conf,
                geometry_accuracy_m=m.get("geometry_accuracy_m", b["geometry_accuracy_m"]), name=m["name"],
                valid_from=m.get("valid_from", b["valid_from"]), source_epoch=b["source_epoch"], flags=flags)
    f.links.append(Link(b["source_id"], "documented_buildings", native, "geometry", "identity"))

    def fact(name, value, note=None):
        return Attr(name, value, b["source_id"], "documentary_record", b["reconstruction_class"], conf,
                    m["geometry_record"], "m" if name.endswith("_m") else None, note=note, selected=True)
    f.add(fact("address", b["address"]), fact("construction", b["construction"]), fact("as_designed_note", m.get("note")))
    if not lidar:
        r = roof(m, b["heights"])
        f.add(fact("height_m", r["top_m"], f"top above {b['heights']['base']}"), fact("levels", m["levels"]),
              fact("roof_documented", r, m["roof"].get("pitch_note") or m["roof"].get("note")),
              fact("roof_material", m["roof"]["material"]))
    return f

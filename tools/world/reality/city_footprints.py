"""City of Key West building footprints (2017), applied record by record after review.

The layer is official but older than lidar 2019 and NAIP 2023, so nothing enters the library on its own:
config/city_footprints.json lists accepted records (missing buildings, parts of merged outlines) with the
evidence that confirmed each one, the library outlines they split, and the records left out and why.
"""
from __future__ import annotations

import json
import urllib.parse
import urllib.request

import shapely
from shapely.geometry import shape

from . import config, frame, ids, paths, receipts
from .model import Feature, Link, geometry_hash

CONFIG = "city_footprints.json"
LAYER_URL = "https://services3.arcgis.com/aIpcLPHSEqH4LbLl/arcgis/rest/services/Building_Footprints___Key_West/FeatureServer/0"
RAW = paths.RAW / "city_of_key_west_gis" / "building_footprints.geojson"


def load() -> dict:
    return config.load(CONFIG)


def acquire(bbox_local: list[float]) -> dict:
    """Downloads the footprints inside a local box [x0, z0, x1, z1] to the raw cache; returns the receipt artifact."""
    x0, z0, x1, z1 = bbox_local
    (e0, n0), (e1, n1) = frame.local_to_projected(x0, z1), frame.local_to_projected(x1, z0)
    query = {"where": "1=1", "geometry": f"{e0},{n0},{e1},{n1}", "geometryType": "esriGeometryEnvelope", "inSR": "32617",
             "spatialRel": "esriSpatialRelIntersects", "outFields": "*", "outSR": "32617", "f": "geojson", "resultRecordCount": "2000"}
    url = f"{LAYER_URL}/query?{urllib.parse.urlencode(query)}"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Hoarbound-KW-Reality/1.0"}), timeout=120) as r:
        data = r.read()
    if json.loads(data).get("error"):
        raise SystemExit(f"city footprints query failed: {json.loads(data)['error']}")
    RAW.parent.mkdir(parents=True, exist_ok=True)
    RAW.write_bytes(data)
    receipt = receipts.load("city_of_key_west_gis")
    receipt.update({"source_id": "city_of_key_west_gis", "retrieved_at": receipts.now_utc()})
    artifact = {"name": "building_footprints", "url": url, "bytes": len(data), "sha256": receipts.sha256_file(RAW),
                "local_path": paths.rel(RAW), "query_bbox_local": bbox_local, "records": len(json.loads(data)["features"])}
    receipts.upsert_artifact(receipt, artifact)
    receipts.save(receipt)
    return artifact


def records(path=RAW) -> dict[str, shapely.Polygon]:
    """OBJECTID (as text) -> projected footprint from the raw cache."""
    doc = json.loads(path.read_text(encoding="utf-8"))
    return {str(f["properties"]["OBJECTID"]): shapely.make_valid(shape(f["geometry"])) for f in doc["features"]}


def features(idreg: ids.IdRegistry, recs: dict, decisions: dict) -> list[Feature]:
    """Library features for the accepted records; a record whose geometry changed since review is refused."""
    out = []
    for oid, why in sorted(decisions["accept"].items(), key=lambda kv: int(kv[0])):
        geom = recs[oid]
        expected = decisions["hashes"].get(oid)
        if expected and expected != geometry_hash(geom):
            raise SystemExit(f"city footprint {oid} changed since review ({expected} -> {geometry_hash(geom)}): review it again")
        fid = idreg.claim(ids.make("buildings", "citykw", oid), ids.make("buildings", "citykw", oid))
        f = Feature(feature_id=fid, family="buildings", cls="building", geom=shapely.orient_polygons(geom),
                    geometry_source=decisions["source_id"], geometry_record=f"OBJECTID {oid}", geometry_method="official_footprint",
                    geometry_recon="authoritative", geometry_confidence=0.8, observed_at=decisions["observed_at"],
                    source_epoch=decisions["observed_at"][:4])
        f.flags.add("reviewed_" + why.get("review", "lidar_naip"))
        if oid in decisions.get("known_issues", {}):
            f.flags.add("height_canopy_suspect")
        f.links.append(Link(decisions["source_id"], "building_footprints", oid, "geometry", "identity"))
        out.append(f)
    return out


def removals(decisions: dict) -> list[dict]:
    """Merged library outlines to take out: feature_id plus the reason naming the footprints that replace it."""
    return [{"feature_id": fid, "source_id": decisions["source_id"],
             "reason": f"{s['reason']}; split into " + ", ".join(f"kw:building:citykw:{o}" for o in s["into"])}
            for fid, s in decisions["split"].items()]

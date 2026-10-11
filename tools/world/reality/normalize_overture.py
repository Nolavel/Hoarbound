"""Overture release -> canonical features with property-level provenance.

Overture rows carry sources[] with per-property entries ('/properties/height' ...)
and, for base/infrastructure|land|water|land_use, the original OSM tags.
"""
from __future__ import annotations

import json

import pyarrow.parquet as pq
from shapely import wkb

from . import frame, ids, paths
from .acquire import OVERTURE_RELEASE
from .model import Attr, Excluded, Feature, Link, geometry_hash

SRC = "overture_2026_09_23_1"

INFRA_FAMILY = {
    "bridge": "bridges", "pier": "coastal_structures", "power": "power", "communication": "utilities",
    "utility": "utilities", "tower": "utilities", "barrier": "barriers", "pedestrian": "street_furniture",
    "waste_management": "street_furniture", "emergency": "street_furniture", "transit": "transit",
    "airport": "airport", "recreation": "land_use",
}
WATER_INFRA = {"breakwater": "coastal_structures", "groyne": "coastal_structures", "dam": "coastal_structures",
               "weir": "coastal_structures", "fountain": "street_furniture", "drinking_water": "street_furniture"}
TRANSPORT_POINTS = {"street_lamp", "traffic_signals", "crossing", "stop", "milestone", "motorway_junction",
                    "charging_station", "give_way", "speed_camera", "toll_booth", "street_cabinet"}
LAND_FAMILY = {
    ("tree", "tree"): ("trees", "tree"), ("tree", "tree_row"): ("trees", "tree_row"),
    ("forest", "wood"): ("vegetation_areas", "wood"), ("forest", "forest"): ("vegetation_areas", "forest"),
    ("shrub", "scrub"): ("vegetation_areas", "scrub"), ("shrub", "heath"): ("vegetation_areas", "heath"),
    ("wetland", "wetland"): ("vegetation_areas", "wetland"), ("grass", "grass"): ("vegetation_areas", "grass"),
    ("grass", "grassland"): ("vegetation_areas", "grassland"), ("grass", "meadow"): ("vegetation_areas", "meadow"),
    ("sand", "beach"): ("land", "beach"), ("sand", "sand"): ("land", "sand"), ("rock", "bare_rock"): ("land", "bare_rock"),
    ("rock", "rock"): ("land", "rock"), ("reef", "reef"): ("land", "reef"),
    ("land", "land"): ("land", "landmass"), ("land", "island"): ("land", "island"), ("land", "islet"): ("land", "islet"),
    ("land", "archipelago"): ("land", "archipelago"),
}
ROAD_ACCURACY = {"OpenStreetMap": 2.0}


def _rows(theme: str, typ: str) -> list[dict]:
    return pq.read_table(paths.RAW / "overture" / OVERTURE_RELEASE / f"{theme}__{typ}.parquet").to_pylist()


def _primary(row: dict) -> dict:
    srcs = row.get("sources") or []
    for s in srcs:
        if not s.get("property"):
            return s
    return srcs[0] if srcs else {}


def _prop_source(row: dict, prop: str) -> dict:
    for s in row.get("sources") or []:
        if s.get("property") == f"/properties/{prop}":
            return s
    return _primary(row)


def _name(row: dict) -> str | None:
    return (row.get("names") or {}).get("primary")


def _dataset_recon(dataset: str) -> tuple[str, str, float]:
    """(method, recon class, confidence) for a geometry from an Overture contributing dataset."""
    if dataset == "OpenStreetMap":
        return "osm_community_trace", "derived", 0.85
    if "Microsoft" in dataset:
        return "ml_footprint_extraction", "derived", 0.6
    if "Esri" in dataset:
        return "community_maps_trace", "derived", 0.8
    return "conflated_source", "derived", 0.6


def _epoch(src: dict) -> tuple[str | None, str | None]:
    return src.get("update_time"), src.get("version")


class OvertureNormalizer:
    def __init__(self, zones, idreg: ids.IdRegistry):
        self.zones = zones
        self.idreg = idreg
        self.features: list[Feature] = []
        self.excluded: list[Excluded] = []

    # -- helpers -----------------------------------------------------------
    def _attr(self, row: dict, name: str, value, prop: str | None = None, method: str | None = None,
              recon: str | None = None, confidence: float | None = None, unit: str | None = None) -> Attr | None:
        if value is None or value == "" or value == []:
            return None
        src = _prop_source(row, prop or name)
        dataset = src.get("dataset", "")
        if method is None:
            method = "osm_tag" if dataset == "OpenStreetMap" else f"{dataset.lower().replace(' ', '_')}_attribute"
        if recon is None:
            recon = "derived"
        if confidence is None:
            confidence = 0.8 if dataset == "OpenStreetMap" else 0.55
        observed, epoch = _epoch(src)
        return Attr(name, value, SRC, method, recon, confidence, source_record_id=f"{dataset}:{src.get('record_id')}",
                    unit=unit, observed_at=observed, source_epoch=epoch)

    def _feature(self, row: dict, family: str, cls: str, layer: str, subclass: str | None = None,
                 namespace_from_osm: bool = True) -> Feature | None:
        geom = frame.to_projected(wkb.loads(row["geometry"]))
        zone, reason = self.zones.classify(geom, family)
        primary = _primary(row)
        if reason:
            self.excluded.append(Excluded(SRC, layer, row["id"], cls, reason))
            return None
        dataset = primary.get("dataset", "")
        osm = ids.osm_key(primary.get("record_id")) if dataset == "OpenStreetMap" and namespace_from_osm else None
        fallback = ids.make(family, "overture", row["id"])
        fid = self.idreg.claim(ids.make(family, "osm", osm) if osm else fallback, fallback, (SRC, row["id"]))
        method, recon, conf = _dataset_recon(dataset)
        observed, epoch = _epoch(primary)
        f = Feature(feature_id=fid, family=family, cls=cls, geom=geom, geometry_source=SRC,
                    geometry_record=f"{dataset}:{primary.get('record_id')}", geometry_method=method,
                    geometry_recon=recon, geometry_confidence=conf, geometry_accuracy_m=ROAD_ACCURACY.get(dataset, 3.0),
                    subclass=subclass, name=_name(row), zone=zone, scope=self.zones.scope_of(zone),
                    observed_at=observed, source_epoch=epoch, last_verified=observed)
        f.links.append(Link(SRC, layer, row["id"], "geometry", "identity", None, str(row.get("version"))))
        for s in row.get("sources") or []:
            if s.get("record_id"):
                role = "geometry" if not s.get("property") else "attributes"
                between = s.get("between")
                f.links.append(Link(f"{SRC}:{s.get('dataset')}", s.get("dataset", ""), s["record_id"], role,
                                    "overture_conflation" if role == "attributes" else "overture_source",
                                    None, s.get("version") if not between else f"{s.get('version')} between={list(between)}"))
        if row.get("names") and row["names"].get("primary"):
            f.add(self._attr(row, "name", row["names"]["primary"], prop="names"))
        tags = dict(row.get("source_tags") or [])
        if tags:
            f.add(self._attr(row, "osm_tags", tags, prop="source_tags", method="osm_tags_verbatim"))
            for key in ("start_date", "historic", "operator", "material", "surface", "height", "ele", "voltage", "cables",
                        "circuits", "frequency", "line", "floating", "mooring", "access", "bridge:structure", "layer",
                        "species", "genus", "leaf_type", "leaf_cycle", "denotation", "wetland", "description", "ref"):
                if key in tags:
                    f.add(self._attr(row, f"osm:{key}", tags[key], prop="source_tags"))
            if "start_date" in tags:
                f.valid_from = tags["start_date"]
        self.features.append(f)
        return f

    # -- themes ----------------------------------------------------------------
    def buildings(self) -> None:
        for row in _rows("buildings", "building"):
            f = self._feature(row, "buildings", "building", "buildings/building", subclass=row.get("class") or row.get("subtype"))
            if not f:
                continue
            ds_height = _prop_source(row, "height").get("dataset", "")
            if row.get("height") is not None:
                if ds_height == "OpenStreetMap":
                    f.add(self._attr(row, "height_m", round(float(row["height"]), 2), method="osm_height_tag", confidence=0.75, unit="m"))
                else:
                    f.add(self._attr(row, "height_m", round(float(row["height"]), 2), method="ml_height_estimate", confidence=0.45, unit="m"))
            f.add(self._attr(row, "levels", row.get("num_floors"), prop="num_floors"),
                  self._attr(row, "levels_underground", row.get("num_floors_underground"), prop="num_floors_underground"),
                  self._attr(row, "min_height_m", row.get("min_height"), prop="min_height", unit="m"),
                  self._attr(row, "building_use", row.get("class"), prop="class"),
                  self._attr(row, "building_use_group", row.get("subtype"), prop="subtype"),
                  self._attr(row, "roof_shape", row.get("roof_shape")),
                  self._attr(row, "roof_direction_deg", row.get("roof_direction"), prop="roof_direction"),
                  self._attr(row, "roof_orientation", row.get("roof_orientation")),
                  self._attr(row, "roof_color", row.get("roof_color")),
                  self._attr(row, "roof_material", row.get("roof_material")),
                  self._attr(row, "roof_height_m", row.get("roof_height"), prop="roof_height", unit="m"),
                  self._attr(row, "facade_color", row.get("facade_color")),
                  self._attr(row, "facade_material", row.get("facade_material")),
                  self._attr(row, "level", row.get("level")),
                  self._attr(row, "has_parts", True if row.get("has_parts") else None),
                  self._attr(row, "is_underground", True if row.get("is_underground") else None))
        for row in _rows("buildings", "building_part"):
            f = self._feature(row, "building_parts", "building_part", "buildings/building_part")
            if f:
                f.add(self._attr(row, "height_m", row.get("height"), unit="m", method="osm_height_tag"),
                      self._attr(row, "min_height_m", row.get("min_height"), prop="min_height", unit="m"),
                      self._attr(row, "levels", row.get("num_floors"), prop="num_floors"),
                      self._attr(row, "roof_shape", row.get("roof_shape")),
                      self._attr(row, "parent_building_overture_id", row.get("building_id"), prop="building_id"))

    def transportation(self) -> None:
        for row in _rows("transportation", "segment"):
            sub = row.get("subtype")
            cls = row.get("class") or sub
            family = "roads"
            if sub == "water":
                cls = "ferry_route"
            elif sub == "rail":
                cls = f"rail_{cls}"
            f = self._feature(row, family, cls, "transportation/segment", subclass=row.get("subclass"), namespace_from_osm=False)
            if not f:
                continue
            flags = sorted({v for fl in (row.get("road_flags") or []) for v in (fl.get("values") or [])})
            f.add(self._attr(row, "road_class", cls, prop="class"),
                  self._attr(row, "road_subclass", row.get("subclass"), prop="subclass"),
                  self._attr(row, "surface_rules", row.get("road_surface"), prop="road_surface"),
                  self._attr(row, "flag_rules", row.get("road_flags"), prop="road_flags"),
                  self._attr(row, "flags", flags or None, prop="road_flags"),
                  self._attr(row, "width_rules", row.get("width_rules"), prop="width_rules"),
                  self._attr(row, "level_rules", row.get("level_rules"), prop="level_rules"),
                  self._attr(row, "speed_limits", row.get("speed_limits"), prop="speed_limits"),
                  self._attr(row, "access_restrictions", row.get("access_restrictions"), prop="access_restrictions"),
                  self._attr(row, "routes", row.get("routes"), prop="routes"),
                  self._attr(row, "connectors", row.get("connectors"), prop="connectors", method="overture_topology"))
            if "is_bridge" in flags:
                f.flags.add("bridge")
            widths = [w.get("value") for w in (row.get("width_rules") or []) if w.get("value")]
            if widths:
                f.add(self._attr(row, "width_m", float(widths[0]), prop="width_rules", method="osm_width_tag", confidence=0.75, unit="m"))
        for row in _rows("transportation", "connector"):
            self._feature(row, "transport_nodes", "connector", "transportation/connector", namespace_from_osm=False)

    def infrastructure(self) -> None:
        for row in _rows("base", "infrastructure"):
            sub, cls = row.get("subtype"), row.get("class")
            if sub == "water":
                family = WATER_INFRA.get(cls, "coastal_structures")
            elif sub == "transportation":
                family = "street_furniture" if cls in TRANSPORT_POINTS else "transit"
            elif sub == "tower" and cls == "lighting":
                family, cls = "utilities", "lighting_tower"
            else:
                family = INFRA_FAMILY.get(sub, "street_furniture")
            tags = dict(row.get("source_tags") or [])
            subclass = None
            if cls == "pier" and tags.get("floating") == "yes":
                subclass = "floating"
            elif cls == "pier" and tags.get("mooring"):
                subclass = "mooring"
            f = self._feature(row, family, cls, "base/infrastructure", subclass=subclass)
            if f:
                f.add(self._attr(row, "height_m", row.get("height"), unit="m", method="osm_height_tag"),
                      self._attr(row, "surface", row.get("surface")),
                      self._attr(row, "infra_group", sub, prop="subtype"))

    def land(self) -> None:
        for row in _rows("base", "land"):
            key = (row.get("subtype"), row.get("class"))
            family, cls = LAND_FAMILY.get(key, ("land", row.get("class") or "land"))
            f = self._feature(row, family, cls, "base/land")
            if f:
                f.add(self._attr(row, "surface", row.get("surface")),
                      self._attr(row, "elevation_m", row.get("elevation"), unit="m"))
        for row in _rows("base", "water"):
            f = self._feature(row, "water", row.get("class") or "water", "base/water", subclass=row.get("subtype"))
            if f:
                f.add(self._attr(row, "is_salt", row.get("is_salt")), self._attr(row, "is_intermittent", row.get("is_intermittent")))
        for row in _rows("base", "land_use"):
            f = self._feature(row, "land_use", row.get("class") or "land_use", "base/land_use", subclass=row.get("subtype"))
            if f:
                f.add(self._attr(row, "surface", row.get("surface")))
        for row in _rows("base", "land_cover"):
            self.excluded.append(Excluded(SRC, "base/land_cover", row["id"], row.get("subtype") or "land_cover",
                                          "duplicate_of_source:esa_worldcover_2021_v200 (Overture land_cover is derived from ESA WorldCover)"))

    def places(self) -> None:
        for row in _rows("places", "place"):
            src = _primary(row)
            geom = frame.to_projected(wkb.loads(row["geometry"]))
            zone, reason = self.zones.classify(geom, "places")
            if reason:
                self.excluded.append(Excluded(SRC, "places/place", row["id"], "place", reason))
                continue
            fid = self.idreg.claim(ids.make("places", "overture", row["id"]), ids.make("places", "overture", row["id"]), (SRC, row["id"]))
            observed, epoch = _epoch(src)
            f = Feature(fid, "places", "place", geom, SRC, f"{src.get('dataset')}:{src.get('record_id')}", "poi_aggregation",
                        "derived", round(float(row.get("confidence") or 0.5), 3), 15.0, subclass=row.get("basic_category"),
                        name=_name(row), zone=zone, scope="reality", observed_at=observed, source_epoch=epoch)
            f.links.append(Link(SRC, "places/place", row["id"], "geometry", "identity", None, str(row.get("version"))))
            for s in row.get("sources") or []:
                f.links.append(Link(f"{SRC}:{s.get('dataset')}", s.get("dataset", ""), str(s.get("record_id")), "attributes", "overture_source", None, s.get("version")))
            conf = round(float(row.get("confidence") or 0.5), 3)
            f.add(self._attr(row, "name", _name(row), prop="names", confidence=conf),
                  self._attr(row, "category", row.get("basic_category"), prop="basic_category", confidence=conf),
                  self._attr(row, "taxonomy", row.get("taxonomy"), confidence=conf),
                  self._attr(row, "brand", row.get("brand"), confidence=conf),
                  self._attr(row, "addresses", row.get("addresses"), confidence=conf),
                  self._attr(row, "operating_status", row.get("operating_status"), confidence=conf),
                  self._attr(row, "websites", row.get("websites"), confidence=conf),
                  self._attr(row, "place_confidence", row.get("confidence"), prop="confidence", confidence=conf),
                  Attr("licence", src.get("license"), SRC, "source_licence", "authoritative", 1.0, source_record_id=src.get("record_id")))
            self.features.append(f)
        for row in _rows("addresses", "address"):
            src = _primary(row)
            geom = frame.to_projected(wkb.loads(row["geometry"]))
            zone, reason = self.zones.classify(geom, "addresses")
            if reason:
                self.excluded.append(Excluded(SRC, "addresses/address", row["id"], "address", reason))
                continue
            fid = self.idreg.claim(ids.make("addresses", "overture", row["id"]), ids.make("addresses", "overture", row["id"]), (SRC, row["id"]))
            observed, epoch = _epoch(src)
            f = Feature(fid, "addresses", "address", geom, SRC, f"{src.get('dataset')}:{src.get('record_id')}", "address_point",
                        "derived", 0.8, 10.0, zone=zone, observed_at=observed, source_epoch=epoch)
            f.links.append(Link(SRC, "addresses/address", row["id"], "geometry", "identity", None, str(row.get("version"))))
            for s in row.get("sources") or []:
                f.links.append(Link(f"{SRC}:{s.get('dataset')}", s.get("dataset", ""), str(s.get("record_id")), "attributes", "overture_source", None, s.get("version")))
            f.name = " ".join(str(v) for v in (row.get("number"), row.get("street")) if v)
            f.add(self._attr(row, "number", row.get("number")), self._attr(row, "street", row.get("street")),
                  self._attr(row, "unit", row.get("unit")), self._attr(row, "postcode", row.get("postcode")),
                  self._attr(row, "postal_city", row.get("postal_city")),
                  Attr("licence", src.get("license"), SRC, "source_licence", "authoritative", 1.0, source_record_id=src.get("record_id")))
            self.features.append(f)

    def divisions(self) -> None:
        for row in _rows("divisions", "division_area"):
            if row.get("subtype") not in ("locality", "macrohood", "neighborhood", "county"):
                continue
            geom = frame.to_projected(wkb.loads(row["geometry"]))
            if not self.zones.rect.intersects(geom):
                continue
            src = _primary(row)
            fid = self.idreg.claim(ids.make("admin_areas", "overture", row["id"]), ids.make("admin_areas", "overture", row["id"]), (SRC, row["id"]))
            observed, epoch = _epoch(src)
            f = Feature(fid, "admin_areas", row.get("subtype"), geom, SRC, f"{src.get('dataset')}:{src.get('record_id')}",
                        "osm_boundary", "derived", 0.7, 10.0, subclass=row.get("class"), name=_name(row), zone="admin",
                        observed_at=observed, source_epoch=epoch)
            f.links.append(Link(SRC, "divisions/division_area", row["id"], "geometry", "identity", None, str(row.get("version"))))
            self.features.append(f)

    def run(self) -> None:
        self.buildings()
        self.transportation()
        self.infrastructure()
        self.land()
        self.places()
        self.divisions()


def summarize(features: list[Feature]) -> str:
    from collections import Counter
    return json.dumps(Counter(f.family for f in features), indent=0)

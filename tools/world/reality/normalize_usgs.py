"""USGS The National Map clips -> candidate features (structures, transport, admin, hydrography)."""
from __future__ import annotations

import warnings

import numpy as np
import pyogrio
import shapely

from . import frame, ids, paths
from .model import Attr, Excluded, Feature, Link

NSD = "usgs_nsd_fl_20260227"
NTD = "usgs_ntd_fl_20260211"
GU = "usgs_govtunit_fl_20260212"
NHD = "usgs_nhd_fl_2024"


def read_layer(source_id: str, layer: str) -> list[dict]:
    path = paths.RAW / "usgs_tnm" / "clips" / f"{source_id}.gpkg"
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        meta, _, geom, fields = pyogrio.raw.read(path, layer=layer)
    names = list(meta["fields"])
    crs = meta["crs"]
    rows = []
    for i, g in enumerate(shapely.from_wkb(geom)):
        rec = {n: _py(fields[j][i]) for j, n in enumerate(names)}
        rec["_geom"] = frame.to_projected(shapely.force_2d(g), crs) if g is not None else None
        rows.append(rec)
    return rows


def _py(v):
    if isinstance(v, np.generic):
        v = v.item()
    if isinstance(v, float) and np.isnan(v):
        return None
    if isinstance(v, np.datetime64):
        return str(v)
    return v if v != "" else None


def _date(v) -> str | None:
    return str(v)[:10] if v else None


class UsgsNormalizer:
    def __init__(self, zones, idreg: ids.IdRegistry):
        self.zones = zones
        self.idreg = idreg
        self.features: list[Feature] = []
        self.building_candidates: list[Feature] = []
        self.road_candidates: list[dict] = []
        self.runway_candidates: list[Feature] = []
        self.water_candidates: list[Feature] = []
        self.public_points: list[Feature] = []
        self.excluded: list[Excluded] = []

    def _scope(self, geom, family, layer, record, cls):
        zone, reason = self.zones.classify(geom, family)
        if reason:
            self.excluded.append(Excluded(layer.split(":")[0], layer, record, cls, reason))
        return zone

    def structures(self) -> None:
        for r in read_layer(NSD, "Struct_Poly_FEMA"):
            g = r["_geom"]
            rec = str(r.get("build_id") or r.get("uuid"))
            zone = self._scope(g, "buildings", f"{NSD}:Struct_Poly_FEMA", rec, "building")
            if not zone:
                continue
            fid = ids.make("buildings", "usa_structures", rec)
            observed = _date(r.get("image_date")) or _date(r.get("prod_date"))
            f = Feature(fid, "buildings", "building", g, NSD, f"Struct_Poly_FEMA:{rec}", "ml_footprint_extraction_usa_structures",
                        "derived", 0.75, 2.0, subclass=(r.get("occ_cls") or "").lower() or None, zone=zone,
                        observed_at=observed, source_epoch="2026-02-27", last_verified=observed)
            f.links.append(Link(NSD, "Struct_Poly_FEMA", rec, "geometry", "identity", None, _date(r.get("prod_date"))))
            note = f"source={r.get('source')}; image={r.get('image_name')}; val_method={r.get('val_method')}"
            common = dict(source_record_id=f"Struct_Poly_FEMA:{rec}", observed_at=observed, source_epoch="2026-02-27")
            f.add(Attr("height_m", r.get("height") and round(float(r["height"]), 2), NSD, "usa_structures_height", "derived", 0.55, unit="m", note=note, **common),
                  Attr("occupancy_class", r.get("occ_cls"), NSD, "usa_structures_occupancy", "derived", 0.7, **common),
                  Attr("primary_occupancy", r.get("prim_occ"), NSD, "usa_structures_occupancy", "derived", 0.65, **common),
                  Attr("secondary_occupancy", r.get("sec_occ"), NSD, "usa_structures_occupancy", "derived", 0.5, **common),
                  Attr("address", " ".join(str(x) for x in (r.get("prop_addr"), r.get("prop_city"), r.get("prop_zip")) if x) if r.get("prop_addr") else None,
                       NSD, "usa_structures_property_address", "derived", 0.7, note="parcel-derived property address", **common),
                  Attr("outbuilding", r.get("outbldg"), NSD, "usa_structures_flag", "derived", 0.6, **common),
                  Attr("footprint_area_m2_source", r.get("sqmeters"), NSD, "usa_structures_area", "derived", 0.9, unit="m2", **common))
            self.building_candidates.append(f)
        for r in read_layer(NSD, "Struct_Point"):
            g = r["_geom"]
            rec = str(r.get("permanent_identifier"))
            zone = self._scope(g, "places", f"{NSD}:Struct_Point", rec, "public_facility")
            if not zone:
                continue
            fid = self.idreg.claim(ids.make("places", "usgs_nsd", rec), ids.make("places", "usgs_nsd", rec))
            f = Feature(fid, "places", "public_facility", g, NSD, f"Struct_Point:{rec}", "tnm_corps_point", "authoritative", 0.85, 20.0,
                        subclass=r.get("fcode_desc"), name=r.get("name"), zone=zone, observed_at=_date(r.get("loaddate")), source_epoch="2026-02-27")
            f.links.append(Link(NSD, "Struct_Point", rec, "geometry", "identity", None, _date(r.get("loaddate"))))
            common = dict(source_record_id=f"Struct_Point:{rec}", observed_at=_date(r.get("loaddate")), source_epoch="2026-02-27")
            f.add(Attr("name", r.get("name"), NSD, "official_facility_register", "authoritative", 0.9, **common),
                  Attr("facility_type", r.get("fcode_desc"), NSD, "official_facility_register", "authoritative", 0.9, **common),
                  Attr("address", " ".join(str(x) for x in (r.get("address"), r.get("city"), r.get("zipcode")) if x) or None,
                       NSD, "official_facility_register", "authoritative", 0.85, **common))
            self.public_points.append(f)
            self.features.append(f)

    def transport(self) -> None:
        for r in read_layer(NTD, "Trans_RoadSegment"):
            if r["_geom"] is None or not self.zones.rect.intersects(r["_geom"]):
                continue
            self.road_candidates.append(r)
        for r in read_layer(NTD, "Trans_TrailSegment"):
            if r["_geom"] is not None and self.zones.rect.intersects(r["_geom"]):
                r["_trail"] = True
                self.road_candidates.append(r)
        for r in read_layer(NTD, "Trans_AirportRunway"):
            g = r["_geom"]
            rec = str(r.get("permanent_identifier"))
            zone = self._scope(g, "airport", f"{NTD}:Trans_AirportRunway", rec, "runway")
            if not zone:
                continue
            fid = ids.make("airport", "faa", rec)
            f = Feature(fid, "airport", "runway", g, NTD, f"Trans_AirportRunway:{rec}", "faa_runway_register", "authoritative", 0.9, 2.0,
                        name=f"{r.get('faa_airport_code')} {r.get('runway_id')}", zone=zone, observed_at=_date(r.get("loaddate")), source_epoch="2026-02-11")
            f.links.append(Link(NTD, "Trans_AirportRunway", rec, "geometry", "identity", None, _date(r.get("loaddate"))))
            common = dict(source_record_id=f"Trans_AirportRunway:{rec}", observed_at=_date(r.get("loaddate")), source_epoch="2026-02-11")
            f.add(Attr("runway_id", r.get("runway_id"), NTD, "faa_runway_register", "authoritative", 0.95, **common),
                  Attr("faa_airport_code", r.get("faa_airport_code"), NTD, "faa_runway_register", "authoritative", 0.95, **common),
                  Attr("owner_type", r.get("ownertype_desc"), NTD, "faa_runway_register", "authoritative", 0.9, **common),
                  Attr("use_status", r.get("usestatus_desc"), NTD, "faa_runway_register", "authoritative", 0.9, **common))
            self.runway_candidates.append(f)
        for r in read_layer(NTD, "Trans_AirportPoint"):
            g = r["_geom"]
            rec = str(r.get("permanent_identifier"))
            zone = self._scope(g, "airport", f"{NTD}:Trans_AirportPoint", rec, "airport_point")
            if not zone:
                continue
            fid = self.idreg.claim(ids.make("airport", "faa", rec), ids.make("airport", "faa", rec))
            f = Feature(fid, "airport", "airport_reference_point", g, NTD, f"Trans_AirportPoint:{rec}", "faa_airport_register",
                        "authoritative", 0.9, 30.0, subclass=r.get("ftype"), name=r.get("name"), zone=zone,
                        observed_at=_date(r.get("loaddate")), source_epoch="2026-02-11")
            f.links.append(Link(NTD, "Trans_AirportPoint", rec, "geometry", "identity", None, _date(r.get("loaddate"))))
            f.add(Attr("faa_airport_code", r.get("faa_airport_code"), NTD, "faa_airport_register", "authoritative", 0.95,
                       source_record_id=rec, source_epoch="2026-02-11"),
                  Attr("ownership", r.get("ownership_desc"), NTD, "faa_airport_register", "authoritative", 0.9, source_record_id=rec))
            self.features.append(f)

    def admin(self) -> None:
        for layer, cls in (("GU_IncorporatedPlace", "incorporated_place"), ("GU_UnincorporatedPlace", "census_designated_place"),
                           ("GU_Reserve", "reserve"), ("GU_CountyOrEquivalent", "county")):
            for r in read_layer(GU, layer):
                g = r["_geom"]
                if g is None or not self.zones.rect.intersects(g):
                    continue
                rec = str(r.get("PERMANENT_IDENTIFIER"))
                name = r.get("PLACE_NAME") or r.get("NAME") or r.get("COUNTY_NAME")
                fid = self.idreg.claim(ids.make("admin_areas", "usgs_gu", rec), ids.make("admin_areas", "usgs_gu", rec))
                f = Feature(fid, "admin_areas", cls, g, GU, f"{layer}:{rec}", "census_boundary", "authoritative", 0.9, 10.0,
                            subclass=r.get("FCODE_desc") or r.get("ADMINTYPE_desc"), name=name, zone="admin",
                            observed_at=_date(r.get("LOADDATE")), source_epoch="2026-02-12")
                f.links.append(Link(GU, layer, rec, "geometry", "identity", None, _date(r.get("LOADDATE"))))
                f.add(Attr("name", name, GU, "official_boundary", "authoritative", 0.95, source_record_id=rec),
                      Attr("population", r.get("POPULATION"), GU, "census_count", "authoritative", 0.9, source_record_id=rec),
                      Attr("managing_agency", r.get("OWNERORMANAGINGAGENCY_desc"), GU, "official_boundary", "authoritative", 0.9, source_record_id=rec))
                self.features.append(f)

    def hydro(self) -> None:
        for layer in ("NHDWaterbody", "NHDArea", "NHDFlowline", "NHDLine"):
            for r in read_layer(NHD, layer):
                g = r["_geom"]
                rec = str(r.get("permanent_identifier"))
                cls = (r.get("fcode_description") or "water").split(":")[0].strip().lower().replace(" ", "_").replace("/", "_")
                zone = self._scope(g, "water", f"{NHD}:{layer}", rec, cls)
                if not zone:
                    continue
                f = Feature(ids.make("water", "nhd", rec), "water", cls, g, NHD, f"{layer}:{rec}", "nhd_1_24k_compilation", "derived", 0.6, 12.0,
                            subclass=r.get("fcode_description"), name=r.get("gnis_name"), zone=zone, scope=self.zones.scope_of(zone),
                            observed_at=_date(r.get("fdate")), source_epoch="2024-01-16")
                f.links.append(Link(NHD, layer, rec, "geometry", "identity", None, _date(r.get("fdate"))))
                f.add(Attr("nhd_fcode", r.get("fcode_description"), NHD, "nhd_attribute", "authoritative", 0.8, source_record_id=rec),
                      Attr("name", r.get("gnis_name"), NHD, "gnis_name", "authoritative", 0.9, source_record_id=rec))
                self.water_candidates.append(f)

    def run(self) -> None:
        self.structures()
        self.transport()
        self.admin()
        self.hydro()

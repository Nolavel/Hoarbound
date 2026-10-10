"""Explicit conflation: one canonical feature per real object, every merged source linked.

Rules and thresholds come from config/conflation_rules.json; every decision is written
as a source_link row (match_method, match_score) so it can be audited and reversed.
"""
from __future__ import annotations

from collections import defaultdict

import numpy as np
import shapely
from shapely.strtree import STRtree

from . import config, ids
from .model import RECON_RANK, Attr, Excluded, Feature, Link, geometry_hash

NSD = "usgs_nsd_fl_20260227"
NTD = "usgs_ntd_fl_20260211"
LEGACY = "hoarbound_legacy_osm_2026_09_29"
DRIVEABLE = {"motorway", "trunk", "primary", "secondary", "tertiary", "residential", "living_street", "unclassified", "service"}


def rules() -> dict:
    return config.load("conflation_rules.json")


def _iou(a, b) -> tuple[float, float]:
    inter = a.intersection(b).area
    if inter <= 0:
        return 0.0, 0.0
    return inter / (a.area + b.area - inter), inter / min(a.area, b.area)


def buildings(features: list[Feature], usa: list[Feature], idreg: ids.IdRegistry, excluded: list[Excluded]) -> dict:
    r = rules()["buildings"]["match"]
    base = [f for f in features if f.family == "buildings"]
    geoms = [f.geom for f in base]
    tree = STRtree(geoms)
    stats = defaultdict(int)
    for cand in usa:
        idx = tree.query(cand.geom, predicate="intersects")
        matches = []
        for i in idx:
            iou, ov = _iou(cand.geom, geoms[i])
            if iou >= r["min_iou"] or ov >= r["min_overlap_of_smaller"]:
                matches.append((iou, ov, int(i)))
        if matches:
            stats["usa_matched"] += 1
            shared = len(matches) > 1
            for iou, ov, i in sorted(matches, reverse=True):
                f = base[i]
                f.links.append(Link(NSD, "Struct_Poly_FEMA", cand.geometry_record.split(":", 1)[1], "corroborates",
                                    "footprint_iou_many" if shared else "footprint_iou", round(iou, 3), cand.source_epoch))
                for a in cand.attrs:
                    if a.name in ("footprint_area_m2_source",):
                        continue
                    conf = a.confidence * (0.6 if shared else 1.0)
                    f.attrs.append(Attr(a.name, a.value, a.source_id, a.method, a.recon, round(conf, 3), a.source_record_id,
                                        a.unit, a.observed_at, a.source_epoch,
                                        note=(a.note or "") + ("; one USA Structures polygon covers several footprints" if shared else "")))
                if iou >= 0.5 and not shared:
                    f.geometry_recon = "cross_verified"
                    f.geometry_confidence = round(min(0.95, f.geometry_confidence + 0.08), 3)
                    f.last_verified = max(filter(None, [f.last_verified, cand.observed_at]), default=None)
                    stats["cross_verified_footprints"] += 1
            continue
        partial = [i for i in idx if cand.geom.intersection(geoms[i]).area > 0.3 * cand.geom.area]
        if partial:
            excluded.append(Excluded(NSD, "Struct_Poly_FEMA", cand.geometry_record, "building",
                                     f"duplicate_of:{base[partial[0]].feature_id} (partial overlap > 30 %)"))
            stats["usa_partial_duplicate"] += 1
            continue
        cand.feature_id = idreg.claim(cand.feature_id, cand.feature_id, (NSD, cand.geometry_record.split(":", 1)[1]))
        features.append(cand)
        stats["usa_added"] += 1
    return dict(stats)


def legacy_osm(features: list[Feature], city_preview: dict) -> dict:
    """OSM tags frozen in the Stage 5 snapshot (lanes, oneway, addr:*, ...) keyed by OSM id."""
    stats = defaultdict(int)
    roads = {}
    for road in city_preview["roads"]:
        osm = road["osm_id"].replace("way/", "w")
        roads[osm] = road
    buildings = {}
    for b in city_preview["buildings"]:
        buildings[b["osm_id"].replace("way/", "w").replace("relation/", "r")] = b
    epoch = "2026-09-29"
    for f in features:
        if f.family == "roads":
            ways = {ids.osm_key(l.source_record_id) for l in f.links if l.source_layer == "OpenStreetMap"}
            for w in ways:
                road = roads.get(w)
                if not road:
                    continue
                stats["roads_tagged"] += 1
                for key in ("lanes", "oneway", "surface", "bridge", "tunnel", "ref"):
                    if road.get(key):
                        f.add(Attr(f"osm:{key}", road[key], LEGACY, "osm_tag_frozen_snapshot", "derived", 0.8, f"way/{w[1:]}",
                                   source_epoch=epoch))
        elif f.family == "buildings" and f.geometry_record.startswith("OpenStreetMap:"):
            b = buildings.get(ids.osm_key(f.geometry_record.split(":", 1)[1]))
            if not b:
                continue
            stats["buildings_tagged"] += 1
            for key, value in b["metadata"].items():
                if key.startswith("street_hint") or key == "address_source":
                    continue
                f.add(Attr(f"osm:{key}", value, LEGACY, "osm_tag_frozen_snapshot", "derived", 0.8, b["osm_id"], source_epoch=epoch))
            if b["metadata"].get("addr:housenumber") and b["metadata"].get("addr:street"):
                f.add(Attr("address", f"{b['metadata']['addr:housenumber']} {b['metadata']['addr:street']}", LEGACY,
                           "osm_addr_tags", "derived", 0.8, b["osm_id"], source_epoch=epoch))
    return dict(stats)


def addresses_and_places(features: list[Feature]) -> dict:
    """Address points / POIs / public facilities inside a footprint become building attributes (point keeps its own feature)."""
    blds = [f for f in features if f.family == "buildings"]
    tree = STRtree([f.geom for f in blds])
    stats = defaultdict(int)
    for f in features:
        if f.family not in ("addresses", "places"):
            continue
        idx = tree.query(f.geom, predicate="within")
        if len(idx) != 1:
            continue
        b = blds[int(idx[0])]
        b.links.append(Link(f.geometry_source, f.family, f.feature_id, "attributes", "point_in_footprint", 1.0, f.source_epoch))
        if f.family == "addresses":
            stats["address_points_in_buildings"] += 1
            b.add(Attr("address", f.name, f.geometry_source, "address_point_in_footprint", "derived", 0.75, f.feature_id,
                       observed_at=f.observed_at, source_epoch=f.source_epoch))
        elif f.cls == "public_facility":
            stats["public_facilities_in_buildings"] += 1
            b.add(Attr("public_facility", f.subclass, f.geometry_source, "official_facility_in_footprint", "authoritative", 0.85,
                       f.feature_id, source_epoch=f.source_epoch))
        else:
            stats["pois_in_buildings"] += 1
            b.add(Attr("poi_category", f.subclass, f.geometry_source, "poi_in_footprint", "derived",
                       round(f.geometry_confidence * 0.9, 3), f.feature_id, source_epoch=f.source_epoch))
    return dict(stats)


def roads(features: list[Feature], tiger: list[dict], idreg: ids.IdRegistry, zones) -> dict:
    cfg = rules()["roads"]
    buf = cfg["cross_verification"]["buffer_m"]
    share_min = cfg["cross_verification"]["min_length_share"]
    road_feats = [f for f in features if f.family == "roads"]
    tiger_geoms = [t["_geom"] for t in tiger]
    tiger_tree = STRtree(tiger_geoms)
    osm_tree = STRtree([f.geom for f in road_feats])
    stats = defaultdict(int)
    for f in road_feats:
        if f.cls not in DRIVEABLE:
            continue
        idx = tiger_tree.query(f.geom.buffer(buf), predicate="intersects")
        if not len(idx):
            stats["osm_roads_without_tiger"] += 1
            continue
        near = shapely.union_all([tiger_geoms[i] for i in idx]).buffer(buf)
        share = f.geom.intersection(near).length / max(f.geom.length, 1e-6)
        if share >= share_min:
            best = max(idx, key=lambda i: tiger_geoms[i].buffer(buf).intersection(f.geom).length)
            t = tiger[int(best)]
            f.links.append(Link(NTD, "Trans_TrailSegment" if t.get("_trail") else "Trans_RoadSegment",
                                str(t.get("permanent_identifier") or t.get("permanentidentifier") or t.get("GLOBALID")), "corroborates",
                                "buffer_length_share", round(share, 3), str(t.get("loaddate"))[:10]))
            f.geometry_recon = "cross_verified"
            f.geometry_confidence = round(min(0.95, f.geometry_confidence + 0.07), 3)
            stats["osm_roads_cross_verified"] += 1
            if t.get("name"):
                f.add(Attr("name_tiger", t["name"], NTD, "census_tiger_name", "authoritative", 0.7, str(t.get("permanent_identifier"))))
                if f.name and (t["name"].lower().split()[0] in f.name.lower()):
                    stats["names_agree"] += 1
            for key in ("us_route", "state_route", "county_route"):
                if t.get(key):
                    f.add(Attr(key, t[key], NTD, "official_route_number", "authoritative", 0.9, str(t.get("permanent_identifier"))))
        else:
            stats["osm_roads_partial_tiger"] += 1
    for t in tiger:
        g = t["_geom"]
        idx = osm_tree.query(g.buffer(buf), predicate="intersects")
        covered = 0.0
        if len(idx):
            covered = g.intersection(shapely.union_all([road_feats[i].geom for i in idx]).buffer(buf)).length / max(g.length, 1e-6)
        if covered >= 0.3:
            continue
        zone, reason = zones.classify(g, "roads")
        if reason:
            continue
        rec = t.get("permanent_identifier") or t.get("permanentidentifier") or t.get("GLOBALID")
        rec = str(rec).strip("{}") if rec else f"geom{geometry_hash(g)}"
        cls = "path" if t.get("_trail") else ("tiger_" + str(t.get("mtfcc_code") or "road").lower())
        fid = idreg.claim(ids.make("roads", "usgs_ntd", rec), ids.make("roads", "usgs_ntd", rec), (NTD, rec))
        layer = "Trans_TrailSegment" if t.get("_trail") else "Trans_RoadSegment"
        nf = Feature(fid, "roads", cls, g, NTD, f"{layer}:{rec}", "census_tiger_centerline", "derived", 0.45, 8.0,
                     subclass=t.get("tnmfrc_desc"), name=t.get("name"), zone=zone, observed_at=str(t.get("loaddate"))[:10],
                     source_epoch="2026-02-11")
        nf.flags.add("single_source_unverified")
        nf.links.append(Link(NTD, layer, rec, "geometry", "identity", None, str(t.get("loaddate") or t.get("publisheddate"))[:10]))
        nf.add(Attr("name", t.get("name"), NTD, "census_tiger_name", "authoritative", 0.7, rec),
               Attr("mtfcc", t.get("mtfcc_code"), NTD, "census_feature_class", "authoritative", 0.8, rec))
        features.append(nf)
        stats["tiger_only_added"] += 1
    return dict(stats)


def road_widths(features: list[Feature]) -> None:
    table = rules()["roads"]["width_inference_m"]
    for f in features:
        if f.family != "roads" or f.candidates("width_m"):
            continue
        key = f.subclass if f.subclass in table else f.cls
        if key in table:
            f.add(Attr("width_m", table[key], "rule", "class_width_table", "inferred", 0.35, unit="m",
                       note="conflation_rules.json roads.width_inference_m"))


def runways(features: list[Feature], faa: list[Feature]) -> dict:
    stats = defaultdict(int)
    osm = [f for f in features if f.family == "airport" and f.cls == "runway"]
    for rf in faa:
        best = None
        for f in osm:
            if f.geom.intersects(rf.geom):
                score = f.geom.intersection(rf.geom).area / max(min(f.geom.area, rf.geom.area), 1e-6) if f.geom.area > 0 else \
                    f.geom.intersection(rf.geom).length / max(f.geom.length, 1e-6)
                if best is None or score > best[0]:
                    best = (score, f)
        if best and best[0] > 0.3:
            f = best[1]
            f.links.append(Link(f.geometry_source, "base/infrastructure", f.geometry_record, "attributes", "replaced_by_authoritative_geometry",
                                round(best[0], 3), f.source_epoch))
            f.links.extend(rf.links)
            f.geom = rf.geom
            f.geometry_source, f.geometry_record, f.geometry_method = rf.geometry_source, rf.geometry_record, rf.geometry_method
            f.geometry_recon, f.geometry_confidence, f.geometry_accuracy_m = "authoritative", 0.92, rf.geometry_accuracy_m
            f.attrs.extend(rf.attrs)
            stats["runways_authoritative_geometry"] += 1
        else:
            features.append(rf)
            stats["runways_added"] += 1
    return dict(stats)


def water(features: list[Feature], nhd: list[Feature], idreg: ids.IdRegistry) -> dict:
    stats = defaultdict(int)
    polys = [f for f in features if f.family == "water" and f.geom.geom_type in ("Polygon", "MultiPolygon")]
    tree = STRtree([f.geom for f in polys])
    for n in nhd:
        if n.cls == "coastline":
            n.family = "coastline"
            n.feature_id = idreg.claim(ids.make("coastline", "nhd", n.geometry_record.split(":", 1)[1]), n.feature_id)
            features.append(n)
            stats["nhd_coastline"] += 1
            continue
        if n.geom.geom_type in ("LineString", "MultiLineString"):
            n.feature_id = idreg.claim(n.feature_id, n.feature_id)
            features.append(n)
            stats["nhd_lines"] += 1
            continue
        best = None
        for i in tree.query(n.geom, predicate="intersects"):
            iou, _ = _iou(n.geom, polys[i].geom)
            if best is None or iou > best[0]:
                best = (iou, polys[i])
        if best and best[0] >= rules()["water"]["match"]["min_iou"]:
            f = best[1]
            f.links.append(Link(n.geometry_source, n.geometry_record.split(":")[0], n.geometry_record.split(":", 1)[1], "corroborates",
                                "polygon_iou", round(best[0], 3), n.source_epoch))
            f.attrs.extend(n.attrs)
            f.geometry_recon = "cross_verified"
            stats["nhd_matched"] += 1
        else:
            n.feature_id = idreg.claim(n.feature_id, n.feature_id)
            features.append(n)
            stats["nhd_added"] += 1
    return dict(stats)


def select_attributes(features: list[Feature]) -> None:
    """Marks one selected value per attribute name: highest reconstruction rank, then confidence."""
    for f in features:
        by = defaultdict(list)
        for a in f.attrs:
            a.selected = False
            by[a.name].append(a)
        for name, cands in by.items():
            if name in ("osm_tags",):
                for a in cands:
                    a.selected = True
                continue
            best = max(cands, key=lambda a: (RECON_RANK.get(a.recon, 0), a.confidence))
            best.selected = True


def power_topology(features: list[Feature]) -> tuple[list, dict]:
    from .model import Edge
    tol = rules()["power"]["pole_on_line_tolerance_m"]
    supports = [f for f in features if f.family == "power" and f.geom.geom_type == "Point"]
    lines = [f for f in features if f.family == "power" and f.geom.geom_type in ("LineString", "MultiLineString")]
    pts = np.array([[f.geom.x, f.geom.y] for f in supports]) if supports else np.zeros((0, 2))
    tree = STRtree([f.geom for f in supports]) if supports else None
    edges = []
    stats = defaultdict(int)
    connected = set()
    for line in lines:
        parts = list(line.geom.geoms) if line.geom.geom_type == "MultiLineString" else [line.geom]
        n = 0
        for part in parts:
            coords = list(part.coords)
            ids_on = []
            for x, y in coords:
                hit = None
                if tree is not None:
                    idx = tree.query(shapely.Point(x, y).buffer(tol), predicate="intersects")
                    if len(idx):
                        d = np.hypot(pts[idx, 0] - x, pts[idx, 1] - y)
                        hit = supports[int(idx[int(np.argmin(d))])].feature_id
                ids_on.append(hit)
            for k in range(len(coords) - 1):
                a, b = ids_on[k], ids_on[k + 1]
                seg = shapely.LineString([coords[k], coords[k + 1]])
                conf = 0.85 if a and b else 0.5
                edges.append(Edge(f"{line.feature_id}#{n}", line.cls, a, b, line.feature_id, seg,
                                  "osm_way_vertex_sequence", "derived", conf))
                n += 1
                if a and b:
                    stats["edges_pole_to_pole"] += 1
                else:
                    stats["edges_open_end"] += 1
                connected.update(x for x in (a, b) if x)
    stats["supports_total"] = len(supports)
    stats["supports_in_topology"] = len(connected)
    stats["supports_position_only"] = len(supports) - len(connected)
    for f in supports:
        f.add(Attr("in_line_topology", f.feature_id in connected, "rule", "pole_on_line_vertex", "derived", 0.9))
    return edges, dict(stats)


LAND_PRIORITY = {"landmass": 0, "island": 1, "islet": 2, "archipelago": 3}


def dedupe_identical_land(features: list[Feature], excluded: list[Excluded]) -> dict:
    """Overture emits one OSM closed way as both a coastline 'land' polygon and a place=island
    polygon. Same object, same geometry: keep one canonical feature, fold the other in as links."""
    from .model import geometry_hash
    groups = defaultdict(list)
    for f in features:
        if f.family == "land" and f.geometry_source.startswith("overture"):
            groups[geometry_hash(f.geom)].append(f)
    drop = set()
    for group in groups.values():
        if len(group) < 2:
            continue
        group.sort(key=lambda f: (LAND_PRIORITY.get(f.cls, 9), f.feature_id))
        keep = group[0]
        for other in group[1:]:
            keep.links.extend(Link(l.source_id, l.source_layer, l.source_record_id, "duplicate_of", "identical_geometry", 1.0, l.source_version)
                              for l in other.links if l.role == "geometry")
            keep.add(Attr("place_class", other.cls, other.geometry_source, "osm_place_tag", "derived", 0.85, other.geometry_record))
            if other.name and not keep.name:
                keep.name = other.name
            keep.attrs.extend(a for a in other.attrs if a.name == "name")
            excluded.append(Excluded(other.geometry_source, "base/land", other.feature_id, other.cls, f"merged_into:{keep.feature_id}"))
            drop.add(id(other))
    features[:] = [f for f in features if id(f) not in drop]
    return {"land_duplicates_merged": len(drop)}

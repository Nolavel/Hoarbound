"""normalize -> conflate -> measure -> select -> write library. Deterministic for a given raw cache."""
from __future__ import annotations

import json
import time
from collections import Counter, defaultdict

import numpy as np
import rasterio
import rasterio.features
import shapely
import shapely.geometry
from scipy import ndimage
from shapely.strtree import STRtree

from . import PIPELINE_VERSION, SCHEMA_VERSION, config, conflate, frame, ids, library, lidar, overrides, paths, receipts
from .model import Attr, Excluded, Feature, Link
from .normalize_overture import OvertureNormalizer
from .normalize_usgs import UsgsNormalizer
from .zones import Zones

L19 = "noaa_lidar_9081"
L16 = "noaa_lidar_6246"
DEM = "noaa_dem_6366"
WC = "esa_worldcover_2021_v200"
WC_CLASSES = {10: "wc_tree_cover", 20: "wc_shrubland", 90: "wc_herbaceous_wetland", 95: "mangrove"}


def _log(*a) -> None:
    print("[build]", *a, flush=True)


def building_measurements(features: list[Feature], dem: lidar.DemCrop) -> dict:
    q = conflate.rules()["buildings"]["lidar_height_quality"]
    g19, g16 = lidar.LidarGrids(L19), lidar.LidarGrids(L16)
    blds = sorted([f for f in features if f.family == "buildings"], key=lambda f: (round(f.geom.centroid.x / 500), round(f.geom.centroid.y / 500)))
    stats = Counter()
    for f in blds:
        c = f.geom.centroid
        s19 = lidar.footprint_stats(g19, dem, f.geom, q)
        s16 = lidar.footprint_stats(g16, dem, f.geom, q)
        d19, d16 = g19.date_at(c.x, c.y), g16.date_at(c.x, c.y)
        rec = f"footprint:{f.feature_id}"
        h19 = h16 = None
        if s19 and s19.get("usable") and q["min_plausible_m"] <= s19["height_p95_m"] <= q["max_plausible_m"]:
            h19 = s19["height_p95_m"]
            f.add(Attr("height_m", h19, L19, "lidar_dsm_p95_minus_ground", "measured", 0.85, rec, "m", d19, "2019",
                       note=f"ground={s19['ground_method']}; coverage={s19['coverage']}"),
                  Attr("roof_median_height_m", s19["height_p50_m"], L19, "lidar_dsm_p50_minus_ground", "measured", 0.8, rec, "m", d19, "2019"),
                  Attr("roof_relief_m", s19["roof_relief_m"], L19, "lidar_dsm_p90_minus_p10", "measured", 0.8, rec, "m", d19, "2019"),
                  Attr("roof_form", "flat" if s19["roof_relief_m"] < 0.6 else "pitched_or_complex", L19, "lidar_roof_relief_threshold_0.6m",
                       "derived", 0.6, rec, observed_at=d19, source_epoch="2019"))
            stats["height_lidar_2019"] += 1
        if s19:
            f.add(Attr("ground_elevation_m", s19["ground_m"], L19, s19["ground_method"], "measured", 0.85, rec, "m NAVD88", d19, "2019"),
                  Attr("lidar_support", s19.get("lidar_support"), L19, "share_of_cells_above_2m", "measured", 0.8, rec, observed_at=d19),
                  Attr("lidar_coverage", s19["coverage"], L19, "share_of_cells_with_returns", "measured", 0.9, rec, observed_at=d19))
        if s16 and s16.get("usable") and q["min_plausible_m"] <= s16["height_p95_m"] <= q["max_plausible_m"]:
            h16 = s16["height_p95_m"]
            f.add(Attr("height_m", h16, L16, "lidar_dsm_p95_minus_ground", "measured", 0.8, rec, "m", d16, "2016",
                       note=f"ground={s16['ground_method']}; coverage={s16['coverage']}"))
            stats["height_lidar_2016"] += 1
        if h19 is not None and h16 is not None:
            tol = max(q["cross_verify_tolerance_m"], q["cross_verify_tolerance_ratio"] * h19)
            if abs(h19 - h16) <= tol:
                f.add(Attr("height_m", round((h19 + h16) / 2, 2), "rule", "lidar_2016_2019_agreement", "cross_verified", 0.92, rec, "m",
                           d19, "2016+2019", note=f"2019={h19}; 2016={h16}; tolerance={round(tol, 2)}"))
                stats["height_cross_verified"] += 1
            elif abs(h19 - h16) > max(2.5, 0.25 * max(h19, h16)):
                f.flags.add("height_changed_2016_2019")
                stats["height_changed_2016_2019"] += 1
        if h19 is None and (s19 is None or not s19.get("usable")):
            stats["no_usable_lidar_2019"] += 1
        levels = [a for a in f.candidates("levels") if a.value]
        heights = [a for a in f.candidates("height_m")]
        if not heights and levels:
            f.add(Attr("height_m", round(float(levels[0].value) * 3.0, 2), "rule", "levels_x_3m", "inferred", 0.4, unit="m",
                       note="no measured height; OSM levels x 3 m"))
            stats["height_inferred_from_levels"] += 1
        if not levels and h19 is not None:
            f.add(Attr("levels", max(1, int(round(s19["height_p50_m"] / 3.2))), "rule", "lidar_roof_median_div_3.2m", "inferred", 0.4,
                       note="no mapped levels; measured 2019 median roof height / 3.2 m (P95 can include overhanging canopy)"))
    return dict(stats)


def lidar_trees(features: list[Feature], dem: lidar.DemCrop, zones: Zones, idreg: ids.IdRegistry) -> dict:
    params = conflate.rules()["trees"]["lidar"]
    g19 = lidar.LidarGrids(L19)
    bunion = shapely.union_all([f.geom for f in features if f.family == "buildings"])
    land = shapely.union_all(zones.scope_land)
    found, dense = lidar.detect_trees(g19, dem, bunion, params, land)
    stats = Counter()
    for g in dense:
        zone, reason = zones.classify(g, "vegetation_areas")
        if reason:
            continue
        c = g.representative_point()
        rec = f"E{round(c.x):.0f}N{round(c.y):.0f}"
        fid = idreg.claim(ids.make("vegetation_areas", "lidar2019", rec), ids.make("vegetation_areas", "lidar2019", rec), (L19, f"canopy:{rec}"))
        f = Feature(fid, "vegetation_areas", "lidar_canopy_dense", g.simplify(0.5), L19, f"canopy:{rec}", "lidar_chm_ge_2m_connected_area",
                    "derived", 0.7, 1.0, zone=zone, observed_at="2019", source_epoch="2019")
        f.links.append(Link(L19, "chm_canopy", f"canopy:{rec}", "geometry", "detection", None, "2019"))
        f.add(Attr("area_m2", round(g.area, 1), L19, "polygon_area", "measured", 0.8, rec, "m2"),
              Attr("individual_trees", "not_separated", "rule", "dense_canopy_policy", "derived", 1.0,
                   note="crowns are not split inside dense canopy; no individual trees are invented"))
        features.append(f)
        stats["dense_canopy_areas"] += 1
    osm_trees = [f for f in features if f.family == "trees" and f.geom.geom_type == "Point"]
    tree = STRtree([f.geom for f in osm_trees]) if osm_trees else None
    radius = conflate.rules()["trees"]["osm_match_radius_m"]
    claimed = set()
    for t in found:
        p = shapely.Point(t["x"], t["y"])
        zone, reason = zones.classify(p, "trees")
        if reason:
            stats[f"excluded_{reason}"] += 1
            continue
        rec = f"E{t['x']:.1f}N{t['y']:.1f}"
        attrs = [Attr("height_m", t["height_m"], L19, "lidar_chm_local_max", "measured", 0.75, rec, "m", t["date"], "2019"),
                 Attr("crown_radius_m", t["crown_radius_m"], L19, "lidar_chm_half_height_area", "derived", 0.55, rec, "m", t["date"], "2019"),
                 Attr("canopy_roughness_m", t["roughness_m"], L19, "lidar_dsm_std_2.5m", "measured", 0.7, rec, "m", t["date"], "2019")]
        match = None
        if tree is not None:
            idx = tree.query(p.buffer(radius), predicate="intersects")
            idx = [i for i in idx if i not in claimed]
            if idx:
                match = min(idx, key=lambda i: osm_trees[i].geom.distance(p))
        if match is not None:
            claimed.add(match)
            f = osm_trees[match]
            f.links.append(Link(L19, "chm_peaks", rec, "corroborates", "nearest_within_3m", round(f.geom.distance(p), 2), "2019"))
            f.attrs.extend(attrs)
            f.geometry_recon = "cross_verified"
            f.geometry_confidence = round(min(0.95, f.geometry_confidence + 0.08), 3)
            stats["osm_trees_confirmed_by_lidar"] += 1
            continue
        fid = idreg.claim(ids.make("trees", "lidar2019", rec), ids.make("trees", "lidar2019", rec), (L19, rec))
        f = Feature(fid, "trees", "tree", p, L19, f"chm_peaks:{rec}", "lidar_chm_local_maxima_v1", "derived", t["confidence"], 1.0,
                    subclass="lidar_candidate", zone=zone, observed_at=t["date"], source_epoch="2019", last_verified=t["date"])
        f.links.append(Link(L19, "chm_peaks", rec, "geometry", "detection", t["confidence"], "2019"))
        f.attrs.extend(attrs)
        features.append(f)
        stats["lidar_tree_candidates"] += 1
    stats["osm_trees_without_lidar_peak"] = len(osm_trees) - len(claimed)
    return dict(stats)


def worldcover_areas(features: list[Feature], zones: Zones) -> dict:
    path = paths.RAW / WC / "worldcover_extent.tif"
    stats = Counter()
    with rasterio.open(path) as src:
        data = src.read(1)
        transform = src.transform
    for value, cls in WC_CLASSES.items():
        mask = data == value
        if not mask.any():
            continue
        labels, _ = ndimage.label(mask)
        for geom, val in rasterio.features.shapes(labels.astype(np.int32), mask=mask, transform=transform):
            g = frame.to_projected(shapely.geometry.shape(geom))
            if g.area < 500.0:
                continue
            zone, reason = zones.classify(g, "vegetation_areas")
            if reason:
                stats[f"excluded_{reason}"] += 1
                continue
            c = g.representative_point()
            rec = f"{value}:E{round(c.x, -1):.0f}N{round(c.y, -1):.0f}"
            fid = ids.make("vegetation_areas", "worldcover2021", rec)
            f = Feature(fid, "vegetation_areas", cls, g, WC, f"map:{rec}", "sentinel_ml_classification_10m", "derived", 0.6, 10.0,
                        subclass=f"worldcover_{value}", zone=zone, observed_at="2021", source_epoch="2021-v200")
            f.links.append(Link(WC, "map", rec, "geometry", "raster_polygonize", None, "v200"))
            f.add(Attr("worldcover_class", value, WC, "raster_value", "derived", 0.6, rec, source_epoch="2021"))
            features.append(f)
            stats[cls] += 1
    return dict(stats)


def coastline_and_shoreline(features: list[Feature], dem: lidar.DemCrop, zones: Zones, idreg: ids.IdRegistry) -> dict:
    stats = Counter()
    for f in [f for f in features if f.family == "land" and f.cls == "landmass"]:
        polys = list(f.geom.geoms) if f.geom.geom_type == "MultiPolygon" else [f.geom]
        k = 0
        for p in polys:
            for ring in [p.exterior, *p.interiors]:
                line = shapely.LineString(ring.coords)
                if not zones.rect.intersects(line):
                    continue
                fid = idreg.claim(f"kw:coastline:{f.feature_id.split(':', 2)[2]}:{k}", f"kw:coastline:{f.feature_id.split(':', 2)[2]}:{k}")
                c = Feature(fid, "coastline", "coastline", line, f.geometry_source, f.geometry_record, "land_polygon_boundary",
                            "derived", 0.75, 3.0, subclass="osm_coastline", zone=f.zone, scope=f.scope,
                            observed_at=f.observed_at, source_epoch=f.source_epoch)
                c.links.append(Link(f.geometry_source, "base/land", f.feature_id, "geometry", "boundary_of", None, f.source_epoch))
                features.append(c)
                k += 1
                stats["osm_coastline_rings"] += 1
    # Measured shoreline: NAVD88 0 m contour of the 2016 topobathy DEM, as land polygons.
    data = np.nan_to_num(dem.data, nan=-99.0)
    mask = (data >= 0.0).astype(np.uint8)
    mask = ndimage.binary_opening(mask, iterations=1).astype(np.uint8)
    rect = zones.rect
    for geom, val in rasterio.features.shapes(mask, mask=mask.astype(bool), transform=dem.transform):
        g = shapely.geometry.shape(geom)
        if g.area < 200.0 or not rect.intersects(g):
            continue
        g = g.simplify(0.75, preserve_topology=True)
        zone, reason = zones.classify(g, "land")
        if reason:
            continue
        c = g.representative_point()
        rec = f"E{round(c.x):.0f}N{round(c.y):.0f}"
        fid = idreg.claim(ids.make("land", "dem6366_0m", rec), ids.make("land", "dem6366_0m", rec))
        f = Feature(fid, "land", "dem_land_above_navd88_0m", g, DEM, f"contour0:{rec}", "dem_threshold_0m_polygonize_simplify_0.75m",
                    "measured", 0.85, 1.0, zone=zone, scope=zones.scope_of(zone), observed_at="2016-04", source_epoch="2016")
        f.links.append(Link(DEM, "mosaic", rec, "geometry", "raster_polygonize", None, "6366"))
        f.add(Attr("area_m2", round(g.area, 1), DEM, "polygon_area", "measured", 0.85, rec, "m2"))
        features.append(f)
        stats["dem_shoreline_polygons"] += 1
    return dict(stats)


def shoreline_alignment(features: list[Feature]) -> dict:
    osm = [f.geom for f in features if f.family == "coastline" and f.subclass == "osm_coastline" and f.scope == "reality"]
    dem = shapely.union_all([f.geom.boundary for f in features if f.family == "land" and f.cls == "dem_land_above_navd88_0m"])
    if not osm or dem.is_empty:
        return {}
    pts = []
    for line in osm:
        n = max(2, int(line.length // 10))
        pts.extend(line.interpolate(np.linspace(0, line.length, n)))
    d = np.array([dem.distance(p) for p in pts])
    return {"samples": int(len(d)), "median_m": round(float(np.median(d)), 2), "p90_m": round(float(np.percentile(d, 90)), 2),
            "share_within_5m": round(float(np.mean(d <= 5.0)), 3)}


def barrier_context(features: list[Feature]) -> dict:
    coast = shapely.union_all([f.geom for f in features if f.family == "coastline" and f.scope == "reality"])
    stats = Counter()
    for f in features:
        if f.family == "barriers" and f.cls in ("wall", "retaining_wall", "fence", "barrier") and f.geom.geom_type != "Point":
            d = f.geom.distance(coast)
            f.add(Attr("distance_to_coastline_m", round(d, 1), "rule", "geometry_distance", "derived", 0.8, unit="m"))
            if f.cls in ("wall", "retaining_wall") and d <= 5.0:
                f.add(Attr("possible_seawall", True, "rule", "wall_within_5m_of_coastline", "inferred", 0.4))
                stats["possible_seawalls"] += 1
    return dict(stats)


def terrain_coverage(features: list[Feature], dem: lidar.DemCrop, zones: Zones) -> dict:
    valid = np.isfinite(dem.data)
    rel = paths.rel(dem.path)
    g = zones.rect
    fid = "kw:terrain:noaa:6366"
    f = Feature(fid, "terrain_coverage", "dem", g, DEM, "mosaic_m6366", "topobathy_lidar_dem_1m", "measured", 0.9, 1.0,
                zone="extent", observed_at="2016-04-19/2016-04-25", source_epoch="2017-03-15")
    f.links.append(Link(DEM, "mosaic", "2016_key_west_mosaic_m6366.tif", "geometry", "identity", None, "etag 38aab58423b972e783fdc666d099d0db-78"))
    f.add(Attr("vertical_datum", "NAVD88 (GEOID12B)", DEM, "fgdc_metadata", "authoritative", 1.0),
          Attr("horizontal_datum", "NAD83(2011) UTM 17N (file label EPSG:32617)", DEM, "fgdc_metadata", "authoritative", 1.0),
          Attr("resolution_m", 1.0, DEM, "fgdc_metadata", "authoritative", 1.0),
          Attr("vertical_accuracy_m", 0.15, DEM, "fgdc_metadata", "authoritative", 1.0),
          Attr("valid_share_in_extent", round(float(valid.mean()), 4), DEM, "pixel_count", "measured", 1.0),
          Attr("height_range_m", [round(float(np.nanmin(dem.data)), 2), round(float(np.nanmax(dem.data)), 2)], DEM, "pixel_stats", "measured", 1.0),
          Attr("raw_crop", rel, DEM, "cache_path", "derived", 1.0),
          Attr("runtime_heightmap", "world/terrain/key_west_preview_2m_la8.png (legacy crop, unchanged)", "rule", "runtime_link", "derived", 1.0))
    features.append(f)
    return {"valid_share": round(float(valid.mean()), 4)}


def bind_facts(features: list[Feature]) -> dict:
    """Documentary facts (config/fact_bindings.json) as attribute candidates on existing features."""
    by_id = {f.feature_id: f for f in features}
    stats = Counter()
    for b in config.load("fact_bindings.json")["bindings"]:
        f = by_id.get(b["feature_id"])
        if f is None:
            raise SystemExit(f"fact binding targets missing feature {b['feature_id']}")
        f.links.append(Link(b["source_id"], "facts", b["record"], "attributes", "documentary_fact_binding", 1.0, None))
        for name, fact in b["facts"].items():
            f.add(Attr(name, fact["value"], b["source_id"], "documentary_record", b["recon"], b["confidence"], b["record"],
                       fact.get("unit"), note=fact.get("note")))
            stats[b["source_id"]] += 1
    return dict(stats)


def chunk_and_local(features: list[Feature]) -> None:
    for f in features:
        p = frame.representative_point(f.geom)
        x, z = frame.projected_to_local(p.x, p.y)
        f._local = (round(x, 2), round(z, 2))
        f._chunk = frame.chunk_of_local(x, z)


def run() -> None:
    t0 = time.time()
    zones = Zones()
    identity = library.identity_map()
    idreg = ids.IdRegistry(identity)
    _log("identity map entries from previous library:", len(identity))
    ov = OvertureNormalizer(zones, idreg)
    ov.run()
    features, excluded = ov.features, ov.excluded
    _log("overture", Counter(f.family for f in features))
    us = UsgsNormalizer(zones, idreg)
    us.run()
    features.extend(us.features)
    excluded.extend(us.excluded)
    stats = {}
    city = json.loads((paths.LEGACY / "city_preview.json").read_text(encoding="utf-8"))
    stats["land_dedupe"] = conflate.dedupe_identical_land(features, excluded)
    stats["legacy_osm"] = conflate.legacy_osm(features, city)
    stats["buildings"] = conflate.buildings(features, us.building_candidates, idreg, excluded)
    stats["roads"] = conflate.roads(features, us.road_candidates, idreg, zones)
    conflate.road_widths(features)
    stats["runways"] = conflate.runways(features, us.runway_candidates)
    stats["water"] = conflate.water(features, us.water_candidates, idreg)
    stats["addresses_places"] = conflate.addresses_and_places(features)
    _log("conflation", json.dumps(stats))
    dem = lidar.DemCrop()
    stats["building_lidar"] = building_measurements(features, dem)
    _log("building lidar", stats["building_lidar"], f"{time.time() - t0:.0f}s")
    stats["trees"] = lidar_trees(features, dem, zones, idreg)
    _log("trees", stats["trees"], f"{time.time() - t0:.0f}s")
    stats["worldcover"] = worldcover_areas(features, zones)
    stats["coast"] = coastline_and_shoreline(features, dem, zones, idreg)
    stats["shoreline_alignment_osm_vs_dem_0m"] = shoreline_alignment(features)
    stats["barriers"] = barrier_context(features)
    stats["terrain"] = terrain_coverage(features, dem, zones)
    edges, stats["power_topology"] = conflate.power_topology(features)
    g19 = lidar.LidarGrids(L19)
    x0, y0 = frame.local_to_projected(-3300, 700)
    x1, y1 = frame.local_to_projected(-1800, -300)
    osm_fp = [f.geom for f in features if f.family == "buildings" and f.geometry_record.startswith("OpenStreetMap:")]
    stats["vector_vs_lidar_alignment"] = lidar.alignment_offset(g19, dem, osm_fp, shapely.box(x0, y0, x1, y1))
    usa_fp = [c.geom for c in us.building_candidates]
    stats["usa_structures_vs_lidar_alignment"] = lidar.alignment_offset(g19, dem, usa_fp, shapely.box(x0, y0, x1, y1))
    _log("alignment", stats["vector_vs_lidar_alignment"], stats["usa_structures_vs_lidar_alignment"])
    stats["documentary_facts"] = bind_facts(features)
    conflate.select_attributes(features)
    chunk_and_local(features)
    ov_layer = overrides.load()
    stats["id_collisions"] = idreg.collisions
    stats["ids_carried_from_previous_library"] = idreg.carried
    meta = {"schema_version": SCHEMA_VERSION, "pipeline_version": PIPELINE_VERSION,
            "built_at": receipts.now_utc(), "frame": "config/frame.json", "extent": "config/extent.json",
            "build_stats": stats}
    library.write(features, edges, excluded, ov_layer, meta)
    (paths.REPORTS / "build_stats.json").write_text(json.dumps(stats, indent=1, default=str) + "\n", encoding="utf-8")
    _log(f"done in {time.time() - t0:.0f}s; features={len(features)} excluded={len(excluded)} edges={len(edges)}")

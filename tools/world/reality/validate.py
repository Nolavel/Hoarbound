"""Automatic checks of the Reality Library. Writes reports/validation_report.{json,md}; exits 1 on errors.

Errors break the contract (provenance, IDs, scope, locked assets). Warnings are real-world
data issues kept as-is in reality (the source geometry is never silently 'fixed').
"""
from __future__ import annotations

import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict

import numpy as np
import shapely
import shapely.prepared
from shapely import validation as sv
from shapely.strtree import STRtree

from . import PIPELINE_VERSION, config, library, overrides, paths, regen

ID_RE = re.compile(r"^kw:[a-z_]+:[a-z0-9_]+:[^\s]+$")
BUILDING_HEIGHT_RANGE = (1.8, 80.0)


def _attrs(col, i) -> dict:
    return json.loads(col["attrs_json"][i])


def run() -> dict:
    lib = paths.LIBRARY
    errors: list[str] = []
    warnings: dict[str, list] = defaultdict(list)
    counts: dict[str, int] = {}
    ext = config.extent()
    pb = ext["projected_bounds"]
    rect = shapely.box(pb["min_e"], pb["min_n"], pb["max_e"], pb["max_n"])
    rect_p = shapely.prepared.prep(rect)
    con = sqlite3.connect(lib)
    data = {}
    for fam in library.families():
        geoms, cols = library.read_layer(fam)
        data[fam] = (geoms, cols)
        counts[fam] = len(geoms)

    # IDs: format, uniqueness across all layers
    seen = Counter()
    for fam, (geoms, cols) in data.items():
        for fid in cols["feature_id"]:
            seen[fid] += 1
            if not ID_RE.match(fid):
                errors.append(f"bad feature_id format: {fid}")
    dups = [f for f, n in seen.items() if n > 1]
    if dups:
        errors.append(f"duplicate canonical feature ids: {len(dups)} e.g. {dups[:5]}")

    # Geometry validity / broken lines / extent / CRS sanity
    invalid = Counter()
    for fam, (geoms, cols) in data.items():
        for i, g in enumerate(geoms):
            fid = cols["feature_id"][i]
            if g is None or g.is_empty:
                errors.append(f"{fid}: empty geometry")
                continue
            if g.geom_type in ("Polygon", "MultiPolygon") and not g.is_valid:
                reason = sv.explain_validity(g)
                invalid[(fam, reason.split("[")[0].strip())] += 1
                if len(warnings["invalid_polygons"]) < 40:
                    warnings["invalid_polygons"].append(f"{fid}: {reason}")
            if g.geom_type in ("LineString", "MultiLineString"):
                if g.length <= 0.01:
                    warnings["broken_lines"].append(f"{fid}: zero-length line")
            b = g.bounds
            if abs(b[0]) < 360 and abs(b[1]) < 360:
                errors.append(f"{fid}: coordinates look geographic, CRS conversion missing")
            if not rect_p.intersects(g):
                errors.append(f"{fid}: outside configured extent")
            elif b[0] < pb["min_e"] - 20000 or b[2] > pb["max_e"] + 20000 or b[1] < pb["min_n"] - 20000 or b[3] > pb["max_n"] + 20000:
                warnings["extends_far_beyond_extent"].append(f"{fid} ({fam}) bounds {[round(v) for v in b]}")
    for (fam, reason), n in invalid.items():
        warnings["invalid_polygon_summary"].append(f"{fam}: {n} x {reason}")

    # Scope: Boca Chica holds outline families only
    for fam, (geoms, cols) in data.items():
        for i, z in enumerate(cols["zone"]):
            if z == "boca_chica_silhouette" and fam not in ("land", "coastline", "water", "terrain_coverage", "vegetation_areas"):
                errors.append(f"{cols['feature_id'][i]}: {fam} feature inside Boca Chica silhouette zone")

    # Buildings: heights, ocean, duplicates
    bg, bc = data.get("buildings", ([], {}))
    land = shapely.union_all([g for g, c in zip(*_layer(data, "land")) if c in ("landmass", "dem_land_above_navd88_0m")])
    land5 = land.buffer(5.0)
    shapely.prepare(land5)
    for i, g in enumerate(bg):
        a = _attrs(bc, i)
        h = a.get("height_m")
        if h is not None and not (BUILDING_HEIGHT_RANGE[0] <= float(h) <= BUILDING_HEIGHT_RANGE[1]):
            warnings["implausible_building_height"].append(f"{bc['feature_id'][i]}: {h} m")
        if not land5.contains(g.representative_point()):
            warnings["building_in_water"].append(f"{bc['feature_id'][i]} ({bc['class'][i]}/{bc['subclass'][i]}) local=({bc['local_x'][i]:.0f},{bc['local_z'][i]:.0f})")
    tree = STRtree(bg)
    dup_pairs = 0
    for i, g in enumerate(bg):
        for j in tree.query(g, predicate="intersects"):
            if j <= i:
                continue
            inter = g.intersection(bg[j]).area if g.is_valid and bg[j].is_valid else 0.0
            if inter > 0.8 * min(g.area, bg[j].area):
                dup_pairs += 1
                if len(warnings["overlapping_buildings"]) < 40:
                    warnings["overlapping_buildings"].append(f"{bc['feature_id'][i]} ~ {bc['feature_id'][j]}")
    counts["overlapping_building_pairs"] = dup_pairs

    # Identical geometries in one family from different features
    for fam, (geoms, cols) in data.items():
        hashes = Counter(cols["geometry_hash"])
        same = [h for h, n in hashes.items() if n > 1]
        if same:
            warnings["identical_geometry"].append(f"{fam}: {len(same)} hashes shared by >1 feature")

    # Coastal: piers attached to land/coast
    cg, cc = data.get("coastal_structures", ([], {}))
    coast = land5
    for i, g in enumerate(cg):
        if cc["class"][i] == "pier" and not coast.intersects(g):
            warnings["pier_detached_from_coast"].append(f"{cc['feature_id'][i]} subclass={cc['subclass'][i]}")

    # Power: positions and topology
    pg, pc = data.get("power", ([], {}))
    for i, g in enumerate(pg):
        if pc["class"][i] in ("power_pole", "power_tower") and (g.geom_type != "Point" or g.is_empty):
            errors.append(f"{pc['feature_id'][i]}: pole/tower without point position")
    edges = con.execute("SELECT COUNT(*), SUM(from_feature_id IS NULL OR to_feature_id IS NULL) FROM utility_topology").fetchone()
    counts["utility_edges"], counts["utility_edges_open_end"] = edges[0], int(edges[1] or 0)

    # Provenance
    no_geom_src = con.execute("""SELECT COUNT(*) FROM feature_index fi WHERE NOT EXISTS
        (SELECT 1 FROM link_store l JOIN link_kind k ON k.kind_id = l.kind_id WHERE l.fid = fi.fid AND k.role = 'geometry')""").fetchone()[0]
    if no_geom_src:
        errors.append(f"{no_geom_src} features without a geometry source link")
    no_src_attr = con.execute("SELECT COUNT(*) FROM attribute_store a JOIN provenance p ON p.prov_id = a.prov_id WHERE p.source_id IS NULL OR p.source_id = ''").fetchone()[0]
    if no_src_attr:
        errors.append(f"{no_src_attr} attribute rows without source")
    auth_rule = con.execute("SELECT COUNT(*) FROM attribute_store a JOIN provenance p ON p.prov_id = a.prov_id WHERE p.reconstruction_class = 'authoritative' AND p.source_id = 'rule'").fetchone()[0]
    if auth_rule:
        errors.append(f"{auth_rule} authoritative attribute values whose source is a rule")
    bad_class = con.execute("""SELECT COUNT(*) FROM provenance WHERE reconstruction_class NOT IN
        ('authoritative','measured','derived','cross_verified','inferred','procedural','manual_override')""").fetchone()[0]
    if bad_class:
        errors.append(f"{bad_class} attribute rows with unknown reconstruction class")
    multi_sel = con.execute("""SELECT COUNT(*) FROM (SELECT fid, a.name_id FROM attribute_store a JOIN attribute_name n ON n.name_id = a.name_id
        WHERE selected = 1 AND n.name != 'osm_tags' GROUP BY fid, a.name_id HAVING COUNT(*) > 1)""").fetchone()[0]
    if multi_sel:
        errors.append(f"{multi_sel} attributes with more than one selected value")
    unknown_sources = con.execute("""SELECT DISTINCT source_id FROM link_kind WHERE source_id NOT IN (SELECT source_id FROM source)
        AND source_id NOT LIKE 'overture_2026_09_23_1:%'""").fetchall()
    if unknown_sources:
        errors.append(f"source links to unregistered sources: {unknown_sources}")

    # Authored work protection
    ov = overrides.load()
    current = dict(con.execute("SELECT feature_id, geometry_hash FROM feature_index").fetchall())
    plan = regen.plan(current, ov["assets"], PIPELINE_VERSION)
    for v in regen.violations(plan):
        errors.append(f"locked asset scheduled for regeneration: {v}")
    counts["assets_needs_rebase"] = sum(1 for p in plan.values() if p["action"] == "needs_rebase")
    for o in ov["features"]:
        if o.get("target_feature_id") and o["target_feature_id"] not in current:
            errors.append(f"override {o['override_id']} targets missing feature {o['target_feature_id']}")

    # Frame alignment measured at build time
    stats = json.loads((paths.REPORTS / "build_stats.json").read_text(encoding="utf-8"))
    for key in ("vector_vs_lidar_alignment", "usa_structures_vs_lidar_alignment"):
        al = stats.get(key, {})
        if al.get("status") == "ok" and (abs(al["best_shift_east_m"]) > 1.0 or abs(al["best_shift_north_m"]) > 1.0):
            errors.append(f"{key}: systematic offset {al['best_shift_east_m']} E / {al['best_shift_north_m']} N m exceeds 1 m")
    con.close()

    result = {"pipeline_version": PIPELINE_VERSION, "errors": errors,
              "warnings": {k: {"count": len(v), "samples": v[:15]} for k, v in warnings.items()}, "counts": counts,
              "status": "fail" if errors else "pass"}
    paths.REPORTS.mkdir(parents=True, exist_ok=True)
    (paths.REPORTS / "validation_report.json").write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    md = ["# Reality Library validation", "", f"Status: **{result['status']}**", "", "## Errors", ""]
    md += [f"- {e}" for e in errors[:100]] or ["- none"]
    md += ["", "## Warnings (real-world data issues; source geometry left untouched)", ""]
    for k, v in result["warnings"].items():
        md.append(f"- **{k}**: {v['count']}")
        md += [f"  - {s}" for s in v["samples"][:6]]
    (paths.REPORTS / "validation_report.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "errors": len(errors), "warnings": {k: v["count"] for k, v in result["warnings"].items()}}, indent=1))
    if errors:
        print("\n".join(errors[:20]), file=sys.stderr)
        sys.exit(1)
    return result


def _layer(data, fam):
    geoms, cols = data.get(fam, ([], {"class": []}))
    return geoms, list(cols["class"])

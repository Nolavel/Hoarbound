"""Accuracy / coverage report. Spatial coverage, attribute completeness and source confidence are
counted separately; nothing is called '100 % accurate' because it was processed.
"""
from __future__ import annotations

import json
import os
import sqlite3
from collections import Counter, defaultdict

from . import config, library, paths


def _pct(n: int, d: int) -> str:
    return f"{(100.0 * n / d):.1f}%" if d else "n/a"


def _selected(con, family: str, name: str) -> dict[str, tuple]:
    rows = con.execute("""SELECT fi.feature_id, p.reconstruction_class, p.method, p.source_id, a.value_json FROM attribute_store a
        JOIN feature_index fi ON fi.fid = a.fid JOIN attribute_name n ON n.name_id = a.name_id JOIN provenance p ON p.prov_id = a.prov_id
        WHERE fi.family = ? AND n.name = ? AND a.selected = 1""", (family, name)).fetchall()
    return {r[0]: r[1:] for r in rows}


def run() -> dict:
    con = sqlite3.connect(paths.LIBRARY)
    rep: dict = {"extent": config.extent()["lonlat_bounds"], "library_bytes": os.path.getsize(paths.LIBRARY)}
    fam_counts = dict(con.execute("SELECT family, COUNT(*) FROM feature_index GROUP BY family").fetchall())
    rep["features_by_family"] = fam_counts
    rep["reconstruction_class_by_family"] = {}
    for fam in fam_counts:
        geoms, cols = library.read_layer(fam)
        rep["reconstruction_class_by_family"][fam] = dict(Counter(cols["reconstruction_class"]))
        if fam == "buildings":
            b_geoms, b_cols = geoms, cols
        if fam == "roads":
            r_geoms, r_cols = geoms, cols
        if fam in ("barriers", "coastal_structures", "power", "trees", "vegetation_areas", "street_furniture", "utilities", "bridges", "water", "coastline", "transit"):
            per = defaultdict(lambda: {"count": 0, "length_m": 0.0, "area_m2": 0.0})
            for g, c in zip(geoms, cols["class"]):
                per[c]["count"] += 1
                per[c]["length_m"] += g.length if g.geom_type.endswith("LineString") else 0.0
                per[c]["area_m2"] += g.area
            rep[f"{fam}_by_class"] = {k: {kk: round(vv, 1) for kk, vv in v.items()} for k, v in sorted(per.items())}

    # Buildings
    n = len(b_geoms)
    src = Counter(r.split(":")[0] for r in b_cols["geometry_record"])
    height = _selected(con, "buildings", "height_m")
    h_cls = Counter(v[0] for v in height.values())
    h_meth = Counter(v[1] for v in height.values())
    roof = _selected(con, "buildings", "roof_shape")
    roof_form = _selected(con, "buildings", "roof_form")
    levels = _selected(con, "buildings", "levels")
    addr = _selected(con, "buildings", "address")
    use = _selected(con, "buildings", "building_use")
    occ = _selected(con, "buildings", "occupancy_class")
    flags = Counter(f for fl in b_cols["flags"] if fl for f in fl.split(","))
    rep["buildings"] = {
        "total": n,
        "footprint_geometry_source": {k: v for k, v in src.items()},
        "footprint_reconstruction": dict(Counter(b_cols["reconstruction_class"])),
        "real_footprints_share": _pct(n, n),
        "height": {"measured_lidar_2019": h_cls.get("measured", 0), "cross_verified_lidar_2016_2019": h_cls.get("cross_verified", 0),
                   "derived_tag_or_ml": h_cls.get("derived", 0), "inferred_from_levels": h_cls.get("inferred", 0),
                   "unknown": n - len(height), "by_method": dict(h_meth),
                   "measured_or_cross_verified_share": _pct(h_cls.get("measured", 0) + h_cls.get("cross_verified", 0), n),
                   "inferred_share": _pct(h_cls.get("inferred", 0), n), "unknown_share": _pct(n - len(height), n),
                   "changed_between_2016_and_2019": flags.get("height_changed_2016_2019", 0)},
        "roof_shape_tagged": len(roof), "roof_form_from_lidar_flat_vs_pitched": len(roof_form),
        "roof_shape_unknown_share": _pct(n - len(roof), n),
        "levels": {"tagged": sum(1 for v in levels.values() if v[0] != "inferred"), "inferred": sum(1 for v in levels.values() if v[0] == "inferred"),
                   "unknown": n - len(levels)},
        "address_known": len(addr), "address_share": _pct(len(addr), n),
        "use_known_osm": len(use), "occupancy_known_usa_structures": len(occ),
        "facade_material_known": len(_selected(con, "buildings", "facade_material")),
        "facade_colour_known": len(_selected(con, "buildings", "facade_color")),
    }
    # Roads
    rcls = Counter(r_cols["class"])
    width = _selected(con, "roads", "width_m")
    lanes = _selected(con, "roads", "osm:lanes")
    surface = _selected(con, "roads", "surface_rules")
    length = defaultdict(float)
    for g, c in zip(r_geoms, r_cols["class"]):
        length[c] += g.length
    rep["roads"] = {"segments": len(r_geoms), "by_class": dict(rcls), "length_km_by_class": {k: round(v / 1000, 2) for k, v in sorted(length.items())},
                    "geometry_cross_verified_with_tiger": Counter(r_cols["reconstruction_class"]).get("cross_verified", 0),
                    "single_source_tiger_only": sum(1 for f in r_cols["flags"] if f and "single_source_unverified" in f),
                    "width": dict(Counter(v[0] for v in width.values())), "lanes_known": len(lanes), "surface_known": len(surface),
                    "sidewalk_segments": sum(1 for s in r_cols["subclass"] if s == "sidewalk"),
                    "crosswalk_segments": sum(1 for s in r_cols["subclass"] if s == "crosswalk")}
    # Power
    topo = dict(con.execute("SELECT 'edges', COUNT(*) FROM utility_topology UNION ALL SELECT 'pole_to_pole', COUNT(*) FROM utility_topology WHERE from_feature_id IS NOT NULL AND to_feature_id IS NOT NULL").fetchall())
    in_topo = _selected(con, "power", "in_line_topology")
    rep["power"] = {"supports": len(in_topo), "connected_into_line_topology": sum(1 for v in in_topo.values() if v[3] == "true"),
                    "position_only": sum(1 for v in in_topo.values() if v[3] == "false"), "topology_edges": topo.get("edges", 0),
                    "edges_pole_to_pole": topo.get("pole_to_pole", 0)}
    # Trees
    tg, tc = library.read_layer("trees")
    rep["trees"] = {"osm_mapped": sum(1 for s in tc["geometry_source"] if s.startswith("overture")),
                    "osm_confirmed_by_lidar": sum(1 for s, r in zip(tc["geometry_source"], tc["reconstruction_class"]) if s.startswith("overture") and r == "cross_verified"),
                    "lidar_candidates": sum(1 for s in tc["subclass"] if s == "lidar_candidate"),
                    "completeness": "unknown: lidar detects crowns >= 2.5 m wide and >= 3 m tall in 2019; small, young and post-2019 trees are missing; dense canopy is stored as areas"}
    vg, vc = library.read_layer("vegetation_areas")
    rep["vegetation_areas_km2"] = {k: round(sum(g.area for g, c in zip(vg, vc["class"]) if c == k) / 1e6, 3) for k in sorted(set(vc["class"]))}
    rep["excluded_by_reason"] = dict(con.execute("""SELECT CASE WHEN instr(reason, ':kw:') > 0 THEN substr(reason, 1, instr(reason, ':kw:') - 1)
        ELSE reason END AS r, COUNT(*) FROM excluded GROUP BY r ORDER BY 2 DESC""").fetchall())
    rep["excluded_boca_chica_by_class"] = dict(con.execute("SELECT class, COUNT(*) FROM excluded WHERE reason = 'boca_chica_out_of_scope' GROUP BY class ORDER BY 2 DESC").fetchall())
    rep["attribute_rows"] = con.execute("SELECT COUNT(*) FROM attribute_store").fetchone()[0]
    rep["attribute_reconstruction"] = dict(con.execute("SELECT p.reconstruction_class, COUNT(*) FROM attribute_store a JOIN provenance p ON p.prov_id = a.prov_id WHERE a.selected = 1 GROUP BY 1").fetchall())
    rep["sources_requiring_attribution"] = [r[0] + " — " + r[1] for r in con.execute(
        "SELECT source_id, attribution FROM source WHERE requires_attribution = 1 AND status = 'integrated'").fetchall()]
    rep["build_stats"] = json.loads((paths.REPORTS / "build_stats.json").read_text(encoding="utf-8"))
    con.close()
    (paths.REPORTS / "accuracy_report.json").write_text(json.dumps(rep, indent=1, default=str) + "\n", encoding="utf-8")
    (paths.REPORTS / "accuracy_report.md").write_text(_markdown(rep), encoding="utf-8")
    print(_markdown(rep)[:4000])
    return rep


def _markdown(r: dict) -> str:
    b, rd, p, t = r["buildings"], r["roads"], r["power"], r["trees"]
    h = b["height"]
    lines = [
        "# Key West Reality Library — accuracy report", "",
        "Spatial coverage, attribute completeness and source confidence are reported separately. "
        "A processed feature is not an accurate feature; see reconstruction classes.", "",
        f"Extent (WGS84): {r['extent']}  ·  library size: {r['library_bytes'] / 1e6:.1f} MB", "",
        "## Buildings", "",
        f"- {b['total']:,} total; footprint geometry from {', '.join(f'{k} {v:,}' for k, v in b['footprint_geometry_source'].items())}",
        f"- {b['real_footprints_share']} real footprints (no box proxies); reconstruction: {b['footprint_reconstruction']}",
        f"- height: {h['measured_or_cross_verified_share']} measured by lidar ({h['cross_verified_lidar_2016_2019']:,} cross-verified 2016+2019, "
        f"{h['measured_lidar_2019']:,} 2019 only), {h['derived_tag_or_ml']:,} tag/ML-derived, {h['inferred_share']} inferred, {h['unknown_share']} unknown",
        f"- {h['changed_between_2016_and_2019']:,} buildings changed height by > max(2.5 m, 25 %) between 2016 and 2019 (flagged, not resolved)",
        f"- roof shape tagged: {b['roof_shape_tagged']:,}; lidar flat/pitched form: {b['roof_form_from_lidar_flat_vs_pitched']:,}; exact roof shape unknown for {b['roof_shape_unknown_share']}",
        f"- levels tagged {b['levels']['tagged']:,} / inferred {b['levels']['inferred']:,} / unknown {b['levels']['unknown']:,}",
        f"- address known {b['address_known']:,} ({b['address_share']}); use (OSM) {b['use_known_osm']:,}; occupancy (USA Structures) {b['occupancy_known_usa_structures']:,}",
        f"- facade material/colour known: {b['facade_material_known']} / {b['facade_colour_known']} (no imagery source reachable)", "",
        "## Roads", "",
        f"- {rd['segments']:,} segments; geometry cross-verified with Census TIGER: {rd['geometry_cross_verified_with_tiger']:,}; TIGER-only (unverified): {rd['single_source_tiger_only']}",
        f"- width: {rd['width']} (inferred = class table); lanes known {rd['lanes_known']:,}; surface known {rd['surface_known']:,}",
        f"- sidewalks {rd['sidewalk_segments']:,}, crosswalks {rd['crosswalk_segments']:,}",
        f"- length km by class: {rd['length_km_by_class']}", "",
        "## Power / utilities", "",
        f"- {p['supports']:,} poles/towers mapped; {p['connected_into_line_topology']:,} connected into known line topology; {p['position_only']:,} position-only",
        f"- {p['topology_edges']:,} topology edges, {p['edges_pole_to_pole']:,} pole-to-pole (rest have an unmapped support at one end)", "",
        "## Trees and vegetation", "",
        f"- {t['osm_mapped']:,} source-mapped trees (OSM), {t['osm_confirmed_by_lidar']:,} confirmed by a 2019 lidar crown",
        f"- {t['lidar_candidates']:,} lidar crown candidates (derived detections)",
        f"- coverage completeness: {t['completeness']}",
        f"- vegetation areas km²: {r['vegetation_areas_km2']}", "",
        "## Other classes", "",
    ]
    for key in ("barriers_by_class", "coastal_structures_by_class", "bridges_by_class", "street_furniture_by_class", "utilities_by_class", "power_by_class"):
        if key in r:
            lines.append(f"- **{key.replace('_by_class', '')}**: " + ", ".join(
                f"{k} {v['count']}" + (f" ({v['length_m'] / 1000:.2f} km)" if v['length_m'] else "") for k, v in r[key].items()))
    lines += ["", "## Features by family", "", "| family | count | reconstruction classes |", "|---|---:|---|"]
    for fam, n in sorted(r["features_by_family"].items()):
        lines.append(f"| {fam} | {n:,} | {r['reconstruction_class_by_family'][fam]} |")
    lines += ["", "## Excluded", "", *[f"- {k}: {v:,}" for k, v in r["excluded_by_reason"].items()],
              "", f"Boca Chica out-of-scope by class: {r['excluded_boca_chica_by_class']}", "",
              "## Attribution required", "", *[f"- {s}" for s in r["sources_requiring_attribution"]], ""]
    return "\n".join(lines) + "\n"

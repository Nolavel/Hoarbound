"""GeoPackage writer/reader for the Reality Library (data/world/key_west/reality/library/key_west_reality.gpkg).

Spatial layers: one per feature family (EPSG:32617, source geometry untouched) plus
utility_topology, game_override and extent_zones. Aspatial tables: attribute,
source_link, source, excluded, feature_index, identity_map, generated_asset, meta.
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

import numpy as np
import pyogrio
import shapely

from . import config, frame, ids, paths, receipts
from .model import Feature, geometry_hash

PREVIOUS = paths.RAW / "previous_library" / "key_west_reality.previous.gpkg"
COLUMNS = ["feature_id", "class", "subclass", "name", "scope", "zone", "chunk_id", "local_x", "local_z",
           "reconstruction_class", "confidence", "geometry_source", "geometry_record", "geometry_method",
           "geometry_accuracy_m", "geometry_hash", "observed_at", "source_epoch", "valid_from", "valid_to",
           "last_verified", "source_count", "flags", "attrs_json"]


def node_name(feature_id: str) -> str:
    """kw:building:osm:w123 -> KW_BUILDING_osm_w123 (Godot/Blender-safe, deterministic)."""
    _, token, rest = feature_id.split(":", 2)
    return f"KW_{token.upper()}_" + re.sub(r"[^A-Za-z0-9_\-]", "_", rest)


PACKED = paths.LIBRARY.with_suffix(".gpkg.xz")
MANIFEST = paths.LIBRARY_DIR / "manifest.json"


def pack() -> dict:
    """Writes the committed form: key_west_reality.gpkg.xz + manifest.json (sha256 of both)."""
    import lzma
    import shutil

    tmp = PACKED.with_suffix(".xz.part")
    with open(paths.LIBRARY, "rb") as src, lzma.open(tmp, "wb", preset=6) as dst:
        shutil.copyfileobj(src, dst, 1 << 22)
    tmp.replace(PACKED)
    con = sqlite3.connect(paths.LIBRARY)
    families = dict(con.execute("SELECT family, COUNT(*) FROM feature_index GROUP BY family").fetchall())
    meta = dict(con.execute("SELECT key, value FROM meta WHERE key IN ('schema_version', 'pipeline_version', 'built_at')").fetchall())
    con.close()
    manifest = {"schema": "kw_reality.library_manifest.v1", **meta,
                "gpkg": {"path": paths.rel(paths.LIBRARY), "bytes": paths.LIBRARY.stat().st_size, "sha256": receipts.sha256_file(paths.LIBRARY)},
                "packed": {"path": paths.rel(PACKED), "bytes": PACKED.stat().st_size, "sha256": receipts.sha256_file(PACKED), "codec": "xz preset 6"},
                "features_by_family": families,
                "note": "Git stores the .xz (GitHub rejects files > 100 MB). 'key_west_reality.py unpack' restores the .gpkg; every reader unpacks on demand."}
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in ("gpkg", "packed")}, indent=1))
    return manifest


def ensure() -> Path:
    """Restores the working .gpkg from the committed .xz when missing or stale."""
    import lzma
    import shutil

    if not MANIFEST.exists():
        return paths.LIBRARY
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    want = manifest["gpkg"]["sha256"]
    if paths.LIBRARY.exists() and paths.LIBRARY.stat().st_size == manifest["gpkg"]["bytes"]:
        return paths.LIBRARY
    if not PACKED.exists():
        raise SystemExit(f"{PACKED} missing; run acquire + build")
    tmp = paths.LIBRARY.with_suffix(".unpack.part")
    with lzma.open(PACKED, "rb") as src, open(tmp, "wb") as dst:
        shutil.copyfileobj(src, dst, 1 << 22)
    if receipts.sha256_file(tmp) != want:
        tmp.unlink()
        raise SystemExit("unpacked library sha256 does not match manifest.json")
    tmp.replace(paths.LIBRARY)
    print(f"[library] unpacked {paths.rel(paths.LIBRARY)}")
    return paths.LIBRARY


def identity_map(path: Path | None = None) -> dict[tuple[str, str], str]:
    if path is None:
        ensure()
    path = path or paths.LIBRARY
    if not path.exists():
        return {}
    con = sqlite3.connect(path)
    try:
        rows = con.execute("SELECT source_id, source_record_id, feature_id FROM identity_map").fetchall()
    except sqlite3.Error:
        rows = []
    con.close()
    return {(s, r): f for s, r, f in rows}


def _selected_attrs(f: Feature) -> dict:
    out = {}
    for a in f.attrs:
        if a.selected and a.name != "osm_tags":
            out[a.name] = a.value
    return out


def _source_key(f: Feature) -> tuple[str, str] | None:
    for link in f.links:
        if link.role in ("geometry",) and link.match_method in ("identity", "detection", "raster_polygonize"):
            return link.source_id, link.source_record_id
    return None


def write(features: list[Feature], edges: list, excluded: list, override_layer: dict, meta: dict) -> None:
    out = paths.LIBRARY
    tmp = out.with_suffix(".tmp.gpkg")
    if tmp.exists():
        tmp.unlink()
    out.parent.mkdir(parents=True, exist_ok=True)
    crs = frame.frame()["projected_crs"]
    by_family = defaultdict(list)
    for f in features:
        by_family[f.family].append(f)
    first = True
    for family in sorted(by_family):
        rows = sorted(by_family[family], key=lambda f: f.feature_id)
        data = {c: [] for c in COLUMNS}
        geoms = []
        for f in rows:
            data["feature_id"].append(f.feature_id)
            data["class"].append(f.cls)
            data["subclass"].append(f.subclass)
            data["name"].append(f.name)
            data["scope"].append(f.scope)
            data["zone"].append(f.zone)
            data["chunk_id"].append(f._chunk)
            data["local_x"].append(f._local[0])
            data["local_z"].append(f._local[1])
            data["reconstruction_class"].append(f.geometry_recon)
            data["confidence"].append(float(f.geometry_confidence))
            data["geometry_source"].append(f.geometry_source)
            data["geometry_record"].append(f.geometry_record)
            data["geometry_method"].append(f.geometry_method)
            data["geometry_accuracy_m"].append(f.geometry_accuracy_m)
            data["geometry_hash"].append(geometry_hash(f.geom))
            data["observed_at"].append(f.observed_at)
            data["source_epoch"].append(f.source_epoch)
            data["valid_from"].append(f.valid_from)
            data["valid_to"].append(f.valid_to)
            data["last_verified"].append(f.last_verified)
            data["source_count"].append(len({l.source_id for l in f.links}))
            data["flags"].append(",".join(sorted(f.flags)) or None)
            data["attrs_json"].append(json.dumps(_selected_attrs(f), ensure_ascii=False, sort_keys=True, default=str))
            geoms.append(f.geom)
        arrays = []
        for c in COLUMNS:
            vals = data[c]
            if c in ("local_x", "local_z", "confidence", "geometry_accuracy_m"):
                arrays.append(np.array([np.nan if v is None else v for v in vals], dtype=np.float64))
            elif c == "source_count":
                arrays.append(np.array(vals, dtype=np.int32))
            else:
                arrays.append(np.array([None if v is None else str(v) for v in vals], dtype=object))
        pyogrio.raw.write(tmp, shapely.to_wkb(np.array(geoms, dtype=object)), arrays, COLUMNS, layer=family,
                          driver="GPKG", crs=crs, geometry_type="Unknown", append=not first)
        first = False
    if edges:
        pyogrio.raw.write(tmp, shapely.to_wkb(np.array([e.geom for e in edges], dtype=object)),
                          [np.array([e.edge_id for e in edges], dtype=object), np.array([e.network for e in edges], dtype=object),
                           np.array([e.from_feature_id for e in edges], dtype=object), np.array([e.to_feature_id for e in edges], dtype=object),
                           np.array([e.via_feature_id for e in edges], dtype=object), np.array([e.method for e in edges], dtype=object),
                           np.array([e.recon for e in edges], dtype=object), np.array([e.confidence for e in edges], dtype=np.float64)],
                          ["edge_id", "network", "from_feature_id", "to_feature_id", "via_feature_id", "method", "reconstruction_class", "confidence"],
                          layer="utility_topology", driver="GPKG", crs=crs, geometry_type="LineString", append=True)
    if override_layer["features"]:
        ofs = override_layer["features"]
        cols = ["override_id", "target_feature_id", "override_type", "status", "params_json", "author", "reason", "created", "source_file"]
        pyogrio.raw.write(tmp, shapely.to_wkb(np.array([o["geometry"] for o in ofs], dtype=object)),
                          [np.array([str(o.get(c)) if o.get(c) is not None else None for o in ofs], dtype=object) for c in cols], cols,
                          layer="game_override", driver="GPKG", crs=crs, geometry_type="Unknown", append=True)
    zpath = paths.RAW / "extent" / "extent_zones.gpkg"
    meta_z, _, zgeom, zfields = pyogrio.raw.read(zpath, layer="zones")
    pyogrio.raw.write(tmp, zgeom, zfields, list(meta_z["fields"]), layer="extent_zones", driver="GPKG", crs=crs,
                      geometry_type="Unknown", append=True)
    _write_tables(tmp, features, excluded, override_layer, meta)
    if out.exists():
        PREVIOUS.parent.mkdir(parents=True, exist_ok=True)
        out.replace(PREVIOUS)
    tmp.replace(out)


def _write_tables(path: Path, features: list[Feature], excluded: list, override_layer: dict, meta: dict) -> None:
    """Aspatial tables. Bulky provenance is normalised into *_store tables + lookups; the
    public names (attribute, source_link, identity_map) are SQL views with the full columns."""
    con = sqlite3.connect(path)
    cur = con.cursor()
    ddl = {
        "feature_index": "fid INTEGER PRIMARY KEY, feature_id TEXT UNIQUE, family TEXT, class TEXT, chunk_id TEXT, scope TEXT, "
                         "geometry_hash TEXT, geometry_record TEXT, observed_at TEXT",
        "attribute_name": "name_id INTEGER PRIMARY KEY, name TEXT UNIQUE",
        "provenance": "prov_id INTEGER PRIMARY KEY, source_id TEXT, method TEXT, reconstruction_class TEXT, unit TEXT, source_epoch TEXT, note TEXT",
        "attribute_store": "fid INTEGER, name_id INTEGER, value_json TEXT, prov_id INTEGER, confidence REAL, selected INTEGER, "
                           "source_record_id TEXT, observed_at TEXT",
        "link_kind": "kind_id INTEGER PRIMARY KEY, source_id TEXT, source_layer TEXT, role TEXT, match_method TEXT",
        "link_store": "fid INTEGER, kind_id INTEGER, source_record_id TEXT, match_score REAL, source_version TEXT",
        "source": "source_id TEXT PRIMARY KEY, name TEXT, provider TEXT, url TEXT, license TEXT, attribution TEXT, requires_attribution INTEGER, "
                  "share_alike INTEGER, authority_level TEXT, crs TEXT, positional_accuracy TEXT, temporal_epoch TEXT, status TEXT, "
                  "feature_classes_used TEXT, retrieved_at TEXT, receipt_json TEXT",
        "excluded": "source_id TEXT, source_layer TEXT, source_record_id TEXT, class TEXT, reason TEXT",
        "generated_asset": "feature_id TEXT, asset_id TEXT, authoring_state TEXT, source_geometry_hash TEXT, last_generator_version TEXT, "
                           "asset_revision TEXT, godot_scene TEXT, blender_file TEXT, updated_at TEXT",
        "meta": "key TEXT PRIMARY KEY, value TEXT",
    }
    views = {
        "attribute": """SELECT fi.feature_id AS feature_id, an.name AS name, a.value_json AS value_json, p.unit AS unit, p.source_id AS source_id,
            COALESCE(a.source_record_id, fi.geometry_record) AS source_record_id, p.method AS method, p.reconstruction_class AS reconstruction_class,
            a.confidence AS confidence, COALESCE(a.observed_at, fi.observed_at) AS observed_at, p.source_epoch AS source_epoch,
            a.selected AS selected, p.note AS note
            FROM attribute_store a JOIN feature_index fi ON fi.fid = a.fid JOIN attribute_name an ON an.name_id = a.name_id
            JOIN provenance p ON p.prov_id = a.prov_id""",
        "source_link": """SELECT fi.feature_id AS feature_id, k.source_id AS source_id, k.source_layer AS source_layer, l.source_record_id AS source_record_id,
            k.role AS role, k.match_method AS match_method, l.match_score AS match_score, l.source_version AS source_version
            FROM link_store l JOIN feature_index fi ON fi.fid = l.fid JOIN link_kind k ON k.kind_id = l.kind_id""",
        "identity_map": """SELECT k.source_id AS source_id, l.source_record_id AS source_record_id, fi.feature_id AS feature_id
            FROM link_store l JOIN feature_index fi ON fi.fid = l.fid JOIN link_kind k ON k.kind_id = l.kind_id
            WHERE k.role = 'geometry' AND k.match_method IN ('identity', 'detection', 'raster_polygonize')""",
    }
    for table, cols in ddl.items():
        cur.execute(f"CREATE TABLE {table} ({cols})")
    for name, sql in views.items():
        cur.execute(f"CREATE VIEW {name} AS {sql}")
    for name in list(ddl) + list(views):
        cur.execute("INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change) VALUES (?, 'attributes', ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
                    (name, name, f"Key West Reality Library: {name}"))
    names, provs, kinds = {}, {}, {}
    idx_rows, attr_rows, link_rows = [], [], []
    for fid_int, f in enumerate(sorted(features, key=lambda f: f.feature_id), start=1):
        idx_rows.append((fid_int, f.feature_id, f.family, f.cls, f._chunk, f.scope, geometry_hash(f.geom), f.geometry_record, f.observed_at))
        for a in f.attrs:
            nid = names.setdefault(a.name, len(names) + 1)
            pkey = (a.source_id, a.method, a.recon, a.unit, a.source_epoch, a.note)
            pid = provs.setdefault(pkey, len(provs) + 1)
            rec = None if a.source_record_id in (f.geometry_record, f"footprint:{f.feature_id}") else a.source_record_id
            obs = None if a.observed_at == f.observed_at else a.observed_at
            attr_rows.append((fid_int, nid, a.value_json(), pid, round(float(a.confidence), 3), int(a.selected), rec, obs))
        seen = set()
        for l in f.links:
            key = (l.source_id, l.source_layer, l.role, l.match_method, l.source_record_id)
            if key in seen:
                continue
            seen.add(key)
            kid = kinds.setdefault((l.source_id, l.source_layer, l.role, l.match_method), len(kinds) + 1)
            link_rows.append((fid_int, kid, l.source_record_id, l.match_score, l.source_version))
    cur.executemany("INSERT INTO feature_index VALUES (?,?,?,?,?,?,?,?,?)", idx_rows)
    cur.executemany("INSERT INTO attribute_name VALUES (?,?)", [(v, k) for k, v in names.items()])
    cur.executemany("INSERT INTO provenance VALUES (?,?,?,?,?,?,?)", [(v, *k) for k, v in provs.items()])
    cur.executemany("INSERT INTO attribute_store VALUES (?,?,?,?,?,?,?,?)", attr_rows)
    cur.executemany("INSERT INTO link_kind VALUES (?,?,?,?,?)", [(v, *k) for k, v in kinds.items()])
    cur.executemany("INSERT INTO link_store VALUES (?,?,?,?,?)", link_rows)
    cur.executemany("INSERT INTO excluded VALUES (?,?,?,?,?)", [(e.source_id, e.source_layer, e.source_record_id, e.cls, e.reason) for e in excluded])
    for sid, s in config.sources().items():
        rec = receipts.load(sid)
        cur.execute("INSERT INTO source VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (sid, s["name"], s["provider"], s["url"], s["license"], s.get("attribution"),
                     None if s.get("requires_attribution") is None else int(s["requires_attribution"]),
                     None if s.get("share_alike") is None else int(s["share_alike"]), s.get("authority_level"), s.get("crs"),
                     str(s.get("positional_accuracy_m")), s.get("temporal_epoch"), s["status"], json.dumps(s.get("feature_classes_used")),
                     rec.get("retrieved_at"), json.dumps(rec) if rec.get("artifacts") else None))
    for a in override_layer["assets"]:
        cur.execute("INSERT INTO generated_asset VALUES (?,?,?,?,?,?,?,?,?)",
                    tuple(a.get(k) for k in ("feature_id", "asset_id", "authoring_state", "source_geometry_hash", "last_generator_version",
                                             "asset_revision", "godot_scene", "blender_file", "updated_at")))
    for k, v in meta.items():
        cur.execute("INSERT INTO meta VALUES (?,?)", (k, json.dumps(v, default=str) if not isinstance(v, str) else v))
    cur.execute("CREATE INDEX attribute_store_fid ON attribute_store(fid)")
    cur.execute("CREATE INDEX link_store_fid ON link_store(fid)")
    con.commit()
    con.execute("VACUUM")
    con.close()


def read_layer(family: str, path: Path | None = None) -> tuple[list, dict]:
    """(geometries, {column: values}) for one family; used by validate/report/preview/export."""
    if path is None:
        ensure()
    meta, _, geom, fields = pyogrio.raw.read(path or paths.LIBRARY, layer=family)
    return list(shapely.from_wkb(geom)), {n: fields[i] for i, n in enumerate(meta["fields"])}


def families(path: Path | None = None) -> list[str]:
    if path is None:
        ensure()
    skip = {"utility_topology", "game_override", "extent_zones"}
    return [name for name, gtype in pyogrio.list_layers(path or paths.LIBRARY) if gtype is not None and name not in skip]

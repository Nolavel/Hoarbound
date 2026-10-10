"""Authoring manifest maintenance (authoring/asset_manifest.json): the Blender roundtrip's memory.

  asset --feature-id kw:building:osm:w1 --state artist_locked --blend art/kw/w1.blend --asset-id kw_asset:w1
  asset --rebase-check     mark changed-source authored assets needs_rebase (never deletes or regenerates)
"""
from __future__ import annotations

import json
import sqlite3

from . import PIPELINE_VERSION, library, paths, receipts, regen
from .overrides import AUTHORING_STATES

MANIFEST = paths.AUTHORING / "asset_manifest.json"


def _load() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def _save(doc: dict) -> None:
    doc["assets"] = sorted(doc["assets"], key=lambda a: (a["feature_id"], a.get("asset_id") or ""))
    MANIFEST.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def _current_hash(feature_id: str) -> str:
    library.ensure()
    con = sqlite3.connect(paths.LIBRARY)
    row = con.execute("SELECT geometry_hash FROM feature_index WHERE feature_id = ?", (feature_id,)).fetchone()
    con.close()
    if not row:
        raise SystemExit(f"{feature_id} is not in the Reality Library")
    return row[0]


def register(feature_id: str, state: str, asset_id: str | None, blend: str | None, scene: str | None) -> dict:
    if state not in AUTHORING_STATES:
        raise SystemExit(f"state must be one of {AUTHORING_STATES}")
    doc = _load()
    ghash = _current_hash(feature_id)
    rec = next((a for a in doc["assets"] if a["feature_id"] == feature_id and (asset_id is None or a.get("asset_id") == asset_id)), None)
    if rec is None:
        rec = {"feature_id": feature_id, "asset_id": asset_id or f"kw_asset:{feature_id.split(':', 1)[1]}", "asset_revision": 0,
               "source_geometry_hash": ghash, "last_generator_version": PIPELINE_VERSION}
        doc["assets"].append(rec)
    rec["authoring_state"] = state
    rec["asset_revision"] = int(rec.get("asset_revision") or 0) + 1
    rec["updated_at"] = receipts.now_utc()
    if state in ("artist_modified", "artist_locked"):
        rec["source_geometry_hash"] = rec.get("source_geometry_hash") or ghash
    if blend:
        rec["blender_file"] = blend
    if scene:
        rec["godot_scene"] = scene
    _save(doc)
    print(json.dumps(rec, indent=1))
    return rec


def rebase_check() -> dict:
    """After a source update: authored assets whose footprint changed become needs_rebase."""
    doc = _load()
    library.ensure()
    con = sqlite3.connect(paths.LIBRARY)
    current = dict(con.execute("SELECT feature_id, geometry_hash FROM feature_index").fetchall())
    con.close()
    plan = regen.plan(current, doc["assets"], PIPELINE_VERSION)
    changed = 0
    for a in doc["assets"]:
        p = plan.get(a["feature_id"], {})
        if p.get("action") == "needs_rebase" and a["authoring_state"] != "needs_rebase":
            a["previous_state"] = a["authoring_state"]
            a["authoring_state"] = "needs_rebase"
            a["rebase_to_geometry_hash"] = current.get(a["feature_id"])
            a["updated_at"] = receipts.now_utc()
            changed += 1
    _save(doc)
    out = {"marked_needs_rebase": changed, "orphaned": sum(1 for p in plan.values() if p["action"] == "orphaned")}
    print(json.dumps(out))
    return out

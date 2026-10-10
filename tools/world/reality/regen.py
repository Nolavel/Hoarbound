"""Regeneration planning: what the editor generator may (re)build for each feature.

The asset manifest (authoring/asset_manifest.json) is the only memory of authored work.
An artist_locked or artist_modified asset is never overwritten; if its source geometry
changed, it is marked needs_rebase and left in place.
"""
from __future__ import annotations

ACTIONS = ("generate", "regenerate", "keep", "keep_locked", "needs_rebase", "orphaned")


def plan(features: dict[str, str], assets: list[dict], generator_version: str) -> dict[str, dict]:
    """features: feature_id -> current geometry_hash. Returns feature_id -> {action, reason, asset}."""
    by_feature = {}
    for a in assets:
        by_feature.setdefault(a["feature_id"], []).append(a)
    out: dict[str, dict] = {}
    for fid, ghash in features.items():
        recs = [a for a in by_feature.get(fid, []) if a.get("authoring_state") != "deprecated"]
        if not recs:
            out[fid] = {"action": "generate", "reason": "no asset yet"}
            continue
        a = recs[-1]
        state = a["authoring_state"]
        changed = a.get("source_geometry_hash") != ghash
        if state in ("artist_locked", "artist_modified", "needs_rebase"):
            if changed or state == "needs_rebase":
                out[fid] = {"action": "needs_rebase", "reason": f"{state} asset; source geometry {a.get('source_geometry_hash')} -> {ghash}", "asset": a}
            else:
                out[fid] = {"action": "keep_locked", "reason": f"{state} asset is authoritative for presentation", "asset": a}
        elif state == "generated":
            if changed or a.get("last_generator_version") != generator_version:
                out[fid] = {"action": "regenerate", "reason": "generated asset is stale", "asset": a}
            else:
                out[fid] = {"action": "keep", "reason": "up to date", "asset": a}
    for fid, recs in by_feature.items():
        if fid not in features:
            out[fid] = {"action": "orphaned", "reason": "feature no longer in reality library; asset kept, review required", "asset": recs[-1]}
    return out


def violations(plan_result: dict[str, dict]) -> list[str]:
    """Guard used by validation and by the generator before writing anything."""
    bad = []
    for fid, p in plan_result.items():
        a = p.get("asset") or {}
        if a.get("authoring_state") in ("artist_locked", "artist_modified") and p["action"] in ("generate", "regenerate"):
            bad.append(f"{fid}: {a['authoring_state']} asset scheduled for {p['action']}")
    return bad

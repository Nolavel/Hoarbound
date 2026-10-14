"""Edit layer: game-authored changes to Reality features, kept apart from the library.

One JSON file per chunk under overrides/edits/ (the chunk that owns the edited feature), so
two people rarely touch the same file. Every record names a data layer. Only `base` changes
what the generator builds; other layers (winter, loot:<set>, story:<state>) are carried into
the chunk export for the runtime and never alter the base world.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import shapely
from shapely import affinity

from . import frame, paths

EDITS_DIR = paths.OVERRIDES / "edits"
SCHEMA = "kw_reality.edits.v1"
OPS = ("remove", "move", "add")
LAYER = re.compile(r"^(base|winter|loot:[a-z0-9_]+|story:[a-z0-9_]+)$")


def file_for(chunk_id: str) -> Path:
    return EDITS_DIR / f"edits_{chunk_id.replace(':', '_')}.json"


def load(directory: Path = EDITS_DIR) -> list[dict]:
    """Every edit record, in file then list order (later records win for the same feature)."""
    out: list[dict] = []
    for f in sorted(directory.glob("edits_*.json")) if directory.exists() else []:
        doc = json.loads(f.read_text(encoding="utf-8"))
        chunk = doc.get("chunk") or f.stem.removeprefix("edits_").replace("_", ":", 1)
        for e in doc.get("edits", []):
            out.append(dict(e, chunk=e.get("chunk", chunk), _file=f.name))
    return out


def check(edits: list[dict], hashes: dict[str, str]) -> tuple[list[str], list[str]]:
    """(errors, warnings): unknown op or layer, missing target, stale source hash, ids reused."""
    errors, warnings, seen = [], [], set()
    for e in edits:
        eid, op, layer, fid = e.get("edit_id"), e.get("op"), e.get("layer", ""), e.get("feature_id")
        where = f"{e.get('_file')}:{eid}"
        if not eid or eid in seen:
            errors.append(f"{where}: missing or repeated edit_id")
        seen.add(eid)
        if op not in OPS:
            errors.append(f"{where}: unknown op {op!r}")
        if not LAYER.match(str(layer)):
            errors.append(f"{where}: unknown layer {layer!r}")
        if op in ("remove", "move"):
            if fid not in hashes:
                errors.append(f"{where}: feature {fid} is not in the library")
            elif e.get("source_geometry_hash") and e["source_geometry_hash"] != hashes[fid]:
                warnings.append(f"{where}: {fid} changed in the source since the edit (needs review)")
        if op == "move" and not all(k in e.get("params", {}) for k in ("x", "z")):
            errors.append(f"{where}: move needs params x and z (local metres)")
        if op == "add":
            warnings.append(f"{where}: add is recorded but not generated yet")
    return errors, warnings


def base_plan(edits: list[dict]) -> dict[str, dict]:
    """feature_id -> the last base-layer remove or move for it."""
    plan: dict[str, dict] = {}
    for e in edits:
        if e.get("layer") == "base" and e.get("op") in ("remove", "move"):
            plan[e["feature_id"]] = e
    return plan


def layered(edits: list[dict]) -> list[dict]:
    """Edits outside the base layer, without file bookkeeping, for the chunk export."""
    return [{k: v for k, v in e.items() if not k.startswith("_")} for e in edits if e.get("layer") != "base"]


def moved(geom, edit: dict):
    """Projected geometry carried so its anchor lands on the edit's local (x, z), turned by yaw_deg.

    yaw_deg follows Godot's rotation about +Y: positive turns east towards north.
    """
    p = frame.representative_point(geom)
    e, n = frame.local_to_projected(float(edit["params"]["x"]), float(edit["params"]["z"]))
    out = affinity.translate(geom, e - p.x, n - p.y)
    yaw = float(edit["params"].get("yaw_deg", 0.0))
    return affinity.rotate(out, yaw, origin=shapely.Point(e, n)) if yaw else out

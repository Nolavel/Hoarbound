"""Loaders for the hand-written configuration under data/world/key_west/reality/config."""
from __future__ import annotations

import json
from functools import lru_cache

from . import paths


@lru_cache(maxsize=None)
def load(name: str) -> dict:
    return json.loads((paths.CONFIG / name).read_text(encoding="utf-8"))


def sources() -> dict[str, dict]:
    return {s["source_id"]: s for s in load("sources.json")["sources"]}


def extent_rules() -> dict:
    return load("extent_rules.json")


def extent() -> dict:
    path = paths.CONFIG / "extent.json"
    if not path.exists():
        raise SystemExit("config/extent.json missing: run 'key_west_reality.py extent' first")
    return json.loads(path.read_text(encoding="utf-8"))


def acquisition_bbox() -> tuple[float, float, float, float]:
    b = extent_rules()["acquisition_bbox_lonlat"]
    return float(b["west"]), float(b["south"]), float(b["east"]), float(b["north"])

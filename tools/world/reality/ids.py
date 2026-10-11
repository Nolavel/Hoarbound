"""Stable feature IDs: kw:<token>:<namespace>:<native id>.

The ID is taken from the source that first supplied the feature's geometry and is
carried forward by the identity map (previous library), so a later change of source
priority never renames a feature. See docs/world/KEY_WEST_REALITY_LIBRARY.md.
"""
from __future__ import annotations

import re

FAMILY_TOKEN = {
    "buildings": "building", "building_parts": "building_part", "roads": "road", "transport_nodes": "node",
    "bridges": "bridge", "coastal_structures": "coastal", "barriers": "barrier", "power": "power",
    "utilities": "utility", "street_furniture": "street", "transit": "transit", "airport": "airport",
    "trees": "tree", "vegetation_areas": "vegetation", "water": "water", "land": "land",
    "coastline": "coastline", "land_use": "landuse", "places": "place", "addresses": "address",
    "admin_areas": "admin", "terrain_coverage": "terrain",
}

_OSM = re.compile(r"^([nwr])(\d+)(?:@\d+)?$")


def osm_key(record_id: str | None) -> str | None:
    """'w462887766@1' -> 'w462887766' (version dropped: identity survives edits)."""
    if not record_id:
        return None
    m = _OSM.match(record_id)
    return f"{m.group(1)}{m.group(2)}" if m else None


def make(family: str, namespace: str, native: str) -> str:
    return f"kw:{FAMILY_TOKEN[family]}:{namespace}:{native}"


class IdRegistry:
    """Guards uniqueness; a collision falls back to the secondary key and is reported."""

    def __init__(self, identity_map: dict[tuple[str, str], str] | None = None):
        self.used: set[str] = set()
        self.collisions: list[tuple[str, str]] = []
        self.identity_map = identity_map or {}
        self.carried = 0

    def claim(self, primary: str, fallback: str, source_key: tuple[str, str] | None = None) -> str:
        if source_key and source_key in self.identity_map:
            fid = self.identity_map[source_key]
            if fid not in self.used:
                self.used.add(fid)
                self.carried += 1
                return fid
        fid = primary if primary not in self.used else fallback
        if fid in self.used:
            n = 2
            while f"{fallback}~{n}" in self.used:
                n += 1
            fid = f"{fallback}~{n}"
        if fid != primary:
            self.collisions.append((primary, fid))
        self.used.add(fid)
        return fid

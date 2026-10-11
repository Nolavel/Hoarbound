"""In-memory records collected by normalizers before conflation and GeoPackage write.

Reconstruction classes (how a value was obtained), see docs/world/KEY_WEST_REALITY_LIBRARY.md:
authoritative, measured, derived, cross_verified, inferred, procedural, manual_override.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any

import shapely

RECON_CLASSES = ("authoritative", "measured", "derived", "cross_verified", "inferred", "procedural", "manual_override")
RECON_RANK = {"manual_override": 7, "authoritative": 6, "cross_verified": 5, "measured": 4, "derived": 3, "inferred": 2, "procedural": 1}


def geometry_hash(geom) -> str:
    """Hash of the projected source geometry quantised to 1 cm (stable across float noise)."""
    q = shapely.set_precision(geom, 0.01)
    return hashlib.sha1(shapely.to_wkb(shapely.normalize(q), hex=False, output_dimension=2)).hexdigest()[:16]


@dataclass
class Attr:
    name: str
    value: Any
    source_id: str
    method: str
    recon: str
    confidence: float
    source_record_id: str | None = None
    unit: str | None = None
    observed_at: str | None = None
    source_epoch: str | None = None
    selected: bool = False
    note: str | None = None

    def value_json(self) -> str:
        return json.dumps(self.value, ensure_ascii=False, sort_keys=True, default=str)


@dataclass
class Link:
    source_id: str
    source_layer: str
    source_record_id: str
    role: str  # geometry | attributes | corroborates | duplicate_of
    match_method: str = "identity"
    match_score: float | None = None
    source_version: str | None = None


@dataclass
class Feature:
    feature_id: str
    family: str           # GeoPackage layer
    cls: str              # canonical class
    geom: Any             # shapely, projected CRS, untouched source geometry
    geometry_source: str
    geometry_record: str
    geometry_method: str
    geometry_recon: str
    geometry_confidence: float
    geometry_accuracy_m: float | None = None
    subclass: str | None = None
    name: str | None = None
    scope: str = "reality"         # reality | context_silhouette
    zone: str | None = None
    observed_at: str | None = None
    source_epoch: str | None = None
    valid_from: str | None = None
    valid_to: str | None = None
    last_verified: str | None = None
    attrs: list[Attr] = field(default_factory=list)
    links: list[Link] = field(default_factory=list)
    flags: set[str] = field(default_factory=set)

    def add(self, *attrs: Attr) -> None:
        self.attrs.extend(a for a in attrs if a is not None and a.value is not None and a.value != "")

    def selected(self, name: str):
        for a in self.attrs:
            if a.name == name and a.selected:
                return a
        return None

    def candidates(self, name: str) -> list[Attr]:
        return [a for a in self.attrs if a.name == name]


@dataclass
class Edge:
    edge_id: str
    network: str
    from_feature_id: str | None
    to_feature_id: str | None
    via_feature_id: str
    geom: Any
    method: str
    recon: str
    confidence: float


@dataclass
class Excluded:
    source_id: str
    source_layer: str
    source_record_id: str
    cls: str
    reason: str

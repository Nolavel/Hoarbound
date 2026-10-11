"""Repository paths used by every Reality Library stage."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REALITY = ROOT / "data/world/key_west/reality"
CONFIG = REALITY / "config"
RECEIPTS = REALITY / "receipts"
RAW = REALITY / "raw_cache"
LIBRARY_DIR = REALITY / "library"
LIBRARY = LIBRARY_DIR / "key_west_reality.gpkg"
REPORTS = REALITY / "reports"
OVERRIDES = REALITY / "overrides"
AUTHORING = REALITY / "authoring"
EDITOR_EXPORT = ROOT / "data/world/key_west/editor_chunks"
PREVIEWS = ROOT / "docs/world/reality_previews"
LEGACY = ROOT / "data/world/key_west"


def rel(path: Path) -> str:
    """Repository-relative POSIX path for receipts and reports."""
    try:
        return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)

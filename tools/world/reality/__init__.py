"""Key West Reality Library: open geodata -> normalized, provenance-tracked GeoPackage.

Pipeline stages live in separate modules (acquire, extent, normalize_*, conflate,
library, overrides, validate, report, diff, preview, editor_export). The CLI entry
point is tools/world/key_west_reality.py.
"""

SCHEMA_VERSION = "kw_reality.v1"
PIPELINE_VERSION = "1.0.0"

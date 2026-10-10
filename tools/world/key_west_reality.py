#!/usr/bin/env python3
"""Key West Reality Library pipeline (offline, editor-time; never used at runtime).

  acquire [--source ID ...]   fill the raw cache + receipts
  extent                      derive config/extent.json from data
  build                       normalize + conflate -> library GeoPackage
  validate | report | diff    checks, accuracy report, change report vs previous library
  preview                     spatial-fidelity map previews (PNG)
  pack | unpack               committed .gpkg.xz <-> working .gpkg (sha256-checked)
  asset ...                   register/lock an authored asset; --rebase-check after source updates
  override-bridge-init        one-time: author the severed-bridge game override from real geometry
  export-editor               per-chunk editor interchange for the Godot editor generator
  all                         acquire -> extent -> acquire (extent-bound) -> build -> validate -> report -> preview

Needs: pyarrow, pyogrio, shapely, pyproj, rasterio, laspy[lazrs], numpy, Pillow.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from reality import acquire, extent  # noqa: E402

VECTOR_SOURCES = ["overture", "usgs_tnm", "legacy"]
EXTENT_SOURCES = ["noaa_dem", "noaa_lidar", "worldcover"]


def cmd_acquire(names: list[str]) -> None:
    names = names or VECTOR_SOURCES + EXTENT_SOURCES
    for name in names:
        getattr(acquire, name)()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command")
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--previous", help="previous library for diff (default: the library the last build replaced)")
    parser.add_argument("--chunk", action="append", help="export-editor: chunk id like -5:0 (repeatable; default all)")
    parser.add_argument("--feature-id", help="asset: Reality Library feature id")
    parser.add_argument("--state", help="asset: generated | artist_modified | artist_locked | deprecated | needs_rebase")
    parser.add_argument("--asset-id")
    parser.add_argument("--blend", help="asset: authored .blend path")
    parser.add_argument("--scene", help="asset: Godot scene path")
    parser.add_argument("--rebase-check", action="store_true", help="asset: mark authored assets with changed sources needs_rebase")
    args = parser.parse_args()
    if args.command == "acquire":
        cmd_acquire(args.source)
    elif args.command == "extent":
        extent.derive()
    elif args.command == "build":
        from reality import build
        build.run()
    elif args.command == "validate":
        from reality import validate
        validate.run()
    elif args.command == "report":
        from reality import report
        report.run()
    elif args.command == "diff":
        from reality import diff
        diff.run(args.previous)
    elif args.command == "preview":
        from reality import preview
        preview.run()
    elif args.command == "asset":
        from reality import assets
        if args.rebase_check:
            assets.rebase_check()
        else:
            assets.register(args.feature_id, args.state, args.asset_id, args.blend, args.scene)
    elif args.command == "pack":
        from reality import library
        library.pack()
    elif args.command == "unpack":
        from reality import library
        library.ensure()
    elif args.command == "override-bridge-init":
        from reality import overrides
        overrides.init_bridge_override()
    elif args.command == "export-editor":
        from reality import editor_export
        editor_export.run(args.chunk)
    elif args.command == "all":
        cmd_acquire(VECTOR_SOURCES)
        extent.derive()
        cmd_acquire(EXTENT_SOURCES)
        from reality import build, preview, report, validate
        from reality import library
        build.run()
        validate.run()
        report.run()
        preview.run()
        library.pack()
    else:
        parser.error(f"unknown command {args.command}")


if __name__ == "__main__":
    main()

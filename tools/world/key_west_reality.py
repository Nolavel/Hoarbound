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
  landmarks                   measured First Exit landmark assets (glTF) + asset manifest records
  shelter-727                 rebuild the 727 shell from the permit layout and replay its passes
                              (glass frost, Blender exterior, wall paint), then its First Exit sockets and yard;
                              --blender-python names bpy's Python
  route-gate                  walkable First Exit + Old Town test route for the production gate
  first-exit-sites            bunker door, spawn and loot sites for the Reality First Exit (game-authored)
  traversal-check             no generated collider on a mapped road, path or footway
  export-editor               per-chunk editor interchange for the Godot editor generator
  editor-index                search index (address, size, footprint) for the Godot Reality editor dock
  blender-shell --feature-id  one building's measured shell (glTF) and sizes for modelling in Blender
  documented [--apply]        buildings from planning records: overlap report; --apply adds them to the committed library
  city-footprints [--apply]   reviewed City of Key West footprints (config/city_footprints.json), same flow
  all                         acquire -> extent -> acquire (extent-bound) -> build -> validate -> report -> preview

Needs: pyarrow, pyogrio, shapely, pyproj, rasterio, laspy[lazrs], numpy, Pillow.
"""
from __future__ import annotations

import argparse
import json
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


def cmd_documented(apply: bool) -> None:
    """Applies config/documented_buildings.json to the committed library (no raw cache needed)."""
    import json
    import shutil
    import tempfile

    from reality import conflate, documented, ids, library, paths
    library.ensure()
    feats = documented.features(ids.IdRegistry())
    measured = [f for f in feats if f.feature_id in documented.lidar_masses(feats)]
    if measured:  # existing buildings drawn on a plan: heights and roofs from the 2019 lidar (raw cache needed)
        from reality import build, lidar
        build.building_measurements(measured, lidar.DemCrop())
        conflate.select_attributes(measured)
    with tempfile.TemporaryDirectory() as tmp:
        target = paths.LIBRARY if apply else Path(tmp) / "dry_run.gpkg"
        if not apply:
            shutil.copyfile(paths.LIBRARY, target)
        report = library.append_features(target, feats)
        report["closed"] = library.close_features(target, documented.supersessions())
    report["applied"] = apply
    (paths.REPORTS / "documented_buildings.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=1))
    if apply:
        library.pack()


def cmd_city_footprints(apply: bool) -> None:
    """Applies the reviewed city footprints to the committed library; lidar heights need the raw cache of their chunks."""
    import json
    import shutil
    import tempfile

    from reality import build, city_footprints, conflate, ids, library, lidar, paths
    library.ensure()
    decisions = city_footprints.load()
    if not city_footprints.RAW.exists():
        city_footprints.acquire(decisions["area_local"])
    feats = city_footprints.features(ids.IdRegistry(), city_footprints.records(), decisions)
    build.building_measurements(feats, lidar.DemCrop())
    conflate.select_attributes(feats)
    with tempfile.TemporaryDirectory() as tmp:
        target = paths.LIBRARY if apply else Path(tmp) / "dry_run.gpkg"
        if not apply:
            shutil.copyfile(paths.LIBRARY, target)
        removed = library.remove_features(target, city_footprints.removals(decisions))
        report = library.append_features(target, feats)
    report.update({"removed": removed, "applied": apply,
                   "heights": {f.feature_id: (f.selected("height_m").value if f.selected("height_m") else None) for f in feats}})
    (paths.REPORTS / "city_footprints.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=1))
    if apply:
        library.pack()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command")
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--previous", help="previous library for diff (default: the library the last build replaced)")
    parser.add_argument("--chunk", action="append", help="export-editor: chunk id like -5:0 (repeatable; default all)")
    parser.add_argument("--route", action="store_true", help="export-editor: only the priority corridor chunks (config/generation.json)")
    parser.add_argument("--feature-id", help="asset: Reality Library feature id")
    parser.add_argument("--state", help="asset: generated | artist_modified | artist_locked | deprecated | needs_rebase")
    parser.add_argument("--asset-id")
    parser.add_argument("--blend", help="asset: authored .blend path")
    parser.add_argument("--scene", help="asset: Godot scene path")
    parser.add_argument("--blender-python", help="shelter-727: Python with the bpy module (default: this one)")
    parser.add_argument("--apply", action="store_true", help="documented: write the buildings into the library and re-pack it")
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
    elif args.command == "route-gate":
        from reality import routes
        routes.run()
    elif args.command == "traversal-check":
        from reality import traversal
        traversal.run()
    elif args.command == "first-exit-sites":
        from reality import first_exit_sites
        first_exit_sites.run()
    elif args.command == "landmarks":
        from reality import landmarks
        landmarks.run()
    elif args.command == "shelter-727":
        cmd_shelter_727(args.blender_python)
    elif args.command == "blender-shell":
        from reality import blender_shell
        if not args.feature_id:
            parser.error("blender-shell needs --feature-id")
        blender_shell.run(args.feature_id)
    elif args.command == "editor-index":
        from reality import editor_index
        editor_index.run()
    elif args.command == "city-footprints":
        cmd_city_footprints(args.apply)
    elif args.command == "documented":
        cmd_documented(args.apply)
    elif args.command == "export-editor":
        from reality import editor_export
        editor_export.run(args.chunk, route_only=args.route)
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


def cmd_shelter_727(blender_python: str | None) -> None:
    """The 727 asset is generated, then authored by three scripts; a new layout replays all of them in order."""
    import subprocess
    from reality import facade_727, landmarks, paths
    glb = landmarks.ASSET_DIR / "kw_727_fort_st.glb"
    spec = landmarks.SPEC_DIR / "kw_727_fort_st.json"
    landmarks.run(only="kw_727_fort_st", replay=True)
    subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "reality/landmark_glass_frost.py"), str(glb), str(spec)], check=True)
    subprocess.run([blender_python or sys.executable, str(paths.ROOT / "tools/blender/build_727_exterior.py")], check=True)
    print(json.dumps(facade_727.apply(spec, glb, landmarks.ASSET_DIR / "kw_727_exterior.glb",
                                      paths.AUTHORING / "asset_manifest.json")["parts"]))
    from reality import first_exit_sites
    print(json.dumps(first_exit_sites.refresh_shelter()))


if __name__ == "__main__":
    main()

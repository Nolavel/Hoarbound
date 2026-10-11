# Key West Reality Library — data

Normalized, provenance-tracked open-data reconstruction of Key West.
Architecture: `docs/world/KEY_WEST_REALITY_LIBRARY.md`. Tool: `tools/world/key_west_reality.py`.

| path | what | git |
|---|---|---|
| `config/frame.json` | the one WGS84 → UTM 17N → Hoarbound local transform, vertical datum | yes |
| `config/extent_rules.json`, `config/extent.json` | extent rules and the derived extent | yes |
| `config/sources.json` | source registry (licence, status, accuracy, epoch) | yes |
| `config/conflation_rules.json` | source priority / matching thresholds with reasons | yes |
| `receipts/*.json` | what was downloaded: URL, ETag, bytes, sha256, rows, tiles, time | yes |
| `library/key_west_reality.gpkg.xz` + `manifest.json` | the library (GeoPackage, xz) | yes |
| `library/key_west_reality.gpkg` | working copy (`key_west_reality.py unpack`) | no |
| `overrides/*.geojson` | Hoarbound game overrides (authored, not reality) | yes |
| `authoring/asset_manifest.json` | generated / artist assets bound to feature ids | yes |
| `reports/` | accuracy, validation, change reports, build stats | yes |
| `raw_cache/` | downloaded sources (~3.3 GB), re-creatable from receipts | no |
| `derived/` | editor interchange chunks | no |

`.gdignore` keeps Godot from importing anything here. Nothing in this folder is read
at runtime.

Rebuild from scratch (network: S3 hosts of Overture, NOAA, USGS, ESA):

```
pip install pyarrow pyogrio shapely pyproj rasterio "laspy[lazrs]" scipy numpy pillow
python3 tools/world/key_west_reality.py all
```

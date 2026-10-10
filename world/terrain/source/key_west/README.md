# Key West terrain source

Status: **the verified 2 m NOAA crop and packed runtime terrain are committed for the Key West startup scene.**

Target dataset for issue #138:

- NOAA / NGS 2016 Key West topobathymetric LiDAR DEM.
- Bare-earth/topobathy terrain is required; buildings and vegetation must not
  be baked into the HFN ground heightmap.
- First geographic scope: Key West, Fleming Key, Wisteria Island, Sunset Key,
  Stock Island, and the intervening water/shallow bathymetry.
- First Godot import keeps real XY scale and real elevation values.

The 620 MiB upstream mosaic stays in the ignored download cache. This folder
contains the derived 16-bit crop and JSON metadata; `noaa_source_receipt.json`
records both NOAA URLs, byte count, SHA-256 and the verified original S3 multipart
ETag. The existing terrain bake
converts that crop to the committed LA8 runtime image without height edits.

Do not edit the upstream DEM in Blender. Any later Blender pass happens only
after the Godot review gate and must be represented as authored HFN changes on
top of the preserved NOAA base.


## First verified Godot preview — 2026-09-29

The first NOAA → HFN → Godot proof completed successfully in Actions run
`36514874180` on `codex`.

Verified preview crop:
- lon/lat: west -81.835, south 24.535, east -81.705, north 24.595;
- derived preview resolution: 2 m/px;
- local Godot bounds: about **13.20 × 6.57 km**;
- raster: 6602 × 3286 px;
- source mosaic reports **EPSG:32617 (WGS 84 / UTM zone 17N)**;
- measured crop elevation range: -8.192 m to 28.526 m;
- sea level in HFN remains 0 m;
- no Blender edits or vertical exaggeration were applied.

The 2 m preview is disposable and exists to judge geography/performance before
committing a production dataset. The NOAA master remains the 1 m source of truth.
The high maximum value is recorded as source data, not interpreted as natural
ground height until infrastructure/outliers are audited.

Godot captures produced:
1. whole-cluster top view;
2. closer Key West top view;
3. oblique cluster view;
4. low coast-scale view.

The terrain loader was also hardened to read the packed LA8 PNG bytes directly
as an `Image`, bypassing Texture2D import/compression settings.


## Stage 4 verified Godot massing — 2026-09-29

Successful preview run: `36520195465` on `codex`.

Visual/data result:
- NOAA terrain remains unchanged; no Blender pass and no vertical exaggeration.
- Ice is no longer a raised full plane. It is rendered 0.04 m below sea level
  and masked to **ocean-connected** cells derived from the DEM, so enclosed
  below-zero terrain does not become fake inland ponds/lakes.
- Ocean mask preview resolution: 8 m/px.
- OpenStreetMap preview import: **12,354 building footprints** and
  **2,681 road ways** / **15,511 road points**.
- Building footprints are represented by one lightweight oriented box each and
  rendered through one MultiMesh for the geography proof.
- Roads are rendered as one combined terrain-draped ribbon mesh.
- OSM preview attribution is included in captures:
  `© OpenStreetMap contributors — ODbL`.
- Four Godot captures passed: cluster top, Key West top, oblique, and low coast.

The Stage 4 assets are still disposable preview outputs. They prove scale,
coverage and spatial rhythm; they are not final production buildings or roads.


## Stage 5 chunk-aware city rebuild — 2026-09-29

Final verified preview run: `36524001180` on `codex`.

The Stage 4 one-global-MultiMesh proof has been replaced by a richer city dataset
and an isolated chunk-aware renderer:

- content chunk size: **512 m**;
- content-bearing chunks: **148**;
- buildings: **12,354**;
- named buildings: **577**;
- buildings with a resolved OSM house number: **379**;
- separately mapped address nodes assigned to buildings: **141**;
- nearest named-road hints (explicitly marked as inferred hints): **10,947**;
- roads: **2,681**;
- named roads: **956**;
- road points: **15,511**;
- maximum buildings in one 512 m chunk: **577**.

Each building now keeps:
- OSM id;
- content chunk id;
- real OSM footprint polygon;
- far-massing oriented proxy;
- height and the height source (OSM height / OSM levels / fallback);
- name and available address/POI metadata.

Each road keeps:
- OSM id;
- name/ref/class;
- lanes/surface/oneway/bridge/tunnel metadata when present;
- real projected polyline;
- chunk-aware road segments.

### Airport block

The preview explicitly selects **Key West International Airport**:
- IATA: **EYW**;
- ICAO: **KEYW**;
- operator metadata: **Monroe County**;
- 2 aerodromes were found in the crop, and EYW/KEYW has explicit priority;
- **92** aeroway features remain in the 2.6 km EYW airport neighbourhood.

The EYW block includes:
- 1 runway;
- 52 taxiways;
- 9 taxilanes;
- 3 aprons;
- 5 terminal features;
- 9 hangar features;
- parking positions and other aeroway support geometry.

The experimental renderer `ChunkedCityMassing` provides:
- per-chunk Ring-0 oriented proxies;
- lazily built exact OSM footprint extrusion near the focus;
- per-chunk road batches;
- explicit airport runway/taxiway/apron geometry;
- metadata debug hooks.

This is still isolated research code. It does not replace the production
`StreamingSystem` yet, and Graciosa / First Exit remain unchanged.


## Stage 6 StreamingSystem + TPS proof — 2026-09-29

Verified Actions run: `36529305655`.

The frozen Stage 5 `city_preview.json` snapshot from run `36524001180`
was reused unchanged. The TPS job explicitly skips the Overpass city rebuild.

Streaming integration:
- the existing `StreamingSystem` remains the single owner of ACTIVE/UNLOADED
  state;
- generated Key West chunks register through a runtime-source API instead of
  introducing a second streaming manager;
- all **148** city chunks use the same state machine and the same
  `instantiation_budget_per_frame`;
- Ring 0 building proxies stay lightweight;
- exact OSM footprint meshes and per-chunk road batches are created only for
  ACTIVE chunks and physically freed on UNLOADED;
- the existing static Graciosa `WorldData/ChunkData` path is preserved.

Regression coverage:
- `tests/systems/test_streaming.gd` now verifies runtime registration,
  Ring 0 creation, ACTIVE transition, far-focus UNLOADED transition, and
  removal of runtime detail;
- final run: `streaming: all checks passed`.

Real project `Player` + `TpsCamera` captures were made at six points:
- Duval Street / Old Town: 3 ACTIVE of 148;
- Front Street / waterfront: 3 ACTIVE (nearby overlap with Duval is retained);
- Truman Avenue: 2 ACTIVE;
- North Roosevelt Boulevard: 4 ACTIVE;
- EYW / South Roosevelt Boulevard: 2 ACTIVE;
- Stock Island / MacDonald Avenue: 3 ACTIVE.

Large teleports show zero old ACTIVE chunks before the new neighbourhood
activates. Nearby Duval → Front Street intentionally keeps overlapping chunks
because the points share the same streaming neighbourhood/hysteresis band.

This proves city detail now follows the TPS focus rather than keeping all
12,354 detailed building footprints live at once.


## Main-scene promotion — 2026-09-29

`res://scenes/world/key_west/key_west.tscn` now starts the game on this dataset.
The 2 m crop retains its preview fidelity; this promotion does not imply final
buildings, audited source outliers, or authored terrain. Both source and runtime
heightmaps are versioned, so normal startup needs no GIS tools or downloads.
The local GDAL 3.12.4 bilinear reconstruction has decoded valid heights of
-8.181 m to 28.462 m; these version-dependent resampling statistics are recorded
in the receipt separately from the historical Actions preview report.

The frozen city, enrichment and ocean mask come from verified Actions run
`36574726378` and are stored under `data/world/key_west/`, with artifact hashes
in `source_receipt.json`. Graciosa is retained under `archive/graciosa/`.

Repack the committed source with:

```powershell
python tools/world/bake_terrain.py --source world/terrain/source/key_west/key_west_preview_2m_height.png --meta world/terrain/source/key_west/key_west_preview_2m_height.json --out-png world/terrain/key_west_preview_2m_la8.png --out-json world/terrain/key_west_preview_2m_la8.json
```


## Place in the Reality Library architecture — 2026-10-10

This 2 m crop's frame is now the authoritative Hoarbound local frame
(`data/world/key_west/reality/config/frame.json`). The Reality Library extent is
larger (+1.8 km north, +0.6 km east, `config/extent.json`); its 1 m DEM crop lives
in the library raw cache. Re-baking the runtime heightmap for the larger extent is a
separate pass; this crop is unchanged.

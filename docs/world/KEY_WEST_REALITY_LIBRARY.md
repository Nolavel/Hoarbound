# Key West Reality Library — architecture

Status: **foundation in place (2026-10-10, `claudeflow`)**. Owner: Claude (Technical Director).
Code: `tools/world/key_west_reality.py` + `tools/world/reality/`. Data: `data/world/key_west/reality/`.

The goal is the most faithful reconstruction of Key West that open data allows, with
every invented value labelled as invented. The library is the single place where
"what is really there" is stored; game changes and generated meshes sit on top of it
and never write back into it.

```
OPEN DATA SOURCES ──acquire──> RAW SOURCE CACHE ──build──> REALITY LIBRARY (GeoPackage)
   (S3 / HTTPS)                 raw_cache/ + receipts/       reality layers + provenance
                                                                     │
                       GAME OVERRIDES (overrides/*.geojson) ─────────┤  copied in, never merged into reality
                       AUTHORING MANIFEST (authoring/*.json) ────────┤
                                                                     ▼
                       EDITOR EXPORT (derived/editor_chunks/*.json) ─> GODOT EDITOR GENERATOR
                                                                     ─> editable .scn/.tscn chunks
                                                                     ─> Blender roundtrip ─> updated scene
RUNTIME loads ordinary scenes/chunks only — no GIS, no network.
```

Principle: **the generator never invents an object whose position, shape or
properties exist in a reachable source.** Where nothing exists, the value is
`inferred` (or absent) and says so.

---

## 1. Where the old pipeline sits

| Old piece | What it is | Place in the new architecture |
|---|---|---|
| `tools/world/build_key_west_preview.sh` | NOAA DEM 6366 → 2 m crop → HFN heightmap + ocean mask + Overpass city | **Terrain runtime bake** stays. Its crop frame became the authoritative local frame (`config/frame.json`). The Overpass step is superseded by the library. |
| `tools/world/build_key_west_city_preview.py` | Overpass → `city_preview.json` (12,354 OSM footprints, 2,681 roads, OBB proxies, 148 × 512 m chunks) | **Frozen legacy runtime snapshot.** Still drives the current game. Its OSM tags (lanes, oneway, addr:*) are ingested as source `hoarbound_legacy_osm_2026_09_29`. Its box proxies are *derived presentation*, not reality. |
| `tools/world/build_key_west_visual_enrichment.py` | Overture attributes + supplemental Overpass (poles, piers, barriers, coastline) | Superseded: the same classes now come into the library with provenance from Overture `base/infrastructure` (original OSM tags preserved). |
| `tools/world/fetch_key_west_landscape.py` | Overture trees / woods / marinas → `landscape.json` | Superseded by library families `trees`, `vegetation_areas`, `land_use`. |
| `bake_key_west_far_city.py`, `bake_key_west_snow_wind.py`, `bake_key_west_chunk_snow.gd` | Runtime presentation bakes from the legacy snapshot | Unchanged. They become consumers of generated chunks in a later pass. |
| `scripts/systems/world/city/*` | Runtime city massing from JSON | Unchanged. The next stage replaces runtime massing with editor-generated scenes (§8). |

Nothing old was deleted or modified. The runtime game still loads the frozen snapshot.

Gaps the audit found in the old pipeline: one crop decided by eye (Fleming Key's north
tip sat 33 m from the edge; islets north of it were cut); provenance only per file
("OpenStreetMap"); OBB proxies used as building geometry at distance; heights from a
fallback table for 97.5 % of buildings (only 303 of 12,354 had an OSM height or levels tag); no stable cross-source IDs; no game/reality split.

## 2. Spatial extent

Derived by `tools/world/reality/extent.py` from rules in `config/extent_rules.json`;
result in `config/extent.json` (committed) and library layer `extent_zones`.

1. **Core**: every coastline-derived land polygon touching the Key West city-limit
   polygon, plus Stock Island (which includes Raccoon Key / Key Haven).
2. **Adjacent islets**: land whose nearest land is the core (not Boca Chica) within
   1.5 km. The gaps show a natural break: all core-side islets are ≤ 489 m away.
3. **Crossing**: Boca Chica Channel Bridge (OSM relation r13373986) kept whole, plus
   1 km past its far landing.
4. **Water margin**: 1 km around 1–3 (twice the islet break) so every shoreline
   structure is inside and the sea continues past every coast.
5. **Never cut land**: a non-context island crossing the rectangle grows it.
6. **Superset of the legacy runtime crop**, snapped outward to the 512 m chunk grid.

| | WGS84 | UTM 17N (EPSG:32617) | Hoarbound local |
|---|---|---|---|
| Library extent | W −81.836047, S 24.532311, E −81.699056, N 24.611610 | E 415369…429193, N 2713419…2722123 | x −6656…7168, z −5120…3584 |
| Size | | 13.824 × 8.704 km = 120.3 km² | 27 × 17 = 459 chunks |
| Legacy runtime crop | −81.835…−81.705, 24.535…24.595 | E 415424…428626, N 2713716…2720288 | x −6601…6601, z −3285…3287 |

Growth vs legacy crop: **+1,835 m north**, +567 m east, +297 m south, +55 m west.

**Boca Chica**: only its outline on the bridge side (5.59 km² of the landmass inside
the rectangle) is kept as `scope = context_silhouette`, together with terrain and
coastline. Its buildings, roads, airfield, vegetation and infrastructure are not
ingested; each skipped record is listed in table `excluded` with reason
`boca_chica_out_of_scope`.

## 3. Coordinate frame and heights

One chain, `config/frame.json`, implemented once in `reality/frame.py`:

`WGS84 lon/lat (EPSG:4326) → UTM 17N (EPSG:32617) → local x = E − 422025, z = 2717003 − N`.

- The origin is the centre of the existing 2 m runtime crop, so current gameplay
  anchors and chunk ids (`floor(x/512):floor(z/512)`) are unchanged.
- 1 Godot unit = 1 m. UTM scale (~0.99966) is documented, not corrected.
- NOAA DEM and lidar are NAD83(2011) / UTM 17N (DEM file labelled EPSG:32617) and are
  used on the same grid. The WGS84 vs NAD83(2011) realisation difference was
  **measured**: cross-correlating OSM footprints against the 2019 lidar elevated-surface
  mask in Old Town gives the best fit at 0.0 m E / −0.5 m N, IoU 0.6151 → 0.6195 —
  inside one 0.5 m cell. No shift is applied; validation fails if it ever exceeds 1 m.
- Godot Y = **NAVD88** orthometric height (DEM: GEOID12B; lidar: GEOID18, cm-level
  difference). Y = 0 is NAVD88 zero, not local mean sea level. The MSL−NAVD88 offset
  at tide station 8724580 is still to be retrieved (host blocked here).
- Shoreline check: OSM coastline vs the measured DEM 0 m NAVD88 shoreline — median 2.21 m,
  p90 10.6 m, 76 % of samples within 5 m (`reports/build_stats.json`). The tail is low
  mangrove islets that never rise above NAVD88 0 m in the DEM.

## 4. Sources

Registry: `config/sources.json` (static facts, licence, status); acquisition facts:
`receipts/<source_id>.json` (URL, ETag, bytes, sha256, retrieval time, rows, tiles).
Both are copied into the library table `source`.

| source_id | What it gives | Licence | Status |
|---|---|---|---|
| `overture_2026_09_23_1` | OSM-derived buildings, roads/connectors, infrastructure (original OSM tags), land/water/land-use, places, addresses, divisions; Microsoft ML footprints | ODbL / CDLA-P-2.0 / per-record | integrated |
| `usgs_nsd_fl_20260227` | FEMA/ORNL **USA Structures** footprints (height, occupancy, parcel address), public facility points | public domain | integrated |
| `usgs_ntd_fl_20260211` | Census TIGER roads (cross-check), FAA runways and airport points | public domain | integrated |
| `usgs_govtunit_fl_20260212` | City of Key West limits, Stock Island CDP, reserves | public domain | integrated |
| `usgs_nhd_fl_2024` | NHD waterbodies, areas, lines, coastline | public domain | integrated |
| `noaa_dem_6366` | 2016 1 m topobathy DEM (terrain + bathymetry) | public domain | integrated |
| `noaa_lidar_9081` | 2019 post-Irma topobathy lidar (COPC), 935 M points over 164 tiles | public domain | integrated |
| `noaa_lidar_6246` | 2016 Key West topobathy lidar (COPC), independent epoch | public domain | integrated |
| `esa_worldcover_2021_v200` | 10 m land cover (mangrove, tree cover, wetland) | CC BY 4.0 | integrated |
| `hoarbound_legacy_osm_2026_09_29` | Frozen Overpass tags (lanes, oneway, addr:*) | ODbL | integrated |
| `noaa_bluetopo`, `meta_wri_canopy_height_1m`, `loc_sanborn` | reachable, not needed yet | public / CC BY | registered |
| OSM live, Monroe County GIS, City of Key West GIS, FGDL, FEMA NFHL, TIGER direct, NWI, NOAA CUSP, NOAA ENC, NAIP, CO-OPS datums, Microsoft direct | | | **blocked in this build environment** (egress policy) |

Blocked sources are registered with what they would add and the licence question to
answer first (Monroe County parcels: redistribution terms unverified). Nothing was
assumed about them. Attribution text: `docs/THIRD_PARTY_NOTICES.md` → "Geodata".

## 5. Library schema

Master file: `library/key_west_reality.gpkg` (GeoPackage, EPSG:32617, source geometry
untouched — Point/LineString/Polygon/MultiPolygon as received). Git stores
`library/key_west_reality.gpkg.xz` + `library/manifest.json` (sha256 of both) because
GitHub rejects files > 100 MB; every tool unpacks on demand (`key_west_reality.py unpack`).

**Feature layers** (one per family; all share these columns):
`feature_id, class, subclass, name, scope, zone, chunk_id, local_x, local_z,
reconstruction_class, confidence, geometry_source, geometry_record, geometry_method,
geometry_accuracy_m, geometry_hash, observed_at, source_epoch, valid_from, valid_to,
last_verified, source_count, flags, attrs_json` (selected attribute values, for quick reads).

Families: `buildings, building_parts, roads, transport_nodes, bridges,
coastal_structures, barriers, power, utilities, street_furniture, transit, airport,
trees, vegetation_areas, water, land, coastline, land_use, places, addresses,
admin_areas, terrain_coverage`. Plus `utility_topology` (edges), `game_override`,
`extent_zones`.

**Tables / views**:

| name | content |
|---|---|
| `attribute` (view over `attribute_store` + `attribute_name` + `provenance`) | one row per attribute **candidate**: value, unit, source, record, method, reconstruction class, confidence, observed_at, epoch, `selected` |
| `source_link` (view over `link_store` + `link_kind`) | every source record merged into a feature: role `geometry / attributes / corroborates / duplicate_of`, match method and score |
| `identity_map` (view) | (source, record) → feature_id; carried into the next build |
| `feature_index` | feature_id → family, class, chunk, scope, geometry_hash |
| `source` | registry + receipt per source |
| `excluded` | every source record not ingested and why (outside extent, Boca Chica, duplicate) |
| `generated_asset` | copy of the authoring manifest at build time |
| `meta` | schema/pipeline version, build time, build statistics |

Example (`attribute` for one building): footprint from OSM (`derived`, 0.85) confirmed
by USA Structures (IoU ≥ 0.5 → geometry `cross_verified`); `height_m` candidates from
lidar 2019 (`measured`), lidar 2016 (`measured`), their agreement (`cross_verified`,
selected), USA Structures (`derived`) and Microsoft ML (`derived`); `address` from the
parcel-derived USA Structures address; `roof_form` from lidar relief (`derived`);
`levels` = median roof height / 3.2 m (`inferred`; P95 can include overhanging canopy —
727 Fort Street measured P95 9.98 m but median 4.72 m).

## 6. Confidence model and time

`reconstruction_class` describes **how a value was obtained**, per feature geometry
and per attribute:

| class | meaning | examples |
|---|---|---|
| `authoritative` | published by the authority responsible for the object | FAA runway outline, Census city limits, USGS facility register |
| `measured` | direct instrument measurement | lidar heights, DEM shoreline, canopy height |
| `derived` | digitised or computed from observations by a documented process | OSM tracing, ML footprints, lidar crown detection, coastline from land polygons |
| `cross_verified` | ≥ 2 independent sources agree within tolerance | OSM ∩ USA Structures footprints, lidar 2016 ≈ 2019 heights, OSM ∩ TIGER roads |
| `inferred` | rule-based estimate, nothing observed | levels from height, road width from class |
| `procedural` | generated presentation with no real counterpart | reserved for the generator, never stored as reality |
| `manual_override` | authored correction | reserved |

`confidence` (0..1) is the source's own reliability for that value. Time fields:
`observed_at` (OSM last edit, lidar flight date, imagery date), `source_epoch` (dataset
release), `valid_from` (OSM `start_date`), `valid_to` (empty = current),
`last_verified` (latest independent confirmation). Epochs are never mixed silently:
USA Structures footprints in Key West are from 2008 NGA lidar, OSM edits span
2011–2026, lidar is 2016 and 2019, WorldCover 2021.

## 7. Stable IDs and conflation

`kw:<token>:<namespace>:<native id>` — `kw:building:osm:w462887766`,
`kw:road:overture:<GERS uuid>` (Overture splits OSM ways), `kw:building:usa_structures:32249190`,
`kw:tree:lidar2019:E421000.2N2716105.8`, `kw:airport:faa:<permanent id>`.
The ID comes from the first source that supplied the geometry; OSM ids drop the
version. The next build reads `identity_map` from the previous library and reuses the
ID even if priorities change (verified: a rebuild carried 88,446 IDs, the change
report showed no added/removed features). Collisions fall back to the secondary key and
are reported (`build_stats.json:id_collisions`).

Conflation (`reality/conflate.py`, rules in `config/conflation_rules.json`):

- **Buildings**: USA Structures matched to OSM/Overture by IoU ≥ 0.30 or 70 % overlap of
  the smaller. Matched → `corroborates` link + its attributes; one USA polygon over
  several OSM footprints shares attributes at reduced confidence. Unmatched USA
  footprints become new buildings; partial overlaps (> 30 %) are excluded as duplicates.
  OSM keeps footprint priority because it fits the lidar better (IoU 0.615 vs 0.559).
- **Address points / POIs / public facilities** inside a footprint become building
  attributes; the point features stay.
- **Roads**: OSM centrelines; TIGER segments within 12 m covering ≥ 60 % length →
  `cross_verified` + official route numbers. TIGER-only roads are added flagged
  `single_source_unverified`.
- **Runways**: FAA polygon replaces the OSM geometry, keeping the OSM ID (priority
  changes geometry, never identity).
- **Water**: NHD polygons with IoU ≥ 0.5 corroborate OSM water; the rest are added.
- **Land**: one OSM way emitted twice by Overture (coastline land + place=island) is merged.
- **Trees**: an OSM tree within 3 m of a lidar crown is confirmed; other crowns are new
  `derived` candidates.
- **Power**: an OSM power line vertex within 0.5 m of a pole/tower makes an edge
  `pole A → line → pole B` (`utility_topology`); ends without a mapped support stay open.

## 8. Measured attributes (lidar)

The NOAA point clouds classify only ground (2) and noise (7); buildings and trees are
both class 1. So:

- **Building height** `height_m` = 95th percentile of non-noise returns inside the
  footprint − median same-epoch ground in a 1.5–6 m ring (DEM fallback). This is the
  **roof top**, not the eave. `roof_median_height_m` (P50) and `roof_relief_m`
  (P90−P10) are stored; `roof_form` = flat if relief < 0.6 m.
  Evidence: lidar 2019 vs 2016 median difference −0.22 m, 72 % within 1 m (n = 13,018);
  USA Structures heights run 1.8 m lower (different definition, 2008), Microsoft ML 3.0 m
  lower. Changes > max(2.5 m, 25 %) between epochs are flagged `height_changed_2016_2019`.
- **Trees**: CHM = 2019 DSM − 2016 bare-earth DEM, σ 1 m smoothing, 2.5 m opening (removes
  poles and wires — measured on an Old Town tile: a 1.5 m opening left crown peaks on the
  utility poles along the streets),
  height-dependent window r = 1.5 + 0.25 h, roughness ≥ 0.3 m (rejects flat roofs,
  boats, trucks), DEM ≥ −0.3 m (water surface over bathymetry made false 3–5 m
  "canopy" at first). Continuous canopy > 2,000 m² (mangrove stands, hammocks) is stored
  as `lidar_canopy_dense` areas — individual trees are not invented inside it.
  Crowns < 2.5 m wide, trees < 3 m, and anything planted after 2019 are missing.
  **Absence of a tree record never means absence of a tree.**

## 9. Reality / game override / generated

| layer | written by | rule |
|---|---|---|
| reality (feature layers) | `build` only | rebuilt from sources; never edited by hand or by the game |
| `game_override` | humans, in `overrides/*.geojson` (EPSG:32617) | references `target_feature_id`; build copies it in; validation fails if the target disappears |
| generated | the editor generator | scenes/meshes derived from reality + overrides; bookkept in `authoring/asset_manifest.json` |

**Bridge override** (`overrides/boca_chica_channel_bridge.geojson`, status
`provisional_author_review`): `bridge_state = severed` on `kw:bridge:osm:r13373986`;
`remove_span` on both US-1 carriageways and the Heritage Trail deck over 40–160 m of the
801 m deck (the 120 m window with the deepest mean channel bed, −2.73 m NAVD88,
abutments kept); two `severed_end` points. The real bridge, roads and pier-free channel
stay intact in reality. Real pier positions are in no reachable source; the generator
must not present invented piers as reality. Length and position are the author's call.

**First Exit landmarks** (`overrides/first_exit_landmarks.geojson`, owner decision
2026-10-10, #211 / #208): `landmark_role` on the real **727 Fort Street** building
`kw:building:osm:w339414849` (address 727 FORT ST from USA Structures; lidar median roof
4.72 m — one storey, matching the planning record) and on the real Fort Zachary Taylor
polygon `kw:building:osm:w524088621` for **Battery Osceola**, whose own footprint exists
in no reachable source and is therefore not invented. Both allow an authored,
reference-backed form that suppresses generic generated massing on that footprint; the
footprint, street relation and provenance stay real. The former custom Fort Street hut is
recorded as `custom_structure` (game content, role undecided); no real footprint lies
within 15 m of it.

## 10. Editor generation

Two steps, both editor-time; the runtime never parses GIS data.

1. **Export** — `key_west_reality.py export-editor [--route] [--chunk cx:cz]` writes
   `derived/editor_chunks/chunk_<cx>_<cz>.json` + `terrain_<cx>_<cz>.f32` (git-ignored).
   Mesh-ready geometry in local metres with **the source of every height**
   (`height_sources` per feature), node metadata, applied overrides and the
   regeneration action. Settings: `config/generation.json`.
2. **Build** — `KeyWestChunkGenerator` (`tools/world/reality_gen/`) turns each chunk into
   `scenes/world/key_west/generated/chunks/Chunk_<cx>_<cz>.scn` plus
   `KeyWest_generated.tscn`, and writes `generation_report.json`.
   - In the editor: run `generate_key_west_chunks.gd` (Script editor › File › Run).
   - Batch: `godot --headless --script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- [cx:cz ...]`.

   Generated scenes are local, regenerable artefacts (git-ignored). Authored work lives
   in Blender/Godot assets registered in `authoring/asset_manifest.json`. The generator
   instances those in place of the generated mesh, so regeneration never overwrites them.

**Priority corridor.** `first_exit` runs Battery Osceola → 727 Fort Street, buffered by 350 m.
It covers chunks x −9…−7, z 2…4 and is generated first, at 1 m roof and terrain sampling.
The rest of the island uses the same rules at 2 m. Fidelity changes sampling, never which
real features exist.

| What | Geometry | Heights from |
|---|---|---|
| Terrain | 512 m tile, 1 m (corridor) / 2 m grid, HeightMapShape3D collision | DEM 6366 (measured). Voids (25 %: open sea beyond coverage, dredged basins): nearest valid depth clamped to MLLW (**inferred**, `dem_void_share` per tile) |
| Buildings | real footprint (holes kept) → walls following the roof edge + roof | ground: lidar ring / DEM; roof: **lidar roof model** |
| Roads, paths, runways | ribbons along real centrelines | DEM; bridge decks: lidar DSM along the line |
| Piers, decks, bridge outlines | real polygons as slabs | lidar DSM median over the polygon |
| Airport pavement | apron / runway / taxiway / taxilane / stopway / helipad polygons as slabs; aerodrome boundaries → markers | DEM |
| Barriers | real polylines as walls | OSM `height` or class default (**inferred**, flagged) |
| Power | real pole positions; wires only on real pole-to-pole edges | lidar max within 1 m of the pole |
| Trees | crown proxies at real detections | lidar CHM height / crown radius |
| Dense canopy | real canopy polygon as a mass | lidar DSM median |
| Pools / ponds / canals | real polygons | pool: rim − 0.3 m; others: MSL −0.265 (8724580) |
| Street furniture, utilities | real points | class default (inferred) |
| Everything else | Marker3D at the real position | DEM |

**Roof reconstruction** (model-driven LoD2, the approach of 3D BAG / Kada & McKinley):
- For each footprint with lidar relief ≥ 0.6 m, the median-filtered 2019 DSM cells inside it
  are fitted with flat, gable along either axis, hip and shed models.
- Fitting is trimmed least squares, so overhanging canopy is rejected. Models are compared by
  truncated L1 error over all cells plus a parameter penalty.
- Slopes are limited to plausible ranges (8°–56°).
- No adequate model (complex roofs, roughly 20 %): a flat cap at the measured median height,
  labelled `flat_cap_complex_roof_unresolved`.
- Authoritative heights clamp the model (727 Fort Street: 6.86 m).

**Scene tree and metadata:**

```
KeyWest
  Chunk_-7_3                     chunk_id, fidelity, library_sha256, builder_version
    Terrain  Terrain_-7_3        (+ Collision/HeightMapShape3D)
    Buildings  KW_BUILDING_osm_w339414849  MeshInstance3D: surfaces walls/roof, Collision
    Roads  Barriers  Infrastructure (poles, KW_WIRE_*)  Vegetation  Coastal  LandUse
    Anchors  FirstExit_Start / FirstExit_Shelter (owner decision #211), Custom_* markers
```

Every feature node carries `feature_id, feature_class, source_geometry_hash,
source_dataset, source_record, source_epoch, observed_at, reconstruction_class,
confidence, scope, override_state, landmark_role, authoring_state, asset_revision,
generator_version, generated_at, regen_action, fidelity`. Meshes also carry
`height_sources`, `roof_source` and `roof_model`. The generator checks this contract
on every chunk and the CLI exits non-zero on any violation.

Building meshes:
- surface 0 `walls`, surface 1 `roof`;
- origin at the footprint centroid on measured ground; 1 unit = 1 m;
- identity transform apart from the origin translation;
- name `KW_<TOKEN>_<namespace>_<id>`.

Placeholder heights (no lidar) are shown in a distinct red material.

**Overrides at generation time:**
- the severed US-1 bridge removes the deck ribbons, the OSM bridge lines and the outline over
  the removed span (full deck width: a 30 m flat-cap buffer of each `remove_span` line);
- landmark roles are written to the node (`landmark_role`). An authored landmark asset in
  the manifest replaces the generic mesh on that footprint.

## 11. Blender roundtrip and regeneration rules

1. Generator writes a mesh per feature (object name as above **and** custom properties
   `feature_id`, `asset_id`, `source_geometry_hash`, `authoring_state`,
   `last_generator_version` — glTF extras survive Blender import/export).
2. Artist edits; the asset is registered:
   `key_west_reality.py asset --feature-id <id> --state artist_modified|artist_locked --blend <file>`.
3. Re-import binds by `feature_id` custom property, not by name.
4. `regen.plan()` decides per feature: `generate`, `regenerate` (only `generated` assets),
   `keep_locked` (`artist_modified` / `artist_locked`), `needs_rebase` (authored asset whose
   source footprint hash changed), `orphaned` (feature gone; asset kept for review).
5. After any source update: `asset --rebase-check` marks changed authored assets
   `needs_rebase`; nothing is deleted. `export-editor` and `validate` refuse to run if a
   locked asset would be regenerated (`regen.violations`), covered by
   `tools/world/reality/test_reality.py`.

## 12. Source update workflow

```
python3 tools/world/key_west_reality.py acquire --source overture   # new release / data
python3 tools/world/key_west_reality.py build      # IDs carried from the previous library
python3 tools/world/key_west_reality.py validate   # contract checks, exit 1 on errors
python3 tools/world/key_west_reality.py diff       # reports/change_report.md (+/−, footprints, heights...)
python3 tools/world/key_west_reality.py asset --rebase-check
python3 tools/world/key_west_reality.py report && python3 tools/world/key_west_reality.py preview
python3 tools/world/key_west_reality.py pack       # only when promoting a new library to git
```

Nothing regenerates the world automatically; the change report is the input to a
selective editor regeneration.

## 13. Storage policy

| level | path | in git |
|---|---|---|
| raw cache (~3.3 GB: USGS state zips 2.6 GB, DEM crop 0.2 GB, lidar grids 0.5 GB, Overture 18 MB) | `reality/raw_cache/` | no — re-downloadable; receipts + checksums are committed |
| receipts, config, overrides, authoring manifest, reports | `reality/{receipts,config,overrides,authoring,reports}/` | yes |
| normalized library | `reality/library/key_west_reality.gpkg.xz` (~24 MB; 133 MB unpacked) | yes, on promotion only |
| editor interchange | `reality/derived/` | no — regenerable |
| previews | `docs/world/reality_previews/` | yes |
| runtime | `data/world/key_west/*.json`, `world/terrain/` | unchanged |

`reality/` carries a `.gdignore`, so Godot never imports the raw cache or the library.

## 14. Validation and reports

`validate` (errors fail the run): ID format and uniqueness, empty geometry, CRS sanity,
features outside the extent, forbidden families in the Boca Chica zone, features
without a geometry source, attributes without source, authoritative values whose
source is a rule, unknown reconstruction classes, double-selected attributes,
unregistered sources, overrides targeting missing features, locked assets scheduled for
regeneration, systematic vector/lidar offset > 1 m, poles without a point.
Warnings (data kept as-is): invalid polygons, broken lines, implausible heights,
buildings in water (structures on piers), detached piers (floating docks), overlapping
buildings (duplicates inside OSM), identical geometries, open utility edges.

Reports: `reports/accuracy_report.md` (coverage, completeness and confidence counted
separately), `validation_report.md`, `change_report.md`, `build_stats.json`.
Previews: `docs/world/reality_previews/01…09*.png` (library maps) `10…16_godot_*.png`, `18_godot_island_overview.png`, the measured landmarks
`19…20_godot_landmark_*.png` and the full game `World` on generated chunks `21_game_world_reality_spawn.png`
(generated chunks rendered in Godot on lavapipe by `capture_key_west_route.gd`).
`17_godot_first_exit_flythrough.mp4` (0.9 MB) is the Battery Osceola → 727 Fort Street
flythrough at 28 m altitude.

## 15. First Exit landmarks (measured)

`key_west_reality.py landmarks` (`tools/world/reality/landmarks.py`):
- measures both landmarks;
- writes glTF to `assets/world/key_west/landmarks/*.glb` (Godot imports them; Blender opens them);
- writes a provenance sidecar per landmark to `data/world/key_west/reality/landmarks/*.json`;
- registers the assets in `authoring/asset_manifest.json` as `kind: landmark`, `generated`.

The chunk generator then instances the asset in place of the generic massing. An
`artist_*` asset is never rewritten; that is the normal Blender roundtrip. Mesh nodes
end in `-col`, so Godot builds their collision.

**727 Fort Street** (`kw:building:osm:w339414849`):

| Element | Value | Class | From |
|---|---|---|---|
| Roof | flat, 4.71 m above the lidar ground ring (5.94 m NAVD88) | measured | 2019 DSM, 1,185 roof cells; 2016 gives 4.76 m |
| Parapet | none (edge 1 cm above the interior) | measured | 2019 DSM edge ring |
| Roof outline | OSM trace + about 2 m roof run-out at both notches (418 m²) | cross_verified | per-edge lidar profiles, both epochs |
| Walls | OSM trace inset 0.45 m = 343.1 m² = City record 3,693 sq ft | cross_verified | eave run-outs measured 0–0.6 m |
| Floor | ring ground + 0.15 m | inferred | — |
| Openings, plan | not modelled | unresolved | Legistar attachments not delivered |

There is a conflict with the record. The City's "existing height 22 ft 6 in" (6.86 m)
is 2.1 m above the roof, and both lidar epochs agree on the roof. The geometry follows
the measurement, and the conflict is kept in the sidecar. Codex was asked for the
record's height datum and for evidence of the post-2020 state (#1).

**Fort Zachary Taylor fronts / Battery Osceola start** (`kw:building:osm:w524088621`):
- a 2.5D surface of the surviving fronts from the 2019 DSM at 0.5 m (43.7k triangles);
- 2019 gaps (9.6 %) are filled from 2016; the two epochs agree within a median 6 cm, MAD 2 cm;
- the outline is dropped to the DEM as walls into the moat;
- exterior massing only, no emplacement detail. No separate Battery footprint exists in
  any reachable source, so the start anchor sits on the measured south-front mass.

## 16. Production streaming

**Placement contract.** The generator writes `scenes/world/key_west/generated/world_data.tres`:
- one `ChunkData` per chunk: id `kw_gen_<cx>_<cz>`, centre position, radius 362 m;
- chunk content is stored relative to the chunk centre, so the unmodified
  `StreamingSystem` places it with `global_position = centre`.

**Experimental profile.** `data/world_profiles/key_west_reality.tres` with
`scenes/world/key_west/key_west_reality.tscn`:
- the production `World` composition root, all 15 systems;
- no `IslandTerrain`, because chunks carry their own DEM terrain and collision;
- spawn on the First Exit start anchor.

The main scene is unchanged.

**Three `StreamingSystem` defects were found by measuring, and fixed:**
- **Queued loads only started on a rescan**, i.e. after the player walked 40 m. A player
  standing at spawn waited more than 120 s and stood on an unloaded chunk.
  `pump()` now fills free load slots, nearest first.
- **The packed-scene cache never shrank.** It is now an LRU of `cold_cache_limit` (8)
  released scenes.
- **`prewarm_before_first_frame` was ignored by static streaming.** The player started
  falling before the fort chunk arrived and ended up inside it at y 0.46. The spawn band
  is now loaded synchronously behind the title card; the player lands on the measured
  fort surface (7.93 m) on frame 1.

Both fixes have tests in `tests/systems/test_streaming.gd`.

**Chunk build changes for streaming:**
- trees, poles and props are MultiMesh nodes, with per-instance provenance arrays;
- building collision is one prism-per-outline shape per chunk. Building a BVH over the
  render triangles cost 108 ms on first instantiate.
- meshes are indexed and attribute-compressed.

Generation needs a rendering driver. A headless dummy renderer saves empty MultiMesh
buffers, so the contract check now fails on that.

**Measured.** `tools/runtime/benchmark_key_west_reality_streaming.gd` uses the production
streaming budgets and real-time movement. Reports are in
`docs/runtime_previews/key_west_reality_streaming/`.

| | First Exit (619 m, 6 m/s) | Island (11.7 km, 25 m/s) |
|---|---|---|
| Spawn to everything near active | 0.44 s (was > 120 s) | 0.42 s |
| Time on an unloaded chunk | 0 s (was 6.7 s) | 0 s |
| Activation p50 / max | 12 / 29 ms (was 122 ms) | 10 / 25 ms |
| Frames > 33 ms | 0 | 0 |
| Static memory peak / after leaving | 190 / 176 MB | 232 / 97 MB |

## 17. Next stages

1. **727 / Battery authored detail.** Openings, floor plan and Battery exterior detail
   wait for the Legistar attachments and preservation drawings or photos (requested in
   issue #1). The measured assets are the base an artist refines (`artist_modified`).
2. **Make the profile the default.** That needs:
   - an author decision;
   - the exported interchange shipped as `editor_chunks.tar.xz` (about 31 MB), so CI and
     fresh clones regenerate scenes in about 3 minutes without the raw lidar cache.
3. **Activation spikes.** Dense Old Town chunks still take 20–29 ms on this CPU (13 of 68k frames over 16.7 ms on the island drive).
   Next, instantiate on a worker thread (Godot's documented build-off-tree pattern)
   or merge buildings per block.
4. **Facades.** Openings and colours need imagery (NAIP blocked) or planning sheets.
   Until then walls stay plain; nothing is invented.
5. **Roofs.** Split complex footprints before fitting. Canopy-polluted lidar P95 heights
   (as at 727) should give way to the roof-band median.
6. **Far LOD.** OBB/hull proxies as separate derived meshes for the ring beyond the load band.

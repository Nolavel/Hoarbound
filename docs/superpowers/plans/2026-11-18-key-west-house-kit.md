# Key West House Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every building in the 400 x 400 m square around 727 Fort Street becomes a recognisable Key West house, built by one kit from a per-house record whose every attribute names its source.

**Architecture:** A Python stage derives a house record per building (documents, lidar, owner observations, HARC type rules) and stores it as provenance-carrying `Attr` rows in the Reality Library; the editor export passes it to each building and turns porch roofs into roof geometry (so static snow covers them). The Godot chunk builder assembles walls, trim, porches, piers, windows and doors from the record through a new `KeyWestHouseKit`, with colours as vertex colours so draw calls stay per surface, not per detail.

**Tech Stack:** Python 3.13 (numpy, shapely, pyogrio; venv in the scratchpad), Godot 4.8-dev6 GDScript, ArcGIS REST (City of Key West), Legistar web API.

**Spec:** `docs/superpowers/specs/2026-11-18-key-west-houses-design.md`

## Global Constraints

- Square: 400 x 400 m centred on 727 (local origin of 727 `[-3530.487, 1583.02]`); chunks −8:2, −7:2, −8:3, −7:3.
- Evidence ladder per attribute: document > lidar (measured) > owner observation (visual) > type rule (`inferred`, flagged).
- Measured absence beats the type: no lidar porch roof along a wall means no porch there.
- Post-1945, CBS, non-residential use codes get masonry or modern types without default porches.
- Colour without a source: HARC palette (Guidelines p. 34) plus, inside Bahama Village, Caribbean brights on about one third of those houses; fixed per house by a hash of the feature id; `recon: inferred`.
- HARC traditional colours (Guidelines p. 34): bodies white, pastels, light gray, beige, buff; trim white or off-white; shutters white, black, gray, dark green; metal roofing silver; porch ceilings light aqua, light blue, white; porch decks gray, green, white; lattice dark green or white; doors white, black, red, dark green, natural wood.
- Legistar documents: facts only, sheets never stored. Street View and Esri imagery: visual only. City GIS: public records with receipts.
- Provenance extends the existing model (`Attr`, `recon` classes, `sources.json`, receipts); no new classification.
- Facade windows stay in a surface named `windows` (frost shader and `WindowBreakage` read it).
- Draw calls in the comparison views within +15 % of today (working number until an HD 620 run).
- Godot: static typing, tabs, `##` comments of at most 2 lines, no new visual `.new()` in `scripts/` or `world/` (ratchet); English code and docs.
- Every task: a test that fails on the old code; CHANGELOG entry at the end; commits on `claudeflow`, never `main`.

## Review Focus

- A building with no HARC survey match and no parcel year (condos, 810 null years): must still get a type (by form and use) and a palette colour, never a crash or an empty record.
- A footprint whose edge is shared with a neighbour (row houses, merged outlines): no porch or windows on a party wall; lidar porch detection must ignore an edge with another building within 1.0 m.
- A tiny outbuilding (< 30 m²) or shed: no porch, no piers, at most one door; it must not be dressed as a house.
- A chunk exported before this change (no `house` block): the builder must produce exactly today's output.
- A documented house whose matter predates a later rebuild (world date 2025-12-31): the newest record valid on the world date wins.

---

### Task 1: City GIS house sources with receipts

**Files:**
- Create: `tools/world/reality/city_gis.py`
- Modify: `data/world/key_west/reality/config/sources.json` (2-space indent), `tools/world/key_west_reality.py` (command `house-sources`)
- Create: receipts `data/world/key_west/reality/receipts/city_kw_harc_survey.json`, `city_kw_mcpao_parcels.json`, `city_kw_harc_guidelines.json`
- Test: `tools/world/reality/test_reality.py` class `CityGisHouses`

**Interfaces:**
- Produces: `city_gis.acquire(layer: str, bbox_local: list[float]) -> dict` (GeoJSON in EPSG:32617 local frame saved under `raw/city_gis/<layer>.geojson`, receipt written); `city_gis.survey() -> list[dict]` with keys `geom` (shapely, local), `address`, `style` (normalised, e.g. `frame_vernacular`), `year_built` (int | None), `contributing` (bool); `city_gis.parcels() -> list[dict]` with `geom`, `address`, `year_built` (int | None), `use_code` (str), `floor_area_sqft` (float | None), `buildings` (int); `city_gis.bahama_village() -> shapely geometry` (local frame, from `BV_CRA_District_2020`).
- Layers: `HARC_CONT_STRUCT1292025_gdb_view`, `MCPAO_PARCELS_KW_ALL_INFO`, `Harc_District` (Bahama Village test uses `BV_CRA_District_2020`), service root `https://services3.arcgis.com/aIpcLPHSEqH4LbLl/arcgis/rest/services/<layer>/FeatureServer/0`.

- [ ] **Step 1: Write the failing tests** `test_style_names_are_normalised` (`"Frame\nVernacular"` → `frame_vernacular`, `"Neo-Classical\nRevival ca.\n1880-1940"` → `classical_revival`, `" "` → None), `test_year_built_parses_circa` (`"c1920"` → 1920, `"1845"` → 1845, `" "` → None), `test_parcel_records_keep_use_and_year` on a 2-feature fixture in the test.
- [ ] **Step 2: Run** `$VENV -m unittest reality.test_reality.CityGisHouses` from `tools/world`; expect FAIL (module missing).
- [ ] **Step 3: Implement** `city_gis.py` with the functions above; `acquire` follows `city_footprints.acquire` (ArcGIS query by envelope in 4326, GeoJSON, retries, receipt with URL, time, sha256, count). Add `sources.json` entries `city_kw_harc_survey`, `city_kw_mcpao_parcels` (licence: public records, City of Key West GIS), `city_kw_harc_guidelines` (URL `https://www.cityofkeywest-fl.gov/DocumentCenter/View/1551/HARC-Guidelines-PDF`, facts only).
- [ ] **Step 4: Run** the tests; PASS. Run `key_west_reality.py house-sources` once; expect counts close to 79 survey and 732 parcel features.
- [ ] **Step 5: Commit** `Key West houses: City GIS survey and parcel sources`.

### Task 2: Type rules and palette

**Files:**
- Create: `data/world/key_west/reality/config/house_types.json`, `tools/world/reality/house_types.py`
- Test: `test_reality.py` class `HouseTypes`

**Interfaces:**
- Produces: `house_types.classify(style: str | None, year_built: int | None, use_code: str | None, storeys: int, area_m2: float) -> tuple[str, str]` → `(type, recon)`; `house_types.defaults(kind: str) -> dict` (cladding, roof_material, foundation, porch_default {depth_m, storeys}, sash, shutters, bay_m); `house_types.palette(feature_id: str, kind: str, bahama_village: bool) -> dict` → `{"body": [r,g,b], "trim": [...], "shutters": [...], "roof": [...], "recon": "inferred"}`.
- Types: `frame_vernacular`, `cigar_makers_cottage`, `eyebrow`, `classical_revival`, `masonry_vernacular`, `cbs_modern`, `commercial`, `outbuilding`. Each with its Guidelines page citation in the JSON.

- [ ] **Step 1: Failing tests** `test_survey_style_wins` (`classify("frame_vernacular", 1938, "01", 1, 90)` → `("frame_vernacular", "documented")`), `test_post_war_masonry_has_no_default_porch` (`classify(None, 1962, "01", 1, 120)` → `cbs_modern`, `defaults("cbs_modern")["porch_default"] is None`), `test_small_buildings_are_outbuildings` (area 18 m² → `outbuilding`), `test_palette_is_stable_and_harc` (same id twice → same colours; trim in the HARC trim set), `test_bahama_village_brights_about_a_third` (over 300 synthetic ids, bright share in 0.25–0.42; outside BV share 0).
- [ ] **Step 2: Run**; FAIL.
- [ ] **Step 3: Implement** the JSON (palette sRGB values, Caribbean brights set, per-type defaults with citations) and `house_types.py`; the hash is `sha256(feature_id)`; brights chosen when `hash % 3 == 0` in BV.
- [ ] **Step 4: Run**; PASS.
- [ ] **Step 5: Commit** `Key West houses: HARC type rules and palette`.

### Task 3: Lidar porch detection

**Files:**
- Create: `tools/world/reality/porches.py`
- Test: `test_reality.py` class `PorchDetection`

**Interfaces:**
- Consumes: `meshing.Surfaces.dsm_window(geom, pad)`, `Surfaces.ground_at(xy)`.
- Produces: `porches.detect(poly_proj, s: meshing.Surfaces, neighbours: list) -> list[dict]`, each `{"edge": int, "offset_m": float, "length_m": float, "depth_m": float, "roof_y": float, "inside": bool}`; `porches.from_dsm(poly, dsm, transform, ground, main_roof, neighbours) -> list[dict]` (pure, testable).
- Rule: per edge ≥ 3.0 m, sample a band from 0.3 to 3.5 m outside (and the outer 3.5 m inside, for porches drawn into the footprint); a porch is a run ≥ 2.5 m where the median height over ground is 2.2–4.2 m and at least 1.5 m under the main roof median, covering ≥ 60 % of the run; edges with another footprint within 1.0 m are skipped.

- [ ] **Step 1: Failing tests** on synthetic DSM grids: `test_front_porch_outside_the_footprint` (a 3 m-high band 2.4 m deep along edge 0 → one porch, depth 2.4 ± 0.3, length ± 0.5), `test_no_porch_on_a_bare_wall`, `test_party_wall_is_skipped`, `test_porch_inside_the_footprint` (lower band within the outline → `inside: True`).
- [ ] **Step 2: Run**; FAIL.
- [ ] **Step 3: Implement** `from_dsm` and `detect`.
- [ ] **Step 4: Run**; PASS.
- [ ] **Step 5: Commit** `Key West houses: lidar porch detection`.

### Task 4: House record stage and library write

**Files:**
- Create: `tools/world/reality/houses.py`
- Modify: `tools/world/reality/library.py` (`upsert_attributes`), `tools/world/key_west_reality.py` (command `houses [--apply]`)
- Test: `test_reality.py` class `HouseRecords`

**Interfaces:**
- Consumes: Task 1 `survey()`, `parcels()`; Task 2 `classify`, `defaults`, `palette`; Task 3 `detect`.
- Produces: `houses.record(fid: str, poly_proj, attrs: dict, survey: list, parcels: list, porch_list: list, documented: dict | None, observed: dict | None) -> list[Attr]` with names `house_type`, `house_storeys`, `house_cladding`, `house_colours`, `house_roof_material`, `house_foundation`, `house_porches`, `house_facades`, each `Attr` carrying `source_id`, `method`, `recon`, `confidence`, `observed_at`; `library.upsert_attributes(path, rows: dict[str, list[Attr]]) -> dict` (replaces `house_*` rows of those features, idempotent, returns counts).

- [ ] **Step 1: Failing tests** `test_every_house_attribute_names_its_source`, `test_measured_absence_beats_the_type` (frame_vernacular, `porch_list=[]` → `house_porches` value `[]`, recon `measured`), `test_documented_beats_lidar` (a documented porch overrides the detected one), `test_unknown_house_still_gets_a_record` (no survey, no parcel year → type by form, palette colour, recon `inferred`), `test_upsert_is_idempotent` (two runs → same row count).
- [ ] **Step 2: Run**; FAIL.
- [ ] **Step 3: Implement** `houses.record`, the stage `houses.run(apply: bool)` over buildings intersecting the square, `library.upsert_attributes` (same row builders as `_store_rows`), the CLI command (prints counts by type and by recon).
- [ ] **Step 4: Run** the tests; PASS. Run `key_west_reality.py houses` (dry) and read the counts: expect most of the 209 buildings as `frame_vernacular`, porches on the order of the survey's frame houses.
- [ ] **Step 5: Commit** `Key West houses: per-house record with provenance`.

### Task 5: Export the record and porch roofs

**Files:**
- Modify: `tools/world/reality/editor_export.py` (KEEP_ATTRS, building mesh), `tools/world/reality/meshing.py` (`porch_roof`)
- Test: `test_reality.py` class `HouseExport`

**Interfaces:**
- Consumes: Task 4 attributes.
- Produces: building export key `mesh["house"]` = `{"type", "storeys", "cladding", "colours": {"body","trim","shutters","roof"}, "roof_material", "foundation": {"kind","height_m"}, "porches": [{"a": [x,z], "b": [x,z], "depth_m", "roof_y", "storeys", "outward": [x,z]}], "facades": [{"a","b","outward","openings": [{"kind","along_m","width_m","sill_m","head_m","shutters"}]}], "recon": {<attribute>: <recon>}}`; porch roofs appended to `roof_v`/`roof_i` (so `static_snow.roof_cap` covers them); `meshing.porch_roof(a, b, outward, depth_m, eave_y, ridge_y) -> tuple[np.ndarray, np.ndarray]` (shed roof falling outward).

- [ ] **Step 1: Failing tests** `test_house_block_in_export` (synthetic feature with `house_*` attrs → `mesh["house"]` keys as above), `test_porch_roof_joins_the_roof_mesh` (roof triangle count grows by 2 per porch; snow cap covers it), `test_old_export_has_no_house_block` (no `house_*` attrs → no `house` key, `roof_v` unchanged).
- [ ] **Step 2: Run**; FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run**; PASS.
- [ ] **Step 5: Commit** `Key West houses: export the record, porch roofs as roof geometry`.

### Task 6: The kit in the chunk builder

**Files:**
- Create: `tools/world/reality_gen/key_west_house_kit.gd` (`class_name KeyWestHouseKit`, static functions)
- Modify: `tools/world/reality_gen/key_west_chunk_builder.gd` (`_building`, `_window_row` callers, materials)
- Test: `tests/systems/test_key_west_house_kit.gd`

**Interfaces:**
- Consumes: Task 5 `mesh["house"]`.
- Produces: `KeyWestHouseKit.walls_colour(house: Dictionary) -> Color`; `KeyWestHouseKit.add_trim(st: SurfaceTool, house: Dictionary, ring: PackedVector2Array, centre: Vector2, base: float) -> int` (corner boards, porch deck, posts every ≤ 2.4 m, railing at 0.9 m, piers and lattice band, shutters beside windows, door panels; returns quads added); `KeyWestHouseKit.add_openings(panes: SurfaceTool, house: Dictionary, centre: Vector2, base: float) -> int` (windows from the record's facades, else legacy rows). Materials: walls and roof switch to `use_vertex_color` (one material each); new surface `trim` (vertex-coloured); `windows` unchanged.

- [ ] **Step 1: Failing tests** in `test_key_west_house_kit.gd`: `_check_surfaces` (a feature with a house block → surfaces `walls`, `roof`, `windows`, `trim`), `_check_colours` (walls vertex colour equals the record body colour to 1/255), `_check_porch` (a 7.2 m porch → 4 posts), `_check_legacy` (no house block → same vertex count and surfaces as before the change, compared against a stored count from the old builder), `_check_party_wall` (facade without openings → no panes on it).
- [ ] **Step 2: Run** `godot --headless --script tests/systems/test_key_west_house_kit.gd`; FAIL.
- [ ] **Step 3: Implement** the kit and the builder changes; cladding by a world-space line pitch (0.18 m lap) in the stylized wall shader path only where `cladding` is siding.
- [ ] **Step 4: Run** the new suite, `test_window_frost`, `test_window_breakage`, `test_key_west_reality_hlod`, `test_world_composition`, `python3 tools/ci/check_runtime_construction.py`; all PASS.
- [ ] **Step 5: Commit** `Key West houses: house kit in the chunk builder`.

### Task 7: Documented houses from HARC packages

**Files:**
- Create: `data/world/key_west/reality/config/documented_houses.json`, `tools/world/reality/documented_houses.py`
- Modify: `houses.py` (consume), `sources.json` (one entry per matter read)
- Test: `test_reality.py` class `DocumentedHouses`

**Interfaces:**
- Produces: `documented_houses.load() -> dict[str, dict]` keyed by address; each record `{matter, date, valid_from, facades: {"street"|"left"|"right"|"rear": openings}, porches, cladding, roof_material, colours?}`; `documented_houses.candidates() -> list[dict]` (addresses in the square with Legistar building-work matters, newest first).

- [ ] **Step 1: Failing tests** `test_records_have_matter_and_date`, `test_newest_valid_record_wins` (two records, world date 2025-12-31), `test_street_side_maps_to_the_edge_facing_the_street`.
- [ ] **Step 2: Run**; FAIL.
- [ ] **Step 3: Implement** the loader and `candidates()`; read the existing-elevation sheets of the candidates (start with 714 Chapman Ln, 221 Petronia St, 715 Chapman Ln, 716 Thomas St, 219 Olivia St, 705 Chapman Ln) and record facts only.
- [ ] **Step 4: Run**; PASS. Dry-run `houses` and list which houses changed from `inferred` to `documented`.
- [ ] **Step 5: Commit** `Key West houses: documented houses from HARC packages`.

### Task 8: Screenshot request list

**Files:**
- Modify: `houses.py` (`screenshot_requests`)
- Create: `data/world/key_west/reality/reports/house_screenshot_requests.md` (generated)
- Test: `test_reality.py` class `ScreenshotRequests`

**Interfaces:**
- Produces: `houses.screenshot_requests(records: dict, streets: dict, limit: int = 40) -> list[dict]` (`address`, `side`, `view`, `score`), and the markdown writer; `houses.observations() -> dict[str, dict]` reading `config/house_observations.json` (address, side, date seen, attributes; recon `visual`), passed to `houses.record(..., observed=...)`.

- [ ] **Step 1: Failing tests** `test_observation_sets_colour_as_visual` (an observed body colour replaces the palette, recon `visual`), `test_documented_houses_are_not_requested`, `test_street_facing_side_is_named`, `test_ranked_by_visibility` (a house on Fort St ranks above one behind it).
- [ ] **Step 2: Run**; FAIL. **Step 3: Implement.** **Step 4: Run**; PASS.
- [ ] **Step 5: Commit** and send the list to the owner (in Russian, address, side, view).

### Task 9: Regenerate the square, verify, document

**Files:**
- Modify: chunk exports and scenes for −8:2, −7:2, −8:3, −7:3, HLOD clusters, digests; `CHANGELOG.md`; `docs/world/KEY_WEST_REALITY_LIBRARY.md` (section "Houses")

- [ ] **Step 1:** `key_west_reality.py houses --apply`; `export-editor --chunk=-8:2 --chunk=-7:2 --chunk=-8:3 --chunk=-7:3`; `export_pack.py pack`; `godot --headless --import`; chunk generation with `--record-digest`; HLOD `--dirty --check --record-digest`. Expect 0 contract violations, HLOD check ok.
- [ ] **Step 2:** Comparison shots from the audit viewpoints (g1–g8) and five street viewpoints on Fort, Petronia, Emma, Olivia, Angela; render statistics; draw calls within +15 %.
- [ ] **Step 3:** Full verification: `reality.test_reality`, the 15 Godot suites used for 727 plus `test_key_west_house_kit`, CI ratchets.
- [ ] **Step 4:** CHANGELOG entry, library documentation, report page update; commit; push `claudeflow`; handoff on issue #1.

# Lofts at Bahama Village in the Reality Library — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the four Lofts masses (A Fort wing, A Allen wing, B, C) opposite 727 to the Reality
Library from approved plans, and regenerate only the chunks they touch.

**Architecture:** A documented-buildings source (`config/documented_buildings.json`) feeds a
build stage that makes ordinary library features with full provenance. The same stage patches the
committed library without the raw cache. The exporter passes a documented roof model to the
existing `building_shell`, so the Godot generator needs no change.

**Tech Stack:** Python 3 (shapely, numpy, pyogrio, rasterio, triangle), GeoPackage, Godot 4.8 CLI
generators (`tools/world/reality_gen/*_cli.gd`).

**Spec:** `docs/superpowers/specs/2026-11-18-key-west-727-reconstruction-design.md`

## Global Constraints

- Coordinates in documented records: EPSG:32617; local frame from `config/frame.json`.
- Provenance per mass: `geometry_source` = registered source id, `geometry_record` = Legistar file
  and sheet, `geometry_method` = `approved_site_plan_georeferenced`, `reconstruction_class` =
  `derived`, `confidence` = 0.6, `geometry_accuracy_m` = 2.0, `valid_from` = `2025-10-30`, flag
  `as_designed_not_surveyed`.
- Feature ids: `kw:building:doc:<source>_<mass>` (e.g. `kw:building:doc:legistar_22_3575_c`).
- Plan drawings are copyrighted: commit facts, coordinates and SHA-256 of the PDFs, never the PDFs
  or crops of them.
- Height cap 35 ft = 10.67 m above the crown of Fort Street (HARC report, 22-3575).
- Comments: English, `##`/`"""` doc style, at most two lines. Untouched chunks must stay
  byte-identical after re-export.

## Review Focus

- Re-running the patch on an already patched library must not duplicate rows (idempotent).
- A documented mass overlapping an existing library building (old parking shed, park outline)
  must be reported, not silently merged.
- Re-exporting an untouched chunk with the freshly acquired DEM/lidar crop must reproduce the
  committed JSON; if it does not, stop: the environment is not at parity.
- A documented roof must never exceed the documented height cap even if the model says otherwise.
- The game must not lose the 727 landmark or the First Exit anchors in the regenerated chunks.

---

### Task 1: Standing rule and source registration

**Files:**
- Create: `.claude/rules/key-west-reconstruction.md`; Modify: `.claude/rules/00-index.md`
- Modify: `data/world/key_west/reality/config/sources.json`
- Create: `data/world/key_west/reality/receipts/city_kw_legistar_22_3575.json`

- [ ] Rule file (VERIFIED 2026-11-18, owner): screenshot-request rule and "approved plan = temporary
  geometry, flagged" rule, as written in the spec; index line added.
- [ ] `sources.json`: entry `city_kw_legistar_22_3575` (Planning Board MDP 918 Fort St, 2022-12-19;
  related 22-3623 HARC, 25-4377 condominium), licence note "public record; drawings © PQH Group,
  facts only".
- [ ] Receipt: attachment URLs, retrieval time, SHA-256 and byte size of each PDF read.
- [ ] Commit.

### Task 2: Documented records and georeferencing

**Files:**
- Create: `tools/world/reality/documented.py`
- Create: `data/world/key_west/reality/config/documented_buildings.json`
- Test: `tools/world/reality/test_reality.py` (class `DocumentedBuildings`)

**Interfaces:**
- Produces: `documented.load() -> list[dict]`; `documented.georeference(plan_px: list[tuple[float,float]], georef: dict) -> shapely.Polygon` (EPSG:32617);
  `documented.features(idreg) -> list[Feature]`.

- [ ] Test `test_lofts_area_matches_record`: the four masses sum to 52 870 sq ft within 6 %.
- [ ] Test `test_fort_facades_sit_behind_the_right_of_way`: Fort-facing edges of A-Fort and C are 4.5–7.5 m
  from the Fort St centreline (OSM way 1058448895).
- [ ] Test `test_records_carry_provenance`: every feature has the Global Constraints provenance and flag.
- [ ] Run; expect FAIL (module missing).
- [ ] JSON stores per mass: `plan_px` corners (sheet 88 crop pixels), `georef` (origin = Fort×Allen
  centreline crossing from OSM ways 1058448895/1058367479, axis along Fort St, scale 1″=50′ =
  0.2345 m/px), facts (levels, height_m, eave_m, ridge_m, roof type, roof material, address,
  units). Heights and the C height step come from elevation sheets of 22-3575; write them with
  the sheet number. A-Allen wing three storeys (owner panorama 2026-11-18, visual).
- [ ] Implement; run; expect PASS. Commit.

### Task 3: Library stage and patch command

**Files:**
- Modify: `tools/world/reality/build.py` (call the stage after `bind_facts`)
- Modify: `tools/world/reality/library.py` (`append_features(path: Path, features: list[Feature]) -> dict`)
- Modify: `tools/world/key_west_reality.py` (command `documented --apply`)
- Test: `test_reality.py` (class `LibraryPatch`, on a temp copy)

- [ ] Tests: `test_patch_inserts_four_masses`, `test_patch_is_idempotent`,
  `test_overlap_is_reported` (expects the overlap list to name existing ids under each mass).
- [ ] Run; expect FAIL.
- [ ] `append_features` reuses `write()`'s row builders (extract `_rows(features)`); deletes rows of
  the same ids first; writes buildings layer, attribute, source_link, feature_index; re-packs
  `.gpkg.xz` and manifest.
- [ ] Run; PASS. Apply to the committed library; record overlaps in `reports/documented_buildings.json`. Commit.

### Task 4: Documented roofs in the shell

**Files:**
- Modify: `tools/world/reality/meshing.py` (`building_shell(..., documented_roof: dict | None = None)`)
- Modify: `tools/world/reality/editor_export.py` (pass the selected `roof_documented` attribute)
- Test: `test_reality.py` (class `DocumentedRoof`)

- [ ] Tests: `test_gable_ridge_and_eave_heights` (rectangle 20×40 m, eave 6.4, ridge 9.6 above base,
  ridge along the long axis), `test_roof_source_names_documents` (`documented_gable_major`),
  `test_roof_is_capped_at_height`.
- [ ] Run; FAIL. Implement as a model dict fed to `eval_roof_model` (same `_design` kinds); lidar
  path unchanged. Run; PASS. Commit.

### Task 5: Environment parity for chunks −8:3 and −7:3

**Files:**
- Modify: `tools/world/reality/acquire.py` (`noaa_lidar(..., bbox_local=None)`)

- [ ] Install the pipeline's Python stack; acquire the DEM crop and the lidar tiles covering the two
  chunks only.
- [ ] Re-export both chunks from the unpatched library; diff against the committed archive members.
  Expected: identical except `exported_at`. If not identical, stop and report.

### Task 6: Regenerate, verify, document

- [ ] Export chunks −8:3, −7:3 from the patched library; `export_pack.py pack`; regenerate their chunk
  scenes and HLOD clusters with the Godot CLIs; update digests.
- [ ] Verify: `python3 -m unittest tools/world/reality/test_reality.py`; the Godot reality suites
  (`test_key_west_reality_fresh_checkout`, `test_world_composition`); boot log clean.
- [ ] Shots from the audit positions (g1–g7) before/after; draw calls and triangles at 727 front.
- [ ] `docs/world/KEY_WEST_REALITY_LIBRARY.md` section "Documented buildings"; `CHANGELOG.md`.
- [ ] Update the audit page; commit; push `claudeflow`.

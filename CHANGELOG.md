# Changelog

Short record of notable production changes. Newest first.

The previous long-form development diary is preserved unchanged in [`archive/CHANGELOG_LEGACY.md`](archive/CHANGELOG_LEGACY.md).

## Unreleased

### Changed

- Reality HLOD v1 on the Old Town sector (chunks -6:1 -5:1 -6:2 -5:2, `config/hlod.json`): generated buildings stream in 128 m cluster cells of the same `StreamingSystem` (detail within 230 m, out past 350 m), and while their chunk is loaded an offline proxy (merged by material, roof snow folded in, no collision) stands in for each cluster that is out; `KeyWestHLODBuilder` writes a deterministic manifest (stable ids, sorted sources, bounds, source hash, counts) and rebuilds only dirty clusters; Reality dock: cluster bounds, tier preview, fresh/dirty, counts, sources, Build selected, Rebuild dirty; CI rebuilds the proxies from clean, checks the digest, partial == full, missing/duplicate/orphan ids, and walks detail → HLOD → detail. Baseline, design and numbers: `docs/technical/REALITY_HLOD.md`.
- Reality winter pass: the dynamic snow on Reality now reads a wind field baked from Reality's own buildings and land (`snow_wind_reality.png`, chosen by the world profile; the legacy bake had a Truman Annex block that does not exist); static snow caps on 13,214 roofs (ASCE 7 slope and exposure factors, windward thinner, lee cornices past the eaves), ridges on fences and wires, caps on pole tops, in a per-chunk `Winter` group (data layer `winter`, never deformed). Chunks now build identically alone or in any order (named collision shapes; the node digest sorted metadata keys by StringName address); CI checks a partial rebuild against the full one. Generator `kw_chunk_builder.11`.
- Reality edit layer: per-chunk edit records (remove, move) tagged with a data layer (`base`, `winter`, `loot:<set>`, `story:<state>`); only `base` changes the generated world, the rest travel with the chunk export; the Reality dock records them with undo. `blender-shell` writes one building's measured shell (glTF) and sizes for Blender, and a returned model registers at the shell's origin.
- Reality editor (stage 1, read-only): `key_west_reality_editor.tscn` shows the whole island as far meshes with detail chunks around the 3D editor camera, and the "Reality" dock finds buildings by address, name or id, frames them (Go to, then F) and identifies the building under the marker or the first one the camera's look ray meets; index from `key_west_reality.py editor-index`.
- Replaced the rejected Jenova experiment with the production GDExtension/godot-cpp path: portable core, real controller adapter, checksum-verified three-platform CI artifact and local installer.
- Added the Quick Access HUD, its 3D anchor rig and supporting UI shader material.
- Reality partial export (`export-editor --chunk`): a chunk now keeps the pieces of roads and areas owned by a neighbouring chunk (22 roads were missing from `-7:3`), and the island chunk list in `manifest.json` stays whole; 3 chunks re-exported alone match the full export. Editor and partial-rebuild plan: `docs/technical/REALITY_EDITOR_PLAN.md`.
- Key West Reality is playable as a separate review scene (`key_west_reality.tscn`, F6; the legacy scene stays the default): First Exit bunker set into Fort Zachary Taylor's courtyard face, every template pickup at a rule-chosen real site (same ids, counts, persistence), `PickupLedger`, and the full 727 loop (repair, fire, warm/dry, eat, sleep, save, reload) checked in the real World.
- Reality world: frozen sea (shared frozen-sea look on water polygons and on terrain below mean sea level), far view from generated per-chunk meshes streamed like the legacy far city, parking and aprons draped on the DEM (flat plates floated over sunken lots and blocked drives), courtyards open in building collision, traversal report. Generator `kw_chunk_builder.9`.
- Reality: roads, paths and parking take the terrain's snow response (they showed through the thin settled cover in patches); buildings that a mapped way runs straight through are no longer generated (owner decision; listed in `reports/buildings_removed_on_ways.json`). Generator `kw_chunk_builder.10`.
- Snowfall: the particle height field re-renders when a chunk streams in, so a roof that arrives after Henry (load inside 727) stops the snow indoors.
- Reality roads: a line now lives in every chunk it crosses (929 roads, trails and rails were drawn only while their single owning chunk was loaded) and samples the ground at least every 32 m; same-machine A/B shows no frame-time change. Generator `kw_chunk_builder.8`.
- Reality vegetation: lidar tree trunks no longer stand on roads (crown centres over streets moved to the road edge: 2,061 → 43 on a ribbon); 54,372 dead-shrub stem clumps from mapped scrub/wetland/mangrove/garden/wood areas (lidar low vegetation weighted), leaning downwind; trees and stems sit on the chunk terrain surface. Interchange re-exported, generator `kw_chunk_builder.6`. Stems ride up with the drawn snow (`snow_stems.gdshader` reads the shell's published `snow_field`), so they poke out at any snow depth.
- Reality chunks: water and canopy slabs now respect polygon holes (islands in water, clearings in canopy were filled); generator `kw_chunk_builder.5`, digest re-recorded.
- Added owner-local cross-language capability contracts under `core/contracts/`; `SaveManager` is the first production consumer, with legacy save providers adapted at the boundary and no extra Port nodes required.
- Added paired English/Russian canonical architecture contracts; full-project ECS is rejected in favor of the Godot/component + domain-core model with selective ECS/DOD only where justified.
- Added canonical player-experience and Key West design doctrine documents and linked them from the PRD / agent workflow.
- Replaced the historical long-form changelog with this concise production log.

## Changelog rule

Record outcomes, not the development session. Prefer one short bullet per meaningful change. Put implementation evidence, experiment history, benchmark dumps and long rationale in the relevant issue, PR or canonical document instead of duplicating them here.

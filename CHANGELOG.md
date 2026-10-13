# Changelog

Short record of notable production changes. Newest first.

The previous long-form development diary is preserved unchanged in [`archive/CHANGELOG_LEGACY.md`](archive/CHANGELOG_LEGACY.md).

## Unreleased

### Changed

- Key West Reality is playable as a separate review scene (`key_west_reality.tscn`, F6; the legacy scene stays the default): First Exit bunker set into Fort Zachary Taylor's courtyard face, every template pickup at a rule-chosen real site (same ids, counts, persistence), `PickupLedger`, and the full 727 loop (repair, fire, warm/dry, eat, sleep, save, reload) checked in the real World.
- Reality world: frozen sea (shared frozen-sea look on water polygons and on terrain below mean sea level), far view from generated per-chunk meshes streamed like the legacy far city, parking and aprons draped on the DEM (flat plates floated over sunken lots and blocked drives), courtyards open in building collision, traversal report. Generator `kw_chunk_builder.9`.
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

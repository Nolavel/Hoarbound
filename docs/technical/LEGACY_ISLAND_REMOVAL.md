# Legacy Key West island: removal plan

The game's main scene is `res://scenes/world/key_west/key_west_reality.tscn` since 2026-10-15. This applies to
`run/main_scene` and the title menu's `game_scene`. The owner decided it; it was proposed in #219.

The legacy island is `key_west.tscn`: `IslandTerrain` on the NOAA crop, `ChunkedCityMassing`, and the First Exit
content. It still loads. Nothing has been deleted yet. This page lists what blocks deletion, re-checked against the code
on 2026-10-15 (`git grep`, excluding `archive/`, `shots/` and docs).

## Done

1. Main scene and title menu point at Reality. `test_startup_presentation` checks it.
2. The hut cabinet fade volume and set dressing moved out of the legacy `KeyWestFirstExit` into
   `scripts/world/first_exit/shelter_cabinet.gd` (`ShelterCabinet`). The 727 shelter no longer calls legacy code. No
   behaviour change.
3. `test_key_west_first_exit` now loads the legacy scene by path instead of asserting it is the main scene.

## Blockers: Reality still uses these (move or rename, never just delete)

| Legacy piece | Reality user | Move to |
|---|---|---|
| `KeyWestStreetProps._materials`, `_palm_mesh`, `_bare_tree_mesh`, `PALM_BASE_HEIGHT_M` | `key_west_chunk_builder.gd` (palms and bare trees in every chunk) | a shared vegetation mesh helper |
| `shaders/environment/terrain/island_terrain.gdshader` | `key_west_chunk_builder.gd` (chunk terrain; paving takes snow through its paved mode) | keep; it is the terrain shader, not legacy |
| `scripts/systems/world/terrain/island_terrain.gd` | `snow_shell.gd` preloads it as `TERRAIN_SCRIPT` (it already reads `snow_ground` for Reality) | drop the preload once the legacy branch goes |
| `ChunkedCityMassing` type | `runtime_performance_policy.gd`, `dev_diorama_map.gd` (typed vars; null under Reality) | remove the legacy branch |
| `IslandTerrain` in `world/world.gd` | profiles with terrain data only; the Reality profile has none | remove with the last terrain profile |
| `data/world/key_west/snow_wind.png` | `SnowChunkCover`/`snow_shell` default when a profile has none; Reality sets its own | point the default at the Reality bake |

## Delete once the blockers are moved

| Piece | Still loaded by |
|---|---|
| `scenes/world/key_west/key_west.tscn` | tests `test_doorway_camera`, `test_key_west_first_exit`, `test_stove_world_time`; capture tools `capture_dev_diorama_map`, `capture_key_west_first_exit`, `capture_motion_matching_street`, `capture_quick_access`, `capture_sky_weather`, `capture_stylized_shadows`, `capture_tps_doorway` |
| `data/world_profiles/key_west_test.tres` | `key_west.tscn`, `test_key_west_first_exit` |
| `key_west_first_exit.tscn`, `scripts/world/key_west_first_exit.gd` | `key_west_test.tres`; CI runs `test_key_west_first_exit` |
| `ChunkedCityMassing`, `key_west_city_visuals.gd`, `key_west_street_props.gd` (after the mesh helper moves) | legacy scene, `capture_key_west*.gd`, `bake_key_west_chunk_snow.gd` |
| `IslandTerrain`, `IslandHeightmap` | legacy scene and the tests and tools above |
| `world/terrain/key_west_preview_2m_la8.*` | legacy profile, CI step, `tools/world/build_key_west_preview.sh`; `tools/world/reality/build.py` only names it in provenance |
| tools `bake_key_west_chunk_snow.gd`, `bake_key_west_far_city.py`, `build_key_west_preview.sh`, `capture_key_west.gd`, `capture_key_west_tps.gd`, `capture_first_exit.gd` | legacy island only |
| tests `test_island_terrain`, `test_city_meshes`, `test_street_props_streaming` | legacy island only |

**Tests that must move to the Reality scene first**, because they guard behaviour Reality also has:
- `test_doorway_camera`: doorway camera at a shelter door; Reality has the 727 door.
- `test_stove_world_time`: authored day/night driver and stove.

**The capture tools** either move to `key_west_reality.tscn` or retire. `capture_quick_access` arrived from `main` on
2026-10-15 and already loads the legacy scene.

## Keep

- **`data/world/key_west/city_preview.json`:** a Reality library source (`tools/world/reality/acquire.py`, `conflate.py`,
  `build.py`, `config/sources.json`, receipts).
- **`world/terrain/source/key_west/` (NOAA crop and receipt):** source provenance. CLAUDE.md keeps the rule that NOAA
  base heights are never edited in code.

## Found while checking: 10 suites that fail on `main` and are not in CI

The same 10 suites fail on current `main` with GodotPhysics and with Jolt, with identical messages:
`test_dev_diorama_map`, `test_door_draft`, `test_doorway_camera`, `test_held_fit`, `test_held_light`,
`test_passage_traversal`, `test_snow_contact_pipeline`, `test_snow_shell`, `test_street_props_streaming`,
`test_tps_camera_orbit`.

`tools/ci/run_tests.sh` runs them, but `checks.yml` runs only named suites. Several are legacy-island tests and go with
the island; the others (door draft, held items, camera orbit, passage traversal) need their own fix.

## Order (one commit each, import gate and tests green)

1. Shared vegetation mesh helper out of `KeyWestStreetProps`; regenerate nothing (same meshes), check the chunk digest.
2. `test_doorway_camera` and `test_stove_world_time` on the Reality scene (727 door and stove).
3. Capture tools to Reality or retired.
4. Remove the legacy branches in `snow_shell`, `runtime_performance_policy`, `dev_diorama_map`, `world.gd`.
5. Delete the legacy scene, profile, First Exit content, city scripts, `IslandTerrain`, the preview crop and the
   legacy-only tests and tools; CI drops `test_key_west_first_exit` and the preview crop step.
6. Graciosa (separate): a small fixture for `test_streaming`, then `StreamingSystem.DEFAULT_WORLD_DATA`, then
   `archive/graciosa`.

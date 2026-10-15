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
4. Palm and bare-tree meshes moved to the shared `WinterTreeMeshes`; the Reality chunk builder no longer uses
   `KeyWestStreetProps` (chunk digests unchanged).
5. `test_stove_world_time` and `test_doorway_camera` run on the Reality scene (727 stove and door).

## Blockers: Reality still uses these (move or rename, never just delete)

| Legacy piece | Reality user | Move to |
|---|---|---|
| `shaders/environment/terrain/island_terrain.gdshader` | `key_west_chunk_builder.gd` (chunk terrain; paving takes snow through its paved mode) | keep; it is the terrain shader, not legacy |
| `scripts/systems/world/terrain/island_terrain.gd` | `snow_shell.gd` preloads it as `TERRAIN_SCRIPT` (it already reads `snow_ground` for Reality) | drop the preload once the legacy branch goes |
| `ChunkedCityMassing` type | `runtime_performance_policy.gd`, `dev_diorama_map.gd` (typed vars; null under Reality) | remove the legacy branch |
| `IslandTerrain` in `world/world.gd` | profiles with terrain data only; the Reality profile has none | remove with the last terrain profile |
| `data/world/key_west/snow_wind.png` | `SnowChunkCover`/`snow_shell` default when a profile has none; Reality sets its own | point the default at the Reality bake |

## Delete once the blockers are moved

| Piece | Still loaded by |
|---|---|
| `scenes/world/key_west/key_west.tscn` | test `test_key_west_first_exit`; capture tools `capture_dev_diorama_map`, `capture_key_west_first_exit`, `capture_motion_matching_street`, `capture_quick_access`, `capture_sky_weather`, `capture_stylized_shadows`, `capture_tps_doorway` |
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

## The 10 suites that failed outside CI (2026-10-15)

They had failed since the start of this repository's history; Jenova once forced every Godot exit code to 0. Eight now
pass:

| Suite | Cause | Fix |
|---|---|---|
| `test_door_draft` | drove the hinge transform, not the door's angle state | test sets `current_angle_rad` |
| `test_held_fit`, `test_held_light` | pinned the pre-"flare pass 2" sideways pose | authored upright fit is the reference (render-checked) |
| `test_passage_traversal` | **game bug:** an authored passage outlived its freed node | the component drops it |
| `test_dev_diorama_map` | **game bug:** map camera moved in `_process` under physics interpolation | interpolation off on that camera |
| `test_snow_contact_pipeline` | unnamed contact camera | named `ContactCamera` |
| `test_snow_shell` | expected 1024² packed field and `snow_shell.gd` in `world.gd` | 896², `deterministic_snow_shell.gd` |
| `test_street_props_streaming` | expected island-wide palms/trees/poles | all kinds per chunk (legacy island) |

Still failing, listed in `tools/ci/known_failing_suites.txt` with the reason:
- `test_doorway_camera`: doorway camera tuning; it moves to the 727 door with this plan.
- `test_tps_camera_orbit`: improved 3 → 2 failed checks by a recompose fix; the rest is boom smoothing near the fade
  end.

`.github/workflows/suites.yml` now runs every suite on every push, report-only; `checks` stays the gate on `main`.

## Order (one commit each, import gate and tests green)

1. Shared vegetation mesh helper out of `KeyWestStreetProps`; regenerate nothing (same meshes), check the chunk digest.
2. `test_doorway_camera` and `test_stove_world_time` on the Reality scene (727 door and stove).
3. Capture tools to Reality or retired.
4. Remove the legacy branches in `snow_shell`, `runtime_performance_policy`, `dev_diorama_map`, `world.gd`.
5. Delete the legacy scene, profile, First Exit content, city scripts, `IslandTerrain`, the preview crop and the
   legacy-only tests and tools; CI drops `test_key_west_first_exit` and the preview crop step.
6. Graciosa (separate): a small fixture for `test_streaming`, then `StreamingSystem.DEFAULT_WORLD_DATA`, then
   `archive/graciosa`.

# Legacy Key West island: removal plan

The game's main scene is `res://scenes/world/key_west/key_west_reality.tscn` since 2026-10-15. This applies to
`run/main_scene` and the title menu's `game_scene`. The owner decided it; it was proposed in #219.

The legacy island was `key_west.tscn`: `IslandTerrain` on the NOAA preview crop, `ChunkedCityMassing`, and the
First Exit content. **The owner approved deletion and it was removed on 2026-10-15.** This page records what went,
what stays, and why.

## Done

1. Main scene and title menu point at Reality. `test_startup_presentation` checks it.
2. The hut cabinet fade volume and set dressing moved out of the legacy `KeyWestFirstExit` into
   `scripts/world/first_exit/shelter_cabinet.gd` (`ShelterCabinet`). The 727 shelter no longer calls legacy code. No
   behaviour change.
3. `test_key_west_first_exit` now loads the legacy scene by path instead of asserting it is the main scene.
4. Palm and bare-tree meshes moved to the shared `WinterTreeMeshes`; the Reality chunk builder no longer uses
   `KeyWestStreetProps` (chunk digests unchanged).
5. `test_stove_world_time` and `test_doorway_camera` run on the Reality scene (727 stove and door).
6. Five capture tools load the Reality scene: `sky_weather`, `dev_diorama_map`, `tps_doorway`,
   `motion_matching_street`, `stylized_shadows`. `tps_doorway` takes the way in from the door's own axis: the 727
   door sits in a side wall, and the line from the zone centre missed the opening by about 64 degrees.

## Removed (2026-10-15)

- Scenes and profile: `scenes/world/key_west/key_west.tscn`, `key_west_first_exit.tscn`,
  `data/world_profiles/key_west_test.tres`, `scripts/world/key_west_first_exit.gd`.
- Legacy city: `ChunkedCityMassing`, `KeyWestCityVisuals`, `KeyWestStreetProps`, `data/world/key_west/far_city/`,
  `data/world/key_west/snow_chunk/`.
- NOAA preview crop `world/terrain/key_west_preview_2m_la8.*` (the NOAA sources stay).
- Tools: `bake_key_west_chunk_snow.gd`, `bake_key_west_far_city.py`, `build_key_west_preview.sh`,
  `capture_key_west.gd`, `capture_key_west_tps.gd`, `capture_key_west_first_exit.gd`.
- Tests: `test_key_west_first_exit`, `test_city_meshes`, `test_street_props_streaming`.
- Legacy branches (step 4): `runtime_performance_policy` loses the legacy city residency and its streaming margin
  (both ran only when `KeyWestCity` existed, never under Reality); `dev_diorama_map` takes labels only from the Reality
  index; `snow_shell` finds snow obstacles only through the `snow_obstacles` group (Reality ground).
- CI: the `key-west-preview` job keeps only its Reality captures (`[painterly-wash-preview]`, `[stylized-shadows]`,
  `[sky-weather-preview]`); the `[key-west-preview]`, `[key-west-tps]` and `[key-west-first-exit]` tags and the preview
  crop build are gone.
- Ported instead of removed: `capture_quick_access` (Codex) loads the Reality scene and waits for the street chunk;
  `test_world_profiles` checks the Reality profile; `test_stylized_shadows` checks the Reality building and tree
  materials; `test_island_terrain` keeps its Graciosa checks without the Key West crop step.

## Kept on purpose

- **`IslandTerrain` and `IslandHeightmap`:** the Graciosa profile, `tools/world/build_first_exit_blockout.gd` (it
  generates the hut template the 727 shelter uses) and test fixtures use them. They go with Graciosa (step 6).
  `world.gd` and `snow_shell` keep their `IslandTerrain` paths for the same reason.
- **`island_terrain.gdshader`:** the Reality chunk terrain shader (paved mode).
- **`data/world/key_west/city_preview.json`, `visual_enrichment.json`, `ocean_connected_mask.png`:** Reality Library
  sources (`tools/world/reality/acquire.py`) and the snow wind bake.
- **`data/world/key_west/snow_wind.png`:** the default wind field of `snow_shell`/`SnowChunkCover` and its tests;
  Reality sets `snow_wind_reality.png` in its profile.
- **`world/terrain/source/key_west/` (NOAA crop and receipt):** source provenance; its receipt still lists the removed
  derived crop, as a record. NOAA base heights are never edited in code.
- `tools/world/reality/build.py` names the removed crop in one provenance string; changing it would change the
  library outputs, so it stays.

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

## Order (done)

1. Shared vegetation mesh helper out of `KeyWestStreetProps`; chunk digest unchanged.
2. `test_doorway_camera` and `test_stove_world_time` on the Reality scene.
3. Capture tools to Reality.
4. and 5. Legacy branches and legacy files removed in one change, after the owner's approval.
6. Still open, separate: Graciosa (a small fixture for `test_streaming`, then `StreamingSystem.DEFAULT_WORLD_DATA`,
   then `archive/graciosa` and `IslandTerrain`).

# Runtime construction audit — what should become an authored scene

Date: 2026-11-13. Base: main `63cbc9f8`. Status: **wall thermometer and stove done**; the rest of the order below is open.

## Why

94 scripts under `scripts/` call `add_child`, and about 577 node, mesh and material
objects are built with `.new()` in code. Anything built in code cannot be seen,
moved or tuned in the editor: the owner has to ask an agent to change a number.
Godot's own guidance is "scenes for composition, scripts for behaviour".

## Method

For each script, two counts were taken:
- `.new()` of visual or physics classes, such as `MeshInstance3D`, `BoxMesh` and `OmniLight3D`;
- `add_child` calls.

Each heavy script was then read to decide whether it builds:
- **content** — a fixed look or layout someone would want to author, or
- **procedure** — geometry or rig state that depends on data at runtime.

`tscn` = how many scenes use the script today.

## A. Move to authored scenes (content built in code)

| # | Script | `.new()` | Builds | tscn | Value |
|---|---|---|---|---|---|
| 1 | `world/key_west_727_shelter.gd` | 13 | 727 furniture, searchables, thermometer, stove pipe, spawn — placed from a plan in code | 1 | **Highest**: the game's main location |
| 2 | `environment/interactive/furniture_kit.gd` | 11 | cabinets and drawers from boxes, 42 hard-coded vectors | 0 | High: every interior uses it |
| 3 | `environment/stove/stove_visual.gd` (+ `stove_warmer`, `stove_log_visual`, `lighter_flame`) | 12+11+6+6 | stove body, door hinge, glow light, steam particles, flame | 1 | High: lights and particles are painful to tune in code |
| 4 | `actors/player/henry/held/held_flare.gd` (+ `held_searchlight`) | 16+7 | tube, light, fog volume, spark particles | 1/0 | High: the same lights-and-particles issue |
| 5 | `environment/thermometer/wall_thermometer.gd` | 13 | plate, bulb, scale labels | 0 | Medium; small, so the ideal **pilot** |
| 6 | `environment/interactive/item_pickup.gd` + `survival_item_visual.gd` | 30+24 | placeholder props built from primitives (crate, tube, glove, tin) | 2/0 | Medium: each item should point at its own visual scene or GLB, with the code as a fallback |
| 7 | `environment/interactive/meal_table.gd` | 11 | tins, parcels, table props | 1 | Low-medium |
| 8 | UI: `ui/menu/camera_settings_panel.gd`, `pause_menu`, `key_hints_panel`, `player_hub_panel`, `vital_cluster` | 18, 6, 8, 7, 9 | Control layouts | 0–1 | Medium: anchors and theme would become editable |

## B. Keep in code (the construction is the procedure)

| Script | Why it stays |
|---|---|
| `world/snow/snow_shell.gd` | Generated clipmap meshes; they depend on runtime data. |
| `items/backpack/backpack_model.gd` | Pocket geometry from `SurfaceTool`, pendulums and straps. It is pinned by `BACKPACK_RIG.md` and `test_backpack_rig.gd`. Only the static shell could move, and the risk is not worth it now. |
| `Controllers/HenryUALAnimation.gd` | The modifier and IK stack. The animation skill forbids reshaping the production graph without a separate task. |
| `ui/debug/dev_diorama_map.gd`, `experimental/*`, `embodied_interaction_lab.gd` | Debug tools and labs; their content is not authored. |
| `items/backpack/carabiner.gd`, physics pendulums | Simulation state, not content. |

## How to move one safely

1. **Parity first.** Before the move, dump a snapshot: node path, type and global transform for every child, and the mesh size and material colour of every visual. A test then compares the new scene with that snapshot.
2. **Split content from behaviour.**
   - The scene holds the nodes, transforms, meshes, materials, lights and particles.
   - The script keeps state, signals and animation.
   - The script gets its nodes through `@onready` or `@export`, never by building them.
3. **Keep the public API and capability contracts unchanged.** Consumers must not notice the move.
4. **One script per PR**, with a render of the affected scene (CLAUDE.md, definition of done).
5. **Ratchet.** Add a CI count of visual `.new()` calls per file, like the dynamic-dispatch ratchet. Moved files must not grow back, and new code must not add any.

## Tools (in place)

- `tools/scene_parity/scene_parity.gd` (`SceneParity`). It snapshots what a tree draws, independent of node names:
  - visual type and transform;
  - mesh and material properties;
  - Label3D text and font settings.

  `snapshot.gd` writes one, from a scene or from a script's code-built tree.
- `tests/systems/test_authored_scene_parity.gd` compares each moved scene with the snapshot taken from the old code. Add a line to `CASES` for every move.
- `tools/ci/check_runtime_construction.py` and `runtime_construction_baseline.txt` form the ratchet, which runs in `checks`:
  - visual `.new()` calls per file may only go down;
  - a new file may not start building content in code;
  - lines marked `procedural` are the category B scripts.

## Pilot: wall thermometer (done)

1. Snapshotted the code-built thermometer (36 visuals) into `tests/fixtures/scene_parity/wall_thermometer.json`.
2. Packed the same tree, with readable node names, into `scenes/environment/thermometer/wall_thermometer.tscn`:
   - `Mount`: nail and wire;
   - `Board`, `Tube`, `Bulb`, `Column`;
   - `Scale`: ticks and figures;
   - `ReadingPlate`, `Reading`;
   - markers `ScaleBottom` and `ScaleTop`. The column travels between them, so moving them in the editor re-scales it.
3. `wall_thermometer.gd` lost its 13 constructions and about 145 lines. It keeps only the behaviour (column, reading, fade). `WallThermometer.instantiate()` replaces `new()` in the 727 shelter and the test.
4. Evidence:
   - the parity test passes, and fails if one tick moves 1 cm;
   - `test_wall_thermometer` passes;
   - `capture_thermometer.gd` was rendered in the real 727 before and after. The frames differ only in the FPS overlay and Henry's idle pose; the thermometer pixels are identical.

## Stove (done)

- `scenes/environment/stove/stove_log.tscn`:
  - `Body` holds `Wood`, `Flame0`–`Flame2` and `Smoke`;
  - the generated wood and flame meshes are saved as `assets/models/stove/stove_log_{wood,flame}.res`, so a modelled log can replace them;
  - the shader materials are local to each log.
- `scenes/environment/stove/stove_visual.tscn`:
  - legs, ash pan, vents, firebox walls, door frame and cooktop;
  - cooking ring, ember bed, `Coals` (12 coals);
  - `FuelLog0`–`FuelLog3` as instances of the log scene;
  - the `Glow` light;
  - `DoorHinge` with the door, bars and knob;
  - `FlueCollar` and `FluePipe`.

  The ember material and the pipe mesh are local to each stove.
- **What stays in code** (6 constructions, in the ratchet baseline):
  - the flue length the 727 sets, applied in `_ready` to the authored pipe;
  - the room light placed on the HeatSource's `flame_light`;
  - the door control, which needs the HeatSource's Feed;
  - the tinder, from `SurvivalItemVisual`. It moves with the item visuals.
- `first_exit_blockout.tscn` and its builder instance the stove scene. The builder now keeps an instanced scene's insides when it sets owners.
- **Evidence:**
  - parity fixtures for the log and for the stove inside the shelter (72 visuals: logs, coals, door, tinder);
  - they fail if one coal moves 1 cm;
  - all stove, shelter and 727 suites pass;
  - `capture_stove.gd` before/after.

## Suggested order

1. ~~`wall_thermometer`~~ — done, see above.
2. ~~`stove_visual` together with the stove satellites~~ — done (stove_warmer and lighter_flame remain for a later pass).
3. `held_flare`.
4. `furniture_kit`.
5. `key_west_727_shelter` — 727 becomes an editable interior scene. This is the biggest gain.
6. `item_pickup` visuals and UI panels, opportunistically.

Steps 1–3 are about one evening each. Step 5 is the largest and should follow the furniture move.

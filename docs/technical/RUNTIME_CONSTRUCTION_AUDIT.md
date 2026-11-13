# Runtime construction audit — what should become an authored scene

Date: 2026-11-13. Base: main `63cbc9f8`. Status: **analysis, no code moved yet.**

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

## Suggested order

1. `wall_thermometer` — the pilot, to prove the parity test.
2. `stove_visual` together with the stove satellites.
3. `held_flare`.
4. `furniture_kit`.
5. `key_west_727_shelter` — 727 becomes an editable interior scene. This is the biggest gain.
6. `item_pickup` visuals and UI panels, opportunistically.

Steps 1–3 are about one evening each. Step 5 is the largest and should follow the furniture move.

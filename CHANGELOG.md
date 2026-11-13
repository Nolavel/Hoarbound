# Changelog

Short record of notable production changes. Newest first.

The previous long-form development diary is preserved unchanged in [`archive/CHANGELOG_LEGACY.md`](archive/CHANGELOG_LEGACY.md).

## Unreleased

### Changed (LOW tier)

- On LOW, streamed vegetation (the `Vegetation` chunk part, including parts streamed in later) casts no shadow, and the sun's shadow is drawn in one split instead of two. Each split re-draws the scene, and the shadow pass was about 1.2M of 3.05M primitives a frame. MEDIUM and HIGH restore the authored shadow mode and the vegetation shadows. `test_graphics_quality_tiers` fails on the old code. Measured on a LOW Duval Street frame (lavapipe): primitives 3.05M -> 2.15M (-30 %), draw calls 724 -> 586 (-19 %). The CPU rasteriser's frame time barely moves (1178 -> 1137 ms) because it is pixel-bound; the FPS gain on an integrated GPU still needs the owner's HD 620.

### Changed

- Hints where testers got stuck:
  - A held item's hint ends with `X · Put away   G · Drop`.
  - The laid bedroll's prompt reads "Roll up the bedroll (F or C)".
  - The empty tin's hint no longer sends the player to the Hub.
  - The road flare's Quick Access readouts were hardcoded English and are now localised (`FLARE_*` keys).

### Verified

- LOW tier cost on Duval Street at 1920x1080 (`probe_low_tier_cost.gd`, lavapipe, relative): 1165 ms as is, 1234 ms without volumetric fog (noise), 1137 ms without sun shadows (-2 %). Neither effect is the LOW bottleneck. The owner's HD 620 log shows 4-5M primitives and up to 1500 draw calls a frame. The probe now counts the primitives each world group draws. A LOW frame draws 3.05M primitives and 724 draw calls. Hiding a group frees: streamed chunks 1.60M (vegetation 1.11M, buildings 0.84M, terrain 0.51M); the sun's shadow pass about 1.20M; Henry with his gear 0.65M; the 727 profile content 0.53M. The groups overlap through the shadow pass.
- #209/#288: `quit(1)` now exits 1 in this project, the #209 repro included. That issue was filed on 2026-10-09; the vendored Jenova GDExtension, its prime suspect, was removed on 2026-10-14 (`16e55a8f`).
- `run_tests.sh` now fails a suite that exits 0 without any pass line, and ends every suite with `HB_SUITE_RESULT: PASS|FAIL|KNOWN_FAIL <suite>`. `test_first_exit_entry_traversal` now prints its PASS. Checked with throwaway suites: quit(1) fails, a silent exit 0 fails, an explicit PASS passes.
- Continue after a relaunch (#42 Gate A), checked across two processes:
  - **Run 1:** `loop_key_west_727.gd --stop-after-sleep` on the exported pack plays the 727 loop to the sleep save and writes `expected.json`.
  - **Run 2:** `tools/runtime/continue_after_relaunch.tscn` runs in a new process. It opens the real title menu, Continue is enabled, presses it, and compares the world: boards, fire, taken pickups, kit counts, and Henry inside the 727.
  - **Result:** PASS. A tampered expectation fails with exit code 1.
  - The snapshot moved to `tools/runtime/shelter_snapshot.gd`, shared with the in-process loop, which still passes.
- Lighter from a coat pocket to the hand works, alone and straight after a held flare. The earlier audit's failure came from the harness order, not the game.

### Changed (0.312c)

- Snow in exported builds: `SnowField.load_wind_field()` checked the imported PNG with `FileAccess.file_exists`. An export ships only the `.ctex`, so it returned false, `use_baked_baseline` stayed off, and the snow drew its moving-window fallback, while the editor (with the source PNG) worked. It now uses `ResourceLoader.exists`. `tools/ci/check_export_snow.gd` runs on the exported pack in `release-smoke`. Found by Codex; confirmed with `--main-pack` from an empty directory (0.312b pack: loaded=false; fixed pack: loaded=true). Owner hardware confirmation is pending.
- Fixed the missing .NET assemblies in the release zips (0.312 and 0.312b). The workflow exported `VERSION=0.312b` as an environment variable, MSBuild read it as the project's `Version`, and NuGet rejected it, so `dotnet publish` inside the Godot export failed. The variables are now `HB_VERSION`/`HB_TITLE`. Release notes come from `tools/ci/release/RELEASE_NOTES.md`, with known limitations listed.
- Graphics quality defaults to LOW again when no settings file exists. On the owner's HD 620, HIGH ran at 3-5 FPS against 9-11 on LOW; MEDIUM and HIGH stay selectable.
- The unverified snow-glint handoff experiment is reverted out of the release path. The snow surface movement on Intel HD 620 remains OPEN.
- `release-smoke` takes a `publish` input: false builds, checks and uploads the zips as a workflow artifact without a release. The export logs' .NET lines are printed.

### Fixed (WIP, claudeflow)

- `release-smoke` fails when the .NET assemblies folder is missing. The 0.312b zips shipped without `data_Hoarbound_*`, and the mono runtime refused to start.
- Snow ice glints fade out on the near clipmap before the 6.25 m handoff, and the chunk cover no longer draws them. The owner's Intel HD 620 frames showed a band of streaked glints starting at the square handoff. Not yet verified on that GPU.
- Snow regression evidence on the current code (lavapipe): the October witness (`capture_snow_surface.gd` + `analyze_snow_surface.py`) gives 0 px over 2 mm in every band (10.1M before a2b7f37f), max 0.06 mm over a 10 m walk. The near lattice matches the streamed ground at a real 727 start at 4 FPS (`probe_snow_lattice.gd`, 0/441 stale). The owner's Intel HD 620 still shows the defect.
- Snow regression probes (`tools/runtime/probe_snow_height_walk.gd`, `probe_snow_packed_walk.gd`; fixed points in `probe_snow_window_lag.gd`): the CPU snow field stays still at fixed points (0.00 cm over 7 window moves). The GPU packed field is under investigation.

### Changed

- Smoke test 0.312b (owner, 2026-11-12):
  - Graphics quality defaults to HIGH when no settings file exists (it was LOW).
  - An item dropped on the Tab hand card is now drawn into Henry's hand when Tab closes. Pocket items go through Quick Access, pack items are presented from storage. The card only marked the selection before.
  - X (`put_away_held`) empties Henry's hands back into storage.
  - C beside a laid bedroll rolls it up.
  - Exported builds write `logs/hoarbound_<time>.log` beside the executable (`BuildLog` autoload, last five kept). The log records the version, OS, GPU and driver.

### Fixed

- Bedroll placement judged height from Henry's capsule centre, a metre above his soles: the 727 floor was always refused and the stove top accepted. It now measures from the soles with a 0.3 m step; the real-727 probe (`tools/runtime/probe_727_bedroll.gd`) lays it on the floor, refuses the stove, opens the sleep dialog and rolls it up.
- Smoke-test tooling: `tools/runtime/audit_727_pickups.gd` takes every 727 pickup by a real F tap and draws every Quick Access pocket; `tools/runtime/probe_snow_window_lag.gd` walks Duval Street at a given `--fixed-fps` and logs the snow window rim and foot plants per metre.
- Holding F on an item that is never shown in a hand (road flare, hammer) refused with a cross; it now takes the item to its pocket, as a tap does.

### Added

- `release-smoke` workflow (manual): exports Windows and Linux on CI and publishes a pre-release `v0.312` "Hoarbound — Smoke Test November 0.312" with zips and SHA256SUMS. Version 0.312 set in `project.godot` and the Windows file metadata.

### Fixed

- Stone scatter no longer reads a freed pickup as a typed object during refresh; collected IDs stay collected and untaken stones can return after eviction. Added lifecycle regression to the required gate.
- Hub carried-item rims reuse their material, focus masks track live instance IDs, and disposable item probes clear overrides before freeing. Empty readout/hand/stove requests return early; unknown nonempty catalog IDs still warn.

### Added

- External xk stream research is indexed under `docs/research/xk/` for optional game-design critique, with provenance, relevance questions, and links from `README.md`, `AGENTS.md`, and `CLAUDE.md`; it is not a source of product requirements.
- `StepStairs` (`scripts/world/props/step_stairs.gd`): a flight of stairs Henry can walk. Visible steps are generated over one wedge collider, because `CharacterBody3D` has no step-up and a 0.17 m box step stops him. Set step count, riser, tread and width; `build_steps = false` keeps only the collider under an authored mesh. New `test_step_stairs`.

### Changed

- First Exit A, Gate A (#42): a repeatable Windows Desktop x86_64 export (`export_presets.cfg`, with a Linux preset beside it for running the same pack here). The packs leave out `tests/`, `docs/`, `archive/`, editor add-ons and every `tools/` folder but `tools/StatsDisplay`, which the world preloads. The MCP game helper is stripped by its own export plugin.
  - Fixed: an exported game started without the 727's interior, spawn point, First Exit sites and compass landmarks. `data/world/key_west/reality` carries a `.gdignore`, so no export ever saw the JSON the game reads there. `addons/reality_editor/reality_export_plugin.gd` ships exactly that runtime subset (9 files).
  - Exported builds open on the title menu (`run/main_scene.template`): New game starts at the 727, Continue loads the last sleep. Before, a relaunched build always started a new game and Continue was only reachable through Esc, Quit to title. The editor's F5 still opens the world directly.
  - Verified on the exported pack itself (run with `--main-pack`): Henry spawns 4.6 m from the 727 door, and `loop_key_west_727.gd` passes every step through to reload.

- Owner's play notes 2026-11-12:
  - The 727's front door swings outwards, as public buildings' entrances do. From inside Henry presses F and walks out pushing the leaf; before, it opened inwards and walking out from the lobby he pushed it shut. `test_doorway_camera`'s half-open scenario now pushes the leaf on the way out.
  - Henry's camera fade no longer shows a 4x4 grid: the dissolve uses interleaved gradient noise (Jimenez 2014), pixel-fine with no repeating pattern. A solid cut-away was tried and rejected: it opened his layered clothes and the inside of his head.
  - Fixed: Henry's hands twitched while walking with the pack on. `ArmStrapClearance` rebuilt the arm's turn axis from the single deepest strap point every frame, and as that point jumped the axis swung about 45 degrees a frame (right hand: 20 velocity flips in 6 s). The push is now the depth-weighted sum over every point met and the axis eases at 6/s; the hands move as smoothly as the walk clip. New `test_arm_strap_smooth`.

- TPS camera after the owner's play test of the direct rig (2026-11-11):
  - Henry stands left of the centre in every space: the shoulder offset now follows the boom's length (0.4 m per metre) instead of being squeezed toward the centre when pressed. His chest holds about 0.35 of a 16:9 frame's width in the open, a 1.5 m corridor and a 3 m room. New `test_tps_camera_framing`.
  - He turns see-through only with the camera jammed against him. The fade is measured from 0.36 m to his body's axis instead of from 0.7 m to his eyes: beside him the camera sees past him and he stays solid.
  - Less pumping against walls: no lens widening by boom length, a shortened boom holds 0.35 s and eases out over 0.6 s, the shoulder's sideways room is read ahead so a jamb closes it in before it cuts it, and lead sweeps start 0.1 m off a wall Henry walks at (they started in contact with it and read no room).
  - Jammed against Henry, the camera now removes what of him stands at the lens instead of an 80 % ghost: the render showed the pack's insides through it. Meshes without the dither shader go by their distance to the camera. Close in, the camera rides at his eye line from 1 m of boom. Renders in `docs/runtime_previews/tps_camera/`.
  - After Codex's review of `86fe2b71` (2026-11-12): `TpsInteractionFraming` is archived with the guided rig. It widened the shoulder or crossed to the other one by itself when a mechanism under the crosshair stood behind Henry; in door D1 it fired on hundreds of frames with no key pressed.
  - The gear on Henry's body without the dither shader (pack, straps, what hangs on it) now goes together, all or none, instead of each mesh blending by its own distance: no half-transparent pack, no straps left hanging.
  - Only contact snaps the boom; the margin off the wall is eased to. Largest frame step in door D1 is 0.27 m and `test_doorway_camera` is back at the 0.3 m limit of #240. A released boom eases out over 0.4 s (was 0.6 s: 95 % took over two seconds).
  - `test_tps_camera_framing` also measures the gear he really carries, not only a chest point: in a 1.5 m corridor its right edge is at 0.56 of the frame, past the centre. Not fixed here.
  - Measured: one camera frame costs 1.0 ms mean, 2.5 ms worst turning in the real 727 headless; 0.8 ms of it is the boom's sphere sweeps (centre, ten feelers, leads). Sweeping half the feelers a frame cut it to 0.7 ms but brought a 0.63 m step back in the door, so it was not kept.
  - Framing study for the owner's rule (left third in rooms, close over the shoulder in tight places, head and shoulder always readable): `tools/runtime/compare_camera_framing.gd` saves frames and shot-quality numbers per preset in the real 727. New `TpsCamera` exports `direct_wall_clearance`, `direct_tight_fov_deg` and `gear_hide_distance`, off by default until the owner chooses.
  - Owner's call after the framing study: the boom in the open is 2.2 m (was 3.0) so Henry reads larger, as in the reference; nothing else changed with it. Indoors the 727 frame barely moves (0.05..0.15 m closer).
  - `trace_camera_route.gd -- <out> route=continuous [video]`: one unbroken route through the 727 (corridor, a full mouse turn, the doorway, the stove room, out of the front door into the open) that also times the camera's own CPU (mean 0.84 ms, worst 2.7 ms headless). Found on it: the front door opens inwards and Henry walking out from the lobby pushes it shut.
  - Fixed: right mouse with a stone in hand could throw the camera metres away. The aim spring's explicit step is unstable over a frame longer than 73 ms; it is now stepped at 120 Hz. New `test_tps_camera_hitch`.
  - The guided rig (lift, swing, auto-look, doorway framing, auto shoulder swap, recompose, composition, body guard) is moved whole to `archive/tps_camera_guided/` with its tests and design record; `TpsCamera` is the direct rig only (1143 -> 675 lines). `test_passage_traversal` now guards `PassageTraversalComponent` alone; `test_doorway_camera` is the direct suite at fixed 60 fps.

- TPS camera: a direct rig is the default (`TpsCamera.direct_rig`). The owner found the camera awkward in narrow spaces; a trace in the 727 corridor and restroom showed it rising over Henry to look down, standing inside his coat, and holding him across the frame.
  - The camera always stands behind the view and only the mouse turns the view. No lift over the shoulder, no swing round Henry, no auto-look, no recentre behind a walking Henry (owner's call), no view tilt.
  - Walls only shorten the boom. The shoulder squeezes and the lens widens up to 8° as the boom is pressed. A close Henry turns see-through (to 80 % at most) instead of the camera climbing. The mouse is never slowed near him.
  - A doorway no longer takes the controls (`PassageTraversalComponent.carry_through` is off): released keys stop Henry and sideways keys steer. He is still eased onto the centre line while the player pushes through.
  - Doorways on the direct rig: the camera no longer jumps when a jamb or lintel cuts its boom (largest one-frame step 1.97 m -> 0.31 m in door D1 of the 727, the rest being the start of an ease under a sudden 150 deg/s swing). Its feelers are now sphere sweeps of the boom's own radius, and two sweeps 0.3 and 0.5 s ahead, by the shoulder's travel and the view's turn rate, warn of what Henry walks or turns the boom into. New `test_doorway_camera_direct`.
  - Fixed in the shared boom blend: the clamp to the centre sweep and the ease to the feelers were exclusive branches, so the feelers' warning was never applied to a boom resting on the centre sweep.
  - Pressed, the camera comes up from the shoulder joints to Henry's eye line so his head stays in frame; with his back on a wall it stays 0.2 m from his eyes instead of standing in his head.
  - Pillars, trunks and furniture 0.25 m thick or more now turn the direct camera in front of them, eased by the feelers, instead of turning see-through (`direct_thin_extent`); thinner posts still fade. New `test_tps_camera_pillar`.
  - New key V (`camera_behind`): turns the camera behind Henry; mouse motion cancels the turn. It is the only recentre on the direct rig. New `test_tps_camera_behind`.
  - Gamepad look: the right stick turns the view through `StickLook` (radial dead zone, squared response, a ramp of extra turn speed at the rim); R3 is `camera_behind`. Walking and other actions are not on the pad yet. New `test_stick_look`.
  - Settings: stick sensitivity, field of view (-10..+15°), camera distance (75..130 %) and a left-shoulder default join mouse sensitivity and invert Y; the panel grew to fit them. `CameraUserSettings` is table-driven and keeps keys it is not asked to write. New `test_camera_user_settings`.
  - Henry no longer crawls 30 % see-through: the direct rig's fade now starts at 0.7 m from his eyes, under the 0.75 m it settles at in a crawl space. New `test_tps_camera_direct_spaces` walks the real Henry crouched through a crawl space and up a stair ramp.
  - The old guided rig stays behind `direct_rig = false` until this one is accepted in play; its three suites switch it on explicitly. New `test_tps_camera_direct` guards the direct rig.
  - The stove's work frame keeps its late fade (the early fade dimmed Henry there; `test_stove_ritual` caught it).

- Every window now draws the baked millimetre frost, and a pane at full coverage is frosted right across.
  - **Generated buildings.** `frosted_window.gdshader` draws the same frost as the landmark glass (no thaw: these houses stay cold). Its old 16 cm fern pattern is no longer drawn anywhere.
  - **Full coverage.** From 80 % to 100 % coverage the middle of a pane packs with two more layers of crystals and a full coat of film. Before, a pane at 100 % kept a see-through middle and looked almost like one at 70 %.
  - **Shared code and textures.** The frost lives in `frost_tiles.gdshaderinc`. Its two tiles are project shader globals (`window_frost_edge`, `window_frost_field`), so the baked city scenes pick them up unbound and were not regenerated.
  - `capture_window_frost_shapes.gd` takes a coverage and `opaque`; a new preview shows 70 %, 100 %, 100 % thawing, and the opaque panes. `test_window_frost` checks the globals and both shaders.
  - GPU cost in the streamed city is not measured: each opaque pane now does 7 texture reads in place of the procedural fern loops.

- The see-through landmark glass (`frosted_glass.gdshader`, the 727 windows) has new frost and a new thaw. Its rule is unchanged: 60-80 % frost in the cold, a warmed room clears.
  - **Any pane size.** Frost comes from two baked tiles at 1 mm per pixel (`assets/environment/windows/`, from `tools/textures/bake_window_frost_sheet.py`), laid in metres: a strip of fern feathers along each edge and a field of small crystals across the pane. A pane of any size or proportion carries crystals of true size.
  - **Thaw.** Each texel thaws by its own need; it soaks to glassy ice, breaks into islands and clears. The wet pane mists with beads and sheds runs 1-2 mm wide.
  - **Ice plates.** Thick soaked frost by the sill comes away as shards that slide down the pane, rest at its bottom edge and melt. Nothing is drawn on the sill itself.
  - **No screen read**, so snowfall behind the glass stays visible; the view through frost is not blurred.
  - The opaque panes of generated buildings (`frosted_window.gdshader`) are unchanged.
  - The 727 probe now scrubs a copy of the game's glass; the test-only natural shader and its sheet are removed. New `tools/runtime/capture_window_frost_shapes.gd` renders six pane sizes.
  - `test_window_frost` checks both tiles are bound with mipmaps (it fails with a tile removed). GPU cost on real hardware is not measured.

- 727 window thaw probe, second pass after the owner's review against a photo reference. The natural thaw no longer draws `frost_pattern` ferns (16 cm cells: too large for the 2.0 x 1.1 m pane, with an angular base).
  - Frost is a baked sheet at 1 mm per pixel (`frost_sheet_727.png`, from `tools/textures/bake_window_frost_sheet.py`): barbed feathers 2-28 cm long grown from the frame, along scratches and from free specks, with fine hoar. The scale follows K. Libbrecht's window-frost notes.
  - Frost depth is uneven round the pane (deep off the sill), not a frame of one width.
  - Runs are 1-2 mm wide and 5-34 cm long, most of them short; the wet pane mists with fine beads.
  - The capture tool takes `close` for a 0.55 m wide view. The preview sheet is replaced.

- The 727 FrontWindow1 thaw probe (issue #281, `tests/scenes/window_727_sdf_probe.tscn`) opens on a new test-only natural thaw shader, `natural_thaw_glass_727.gdshader`. **V** switches to the unchanged V3 sheet. Production glass and `frost_pattern.gdshaderinc` are untouched.
  - Frost scatters the view behind it: the pane blurs the screen by frost thickness. Thick frost is white, thin frost blue, soaked frost grey-green. At 0 % the whole pane is frosted.
  - Each texel thaws by its own need (warm spots, frame, height on the pane, thickness, noise). It soaks, breaks into slush islands, then clears. The upper pane leads and a band by the frame survives.
  - Beads run down wandering lanes and cut clear tracks through the frost below. Cleared glass keeps water beads that bend the view.
  - It is an authored illusion on one 0..1 value, unshaded, not yet judged under the real 727 lights.
  - Added `tools/runtime/capture_window_727_thaw.gd` (stills per thaw step), `tests/systems/test_window_727_thaw_probe.gd`, and a preview sheet in `docs/runtime_previews/window_frost/`.

- Removed three snow suites from the `snow-clipmap-preview` experiment, at the owner's request: test_snow_architecture_contract, test_snow_contact_pipeline and test_snow_surface_clipmap. They tested a snow architecture (multi-channel deformation, radial L0–L2 rings, no live contact writes) that `main` does not ship, so they were red on every branch. They were also dropped from `snow_architecture_gate.sh` and the snow job loops in `checks.yml`.

- Four suites that were red on `main` are green again.
  - test_shelter_workflow and test_quick_access still read the feedback label and readout that commit `54f88bde` moved into the gameplay UI. They now listen to `ConsumptionController.water_status_requested` and `QuickAccessComponent.readout_changed`. With the hide signal removed, test_quick_access fails.
  - test_render_layers: render layer 21 had lost its `snow_tile_experiment` name in `project.godot`, though `RenderLayers.SNOW_TILE_EXPERIMENT` still draws on it. The name is restored.
  - test_container_kinds runs at `--fixed-fps 30` in CI, as its run line says. Without it, the hangers swung on wall-clock deltas, and once a pan hung into the chest on `main`. That failure was not reproduced here (three runs passed under load), so this fix is untested against it.

- Class D dynamic dispatch is closed (§16). The ratchet baseline is 17 calls in 3 files; all of them are class A (composition-root hooks) or class B (native and lab tools).
  - `GroundSourceCapability` gives snow chunk cover the ground height and, optionally, the obstacle outlines. Key West ground and island terrain keep their legacy `get_height` / `get_snow_obstacles_in_rect` names.
  - The new `CapabilityContract.bind` turns an operation into a Callable once, so the per-vertex height loop costs no lookup per call.
  - `InteractionDataCapability` lets a scene loaded by an InteractiveArea give its name, description, colour and radius (the flashlight and the filter mask).
  - `test_capability_contract` also covers the locomotion readout, the ground source and the interaction data. It fails when `bind` returns nothing; snow chunk cover then reports that the ground is not a source.

- Class F dynamic dispatch is closed (§16). The ratchet baseline drops from 108 calls in 33 files to 21 calls in 5 files.
  - The PlayerState and SoundSystem autoloads gain `class_name PlayerStateService` and `SoundSystemService`. All 29 untyped calls to them, and to `InputSystemsService`, are now typed. The stove and timed actions set `PlayerStateService.Mode` directly instead of looking the enum up by name.
  - Body actions go through `InteractHostCapability`: animate, face, the action lock, and the new `hold` / `holding_still`. Test walkers still work, and a missing operation is skipped.
  - Henry's animation and the camera read speed, crouch and view through the new `LocomotionReadoutCapability`. Test bodies keep their legacy names, which are adapted at the boundary.
  - Other calls become typed references: foot contacts (`MotionMatchingLocomotion`), snow obstacles (`KeyWestRealityGround`), the time accelerator (`DayNightManager`) and the stove warmer prompt.
  - `QuickAccessUI._zone_item` becomes public `zone_item`, since the focus motion reads it.

- StreamingSystem and InputSystems find their participants through capabilities (`core/contracts/`). This is class D in §16. The ratchet baseline is now 108 calls in 33 files.
  - `StreamSourceCapability`: chunks, activate, deactivate, and an optional ring0. The far view and the test sources keep their legacy `*_stream_*` names, which are adapted at the boundary.
  - A source that cannot activate or deactivate is now refused whole at registration. It used to register chunks it could never load or unload.
  - `InteractClaimantCapability`: claimed, plus optional held and released. The sleep prompt and the stove keep their `on_interact_*` names.
  - `claim_interact` refuses a node that cannot take the key and keeps the current owner. Such a node used to take the key and fail on the next press.
  - The two `PlayerState` reads left in InputSystems are class F (the autoload has no `class_name`).
  - test_streaming and test_player_state cover the refusals and own-name providers. test_player_state fails with the refusal removed. Streaming, HLOD boundary, sleep prompt, fire and stove suites pass.

- InteractComponent works its host through `InteractHostCapability` (`core/contracts/`). This is class D in §16.
  - Every operation is optional (animate, attention origin and direction, face, walk to, stop, action locked). The host's legacy names are adapted at the boundary, so Henry and the test walkers are unchanged.
  - Typing the host as `Player` broke the walker stubs in test_interaction and test_pickup_affordance, so a contract was used instead.
  - `run` answers `[ok, result]`, so a missing operation is told apart from a false answer.
  - The ratchet baseline is now 121 calls in 34 files. The one call left is class F, `is_movement_blocked` on the PlayerState autoload.
  - `test_capability_contract` covers adaptation, partial hosts, mapped names and absent operations. It fails when `run` stops checking the operation.

- More class D dynamic dispatch removed (§16). The ratchet baseline is now 140 calls in 34 files.
  - The Hub hands an item to its user through `ItemUserCapability`. Six components use items (bedroll, hammer, held item, flare, snow scoop); their legacy `can_use`/`use` names are adapted at the boundary.
  - Passage traversal reads doors and narrow passages through `PassageProviderCapability`.
  - A swinging door steps only Henry (`as Player`) out of its arc; it used to ask any blocker for `move_to_position`.
  - Inventory reads the burning flare's weight from `HeldLightComponent` by type. It is the only provider, so no abstraction is added for one (§13).
  - `test_capability_contract` covers both new contracts.

- The simulation clock advances its participants through `SimulationParticipantCapability` (`core/contracts/`), as saves already do. This is class D in §16.
  - The legacy `advance_simulation` / `get_simulation_priority` names are adapted at the boundary, so weather, afflictions, snow, the held light and the bio monitor are unchanged.
  - Any provider, a C++ weather included, may publish its own names.
  - `CapabilityContract.has_operation` allows an optional operation; a missing priority defaults to 1000.
  - `test_capability_contract` covers adaptation, the default, mapped names, refusal and priority order.
  - The ratchet baseline is now 149 calls in 38 files.

- Quick Access draws, names and uses what a hand shows through `HeldDrawCapability` (`core/contracts/`). The held item, the hammer and a flare publish it beside `HeldReleaseCapability`. This is the last class E dynamic dispatch (§16).
  - `quick_access_component.gd` lost all 14 `has_method`/string `call` uses, and the ratchet baseline drops to 151 calls in 39 files.
  - The hammer answers Quick Access use explicitly with false, as it did by lacking the method.
  - The flare's burning readout asks `HeldLightComponent` by type.
  - Quick Access, flare and hand suites fail identically before and after (two known flare-hint checks).

- Containers ask any way in through one small seam, `Opener`: `is_open`, `is_swinging`, and a `toggled` signal (architecture step 6).
  - `Cabinet` and `Drawer` extend it, and `ItemContainer.openers` is `Array[Opener]`. `is_reachable` no longer switches on `is Cabinet` / `is Drawer`.
  - A new kind plugs in with no change to the container. `test_container_kinds` proves it with a sliding door, which the old type switch failed.
  - `Cabinet.door_toggled` is now the shared `toggled`; nothing outside listened to it.

### Added

- Full-screen Hub action glow (#282): smaller soft top/bottom arcs, gray idle, amber item focus/taking/carrying, brief green/red real transfer results; compass hidden in Hub and during pickup gesture/approach/stow.
- First Exit A compass (owner 2026-11-09, #293): a thin top tape that follows the camera's horizontal view, and one ochre mark for 727. No distance, no turn arrows, no lit route. The mark is armed once, on the Battery Osceola scenario start only; the developer shelter spawn does not arm it. Entering the 727 interior clears it, and leaving does not bring it back. R marks the known house again. Knowledge lives on `FirstExitBearings`, not on the HUD or on Henry, and survives sleep/save. Older saves without this key do not grow a new mission mark.
- 727 shelter: a kitchen cupboard, a dresser and a chest in the waiting room, searchable with the pack like the waiting-room cabinet (owner).
  - They are built by the new shared `FurnitureKit`, which the test row now uses too. Each stands 1 cm off its wall; the chest stands 17 cm off, room for its lid.
  - Contents are game-invented: the cupboard holds a SPoV can and an empty tin; the dresser nails and tinder, with the bottom drawer empty; the chest a tin of pineapple.
  - `test_727_furniture` checks the placement against the real shell's walls (ray gaps), and the search at each piece: no pack mesh in the furniture, the walls or the floor, and every item in sight.

- CI ratchet on dynamic dispatch (ARCHITECTURE §16, architecture step 3).
  - `tools/ci/check_dynamic_dispatch.py` counts `has_method(` and string `.call(` per game-code file against `tools/ci/dynamic_dispatch_baseline.txt`. Each file there has its count and class (A–F); class F, an untyped call on a known class or service, is new in §16.
  - A file may not add a call, a new file may not start, and a file that removed some must lower its line.
  - Baseline: 165 calls in 40 files. It runs in `checks` with its unit test.

### Fixed

- First Exit compass (#293): the bearings script no longer names `class_name World`, so loading the gameplay HUD does not cycle through it. CI jobs that install the .NET SDK pin `ubuntu-24.04` (`ubuntu-latest` is 26.04 and has no `dotnet-sdk-8.0`).
- First Exit compass (#293): the debug clock is off in the game (`perfomance_visible_display` on the world clock), not only in the preview. The preview's inside-727 save now boots a new world through `pending_load_slot`.
- Containers filled off-tree, like the 727 house, stacked every item in one spot. Off-tree an item measured as nothing, and that size was cached. They now lay out on entering the tree, and an off-tree size is never cached. `test_727_furniture` checks the items stand apart.
- Pickups draw every item `SurvivalItemVisual` knows (empty tin, tinder, mug, pan…) instead of a 32 cm placeholder parcel; the parcel had hidden the SPoV can in the cupboard.
- At the cut to a container's frame, what hangs off the pack hangs at rest (`PendulumHang.rest_now`). It no longer carries the swing from the pack's way off his back into the planned pose.
- `test_key_west_727_shelter` expected the mattress the owner removed on 2026-11-03; it now skips it, and the suite passes again.
- Taking an item into the hand (hold F) is now whole or nothing. With two things held, the first was put away before the second refused, so a refused take left a hand empty.
  - The hand components publish the new `HeldReleaseCapability` (`core/contracts/`), whose `can_release` is each holder's own guard: the held item, the hammer, and a flare (only unlit and still owned by storage).
  - `HandsTransaction.check()` asks every holder before anything changes. Storage takes the new item first, the one step that may still refuse; then the holders let go.
  - `tests/systems/test_hands_transaction.gd` reproduced the defect on the old code, passes now, and gates `checks` with the capability contract.
- The same partial release in four more places, fixed through one step, `HeldReleaseCapability.release_all`: every holder is asked first, and only when all can let go do they let go.
  - Sitting down, laying the bedroll, opening the pack and taking an armful each emptied the first hand before a second hand refused. Each now refuses with every hand as it was.
  - A Quick Access pocket change hides only what can go back to storage; a burning flare stays in hand.
  - `tests/systems/test_held_release_callers.gd` covers all five on the real player. It failed four times on the old code, passes now, and gates `checks`.

- CI `checks`: the filename gate failed on every branch because of an orphaned `tools/runtime/_boot_warn.gd.uid` left by an earlier commit; it is removed.
- The capability contract now gates `checks` (ARCHITECTURE §16, rule 4).
  - `tools/ci/required_suites.txt` lists the contract suites; `run_tests.sh <suite...>` runs them with the same verdict as the full run.
  - `test_capability_contract` gained the refusal cases: a refused publish publishes nothing and keeps what was there; a freed provider answers nothing; a non-Dictionary capture refuses the whole save and the last good save stays; a slot without a participant's key leaves it untouched; a half-legacy provider is refused.
  - Verified by breaking the contract on purpose twice; the suite failed both times (4 and 5 checks).

- 3D inventory at furniture: the pack never passes into a cabinet, a drawer or a door, and every item inside shows (owner). Just before the cut the pack moves out until no part of it (body, open panel, what hangs) comes within 2 cm of the furniture. The view then turns up or aside and backs off until it sees each item past everything (`ContainerClearance`).
  - Kitchen cupboard: the open panel went into the right door; drawers: the front panel hid what lay inside.
  - One fitting for every kind of furniture (owner).
    - The owner's framing stands as authored at the 727-like cabinet: the camera exactly, the pack within 3 cm. It had drifted from my pack turn, the camera backing off and a wide reserve under the pan.
    - A side door on the pack's side opens all the way (175°), and the pack stands before it, nearer the camera.
    - What hangs off the pack is checked as it really hangs at rest.
    - Looking down into a drawer or chest, the pack's opening turns to the camera.

- 3D inventory at a cabinet: the pan and other hangers no longer go through the floor or into the cabinet. Both are now obstacles for the hangers.
  - Owner's framing: the camera turned a little right, the pack further right and a little higher (the pan hangs free), Henry out of the frame.
- "Parameter material is null" errors when the game starts and around containers. Item models made only to be measured (pocket sizes, shelf layout, loose items) were freed before ever being drawn, while carrying shader overrides, which Godot 4.8-dev reports from the renderer.
  - `SurvivalItemVisual.release` drops the overrides first. Spawning Henry went from 44 errors to 0 on Vulkan.

### Changed

- Architecture docs: a contract policy (ARCHITECTURE §16, RU too) and decision records (§17, `docs/technical/adr/`).
  - §16 has a table of when to use a direct call, a signal, a command with a result, a capability or injection, and four rules for cross-system links.
  - It classifies the existing `has_method` uses into kinds A–E; the current count is a temporary debt baseline.
  - It works through two references: `SaveParticipantCapability` and `HandsTransaction` (its partial commit).
  - The decision records: ADR 0001 no global ECS, ADR 0002 capabilities only at real seams, ADR 0003 GodotPhysics3D and native code after profiling.

- Claude tooling: project skill `hoarbound-godot-studio` with review lenses for the engine, GDScript, C#, shaders and GDExtension, and procedures for code review, performance profiles, asset audits and test evidence. Adapted by selection from Claude Code Game Studios (MIT, attribution in the skill's `NOTICE.md`). Its hooks, settings and process are not adopted.

- 3D inventory at furniture, owner's design: the second F (the eye) searches where Henry stands. He walks up himself, so he no longer walks to a point; he only faces it and crouches at low furniture.
- Containers of every kind: several doors (`openers`), drawers (`Drawer`), lids on a horizontal hinge (`Cabinet.swing_axis`), shelves that open upward (`opens_up`: the frost and the eye on top, the view looking down into them).
- Test row of furniture (`ContainerRow`, also in `TestScene`): a floor cabinet, a two-door kitchen cupboard on a wall, a dresser with three drawers, a floor chest; some hold things, some are empty. `test_container_kinds` runs the search on each.

- 3D inventory at a cabinet, two presses of F (owner's design).
  - The first F only opens the door. What is inside shows half-seen behind frost, and a search marker (F with an eye inside its ring) sits on the open face.
  - The second F walks Henry over. He crouches as he takes the pack off, seen as by Tab, then the view cuts hard to the cabinet-and-pack frame.
  - Shelf items are no longer taken by F directly.
- 3D inventory (Hub): the silhouette of the garment that owns the hovered pocket (coat or trousers, not both) fades in, with a dot where that pocket is (owner), and fades out after.
- Pockets have real inside sizes in cm and take only what fits by the item's model. The hammer, the axe and the pan no longer go into coat or trouser pockets (owner); tins, the knife and the lighter still do.
- 3D inventory (Hub): small things in numbers (nails, tinder, flares, empty tins) lie in the pack as one bundle per stack, and the readout says how many ("Nails ×20"). 20 nails used to take 20 places.
- 3D inventory (Hub), gamepad: a flick of the stick steps the ring to the nearest item, card, the hand or the pack that way, instead of steering a free cursor.
- 3D inventory (Hub): a threat shuts the open pack, since time never stops there. That is a blow (new `PlayerHealthSystem.hurt`, not frostbite's slow loss) or a fall; other threats can call `interrupt()`.
- 3D inventory (Hub): taking costs time. LMB is held while a line fills round the item, and letting go early takes nothing.
  - The bottom strap and heavy items take longer. Cold hands take up to 2.5 times as long and shake the ring.
  - A tin off the bottom strap takes 0.63 s warm and 1.57 s with frozen hands.
- 3D inventory: the body's pockets stand in a row at the bottom centre: trousers, the hand card, coat.
  - The clothes panel is hidden (owner's call). Its code stays behind `PackQuickShelf.SHOW_BODY_PANEL`.
- 3D inventory at a cabinet: F opening its door (or Tab beside an open one) sends Henry over to it.
  - He walks to the side away from the door's hinge and crouches at a low cabinet.
  - The frame then holds only the pack and the cabinet, side by side at about 48% of the width each (owner's sketch). Henry is hidden.
  - The view looks in at an angle, so the cabinet's front turns to the pack. The pack stands open toward the view, its front panel flat.
  - The pack sits close against the cabinet, higher and well nearer the view, its bedroll kept in frame, with no gap to the cabinet. Its front nearly shares the cabinet's plane. The frame is tighter.
  - Henry no longer freezes on the way. A walk blocked short of the spot now counts as arrived after 0.25 s, where before he pushed for 4 s. The door clip is cut once his hand reaches the door.
  - The chest-pack variant is gone.
  - The framing is authored in the editor: `tests/scenes/container_framing_stage.tscn` (floor, cabinet, Henry, pack, camera).
    - Save framing writes `data/items/container_framing.tres`. The game puts the camera and the pack there, mirrored for the other side.
    - Henry walks to his point and stays blurred behind the pack.
  - While the Hub is open no world prompt (a door, the cabinet) is offered, just as pickups already were not.
  - The ring carries items shelf ↔ pack ↔ pockets through new Hub moves (`move_from_container`, `move_to_container`).
  - A full shelf refuses, and the shelves stay sharp under the focus blur.
- Furniture can hold items: `ItemContainer`.
  - Shelves are derived from the furniture's own panels, items stand on them by real size, and the contents are saved.
  - Items stay ordinary pickups, so F still takes them.
  - The 727 waiting-room cabinet now holds the SPoV can and the gloves on its shelves. Its dressed stew and pineapple tins are real items now (owner's call).
  - The cabinet's dressed mug is gone, since it duplicated Henry's own.
  - An older save that took them from the world is respected.
- Item readout shows grams under 1 kg (a lighter read "0.0 kg").
- 3D inventory: RMB (pad X) uses the hovered item, and the hint names the verb.
  - A sealed tin opens where it lies, in its pocket or under the straps, and the pack stays open.
  - Food and drink close the pack, because Henry needs his hands, and then he eats or drinks.
  - What cannot be used says why. New action `pack_use` shares RMB with `present_held`; the overlap is allowlisted.
- Pack contents no longer flicker on every change.
  - The pack rebuilt every outside item (thermos, tools, mug, pan) on each change, so they came back unmasked by the focus blur and unfrozen.
  - Now only the places whose item changed are redone (`BackpackModel.remove_slot_item`/`unhang_item`).
  - New hangers take the freeze, and the focus blur masks a mesh as it enters the tree.
  - The put-in jolt has a base dip (1.2 cm) so even a lighter jolts it.
- 3D inventory: cloth sounds and a jolt.
  - Taking, putting and dropping rustle the cloth, and a refusal pulls softer. The clips are Freesound #237047, CC0, supplied by the owner.
  - The held pack dips under what is put into it, about 2 cm per kg, then bounces back.
  - The readout names the fifteen items that had no Russian name.
- 3D inventory: the item under the ring shows its readout, and a load bar shows what Henry carries.
  - The readout gives the name, weight and key number: a flask's water, food's calories, or else the size.
  - The load bar shows the carried weight against the limit, with a tick where Henry starts to slow.
  - The hovered item's share is lit on the bar. Data comes from the new `ItemReadout`.
- Work trousers gain a right thigh pocket (`legs_outer/thigh_right`, Quick Access).
  - The HUD builds its card from the left thigh's, below the pack lid in the cross.
  - It has its own anchor (`ThighRightAnchor`) and is reached with the wheel; keys 1-4 are unchanged.
- 3D inventory layout pass.
  - The clothes panel is smaller, near the left edge, and the trousers sit apart from the coat.
  - The hand card stands beside the panel.
  - The body cards' gradient fades the other way and is fainter. Items no longer spin on cards.
  - Everything but the held pack and the inventory, Henry included, blurs while the pack is held (`PackFocusBlur`).
    The pack writes a stencil mask, and a full-screen quad blurs the rest. Depth of field could not part them.
- 3D inventory: the coat's and trousers' pocket cards sit on a see-through grey panel of Henry's clothes at the left.
  - The panel is baked from the real jacket and trousers by `tools/runtime/bake_body_silhouette.gd`.
  - A hand card at the right shows what Henry takes in hand; a pocket's item let go on it becomes the pick.
  - The ring cursor flows into the hovered item's real silhouette (rasterised and traced), not a convex hull.
  - A carried item shows at its true size. Nothing on the pack wears the amber pick rim any more.
  - Hangers on the pack (mug, pan, carabiners) freeze once it is held still, and thaw when it goes back on.
- 3D inventory: Quick Access cards no longer duplicate what is seen on the pack.
  - The side pockets' and carabiners' items are hovered right on the pack, with no card drawn.
  - Only hidden pockets (coat, thigh, lid) stay as 3D cards at the frame's sides.
  - Over any item the ring cursor flows into the item's outline on screen.
  - `PackStraps` now measures each item's outline once per id instead of every frame.
- Clipped mug no longer shakes in a tipped pack. `PendulumHang` stopped it where its own swing meets the obstacle
  (conservative advancement) and never let it deeper than it was. It backs out of the margin one small step a frame,
  instead of being thrown past a grazing contact and falling back every frame.
- 3D inventory: the ring cursor and hands now work on the straps and the live Quick Access cards
  (`PackHandling`, built by the Hub on Tab).
  - Take from a pocket or the pack with LMB (pad A), and let go over the other to move it there.
  - The pack and the pockets refuse in red with a reason. G (pad Y) puts the hovered item down on the ground.
  - New Hub moves: `drop_from_pack`, `drop_from_zone` and `move_between_zones`.
  - `ItemPickup.ground_ahead`/`spawn_dropped` are shared with the hand's drop.
  - The physics compartment (`PackInterior`), its stands and captures, and the wheel/RMB actions
    (`pack_turn_*`, `pack_shove`) are removed.
  - Stand: `tests/systems/test_pack_hands.gd`.
- 3D inventory, pack in hand:
  - One strap stays over Henry's shoulder and lies on the jacket down his chest.
  - Quick Access beside the open pack shows the real pockets' 3D items on gradient cards at the frame's sides,
    with no text. Items fly from a card into the pack under the straps.
  - The inner straps are fixed to the side walls and draw out round what they hold.
  - The camera shows the dropped panel.
  - Verlet strap chains pin their ends every step.
- 3D inventory: the main compartment holds its contents under three straps instead of physics (`PackStraps`).
  - Each item, sized by its real outline, stands into the lowest tier with room against the back wall, layer
    by layer. That tier's strap pulls in and buckles.
  - Items that do not fit are refused, the side walls stay flat, and nine SPoV tins fill one layer.
  - `PackRig` feeds it from the inventory.
  - The Tab view capture now shows nine tins going in.
- 3D inventory, stage 3: Tab takes the pack into Henry's hands (`PackFrontHold`).
  - It swings off his back to before his chest, opening toward a fixed camera that faces him, tipped so he sees
    in from above. The front panel drops open away from him, and his hands hold the sides.
  - The Quick Access cards stand pinned on their live anchors. Tab or Esc puts the pack back on.
  - Full inspection is unchanged. Capture: `tools/runtime/capture_pack_view.gd`.
- 3D inventory, stage 2: Quick Access beside the open pack (`PackQuickShelf`). Each quick pocket is a card on
  the Quick Access gradient (`BG_frame.gdshader`), with its item in 3D: body pockets left of the pack, its
  outside pockets right.
  - Items move card to pack, pack to card and card to card with the ring and LMB, by the inventory's fit rule.
  - A refusing pocket turns red and shows its reason. G throws a card's item out.
  - New strings: `INVENTORY_POCKET_FULL`, `INVENTORY_POCKET_TOO_SMALL`, `POCKET_*`.
  - Stand: `tests/systems/test_pack_shelf.gd`. Capture: `tools/runtime/capture_pack_shelf.gd`.
- 3D inventory: a calmer heap while one item is rearranged. The mean speed of the other items while one is
  dragged went from 0.097 to 0.004–0.063 m/s.
  - Only touched items wake (sleeping islands), and a calm-down restarts only when that item itself is knocked.
  - The hand has limited strength (12 m/s², 1 m/s), and a held item slips (friction 0.05).
  - Items carry their weight where their bulk is (a tool's head), go in heavy end down, and turn back toward a
    fitting turn when no shift fits them inside the canvas.
  - The RMB sweep is a hand's width and lifts a little.
- 3D inventory, stage 1: hands in the open pack (`PackHandling`, `PackCursor`; see
  `docs/technical/PACK_INTERIOR.md` and `CONTROLS.md`). Time keeps running.
  - A ring cursor picks items by their drawn outline and shows "G — drop" (Y on a pad).
  - LMB takes an item and drags it, and the ring hides while it is held. The wheel turns it.
  - RMB sweeps the heap, and G throws the item out.
  - An item that does not fit gets a red rim and its reason (`INVENTORY_HINT_DROP` is new).
  - There are new `pack_*` actions with gamepad bindings: A, X, LB/RB, Y and the left stick.
  - The interior gains `pick`/`hold`/`turn_held`/`remove`/`shove`, a speed cap, and a heavier held item.
  - Stand: `tests/systems/test_pack_handling.gd`. Capture: `tools/runtime/capture_pack_handling.gd`.
- 3D inventory, stage 0: the main compartment's physics sandbox (`PackInterior`, see
  `docs/technical/PACK_INTERIOR.md`). Items lie loose in it as rigid bodies, in a physics space of
  the pack's own.
  - The collision walls are the canvas's inner rounded surface, plus the 16 mm it may stretch. Every
    item's support points are projected back inside after each step.
  - Items go in the way they fit (the frying pan on edge), and bulky or oversized items are refused.
    Two new strings give the reason: `INVENTORY_TOO_BIG` and `INVENTORY_NO_ROOM`.
  - Canvas (`backpack_canvas.gdshader`):
    - Slack cloth now sags only onto the contents, never through them.
    - The side pockets and the carabiner loops ride the wall's bulge and the open front's give.
    - A pocket's sewn layer is no longer drawn from inside, so it stops showing through the wall in an
      open pack.
    - The interior's volume feeds the fill.
  - The slot layout's inner shelf is removed.
  - Stand: `tests/systems/test_pack_interior.gd`, which checks every item against the cloth as the
    shader draws it. Capture: `tools/runtime/capture_pack_interior.gd`, with the pack hanging and open.
- Archived the sequential five-color UI edge-glow shader, self-contained Godot demo and 6-second capture script in the production repository as a visual reference; no inventory/runtime integration.
- Added a Godot-native animation integration reference and the `/hoarbound-animation` Claude Code skill. Both point to Henry's existing AnimationTree/IK owners, GLB QA and the frozen Motion Matching acceptance gates; no runtime animation behavior changed.
- Work in progress: the shoulder straps are now the school backpack's own pad, webbing and buckle
  (`tools/blender/build_pack_straps.py`). The mesh is straightened into strap space and bent on the GPU
  along the strap path on the jacket (`shaders/items/pack_strap_bend.gdshader`, a spline mesh).
  `measure_straps.gd` now measures the bent mesh itself and can learn a bow for the free runs.
  - The pad now spreads to the path's width over the shoulder, as the old band did. The straps take
    the pack's grey-blue canvas colour; the school pack's near-black texture adds only weave and wear.
  - A first learned bow for the free runs is in `strap_points.json`.
  - Still open: the strap mesh dips up to about 13 mm into the jacket under the arm at rest, which may
    be the sleeve lying over the strap.
- Hand grip system (`HandGrip`), first used for the searchlight. This replaces the per-item hand fitting.
  - Cause of the twisted sleeve, measured: the old solver bent the wrist 106° and rolled the hand -93°
    against the forearm. A real wrist allows about 70° of bend and no roll of its own. With linear
    blend skinning and no forearm twist bones, the sleeve pinched like a candy wrapper.
  - The item gives only its handle (anchor and radius). Godot's own `TwoBoneIK3D` reaches the arm, the
    wrist turns within a 60° cone, and `BoneTwistDisperser3D` spreads the roll over the upper arm,
    forearm and hand. The fingers close joint by joint until their tips meet the handle, the way Auto
    Hand does it.
  - The searchlight is carried as a lantern: arm down, bar in the fist along the beam. The forearm
    turns the beam toward the head's facing (up to 50°) and the wrist tilts it (up to 25°).
  - Measured on the stand: wrist bend 45° (was 106°); roll hand 12°, forearm -14°, upper arm -5°
    (was hand -93°).
- The lighter's present hold moved onto `HandGrip`.
  - The lighter stands in a closed fist, thumb on its front. It used to sink into a flat hand.
  - Wrist bend is 8° (was 28°); forearm roll -18° (was -33°).
  - The thumb now closes onto the held item too.
- Superseded by the hand grip system above: the earlier searchlight grip fixes.
  - The palm now closes down on the carry bar. `DoorHandIK`'s `into` vector is the back of the hand,
    and the searchlight passed "down", which turned the palm up.
  - Fingers now curl toward the palm. `StoveHandReach` used to bend them back over the knuckles,
    which also affects the lighter fist.
  - The light now aims where Henry's head looks. With a light in hand, the head look stays on while
    walking and keeps its pitch.
  - Still open: the sleeve twists at the wrist, because the whole roll is put on the hand bone.
- Outfit texture imports are committed with VRAM compression and mipmaps, normal maps flagged.

### Fixed

- Frying pan strikes reworked after the owner's review.
  - No lunge: strikes now play on the upper body only, through a new filtered `upper_actions` one-shot
    in Henry's tree (spine_02 up and the arms). Legs and hips keep their stance, or the walk.
  - Slower: the quick swing plays at 0.7 pace, the rise to the wind-up at 0.8, the chop at 1.0.
  - Hit windows were re-traced from the pan's path with the upper body only. Quick: head height,
    0.6 m reach. Heavy: comes down to waist height 0.8 m ahead.
  - Sounds: a light clank for the quick strike and a heavy bong for the held one. They are
    synthesised by modal synthesis (`tools/audio/make_pan_hits.py`) as stand-ins, because Freesound
    is not reachable from this environment.
- Items clip back onto the carabiners as side-pocket items go back in. Put back, the pan (and the mug)
  starts 7 cm above the rod, drops onto it in 0.28 s, and the knock sets it swinging
  (`PendulumHang.nudge`).
- Frying pan strikes (`StrikeComponent`, any item with `strike_impulse`; the pan's is 9 N·s).
  - LMB is a quick diagonal (`Sword_Regular_A`).
  - RMB raises the pan overhead and holds the wind-up (`Sword_Attack` held at 0.30 s). Releasing it
    brings the chop down faster: 70–100% of the full impulse, by how long it was held, up to 1 s.
    The quick strike carries 45%.
  - The hit is traced along the pan's actual path between frames (spheres along the segment, only
    out ahead of Henry), so a fast swing cannot pass through something.
  - Rigid bodies take the impulse; anything that publishes ThrowImpactCapability takes the hit.
  - The pan rides the animated fist: `HandGrip.fit()` closes the fingers on the handle without
    moving the arm.
  - `test_strike`: a crate is knocked away, and the held strike is harder than the quick one. The
    clip times come from tracing the pan's path. The hit sound is the mug knock for now.
- G puts whatever is in Henry's hand down on the ground ahead as a pickup.
  - Armfuls and a burning flare keep their own G.
  - The item leaves the pocket it was shown from.
  - Pickups now carry the item's runtime state, so a dropped searchlight keeps its charge
    (`test_drop_held`).
- Holding LMB raises the searchlight forward before the chest to aim; releasing lowers it again.
  The beam still follows the head.
- Searchlight follows the head up and down, and is carried a little forward (owner).
  - Cause of the flat beam: attention is kept level (`view.y = 0`), so the head never pitched and
    the light following it stayed flat. With a light in hand, the head now takes the camera's pitch
    (up to 40°).
  - Stand: camera 19° up gives a 19° beam; 25° down gives -25°.
  - The carrying hand sits 72% of the arm down and 45% forward (was 82% / 22%), ahead of the thigh.
- Arms no longer spread wide off the straps, and the right arm no longer twitches.
  - `ArmStrapClearance` now turns at most 8° (was 25°), measured on the inner sleeve (lower quartile
    radius).
  - The turn eases both ways. Its old instant push read as a twitch.
  - An arm holding something through `HandGrip` is left to its grip.
- Frying pan on the left carabiner.
  - The model is Codex's worn 24 cm pan, cherry-picked from `codex` (`assets/items/frying_pan`).
  - It is now an item (`frying_pan`, 1.1 kg) in the starting kit, kept in the pack's new
    `pack_carabiner_left` pocket.
  - It hangs by its oval eye on the rod, as the mug does on the right: a hinge on the rod inside the
    carabiner's swing, and it knocks on the pack when Henry moves.
  - `test_backpack_rig` R1 now expects both carabiners loaded. Measured: the pan never sinks into
    the pack (4.1 mm at most, within the 6 mm contact margin), and it comes to rest.
  - The pan's Blender sources are kept out of Godot's import with `source/.gdignore`.
- Bedroll on C (owner request). Crouch moves to left Ctrl.
  - Henry carries the bedroll again: it is in his starting kit, strapped on the pack.
  - C shows the open bedroll on the floor ahead as a grey see-through ghost (reddish where it cannot
    lie). The ghost has no colliders. F lays it out and it unrolls, ready to sleep on. C again puts the
    ghost away.
  - The stand-in roll that used to travel along with the unrolling mat is gone.
  - The unused `toggle_active_gizmo` action is removed: it sat on Ctrl and had no consumer.
- The old floor mattress is removed from 727 Fort St. Henry sleeps on the bedroll he lays.
- Fixed `HenryUALAnimation._keep_head_facing` erroring "!is_inside_tree()" hundreds of times. A
  skeleton outside the tree still reported updates; those calls are now skipped.
- Static world shaders no longer require tangents. Static world materials never take a normal texture
  (`make_static`), but `NORMAL_MAP` was still compiled into their shaders. Godot then demanded
  tangents from every generated chunk mesh (the "requires tangents" warning). `NORMAL_MAP` is now
  left out under `HFN_STATIC_WORLD`.
- Under the arm, the strap is no longer swallowed by the sleeve.
  - Measured with `measure_straps.gd`: the torso cloth there already cleared the strap (1–3 mm). The
    sleeve lay over it by 11–19 mm, because the arm itself passed through the strap.
  - Pressing the sleeve toward the arm hit the 30 mm press limit and opened a hole in the sleeve, so
    that approach was dropped.
  - Fix: `ArmStrapClearance` (a skeleton modifier, active only while the pack is worn) treats the
    sleeve as a capsule round the upper arm, its radius measured from the jacket. Where the capsule
    meets the strap, the arm turns at the shoulder just far enough to clear it, the way spring-bone
    colliders push bones out. The shoulder joint under the pad is left alone. The turn applies at
    once and eases back slowly, capped at 25°.
  - Result: at rest, nothing under the arm (was 8–13 mm); walking 6–9 mm (was 18).
- The stove ritual's hand breaks the wrist when measured: hand roll up to 94–141° and wrist bend up to
  85° while laying fuel and lighting. It is next to move onto `HandGrip`.
- Mug on the carabiner no longer sinks into the hammer/axe handles (`test_backpack_rig` R3/R9 were red on
  `main`). Cause, measured: the 1.4 cm handle capsule slipped between the mug's contact points. Each 2 cm
  cell took its first vertex, so the worst vertex sat 1.7 cm from any point; the mug went 8–10 mm into the
  handle while every point stayed clear. Each cell now takes the vertex nearest its cell's mean (vertex
  clustering, Rossignac & Borrel), which brings that down to 1.45 cm. The contact margin is now 6 mm (was
  4) to cover how far the handle dips between points. A 1 cm grid also passed but tripled the contact cost
  per frame.
- The knit hat attachment is named `Hat` again, matching the other garment groups (`test_equipment`,
  `test_knit_hat`).

### Added

- Henry has his own head: the generated candidate made from the owner's reference. It is not final art;
  it is used as the current head.
  - **Placement** (`owner_head` in `tools/blender/build_henry_outfit.py`): decimated to 6000 faces with
    smooth shading. It is scaled so the chin-to-skull height matches the mannequin's head (×0.375; the
    skull width matches within 3 mm), and its chin sits on the mannequin's chin.
  - **Rig:** the neck is cut inside the turtleneck, and the head is skinned to `Head`, blending to
    `neck_01` down the neck. The mannequin's head and neck are removed.
  - **Turtleneck** top now dips 11.5 cm towards the front, so it sits under the chin and still rises
    past the jacket collar at the back.
  - **Knit hat fit, second pass** (owner: "too high", then "the cuff grips oddly"):
    - The front cuff now sits 2 cm under the hairline, which the build finds on the face's front profile.
    - The cuff is fitted round the head at its own height and keeps its knit band.
    - Only the crown and pom come down onto the head (×0.84), with 1.5 cm of slack.
    - Hair under the hat is pressed by rays from the middle of the head to the hat's inside, so no tuft
      pokes through the crown.
    - His ears no longer cut through the collars (owner). The lobes hang to 1.637 m, and both collars
      stood higher at the sides (1.676 and 1.683 m). The turtleneck's top now has a back, side and front
      profile: high at the back, 7 cm lower at the sides, under the chin in front. The jacket's collar is
      turned down beside each ear to 1.7 cm under the lobes, to leave room for the head's tilt.
    - Measured in game, deepest ear point inside a collar: turtleneck 17 → 7 mm, with far fewer points.
      The jacket's collar still reads up to 17 mm on that metric, which also counts ears hanging over the
      collar's edge. Close-up captures show no crossing.
  - **Knit hat fit:** the build measures the head (`fit_hat`) and writes the fit to
    `assets/characters/henry/knit_hat/hat_fit.json`, which the game applies. The hat is lifted 3 cm,
    centred on the head (it sat 2 cm too far back) and scaled ×1.048 round its axis, so its inside
    rests 3 mm off the scalp. The scalp is taken as the head's 70th-percentile radius per angle, so
    tufts do not count. Hair still outside the hat above its brim (543 points) is pressed under it,
    and only short hair shows below the brim.
  - **Turtleneck front:** the top dips evenly round to the front (a U, not a V), so the turned-down
    roll reads as one band under the chin.
  - **Texture names:** every image in the outfit glb is now named after its material. Godot extracts
    textures by name, and "Image_0" collisions put the jacket's plaid on the head.
- Bedroll art from the `codex` branch (cherry-picked): `bedroll_open` and `bedroll_packed` models and
  textures, plus the pack mounting. The laid bedroll unrolls using that open mat.
- The bedroll is laid only in a warm room: inside an interior thermal zone warmer than freezing. Out in
  the cold the preview is red, with "Too cold here — lay it in a warm room". Laid, it unrolls over 1.2 s:
  the bundle rolls from the head to the foot, the pad spreads behind it, and the pillow roll is left at
  the head. A save restores it laid out, with no unrolling. The warmth check now lives in
  `ThermalZone.is_warm_at`, which the snow splats also use.
- Henry wears a chunky knit sweater with a high, thick turtleneck covering the whole neck (owner:
  "вязанный бабушкин свитер с высоким толстым воротником").
  - **Body and sleeves:** built in `tools/blender/build_henry_outfit.py` as a thin layer under the
    jacket. It takes the jacket's weights where it lies under it, so the two never cross.
  - **Turtleneck:** a knitted tube round the neck (`owner_garments.turtleneck`). It follows the skin by
    rays from the neck axis and is capped at the shoulders. It is kept inside the jacket's collar, rises
    past it at the back, and its top is turned down. It is skinned from the neck and head.
  - **Knit textures** are procedural: `tools/blender/make_knit_textures.py` makes the body in burgundy
    stockinette with a cream Fair Isle pattern (lice, dotted diamonds, a zigzag; colour per stitch from
    a chart), and the turtleneck in plain burgundy 2x2 rib. Each comes with albedo, normal and ORM. The
    texture hosts are blocked from this environment.
- The owner's reference for Henry's look is saved in `docs/art/henry_reference/`.
  - **UVs** are tube UVs at real stitch size.
  - **Skin under the sweater** is removed from the model. The sweater is always worn: `BASE_LAYERS` in
    `HenryUALAnimation`.
- Henry now starts wearing the approved dark knit hat. Its cuff, crown, and pompom are separate game meshes on the Head bone; the existing `head_outer` equipment slot controls visibility. The old beanie is hidden. The source Blender file, baked knit maps, GLB, and four Forward+ review captures are included.
- Pack shoulder straps laid on the plaid jacket (WIP, owner review).
  - **Strap points** are jacket triangles: `tools/runtime/measure_strap_points.gd` casts rays and writes
    `scenes/actors/player/henry/strap_points.json`. `PackShoulderStraps` skins them each frame exactly
    as the GPU skins the jacket, after every modifier, so the strap has no motion of its own.
  - **Cloth under a strap** is pressed in by a depth measured over Henry's poses. The depth is stored
    in the jacket's vertex colour, and the shader applies `garment_press` only while the pack is worn.
  - **Corridor weights:** in the corridor along the straps, the jacket's weights are smoothed and its
    neck weight is moved to `spine_03`.
  - **Pack seating:** lean is now 0° and the offset is −0.265, so the back face clears the jacket by 4.8 mm.
  - **Measurement** (`tools/runtime/measure_straps.gd`):
    - strap to pack: 0 mm;
    - cloth in the strap: 0 at rest, ≤ 6 mm crouching;
    - the free run into the jacket crouching: ≤ 16 mm.
  - **Known failures in `test_backpack_rig`:**
    - R3/R9: the mug sinks 8–10 mm into the upright pack;
    - R7: the chest drift is 3.3 mm, because the strap now rides the cloth, not the bone.
- Henry's jacket hem and collar swing on springs (owner: "hem and collar on springs").
  `tools/blender/build_henry_outfit.py` adds eight two-bone chains around the hem from the pelvis and five
  around the back of the collar from `spine_03`. Each chain is found by rays to just inside the cloth,
  stepping back past the ragged edge, and skips openings. The cloth there is handed to the chains,
  blended by angle and height. In game, `JacketSprings` (a `SpringBoneSimulator3D`) runs them after
  every other pose change, with thigh and neck capsules. Values come from a trace
  (`tools/runtime/trace_jacket_springs.gd`): the hem swings about 18° walking (the thighs push it)
  and about 30° sprinting, and settles about 0.3 s after a stop. The collar swings 3–7°.
- Outfit layers checked in motion (owner: no clothing through Henry or through each other in Godot).
  Twelve clips (idle, walk, jog, sprint, crouch, jump, pick-up, interact, torch, sitting, roll),
  eight frames each, with the same skinning Godot uses:
  - **Jeans through the boot shafts:** 0 points in every clip.
  - **Jeans through the jacket:** the waist and belt stuck out by up to 3 cm when bending. Under
    the jacket the jeans are now laid flat on the body and take the jacket's weights, so the two
    layers move as one. Idle, walk, interact and pick-up are at 0-7 points. Crouch, sitting and
    roll still flag 1.7-5.6%, all on the back-pocket welts and belt pieces (inward normals fool
    the ray test); renders of those poses show nothing through.
  - Skin under clothing is hidden in game, so the body cannot show through the cloth.
- Outfit artefacts fixed (owner review: a flap on the jeans, collar and sleeves torn in poses).
  - **Jeans:** the visible mesh rides on a sparse cloth proxy (Surface Deform), so the pocket bags
    sewn inside stay inside.
  - **Jacket mesh:** simulated on its own mesh. On a decimated mesh the plaid bent, and bound to a
    proxy the hem and folded collar threw spikes past its edges. It settles on the body only;
    resting on the jeans the hem crumpled. The hem is then lifted off the jeans.
  - **Jacket weights:** the collar took the head's weights (nearest bone to the jaw) and tore in
    poses; they go to the neck. Shoulders, collar, front placket and cuffs get local weight
    smoothing. The worst edge stretch in a pose fell from 10x to 3x (armpit and hem, normal folds).
  - **Sleeves:** centred on the arm by one fitted line along it, not slice by slice; slices
    sheared the cuff 6.7x, now 1.08x. Collar and cuffs are held as cut during the drape.
  - Checked without gloves (Henry starts without them).
- Henry's outfit rebuilt with cloth: the plaid jacket and the jeans are draped on the body (Blender
  Cloth), then the refitted boots go on and the jeans are tucked in. Checked in Godot from all sides.
  - **Jacket:** sparser cloth mesh (3000 faces), re-posed A to T, sleeves fitted to the arm and
    centred on it slice by slice, 5% wider in girth (not length). Draped held at the collar, the
    front placket and the sleeves. Skinned from the body; hand weights merged into the forearm.
  - **Jeans:** welded into one cloth (belt and loops ride on it), draped held at the waist,
    tapered into the boot shafts, cut inside them; inside the boot they take the boot's weights.
  - **Skin under the cloth:** hidden where a ray from it meets the garment (20 cm reach).
  - **Fixes found on the way:** the re-pose lifted the armature's action (a frame change put the
    pose back); sleeves were held during the drape (the thin arm slipped between the sparse
    sleeve's points); a sleeve cut to hang sat 4 cm under the re-posed arm, which poked through.
- The owner's boots, refitted (owner review: the shin showed past the shaft, gaps at the heel and
  inner side). Accepted by the owner; built into the outfit with the next jeans pass.
  - **Size:** 5.5% larger, about each sole's centre (soles stay on the floor).
  - **Shaft:** wrapped round the shin from the ankle up (10 mm left for the tucked jeans); the
    lining is drawn up to the rim and kept inside the shell; the fur cuff rides on it.
  - **No skin through it:** above the foot's underside the shell is pushed out only where the
    leg or foot comes through, 8 mm. Rendered as the game draws it: 0 skin pixels standing,
    walking, inner side and back.
  - Fixed in the fit helper: Shrinkwrap `OUTSIDE_SURFACE` laid every point on the body (it made
    the jeans and jacket cling); `OUTSIDE` moves only points inside it.
- Outfit fit, second pass (owner review: short, crumpled sleeves; jacket too tight; jeans over
  the boots). Work in progress: the next pass drapes both garments with a cloth simulation.
  - **Sleeves:** after re-posing they reached x 0.81 m, past Henry's whole hand, and the cuff took
    hand weights and crumpled. Each sleeve is now scaled along the arm to end 1 cm past the wrist,
    and hand and finger weights are merged into the forearm.
  - **Ease:** the jacket is moved 2 cm out along its normals, with a 2 cm margin off the body.
  - **Jeans at the boots:** they taper onto the leg, stay inside the rigid shaft (Shrinkwrap
    Inside) and are cut by an exact plane 6 cm below the cuff. With the knee bent they still come
    out of the shaft; still open.
- The owner's plaid jacket and jeans on Henry (Sketchfab, CC-BY-4.0; `assets/characters/gear/CREDITS.md`).
  They replace the generated jacket, skirt, trim, hood and trousers.
  - **Jacket re-posed A to T:** its sleeves hang 42.6 / 42.0 degrees, measured by a line through each
    sleeve. It is bound to a copy of the armature posed to match, then posed back to the T-pose.
  - **Fit and skin:** Shrinkwrap (Outside Surface) keeps each layer off the body (jeans 6 mm,
    jacket 12 mm, and the jacket's hem over the jeans). Weights come from the body's nearest face.
  - **Jeans:** shell, its patch layer (it fills the shell's open panels) and belt, decimated to
    16k faces with the sewn panels' edges held, cut under the boots' fur cuff.
  - **Body mask by coverage:** skin is hidden where a ray from it along its normal meets one of
    these garments, as well as by region. Checked with object-ID renders, idle and walking.
  - **Materials:** the character shader reads glTF metallic-roughness maps (G roughness,
    B metallic, R occlusion when packed in); off by default, so the world is unchanged.
  - The jacket has no hood; a hood up and down is still to come.
  - Stills: `docs/runtime_previews/outfit/`, from `tools/runtime/capture_outfit.gd`.
- The owner's boots (`assets/items/boots/boots.glb`) on Henry, replacing the generated boots and soles.
  - **Fit:** modelled in the mannequin's rest pose (same footprint as the old boots), so no move or
    scale. `build_henry_outfit.py` imports them and gives each piece (shell, lining, fur cuff) the
    body's skin weights from the nearest face, foot and leg bones only, so they bend at the ankle.
  - **Materials:** the painted colour and normal maps are kept; double-sided pieces stay double-sided
    and the alpha-cut fur fibres keep their own material (`HenryUALAnimation._attach_garments`).
  - **No clipping:** the trousers now end just under the fur cuff (its height read from the GLB), and
    the ring of big shin faces at the boot edge is hidden with the boots; before, the trousers and the
    calf poked through the back of the rigid shaft. Checked with an object-ID render from behind.
  - Stills: `docs/runtime_previews/boots/`, from `tools/runtime/capture_boots.gd`.

### Changed

- Quick Access follows what Henry wears (#260, owner).
  - **Which pockets:** pockets now carry a `quick_access` flag. The pack's two compartments are
    Hub-only, so it replaces the hard-coded `pack/pack_main` exclusion.
  - **Outside the pack:** while the pack is worn, what sits outside it gets its own cards: the side
    pocket, the two tool sleeves and the carabiner. They are pinned to the pack's own anchors
    (`BackpackModel.get_quick_anchor`) and go when the pack comes off.
  - **Layout:** in the spread they stand as one column beside the body cards; in the cross they
    take the diagonals. The layout test now checks them for overlaps too, and `test_quick_access`
    checks the rule.
- The mug clipped on the pack knocks on the tool handles (#260).
  - **Strikes:** `PendulumHang` emits `knocked` on a fresh strike, and the pack plays it through
    `SoundSystem`, louder for a faster strike (stand rule R14).
  - **Sound:** a random one of the owner's three recordings (`assets/audio/sfx/items/mug/`)
    replaces the first synthesised attempt.
  - **Strike timing:** a strike is judged on the swing's rate before the frame's spring step, so a
    mug lying on a handle no longer "knocks" every frame.
  - **Contact cost:** the long frames made `test_doorway_camera` pop. Contact points are now one
    per 2 cm (4 mm margin), and a carabiner counts every other point of its mug. The pack's
    distance query skips pockets and handles away from the sides. A loaded carabiner fell from
    ~6 ms per frame to ~1.5 ms and the mug to ~0.6 ms (headless CPU).
- Snow footsteps (thin, crust, step, wet, deep) play a random one of the owner's eight recordings
  (`assets/audio/sfx/player/snow_footsteps/`). The synthesised squeak and pull-out layers stay on top.
  `generate_snow_footsteps.py` no longer writes those five banks, and their old WAVs are removed.
- Pack sway now never rocks past its 2.5° cap; before, a spring overshoot on a jolt (frame-time
  jitter) carried it to 4.3°.
- `tools/ci/run_tests.sh` reads a suite's `## ci-args:` line. The backpack stand asks for
  `--fixed-fps 30`, so CI runs it at game speed as it is run locally.
- Right side pocket split into two bottomless sleeves holding a Build-Rite hatchet and claw hammer
  (#260, owner refs).
  - **Tools:** built in Blender by `tools/blender/build_hand_tools.py` (`assets/items/axe/Axe.glb`,
    `assets/items/hammer/Hammer.glb`), each with a wrap-round price tag drawn by the script ($24.99
    and $9.49). They have rusty heads, a yellow and a red plastic handle, dark rubber grips and a
    holed butt. The new `worn_tool.gdshader` paints the wear in blocky cells, like the refs.
  - **Pocket:** a dark divider splits the right pocket into front and back sleeves. Each tool hangs
    by its head on the rim, its handle through the open bottom. Each sleeve shrink-wraps its handle
    as an ellipse and keeps the thermos's hem stretch on push-in. The tools are placed clear of a
    full pack's wall and of each other.
  - **Mug:** it now knocks against the handles. It turns only about the carabiner's rod (a hinge),
    seeks the nearest clear angle, has contact friction and a 3 mm contact margin. A loaded
    carabiner leans out from the pack.
  - **Data:** the pockets are `pack_side_right_front` and `pack_side_right_back`. The starting
    loadout gains the axe and the hammer.
  - **Stand:** new rule R13 (sleeves). R4 now counts vertices. R9 covers the hinge, the swing left
    at rest and the contact margin. R5 and R12 check the empty right pocket with the tools taken out.
  - **Pending:** Quick Access for the slots outside a worn pack, and a knock sound
    (`BACKPACK_RIG.md`).
- The empty side pocket is sewn onto the body (#260, owner review: "looks torn off the pack").
  - **Measured:** its seam stood 11 mm off the body, and its edges 14-16 mm. It was laid on a
    flat wall at x = 0.17, while the body is a box rounded by 6 cm that curves in near the bottom,
    front and back. It also stood 12 mm thick.
  - **Fix:** every pocket's wall side, and the empty pocket's inner layer, now lie on the rounded,
    slumping body surface (`body_side_x`, the same in the shader and in GDScript). The empty
    pocket's outer layer is a 3-5 mm fold. The seam is now 0.0 mm off and the cloth at most
    5.3 mm off the body.
  - **Stand:** new rule R12. `capture_backpack_stills.gd pocket right` frames the right pocket.
- The clipped mug hangs by physics (#260, owner review: "the same mistake again").
  - **Cause:** it was stood upright with its handle on the rod and its body 7 cm to the side. No
    body hangs on a pin like that, and stand rule R3 ("mug hangs out from the wall") had locked the
    pose in.
  - **Pose:** it now turns about the handle's hole until its centre of mass is under the rod, so it
    hangs tilted, rim out. The centre of mass is the area-weighted shell centroid of its mesh.
  - **Contact:** `PendulumHang` leans it off the pack instead of letting it swing through. It uses
    the signed distance to the rounded body and the pocket cloth (Inigo Quilez's rounded box) and
    bisects for the least tilt that clears; a flat side face gave false contact at the rounded bottom.
  - **Stand:** R3 checks the centre of mass is under the rod, the mug never inside the pack and
    ground clearance (it hangs 14 cm below the pack bottom, 1 m above the ground). R9 checks no
    frame is inside the pack. The mug's stop is now 60°; the pack is its real limit.
- Pocket loops and carabiners are sewn at the middle of each side pocket (#260, owner review).
  Before, the seam stood at the hem: above an empty pocket's drooping rim, and pulled about by the
  hem springs, so the loop seemed to hang in the air. The clipped mug now hangs 7 cm below the pack
  bottom (stand limit 8 cm). Its damping is now 0.65, so the lower pivot does not drive it into its
  stop. `capture_backpack_stills.gd back` gives one view from straight behind.
- Side pocket and thermos (#260, owner review). Measured first:
  - **Floor:** the thermos stood 6 mm off the pocket floor because a slot constant set its height.
    It now stands on `POCKET_FLOOR_Y`, the pocket mesh bottom plus its lining.
  - **Shape:** the cloth wrapped the item's box and kept the box's normals, so it read as a box.
    A round item (meta `round_radius`) is now shrink-wrapped as a cylinder: nearest point plus
    lining, as Blender's Shrinkwrap does. The normals turn with it.
  - **Pushing in:** a thermos put into a side pocket is pushed in bottom first (~0.4 s). Its foot
    flares the hem and friction drags the hem down; the cloth under its bottom stays the empty
    pouch. Then both hem springs let go and the cloth closes on it. Everything derives from the
    item's live bottom, not a timeline.
  - **One rule:** `BackpackModel.pocket_cloth_point` is the shader's twin, used by the loops, the
    inspector and the stand.
  - **Stand:** R10 (seated, hugging) and R11 (insertion). R11 caught cloth inside the thermos at
    the floor's rounded edge: the disc rule went by normal, not by the item's bottom. Fixed.
  - **Capture:** `capture_backpack_stills.gd insert` records the push frame by frame.
- `capture_backpack_worn.gd` takes `short`: a 4 s close clip of the thermos in its pocket and the
  mug swinging as Henry walks, stops and sidesteps.
- Water flask is now a steel thermos (#260), built in Blender by `tools/blender/build_thermos.py`
  (`assets/items/thermos/Thermos.glb`). It has a threaded neck and a flip-top lid on a hinge that
  does not come off (`Thermos_Lid`, which turns about local +Z). The painted body and steel use the
  carabiner's chipped worn-paint shader in olive drab. Blender colours are linear, so the first sRGB-like
  values exported a pale teal. Item ids and volumes are unchanged; the printed volume mark is gone
  at the owner's request, and the latch keeper now sits on the neck instead of 3 mm off it.
- Backpack carabiners and the clipped mug swing both ways (#260). `PendulumHang` keeps its state in
  world space, so a hanger lags when its parent turns. Before, it turned rigidly with the parent and
  the mug barely moved on its carabiner. The mug is calmer and settles quickly (1.8 Hz, damping 0.5,
  35° stop); in the clip its 75° stop let it fly out level on a sidestep. Stand rule R9 also checks
  that no hanger reaches its stop and that each settles to world down at rest. The stand must run
  with `--fixed-fps 30`: without it headless frame times are not 1/30 s, and the first R9 numbers
  were wrong. At 30 fps the peaks are 20°/26° and 18°/26° (carabiners) and 29°/15° (mug),
  fore-aft/sideways. `capture_backpack_stills.gd pocket` gives three close views of the side pocket.
- Owner accepted the road flare shadows and restrained scattering on 2026-10-29.
- Road flares cast dynamic shadows in hand and after a drop, with exposed contact-shadow bias.
  The emissive tip no longer casts shadows around its enclosed light. A weak, non-emissive
  local FogVolume adds adjustable scattering through the existing Forward+ fog. The flare
  night harness now captures matched shadow/scattering views and measures moving-light cost;
  its camera excludes the reserved snow-contact layer. Local-light NPR shaders are unchanged.


### Added

- Backpack lab, stage 1 (#260): a front-loading pack without soft-body physics, not yet on Henry.
  - **`BackpackModel`:** a canvas shell plus a front panel. Both are one rounded box split at the front edge, so
    the closed panel meets the shell with no seam.
  - **Opening:** the panel unzips and folds down 104 degrees on a bottom hinge, on a spring. Its free edge droops
    under gravity and wobbles when it stops. A mesh pocket is drawn on its inside.
  - **Slots:** a shelf and three lower columns in the main body, and a side pocket.
  - **Fit:** `backpack_canvas.gdshader` pushes the canvas out round each item's box proxy, plus a lining, so a
    flask bulges the side pocket. An emptier pack slumps: its top drops and its walls cave in.
  - **Straps:** the straps, handle and buckles are baked in pack space and move with the canvas.
  - **Owner review:** there is a pocket on each side, open at the top and sized for a bottle that stands out of it.
    The canvas gives 2 cm at most (3 cm in a pocket) and no longer balloons round an item bigger than its pocket.
  - Capture: `tools/runtime/capture_backpack_lab.gd` (two views of one run).
- Backpack on Henry, stage 2 (#260): `PackRig` now draws a `BackpackModel` (`use_canvas_model`) in place of the
  old box and flaps. `PackRig` still owns the Hub, inspection and setting the pack down.
  - **Openness:** closed, ajar 24°, top-only 42°, and fully open for the Hub.
  - **Fill:** carried weight over 14 kg sets the fill, so a light pack slumps.
  - **Sway:** the pack hangs from a pivot at its top back. Henry's acceleration drives a pitch and roll spring
    (at most 9°); it swings slower when loaded.
  - **Kenny:** he is off the starting loadout for now (owner's call). His item, fixture and set-down code stay.
  - **Zip:** a black zip with lighter teeth runs along the panel's top and sides. Two sliders start together at the
    top centre and run out to the corners and down the sides. The panel folds out only above the line they have
    reached (a shader bend, not a hinge node). It closes in reverse: the panel folds back, then the sliders return.
  - **Quick stow:** the sliders run 15 cm down the sides and the freed top folds out 55°. The walls by the open
    seam give a little.
  - **Carabiners:** a strap loop on each side near the top, each with a swinging screw-gate carabiner (`Carabiner`,
    worn red paint, knurled sleeve). They swing like a pendulum. `Hang` is the clip point for later, e.g. the mug.
  - **Shoulder straps:** `PackShoulderStraps` runs a band from the pack top over each shoulder, down the chest and
    under the arm to the pack's bottom corner. It is rebuilt from the bones every frame.
  - **Fit:** the pack's back face was 10 cm inside the coat (measured coat back 0.21 m behind spine_03), so the coat
    showed inside the open pack. `backpack_offset` moved to (0, -0.03, -0.31). The inner shelf no longer pokes
    through the panel.
  - **Owner review 2:**
    - The pack now leans 12.5° along the coat's measured back line and rocks at most 2.5°, about the middle
      of its back. It only rocks as Henry starts and stops.
    - The shoulder straps come from points measured on the jacket mesh and ride the chest bone, so they no
      longer swing with the pack. Each lies flat on its coat normal, with no twist. Their pack ends are sewn
      to the top of the back pad and to the bottom corners.
    - The grab handle is an arch sewn to the top.
    - The zip edge stays ajar 1.5 cm wherever the sliders have not yet closed it.
  - **Owner review 3:**
    - The strap points were up to 6 cm off the coat. They are now ray-measured on the jacket mesh, with an extra
      mid-chest point so the curve cannot cut into the coat's bulge.
    - The flask stands flat against the wall in a widened side pocket.
    - The mug hangs from the carabiner by its handle.
  - **Owner review 4 (straps):**
    - The straps were laid on the collar: about 11 cm out, where the collar and hood ring reaches 18 cm.
      Rays cast at the coat mesh also missed its outer layers.
    - They now follow authored anchors bound to the bones (`pack_strap_anchors.tscn`): upper back and
      shoulder on the clavicle, chest and armpit on spine_03, mirrored to the other side.
    - On the body the strap is tight. The pack-to-back and armpit-to-pack runs are verlet chains with
      2–5% slack, kept outside the torso, so the pack rocks without dragging the straps.
    - Off his back each strap is a limp loop on the snow.
    - `.tscn` stores a basis by rows; anchors written by columns had their normals swapped, which twisted
      the band. Band normals also keep to one side now, so a band never flips.
  - **Owner review 5:**
    - The free strap runs on the back are cinched taut (length 1% under the straight line). They no longer
      dangle.
    - Side pocket contents no longer push the main wall: pocket items shape only the pockets, and the body
      shell, panel and straps take only main items. Before, the wall bulged past the flask and left it inside
      the cavity.
    - Pocket items sit 1 cm outboard.
    - Look from the owner's reference, in the NPR 2.5D style: worn grey canvas, a stitched leather base, pale
      rubbed edges, mottling, grime low down, and banded light. Grey webbing straps.
    - Tool: `tools/runtime/inspect_backpack.gd` loads the starting contents. It reports item boxes, pocket items
      reaching into the cavity, main items poking past the canvas give, overlaps, and the handle's gap to the
      top. It renders front, side and top orthographic views and a three-quarter view, see-through with wire
      boxes and with the real canvas. The worn capture logs each free strap run's sag.
  - **Owner review 6:**
    - Side pockets are cloth now, not scaled boxes. An empty pocket falls flat on the body wall and its mouth
      closes. A pocket holding something wraps it, its wall side stays on the wall, and stretched cloth goes
      paler.
    - Slack cloth creases (shape and shade): empty pockets, and the top of a slumped pack.
    - The canvas takes the world's painterly breakup at pack scale (`painterly_surface.gdshaderinc`). The front
      panel carries a stitched leather maker's patch with a pressed mark.
    - The side compression straps are gone.
    - The bedroll is strapped across the top in front of the handle, so the leather bottom is flat and the
      pack stands anywhere.
    - Pocket cloth that starts inside the item it holds goes all the way out to the item's face. Wrapping
      it only 85% of the way left the flask showing through. The inspector mirrors that wrap and reports any
      poke-through (now 0.0 cm).
    - The carabiner loops moved to the pocket rims, so the mug hangs level with the pack's bottom (0.2 cm).
  - **Owner review 7 (stand and map):**
    - Free strap runs are straight segments. The chain and torso capsule bowed them 2–2.6 cm and let them
      swing forward as Henry moved.
    - Pocket loops and carabiners follow each pocket's cloth as it is now (`pocket_outer_x`). An empty pocket
      lies flat, but the loop had stayed 8 cm out in the air. On the flask side the loop had sat inside the
      flask.
    - Loops are 5 cm tall from the rim and carabiners pass through them, so the mug ends above the bottom.
    - `docs/technical/BACKPACK_RIG.md` maps every space, authored point, measurement and rule.
      `tests/systems/test_backpack_rig.gd` checks the rules on Henry standing and walking, before any
      render (R1–R7, all pass).
  - **Pivots:**
    - Pocket loops are sewn at the rim and hang out and down, and each carabiner is threaded through its
      loop's lower end. Before, they stood up as tabs.
    - The mug's handle sits on the carabiner's rod with its hole along the rod, and the mug hangs upright
      outboard of the wall. Before, the hole crossed the rod.
    - The stand checks every pivot (R3).
  - **Hitch fix:** a long frame (seconds while Reality loads) blew the pack's explicit springs (sway, panel,
    fill, pendulums) to NaN, and the pack drew lying on its side in stills captured without a fixed frame
    rate. Each spring step is now capped at 0.05 s, and non-finite values reset. Stand rule R8 checks a
    1-second hitch.
  - `tools/runtime/capture_backpack_stills.gd` takes eight settled close-ups round Henry and logs the pack's
    up vector.
  - **Hanging:** `PendulumHang` swings anything from a pivot. The carabiner swings in its loop and the mug
    swings on the carabiner's rod: a double pendulum driven by Henry's motion. The carabiners moved onto the
    side pockets.
  - **Contents:** the pack has new pockets: a second main compartment, two side pockets and a carabiner. Henry
    starts with a SPoV can and tinned stew lying loose inside, a flask in the left side pocket and the mug on the
    right carabiner. `PackRig` mirrors the pack's pockets into the canvas whenever they change.
  - Capture: `tools/runtime/capture_backpack_worn.gd`.
- Isolated soft-container physics lab (#254): six draggable cubes/spheres, pinned rims,
  upright/60-degree tilt and reproducible Jolt capture; experimental 4.6.3 evidence,
  pending verification on the project engine baseline.

- Snow that sticks and melts (#257, stage 4).
  - **Splats:** a snowball bursts into a puff and leaves a `SnowSplat` decal on what it hits. In the cold the
    splat stays (the 32 newest are kept). Inside a heated interior zone it slides down 12 cm and melts in 45 s.
  - **Melting in the hand:** `HandSnowMelt` melts a handful held in the warm. It lasts 40 s in a barely warm room
    and 20 s at 20 C, shrinks in the hand, leaves up to 0.3 wetness in the glove, and is gone. Below freezing it keeps.
  - Tests: `test_hand_snow_melt`, plus the splat check in `test_throw`.
- Breakable window glass (#257, stage 3).
  - **Which panes:** `WindowBreakage` cracks and breaks the pane a throw lands on, on any house: the 727 window
    breaches, and every pane quad of a generated facade's `windows` surface, found from the hit point.
  - **Damage adds up:** a pane cracks at 2 N*s and breaks at 5 N*s. A snowball (0.2 kg at 13 m/s) cracks it and a
    second breaks it; a stone (0.35 kg at 15 m/s) breaks it at once.
  - **Look:** cracks radiate from the impact, a broken pane shows a jagged dark hole with shards round it, and
    shards fall. There is no glass sound yet: the project has none.
  - **Saved:** damage persists, panes included.
  - **727 glass holds heat:** a closed pane leaks 12 % of its hole (`ShelterBreach.glazed`, `GLASS_LEAK`), so the
    heated room's sealing goes from 0.085 to 0.877 and its heat ceiling from 3.4 to 16 C. A broken pane is a full
    hole again (owner decision; boards to be reworked later). 727 window breaches now carry the spec's opening sizes.
  - **Plumbing:** `ThrowImpactCapability` passes the struck collider; world sinks take hits nothing nearer claimed.
    Test: `test_window_breakage`.
- Throwing snow and stones (#257, stage 2).
  - **Aim and throw:** with a throwable in hand (`ItemResource.throw_speed_mps`: handful 13 m/s, stone 15 m/s),
    hold RMB to aim. A dotted arc and a landing ring show the flight, with a slow hand sway of about 1.2 degrees.
    LMB while aiming throws on UAL2 `OverhandThrow`, released at 0.29 s (traced on Henry in game: the whip
    forward starts at 0.28 s), with 0.8 degrees of jitter. LMB without aiming still eats the handful.
    At the release the throw is solved again from the real hand position to where the arc landed.
    Owner review: snow and stones sit in the right hand (`HeldFit.hand = RIGHT`), the hand that throws, so the arc
    starts at the snowball. Holding RMB plays the throw to its wind-up (0.24 s, hand up and back) and holds it there
    (`HenryUALAnimation.set_action_pace`); LMB lets the clip run on into the release, and letting go of RMB lowers
    the arm. A scoop leaves a hand-sized hollow in the snow (a body on the snow contact layer presses the field).
    Second review:
    - **Wind-up height:** the wind-up is held on its exact frame through a `TimeSeek` in the action
      subtree (`hold_action_at`). The real-time timer had stopped it early at lower frame rates, with the arm low.
    - **Stance:** aiming turns Henry 60 degrees side-on, left shoulder leading, and the throw swings him back square
      to the target.
    - **Spring aim:** the aim point trails the camera's on a 3 Hz spring that overshoots a touch.
    - **Camera push-in:** the camera closes in over the shoulder to 0.68 of its boom on a 2.4 Hz spring, read
      through the new `AimIntentCapability`.
- TPS camera no longer sinks into the snow. The snow is not collision, so the boom sweep stopped only at the
  ground and the lens could end up under the snow top when looking up from deep snow. The lens now stays at least
  `snow_clearance_m` (0.25 m) above `SnowField.get_snow_top` under it.
  - **Launch:** `ThrowComponent.launch_direction` solves the low arc to the camera's aim point, and lobs at
    45 degrees when the point is out of reach.
  - **In flight:** `ThrownItem` strikes its first contact through the new `ThrowImpactCapability` (`core/contracts`).
    Snow bursts and is gone; a stone rolls to rest on ground damping and becomes a pickup again.
  - **Wall stones:** `StoneScatter` lays stones at the foot of house walls near Henry, from the building outlines.
    About 7 % of 4 m wall spots hold one, hashed by position so a wall's stones never move. A taken one stays
    taken through the `PickupLedger`.
  - New item: `stone` (0.35 kg). Tests: `test_throw`, `test_stone_scatter`.
- Snow by hand (#257, stage 1).
  - **F on open snow** with nothing else in focus: Henry stoops (`pickup_right_low`). A held empty mug fills with snow
    in hand, and a free hand takes a handful of snow (`snow_handful`, now actually produced in play).
  - **Refused** indoors or where less than 3 cm of settled snow lies underfoot (`SnowField.get_depth`).
  - **Signal:** `InteractComponent.interact_unclaimed` hands the unclaimed F to ground actions.
  - **Visuals:** the mug shows a heap of snow above the rim, and the handful is a lumpy snow clump instead of the
    placeholder parcel.
  - Item Use on a packed mug still scoops as before. Test: `test_snow_scoop`. Capture: `tools/runtime/capture_snow_scoop.gd`.
- 727 chimney and roof smoke (#252).
  - **Root cause of the break:** the stove's flue had a fixed length (`FLUE_H` 1.7 m) and stopped at 3.08 m under the
    3.66 m ceiling. The roof stack stood over the stove's centre, not over the flue, and was twice as thick.
  - **One continuous flue:** `StoveVisual.flue_length` and `flue_base()` let the shelter run the flue into the ceiling
    (`interior.ceiling_y`). The roof stack continues it on the same axis and radius up to roof + 0.8 m, with a cap.
  - **`ChimneySmoke` on the cap:**
    - it smokes only while the `HeatSource` burns, and its density follows the fire's intensity;
    - `chimney_smoke.gdshader` pulls every puff toward the air's velocity: the weather's wind with its gust, plus the plume's rise;
    - a gust therefore bends the whole plume at once. Godot's built-in damping cannot do this: it slows a particle
      by a constant amount instead of pulling it toward the air.
  - The road flare reuses the same noise-edged puff texture (`ChimneySmoke.puff_texture`).
  - Test: chimney checks in `test_key_west_727_shelter`. Capture: `tools/runtime/capture_chimney_smoke.gd`.
- Weather profile `clear` (no wind, no snowfall) for tests and captures. It is `manual_only`: it is set only by
  `set_weather`, never drawn by the weather roll (`WeatherProfile.manual_only`, `_pick_weighted` skips it).
- SPoV canned meat (owner's artist asset, `assets/source/spov_canned_meat/CanModel.rar`). `tools/blender/build_spov_can.py`
  builds `assets/items/spov_can/SPoV_Can.glb`: 10.4 x 6.1 x 7.1 cm (a 340 g luncheon-meat tin, the artist's proportions
  kept), 356 + 240 tris. The 40 lid-seam edges shared by three faces are split, and the pull ring is laid flat on the
  recessed lid at one end. The painted label is matte paper: the source Metallic map marked the whole surface metal,
  so the label is masked out of it. Items `spov_can` → `spov_can_open` follow the pineapple contract, with no tool
  needed: the first Use pulls the ring, the next eats 1,070 kcal (340 g x 3.15 kcal/g). The open can hides the ring
  and shows the meat. Owner: the emptied can is thrown on the floor. A new `ConsumableData.discard_leftover` tosses it
  as a falling body (`ConsumptionController.leftover_discarded`) instead of keeping an inventory item. No ring-pull animation yet; opening plays the existing `fix` action. One can lies on the
  bottom shelf of the 727 waiting-room cabinet, label to the door. The open-tin hint now names the ring or the knife
  (`ConsumptionController.open_action_key`). Test: `tests/systems/test_spov_can.gd`. Capture:
  `tools/runtime/capture_spov_can.gd`.
- Held lighter flame on RMB (`present_held`). While RMB is held, Henry raises the lighter before his chest
  (a second `StoveHandReach`, `PresentReach`, palm turned in), and after 0.3 s the flint wheel rolls and the flame lights.
  The lighter stands upright in the fist while raised; on release its authored HeldFit returns. The flame burns while RMB
  is held but goes out after 10 s anyway; a fresh press lights it again. The flame is now one node, `LighterFlame`,
  shared by the held lighter and the stove act. Capture: `tools/runtime/capture_held_lighter.gd`.
  Lowering fix (owner report: the hand jerked before letting go): the raised fist now keeps the hanging wrist
  roll (thumb up), so the hand no longer turns over at half weight. The arm eases down over 0.4 s. The lighter
  turns from upright back to its HeldFit in the hand's frame, so it no longer flips. Measured by a per-frame
  trace of the hand bone's roll axis.
- Authored lighter model (`assets/items/lighter/Lighter_game_ready.glb`, owner's asset) replaces the orange box
  everywhere: world pickup, held prop and the stove lighting act. `LighterStrikeVFX` holds it with the grip at the
  origin and the burner nozzle on its +Y axis; the flint wheel rolls on each strike. The flame is a tongue mesh with
  the stove log-flame shading (blue root, yellow body, view-facing edge, faded tip, `lighter_flame.gdshader`). It
  pivots on the nozzle and always burns world-up whatever the hand's tilt. At the stove the nozzle sits 12 mm under
  the tinder so the flame's middle licks it. Close-up capture: `tools/runtime/capture_lighter.gd`.
- Work gloves you can find and wear (#236, owner: the 727 cabinet). `tools/blender/build_henry_outfit.py` cuts
  `Outfit_Gloves` from the hands and fingers, from the wrist up under the sleeve, in dark leather brown. They are
  decimated to about 6,000 vertices and hide `Skin_Gloves` while worn. The pickup lies on the top shelf of the
  727 cabinet beside the mug (`GlovesShelter`), with a blocky pair as its world prop. The outfit now rebuilds with
  Blender 5.2 (`pip install bpy`); the previous meshes come out vertex for vertex.
- Wall thermometer in the 727 waiting room (#236), just inside the lobby arch (`WallThermometer`, nail at 1.7 m, placed
  from the landmark spec's furniture list). It is an ordinary glass thermometer on a board, hung by a wire loop from a nail, with a red column from −40 to +40 °C; the figure
  (`THERMOMETER_READING`, °C only) sits on a grey gradient plate below it and fades out between 2.5 and 3 m from Henry.
  It reads outdoor air plus its zone's warmth; the column and figure follow it smoothly. No interaction.
- Stove fire per log, ported from the `codex` branch (Codex's work, finished here). Each log has its own
  irregular geometry, char, flame and embers, plus weak ignition smoke. Henry's arm reaches in through
  `StoveHandReach` to take, insert and release each item. Tinder comes only from a Quick Access pocket or
  the hand, not the pack. Log poses and char origins survive save/load and refuel. `HeatSource` stays the
  only authority on fuel and heat. Codex's 11 MB of capture media stayed on its branch.
- Frostbite consequences (#236 stage 6, owner direction). Each body part gets frostnip, then frostbite, after
  its cold load is held long enough (0.6 for 20 min; 0.85 for about 36 min). The stage heals in warmth
  (frostbite over 6 h) and is saved. Six afflictions carry the effects:
  - numb hands slow fine work, so the lighter hold grows from 3 s to about 5 s and laying fuel takes longer;
  - frostbitten feet slow walking and allow no sprint;
  - frostbite drains health (4–5 per game hour, through the new `PlayerHealthSystem.drain`, without hit feedback).
  The modifiers reach movement, actions, fatigue and the stove through the new `StatusModifierCapability`;
  the three existing string-call readers moved onto it. `test_frostbite` covers stages, healing, afflictions,
  health, sprint, the lighter and gloves.
- Work gloves: a `hands_outer` slot and the `work_gloves` garment (insulation 4 °C, windproof 0.6). There is no
  visual mesh yet (needs a Blender outfit pass) and they are not placed in the world.

- Body part library (#236): `BodyPartDefinition` / `BodyPartLibrary` (`core/body/`, `data/body/`) describe the
  head, hands and feet. Each has its garment region, wind exposure, cold sensitivity, cold thresholds, HUD mask
  and bones. `ExtremityCold` and the HUD silhouette read the library instead of hard-coded regions.
  Wind now reaches each part by its own exposure and its cover's windproofing: the face takes the whole wind,
  booted feet about a third. A new part is data only. `test_cold_readouts` covers the library, the wind split
  and a data-only part.

- Daily air temperature (#236 stage 5): `ThermalManager` uses `data/climate/air_temperature_day.tres` when no
  curve is assigned (world.gd creates it in code, so it always ran flat at −18 °C). The air is coldest at
  05:30 (−28 °C) and warmest at 14:30 (−8 °C), with weather offsets on top. `test_cold_readouts` checks the
  extremes and the midnight wrap.

- Vitals HUD rework (owner design, #236; spec in `docs/technical/VITALS_HUD.md`). The round progress rings
  are replaced by gradient columns: a dark column fading upward and a state-tinted pigment over it that
  empties from the top, with a thin edge line and rounded bottom. Green, yellow and red blend across each
  threshold. The symbols stay half-tone until a vital nears critical. Trend chevrons sit above a rising
  column and below a falling one, doubled for a fast change. Body temperature and `FEELS ±N°` sit beside
  the warmth column. A faint front silhouette stands over it and frosts blue from the fingertips, toes and
  crown with the new extremity cold load. The block moved toward the corner: smaller columns, a larger
  health strip (260 × 16).
- Extremity cold (`ExtremityCold`, `ThermalManager.get_extremity_cold`): a 0..1 load on the head, hands and
  feet from felt cold, that region's garment insulation and its wetness (`EquipmentComponent.get_region_protection`).
  It is saved, warm sleep clears it, and it is a warning layer only.

- Floor snow prints (owner request): indoors Henry's boots leave white prints, the inverse of the snow print:
  white where the tread's grooves packed with snow outside, broken into clumps (`BootSole.floor_print_image`,
  the same lug pattern the snow shader presses). A step outside on snow fills the tread; each indoor step
  leaves 20 % of what it holds, so about ten prints fade out step by step, and the tread melts empty in about
  2 min in a 20 °C room. A print holds, then fades over its last half: 5 min in a 20 °C room, 25 min at
  0 °C (`FloorSnowPrints`, `test_floor_snow_prints`). The decal is a cube one sole long with the sole's
  shape in its texture: a thin, long decal box lost screen tiles of the print in Forward+ (seen on the 727
  floor; godotengine/godot#73945). The two prints bake in ~34 ms at load.
- Blizzard flow (`BlizzardFlow`, FUTURE_INTENT §10): blown snow as fog volumes on the wide streets
  (pavement ≥ 7 m, Key West's top ~15 % of road length) that run with the wind (|cos| ≥ 0.6, street-canyon
  channelling), up to six near Henry. Density is the blowing-snow extinction for the live 10 m wind, gusts
  included: Tabler's visibility V = 1.126e8·U^-4.85 m (TRB SR185) through Koschmieder 3.912 / V, capped at
  ~13 m visibility. It starts only past the snowpack's blowing threshold (5–10 m/s) with snow laid. Densest
  at the street and thinning with a 3 m scale height (body height); ~12 m billows with gaps and a 5 m tear
  octave advect downwind; volumes fade in and out over 2 s. Each billow core settles at the overcast it
  scatters (the environment ambient: Godot scales fog EMISSION by density), so the flow reads lighter than
  the air, not as dark bands as with a fixed 0.18 glow (measured at forced density). Flakes ride each
  volume and the ground streamers run along the flow streets, on screen only. Street centrelines come from the road ribbons `KeyWestRealityGround` already paves
  (`get_wide_streets`, `test_key_west_reality_ground`). The weather readout shows the flow.
- Key West mug model (owner request): `SurvivalItemVisual` draws `assets/items/mug/Mug_game_ready.glb` for the
  mug, mug of snow and warm water (held, world pickups, shelter cabinet) instead of the grey cylinder. The model is
  real scale (13 x 8.7 x 10 cm, base at 0); snow and water are a disc inside the measured 4.4 cm inner wall.
  Henry starts with the mug in the pack lid pocket instead of the pack, so one Quick Access pocket is free at start.
- Weather debug (debug builds, Key West), one key, 0. The first press shows the profile, scheduler or pin,
  blend, wind and drift gate, snowfall, visibility, cover, hour, sun beam, shelter state and the live streak,
  ground-drift counts. Each next press pins calm, snowfall, windy, blizzard in turn; the one
  after blizzard hands the weather back to the scheduler and hides the readout.
- Rooms frame Henry low-left (owner note): any room uses the tight composition and the camera rises until his eyes
  sit at mid-height (stove 29–30 % / 46–47 %, was 33 % / 37 %). Auto shoulder swap when the player's side is walled off
  and the other is free, with delays, never in doorways or during mouse turns (Sifu, a Borderlands 4 camera mod;
  Ghost Recon Breakpoint's complaints). Deoccluder-style hold measured worse and ships off. Open camera items are
  listed in `docs/technical/TPS_CAMERA.md` → Open items.
- Leeward wall drifts baked into the Key West wind map (owner request: the lee side of every house had
  deeper drifts, the windward side less).
  - `bake_key_west_snow_wind.py --reality`: ASCE 7-16 leeward drift per wall, height from the roof run along
    the wind (0.3–1.1 m at full cover, capped at half the wall), tapering over 4 hd; windward banks halved.
    `factor_max` 2.5 → 8.5. Chunk cover, clipmap rings and SnowField read the same map, so drifts are drawn
    and waded alike.
- Snow material and drift crests (testers: the snow read as jelly).
  - Causes, from close-up frames on Duval Street: no detail under the 2 m lattice and the ~0.7 m ripple, a
    near-uniform albedo (±3 %) and plastic specular, so shadowed snow was a flat blue fill; print floors drew
    topographic rings (`sin(depth × 110)` strata over lumpy floors) and glints were view-independent
    emission confetti. Deep trench walls showed agate rings; a debug render split albedo from normal and
    put them in the albedo: the shared painterly pass seeds its pigment noise with the surface normal,
    which on a curved trench wall sweeps through dozens of noise periods. Snow now passes the ground's up
    vector to that pass in both layers.
  - Now both layers share per-pixel grain on level snow (7 cm and 2.4 cm, each fading before a pixel spans
    it), albedo patches and grain hollows, ice facets that flash toward the sun in `light()` (none in shadow,
    none on packed floors), `SPECULAR` 0.3 and a cubic B-spline wind map for shading slopes. Print slopes use
    a three-texel Sobel without the outline jag; deep pits darken with depth; a boot's outline and tread are
    kept only on and around its sole, not where the wading body pressed deeper.
  - Lee drifts keep a trough at the wall foot (the lee eddy) and crest 3 m out, with only a 1-2-1 pass so the
    crest survives on the 2 m lattice; `factor_max` 8.5 so crests are not clipped.
- Snowpack firmness (owner request: furrows belong to fresh wet snow; a dry cold pack is a crust that breaks
  with difficulty, then the leg drops fast).
  - `SnowPresentationSystem.firmness` (saved): snowfall buries the crust, dry cold and wind harden it over a
    day, a thaw softens it. It sets the field's softness, crust strength and how deep and fast a broken crust
    drops; only loose snow (firmness < 0.5) lets the wading body and dragging toe cut a trench.
  - Tests in `test_snow_presentation`, `test_snow_resistance`, `test_snow_shell`; `snow-walk` CI runs both packs.
    Duval Street walk: fresh pack 3 plunges (drift pockets only), crust pack 29 with clean-walled postholes.
  - `snow-walk` reads the GPU print field under every standing boot (`SNOW_WALK_GHOSTS`) to chase the
    "walks through drawn snow without a mark" report: 0 of 509 boots in over 5 cm of snow left no print on
    this route, so the report is not reproduced here yet.
- Snowpack and boot prints (owner request).
  - `SnowResistance`: wind crust holds a boot until the step's load breaks it (strength varies in ~1.6 m patches,
    running breaks more), drifts hide soft pockets where a leg plunges almost to the ground; a plunge dips the
    stride and plays a crust snap. Collision stays on the ground. `test_snow_resistance`.
  - Prints are Henry's army boot outsole (`BootSole`): heel block, arched shank, ball, round toe, in both the
    persistent stamp and the contact soles. The packed field carries each print's sole uv, and `snow_ground` draws
    the exact outline and the lug tread per pixel.
  - `capture_snow_walk.gd` and the `snow-walk` job in `checks.yml`: TPS and leg-height videos of the walk.
  - Independent review (Sonnet agent + `/code-review high`): prints shade per pixel in coarse rings, narrower morph
    bands, no string `has_method`/`connect` seams, retry cap at the coast. It also caught that the wall lee ramps
    never ran over the baked map; they are now out of the drawn base until the chunk bake carries them.
- Henry is never see-through in play (owner rule). A body guard predicts where each mouse step would put the camera
  and soft-stops turns that take it closer than 0.8–0.6 m to his eyes (turning out is free); walking into a wall
  speeds up the shoulder lift; the framing offset follows the real camera distance; over the shoulder the view keeps
  his eyes inside the frame. The fade remains only as an emergency at 0.45 m. 727 trace: faded frames 0 in every
  phase (were up to 59). `docs/technical/TPS_CAMERA.md` → Body guard.
- Shoulder lift in corners (owner request): with little room behind Henry the camera climbs over his shoulder (70° up
  the orbit, view tilted 35°, pivot up to 0.3 m under the ceiling) instead of pressing into him. In the 727 corner his
  head left the frame in 1 of 240 turn frames (was 51) and facing the corridor wall in none (was 25).
  `docs/technical/TPS_CAMERA.md` → Shoulder lift.
- Tight-space camera composition (owner reference): Henry at the frame's left (eyes at 27 %) in cramped rooms, after
  Cinemachine Third Person Follow, Grossman's framing (NZGDC 2025) and Nesky (GDC 2014). Measured first with
  `tools/runtime/trace_camera_tight.gd` in 727: the composition followed the view (0.50–0.80 at the stove during one
  turn), a room search turned the camera 30° by itself, and the mouse stuck at −81° in the corridor. Now the
  composition reads room all round Henry (0.58–0.59), the shoulder offset scales with the boom (no lens shift, aim and
  walk share the centre), recompose eases with hysteresis, no automatic turns in tight spaces, and the doorway mouse
  stop applies only while Henry passes a door. `docs/technical/TPS_CAMERA.md` → Tight-space composition.
- Quick Access in tight spaces gathers in a cross at the screen centre (coats left/right, pack lid above, thigh below).
  The old diagonal orbit took each pocket's side from its projected anchor, so two pockets could land in one corner
  and overlap; places are now fixed and spaced from the real card sizes, and the cross is bounded as a whole.
- Stove fire burns unevenly (owner request). It catches small and grows with the `HeatSource` warm-up
  (0.08 -> 1 intensity, smoothstep): the firebox starts at 45%, the room light at 20%. At the nominal burn
  two Perlin layers replace the old sine product: a slow swell (~0.35 Hz, a little brighter or dimmer, never
  repeating) and fast flame jitter (~9 Hz); embers follow mostly the swell. Mean energies match the old ones.
  `test_stove_visual` now checks a dim catch and a nominal warmed burn.
- Interior shadow mode (owner request). Outdoors shadows keep the dry-brush edge. Under a shelter roof they
  return to the earlier value-noise edge (4186533).
  - `stylized_shadow_interior_mode` now feeds the shared shadow include and turns the brush mix down to 0.
  - `ShelterGradeBinder` fades it with the LUT, on `sheltered_changed` over `shelter_blend_s`.
  - 727 Fort St floor is dark old wood (`floor_old_wood_727.tres`), swapped for the glb `floor_vinyl` on import,
    so the stove shadows read on it.
- Colour grade crossfade (from Grok's `grok` branch).
  - Grok's rules are kept:
    - outdoor LUTs blend over ±0.5 h corridors at 05/07/17/21 h;
    - Shelter fades in and out over 0.5 s;
    - `blend_outdoor_profiles` and the capture tool.
  - His fullscreen blend pass is replaced. It graded the linear pre-tonemap image with the Environment adjustment
    off: a 0.22 mean colour pop at the start and end of every blend, and the painterly far wash was erased.
  - Now `LutBlendCache` bakes in-between LUTs for every profile pair on worker threads (UE4 CombineLUTs approach).
    The nearest of 16 steps goes into the Environment's own LUT; brightness, contrast and saturation lerp.
  - Ends match the snaps within frame noise (0.005 / 0.002). Each step is below 0.005.
  - `test_lut_blend_cache`; `docs/visual_fx_shaders.md` → Color Grade Blend.
- Dev street spawn (owner request): `World` → Developer tools → **Dev Spawn Street** picks one of ten streets from different parts of the island (Whitehead, Duval, Truman, White, Flagler, South and North Roosevelt, Sigsbee Road, Stock Island 5th Street and College Road). In debug builds Henry starts mid-street there instead of the scenario spawn. `KeyWestDevWaypoints.teleport_to` holds him until the street's chunk is live, the same way F6 does, then faces him and the camera along the street. Points live in `routes/dev_street_spawns.json`. Each sits on the centreline at the spot farthest from building outlines, on land: the minimum ground within 8 m is 0.16–2.71 m NAVD88, above MHHW. `test_dev_street_spawns` checks the dropdown against the file and each point against its generated chunk (live ground above sea level, outside every outline), and that Henry is held there. `capture_dev_street_spawn` takes a third-person frame per street.

### Fixed

- The sweater no longer shows through the jacket (owner: through the back and at the collar). There is
  no cloth physics, so the hidden parts of the inner layer are not drawn at all. This is the same
  layered-clothing technique that already hides the skin under the clothes.
  - **Hidden by rays:** sweater and turtleneck faces whose points the jacket covers are removed
    (`cull_covered`, 1007 + 383 faces). A point counts as covered when most of a fan of five rays along
    its normal, either way, meets the jacket within 8 cm, so a narrow seam gap does not count.
  - **Back half:** the sweater's back half goes too. The jacket has a real gap at the yoke seam, and the
    sweater's body is only meant to show at the open front.
  - **What stays:** the open front, the turtleneck above the jacket's collar and the edges tucked under
    the jacket. Checked front, side, back and walking.
  - **Turtleneck and lapels in front** (owner: the collars crossed in front). The turtleneck's limits by
    the skin and the jacket are now measured where each point really is: its top dips to the front, but
    it used to be measured at the ring's back height. They are re-applied after smoothing, so averaging
    cannot carry the knit back out through the jacket. The few roll faces the lapels still lie across
    are dropped (`cull_crossing`). Collar-to-jacket crossing face pairs in the rest pose: 257 (170 in
    front) → 0.
  - **Turtleneck and jacket collar at the back** (owner: the turtleneck cut through the jacket's
    collar). The turtleneck followed the neck and head, while the jacket's collar hangs on its spring
    bones, so the two parted whenever the head moved. Inside the jacket's collar, and 1 cm past its edge,
    the turtleneck now takes the jacket's weights, easing back to the neck's over 3 cm above. Skull
    weight goes to the neck. `follow` now creates every source bone's group first: before, the transfer
    silently dropped bones the target lacked, such as the collar springs.
    - Crossing face pairs in clip poses (idle, walk, sprint, crouch): 160–214 → 4–18. In-game captures
      from behind, walking and sprinting with the springs live, show none.
  - **Turtleneck closes on the neck under the chin** (owner). It is now built round Henry's own neck,
    which is long and thin, instead of the mannequin's, which his head replaced. It is no longer culled
    as "under the jacket", since it shows from above and in the open front; only the few faces that
    cross the lapels go.

- Henry's knee no longer snaps backwards for a frame when he walks in snow. `LegTwoBoneIK` now bends the
  knee in the leg's own hinge plane. Before, it bent towards whichever side of the new hip-to-target line
  the old knee lay. A big snow lift put the knee behind that line, so the solve folded it back. Traced on
  Duval Street: before the fix the knee went from +253 mm ahead to −201 mm behind and back again. This
  happened at peak swing (about 90° of knee bend), always after `SnowFeet`.
- Henry stands still at idle (owner: arms swayed and the chest heaved all the time). The idle and crouch
  idle clips keep only a share of each bone's swing about its mean pose: 40% in the chest, 30% in the
  neck and head, 15% elsewhere. Measured live over 3 s: arms 3.2–3.9° → 0.6–1.0°, shin 5.5° → 1.3°,
  chest 1.9° → 0.5°.

- Jeans crotch (owner: "штанина косяк"): the drape left a web between the legs, reaching 11 cm below
  the crotch, which stretched into a tab or bar on every step. The build now lays that web on the body
  (`close_crotch`) and raises the inseam onto the crotch (`raise_seam`). Below the crotch each leg follows
  only its own leg, and the seam follows the pelvis. Checked standing and walking, front and back.

- TAB (Hub) showed the dev map's labels (house numbers, street names) around Henry (owner review).
  `PlayerHubComponent` made a fresh `HubCamera` with the default cull mask, which includes the
  reserved layers (`DEV_MAP_LABEL`). It now takes the game camera's cull mask, environment,
  attributes and compositor; `test_player_hub` checks the mask.
- The owner's sound recordings were barely heard and synthetic layers still played (owner review).
  - **Levels:** the recordings are about 18 dB quieter than the synthetic banks the mix was set for
    (footsteps -35.7 against -17.9 LUFS, EBU R128; mug peaks -20 against -4 dBFS). Each bank's
    `volume_db` now adds that measured difference: footsteps -9 to +8.8 dB, mug -10 to +6 dB.
  - **Pitch:** depth pitched the footsteps down to 0.82 (a fifth lower), so they no longer
    sounded like the recordings. They now play at their own pitch; depth shades only the level.
  - **Synthetic layers removed:** the `snow_squeak` and `snow_pull` banks, their WAVs and
    `tools/audio/generate_snow_footsteps.py` are gone. A play trace on Reality now shows only the
    owner's footstep and mug banks.
- Pack pockets and the hand (owner review, #260).
  - **Shown twice:** a hammer drawn from its sleeve stayed drawn in the sleeve too. The pack now
    leaves out the pocket whose item a hand shows (`QuickAccessComponent.get_held_source_zone`).
  - **Pockets traded contents:** `draw()` put the held item away and then still traded pockets with
    the stale source, so the thermos moved into the hammer's sleeve. The pack's pockets are fixed
    places and no longer trade; coat pockets still do. Stand rule R15; `test_held_weight` keeps its
    trade on coat pockets now that the loadout puts the hammer on the pack.
- Pack hitches after the backpack merge (owner FPS capture, #260). Measured on Reality with Henry
  starting, stopping and turning (560 frames, headless):

  | | mean | p99 | max |
  |---|---|---|---|
  | before the merge | 7.4-8.2 ms | 15.5-16.6 ms | 18 ms |
  | merged | 14.2 ms | 31.7 ms | 40 ms |
  | now | 8.4-9.3 ms | 17-19 ms | 21-26 ms |

  - **Hanger contact:** peaks of 8-13 ms in one frame came from the hinge search (up to 66 angles,
    each over every point). Newton steps now find a clear turn and bisection backs it off; points
    over 6 cm from the obstacle are left out after the first pass. Peaks are about 4 ms.
  - **Straps:** about 5,000 per-vertex `ImmediateMesh` calls a frame became one indexed upload
    (8 vertices per point, cached indices): 1.1 ms to 0.4 ms.
  - The GPU's ~110 ms on the HD 620 is the Reality world, as before the merge. The whole pack is
    25k triangles.
- Backpack zipper spammed `det == 0` errors when fully open (owner review). A slider past the
  seam's end sampled two clamped points, so its tangent was zero and the tab basis degenerate. The
  seam run is now clamped to its length; 50 errors per 120 frames before, 0 after.

- Wind gusts ran about 100x slower than their profiles say. `WeatherController` samples its gust noise at
  elapsed / `gust_period_s`, but the noise kept FastNoiseLite's default frequency of 0.01. A 5 s gust period
  therefore took about 8 minutes, and in a minute of "windy" the wind moved only 11.00 to 11.19 m/s. The noise
  frequency is now 1, so one unit is one period: the same minute sweeps 8.86 to 13.09 m/s. This affects
  everything that reads wind: chimney smoke, blowing snow, breach drafts and wind chill. Test: `test_weather_gusts`.
- TPS camera steps in doorways (#240 stage 3 v2). The camera no longer flips to the other side of a door plane
  while the doorway holds the frame. A neighbouring door waits until the current one lets go, a hand-over's
  shoulder step is eased out, and a doorway may pull the shoulder at most 0.5 m off Henry. On the 727 route, real
  jumps over 0.3 m fall from 3 to 0, and `test_doorway_camera` no longer pops on the yaw swing. The tight-space
  trace is unchanged.
- A room Henry is not in now keeps warming or cooling. `ThermalManager` advanced only the zones Henry's probe
  overlapped, so a room left with a dying fire stayed as warm as when he walked out. Every loaded `ThermalZone`
  now advances (`ThermalZone.get_all()`); the wall thermometer made the stale reading visible.
- Negative temperatures in IM Fell English SC (FEELS, the thermometer) use an en dash: the font has no minus sign and
  draws "-" like a tilde (`TemperatureText.signed`).
- Stove transfers and the lighter hold no longer depend on where the IK palm lands. In the first port a log
  was laid only when the solved palm was within 4.5 cm of the target. In the 727 shelter workflow the arm
  stopped 0.44 m short and the log was silently never laid. Contact is now a point on the act's timeline;
  the arm only presents it.
- Pocket takes keep an item's runtime state. The flare rollback (`HeldOwnership.take` / `restore`), stove
  fuel and eating now use `take_pocket_instance()`; the id-only `take_from_pocket()` refuses stateful items,
  so those paths would have silently failed once items carry state.
- Warmth colour now follows the hypothermia stages (yellow from CHILLED 36 °C, red from HYPOTHERMIC 33 °C).
  The generic 66 %/33 % ring thresholds left 31 °C (the CRITICAL stage) yellow.
- Felt temperature is computed on world ready and on load. Before, it stayed 0 °C until the first
  quarter-hour clock step (about 19 s after a start or load), so `FEELS` would have read +0°.
- Room warmth survives streaming and saves: `ShelterState` stores each zone's accumulated fire heat and
  restores it (`ThermalZone.restore_heated_offset`). Before, a warmed house came back cold.

- Item integrity (Codex, e63bee8e; reviewed in #70): `ItemCatalog` no longer lets a repeated definition id silently
  replace the first (`validate_entries()`, an error at index time). A stackable item refuses an `instance_state`
  instead of dropping it. Pack ↔ pocket moves in the Hub and Quick Access swaps carry each item's state
  (`stow_instance`, `take_pocket_instance`, optional `pocket_states` in the equipment save; old saves load).
  id-only `take_from_pocket` refuses a stateful pocket item rather than erasing its state. `test_item_integrity`
  covers it (fixture now runs on the first frame, so the coat's pockets exist).

- Stove ritual edge prompt (owner request): F no longer makes the centre prompt vanish. Its brackets part to
  the screen edges (72 px in), the yellow strip splits into its two halves, one by each bracket: `[F] BACK`
  on the left, `STOVE` on the right. Any `InteractiveArea` can offer this through `get_session_prompt_data()`
  while it sits in the `active_work_session` group; the stove feed does from the door opening to F.
- Stove ritual (owner request): the ring no longer climbs to the top screen edge (it was lifted 70 px over a
  point 1 m above the cooktop, then clamped); it now sits at the bottom centre, 200 px above the lower
  edge (`bottom_offset_px`). The work view no longer turns sideways with the mouse (pitch only, 12 degrees): a
  left turn brought the eye into Henry's head and faded his body out. `test_stove_ritual` checks the lock.
- Quit to title from the stove ritual logged two errors: the ritual's teardown restores `PlayerState` to
  ON_FOOT after the key hints panel has left the tree, and the panel rebuilt itself detached. The panel now
  ignores mode changes outside the tree (`test_key_hints_teardown`).
- Boot tread readable at play distance (owner: the print "sometimes seems invisible"). The snow shader switched
  the lug pattern off once a pixel on the snow passed 2–6 mm; at the shipped render scale (0.77, FSR) a fresh
  print 2.5 m from the TPS camera spans 4 × 8 mm pixels (measured), so the tread showed only in steep
  close views. Now the pattern blends to its mean shade (lugs cover 34 % of the sole) between 4 and 11 mm
  pixels, measured as the pixel's area on the snow, the way a mip chain filters a texture; groove shade
  0.1 → 0.28.
- Spindrift removed (owner: the plume "bubbles" do not fit). `SnowSpindrift` and its spawning in `WindGusts`
  are gone; the original ground streamers stay. The blowing-snow threshold (`WindGusts.blowing_snow_threshold`)
  stays for the blizzard flow.
- A square of snow around Henry at scene start, then a hitch and it vanished (owner report). Road paving
  had been queued ahead of the chunk snow covers, so no cover was built (measured: 0 of 4 at frame 60)
  while paving ran. Henry's rings drew a square of snow over bare terrain until the queue cleared and the
  cover under him landed in one frame. Covers and paving now run side by side on their own budgets
  (3 ms / 1.5 ms), the cover under Henry first. The field rebuild that follows paving is sliced like a
  walking move instead of done at once.
- Quick Access cards overlapping at some camera angles (owner note).
  - Cause: the layout blended spread and cross by how much the cards overlapped, so a partial overlap gave a
    partial blend that left them on top of each other (`test_quick_access_layout`: 71 overlaps on the old code).
  - The layout is now spread or cross, never a mix; crowding or a tight framing latches the cross, and leaving
    it needs twice the clearance, so it cannot flicker. Same test: 0 overlaps over 7 distances × 12 angles.
- Quick Access drew an item into the hand while its pocket card still showed it. Drawing another pocket now
  trades places: the drawn pocket keeps the held item, the hand shows the new one, and the pocket whose item
  is in hand reads empty (`QuickAccessComponent.draw`, covered in `test_held_weight`).
- Ground drift passed through roofs: its particles had no collision mode (default off). They now collide
  with the snowfall height field, which also stays up in wind without snowfall. Streamers no longer start
  under a roof or a canopy.
- Static shadows' torn outlines boiled on every camera tick. The three-tone cut used hard `step`s, so the TPS
  camera's sub-millimetre damping moves flipped whole contour pixels each frame; the cascades themselves are
  texel-snapped and hold (measured). The cuts are now one pixel wide (`fwidth`): contour pixels changed by a
  1 px move fell from 0.112 % to 0.025 % (0.023 % with no stylisation), the torn look unchanged.
- Static shadows jumped every 2.5 s: the sun's direction was re-aimed every game minute (0.25° of azimuth, about
  11 cm at the tip of a 25 m pole shadow), and stable cascades hold only while the light does not turn. The sun
  now turns once per `sun_step_minutes` (4 game minutes, 10 s at the 60-minute day), eased over
  `sun_blend_seconds` (2 s); loads, clock jumps and acceleration snap (`test_sun_steps`).
- Snow under Henry's feet could stand 20 cm off the drawn snow. Measured at the Duval spawn: field top minus
  lattice ground 0.41 m against a drawn 0.21 m. SnowField sampled ground before the chunk streamed in
  (`KeyWestRealityGround.FALLBACK_Y` 1.0 m against 0.8 m real) and kept that cache across window moves. The
  shell now notes cells sampled off live ground and rebuilds the field in place once that ground streams in
  (same retry scheme as the chunk lattice); after the fix 0.211 against 0.209. Depth, and so how far a boot
  presses, is now measured down to the true terrain where its 1 m corridor tiles rise above the 2 m lattice
  (`test_snow_shell`). The crust lip (`rim_at`) is gated to crust: on loose snow its 8-tap rings drew echo
  contours around every print.
- Boot prints on streets showed white holes in the forefoot and heel. Measured at the Duval spawn: snow top
  1.011 m, road ribbon 0.876 m, terrain 0.802 m, so a full press (give 0.179 m) put the print floor 4 cm under
  the asphalt and the road mesh drew through it. Road ribbons are exported as DEM + 5 cm sampled every 32 m, so
  their lift over the terrain varies. `KeyWestRealityGround` now rasterises each chunk's road triangles into a
  copy of its height tile (frame-budgeted, the chunk under Henry at once). The new `get_surface_height` is
  the ground snow depth is measured to; decks over 0.3 m stay the physics ray's. The field rebuild retry
  also never fired when the first build already saw unstreamed ground (its counter began at 0); every fresh
  build now arms it (`test_key_west_reality_ground`).
- CI: report uploads (`suites` log, capture previews) no longer fail the run when the repository's artifact
  storage quota is full; every suite had passed on `main` while the job showed red for the upload alone.
- CI report artifacts (captures, videos, suite logs) are kept 3 days. The suite log and the Reality reports had
  no `retention-days`, so they stayed the default 90 days on every push and filled the storage quota. The
  GDExtension binaries keep their own retention: the local installer downloads them.
- Outer snow cover no longer crawls or pops while Henry walks (owner report; Codex's `codex` attempts kept the moving square).
  - Cause, measured with a fixed top-down height witness on Duval Street: the shell was one graded square mesh
    that jumped 3.2 m with the field window and blended into the chunk cover over a window-relative 6 m band.
    Each jump put every world point under different vertices and blend weights; the drawn height changed only
    on window moves.
  - Method (Batman: Arkham Origins, GDC 2014; God of War Ragnarök): one base snow surface everywhere, only
    Henry's deformation is local. With the chunk lattice the rings draw exactly the chunk cover's surface (terrain
    on its 2 m triangles + settled depth and wind ridges) and shading (`snow_far_shade`), plus prints that fade
    4.5–6 m out. A first pass blended a field-based near surface into the chunk one by distance; it breathed in
    a 4–8 m band (10.1M pixel-steps over 2 mm on the witness) and was replaced.
  - `SnowClipmap` rings: spacing doubles from 3.1 cm, the mesh follows Henry snapped to its coarsest spacing and
    morphs ring to ring by distance (geometry clipmaps, Losasso & Hoppe 2004; CDLOD, Strugar 2009). The chunk
    cover yields inside 6.25 m through the `snow_lod` global. SnowField mirrors the base for Henry's feet.
  - Wind relief: sastrugi with a steep lee face replace the blotchy ripple, the same in both layers and in chunk
    geometry; slopes are analytic (one noise lookup with its gradient).
  - Witness on Duval Street, 88 frames: largest step main 453 mm → first pass 43 mm → one base surface
    0.06 mm; steps over 2 mm and coverage flips 0 in every distance band. GPU on lavapipe 1347 → 1754 ms
    median (+30 %, software rasteriser).
  - The blue, sunken square in captures was the capture hiding every Control, including the snow passes'
    ColorRects: the shaped field stayed at the clear colour (7 cm packed everywhere). Captures hide only root UI.
  - 53k vertices on high instead of 113k. A/B evidence: `checks.yml` `snow-surface` job (new vs `main`).
  - `test_snow_clipmap` (CPU emulation of the vertex morph), `tools/runtime/capture_snow_surface.gd` +
    `analyze_snow_surface.py`, `checks.yml` → `snow-surface` job; `docs/technical/SNOW_COVER.md` → Drawn surface.
- The 727 corridor (1.8 m wide, doors on both sides) was guessed as a 1.76 m deep doorway, so the mouse soft-stopped
  in its cone along the whole corridor. Guessed openings deeper than `max_guessed_depth` (1.2 m) are corridors.

- 727 Fort St shell (walls, partitions, floor, ceiling) shades with the stylized shadow contract again. Reality chunks
  instanced the glb with its plain `StandardMaterial3D`, so indoor stove shadows lost their torn edge after the shelter
  moved from the First Exit hut into 727. A post-import script (`tools/import/stylized_landmark_import.gd`) converts
  the surfaces; `test_key_west_727_shelter` checks them.

- Editor docks no longer stretch the editor past the screen: ItemFitter (min 360×760) and Reality scroll inside their
  tabs. Godot AI dock: its one-line labels and buttons clip with an
  ellipsis. The 4.3.0 self-update had reverted its Inspector-group slot; restored. Customizations are listed in
  `docs/technical/GODOT_AI_INTEGRATION.md`.

- Godot AI and ItemFitter now default to the Inspector dock group instead of a separate lower-right group. Existing editor layouts retain their saved placement.
- Sky weather character, finishing Codex's cloud pass (owner review: windy clouds and the night barely differed).
  - Causes:
    - clouds followed snowfall only, so windy (snow 0.15) looked calm;
    - the sky shader's sun term is scaled by a Beer transmittance of about 0.02, so clouds had no lit side and
      read as dark smoke;
    - night clouds were black on black;
    - the volumetric fog and the paper-white wash greyed the night out.
  - Now `PainterlyDayNightManager`:
    - wind sculpts bodies (contrast, bellies, size, clearer air over them);
    - snow closes the deck;
    - a blizzard veils it;
    - the moon lights the deck at night.
  - New sky uniform `cloud_top_light`: a directional self-shadow, one height sample toward the light, gives lit tops
    and dark bellies.
  - The wash and paper colour follow daylight (paper → ink), and darks lift toward it.
  - Petronia Street capture, Codex → now:
    - Night sky mean: calm 0.195 → 0.054, blizzard 0.768 → 0.338 (no more white night sheet).
    - Night windy cloud local contrast: 0.0121 → 0.0232.
    - Day windy: 0.0122 → 0.0137. The day change is smaller because the camera sees mostly the hazy horizon band.
  - New `test_sky_weather_character`; `capture_sky_weather` shoots eight states (snowfall added). Rules in
    `docs/visual_fx_shaders.md`.
- Physics back on GodotPhysics3D (owner decision after the play test). Jolt ran slower on the owner's machine, with more hitches and erratic snow contact. `project.godot` names the engine explicitly; the Jolt measurements stay in `REALITY_HLOD.md`.
- Painterly wash erased every transparent surface. The pass reads the screen texture (opaque geometry only), writes every pixel and drew last among transparents (`render_priority = 127`). Falling snow and the 727 frosted glass vanished under it, and the owner saw no snow and a clear 727 window. Test pane: 127 → (0.74, 0.75, 0.76), the pane gone; −128 → (0.95, 0.35, 0.36). The pass now draws first among transparents (`render_priority = -128`).
- Painterly wash strength follows snowfall (owner rule): new `wash_strength` mixes the pass with the untouched frame, 10 % in calm weather up to 100 % in a blizzard (`PainterlyAtmospherePass.wash_strength_for`). Before, the full wash showed in calm weather too. `test_painterly_sky_rule` checks the curve, the live binding and the draw order.
- Main scene start moved to the 727 shelter (owner, 2869065b: `spawn_at_shelter = true` in `key_west_reality.tscn`). That commit also left stash-conflict markers in `project.godot`, so Godot could not parse it; resolved with `snow_field` kept in `[shader_globals]`. `test_key_west_reality_fresh_checkout` asserted a bunker start. It now checks the start the scene chooses: within 12 m of the route's `727_fort_st_entrance` goal with `spawn_at_shelter`, else before the bunker door. Both branches pass.
- Ground lost under the start after island-wide HLOD (CI `key-west-reality` red on f8082a57: the dev teleport trace had 9 of 9 targets wrong). At boot `KeyWestRealityGround` indexes every node in the stream container. HLOD cluster scenes carry their source chunk's `chunk_id`, so indexing a cluster dropped that chunk's terrain and building outlines. With HLOD only in Old Town the start chunks never had clusters; now `-8:3`, `-8:4` and `-9:3` do. Effects: heights fell back to 1.0 m, the F6 wait never ended, and snow ignored the fort-area outlines. A node with `cluster_id` is no longer indexed; its buildings are already in the chunk root's `snow_footprints`. `test_key_west_reality_ground` checks that a cluster leaves its chunk's ground and outlines. Trace after the fix: 0 of 9 wrong.

### Changed

- Road flare at night (owner picked variant C). The light's volumetric-fog tint drops from 1.0 to 0.3: the
  default tint filled the night fog with a red haze, which was the main cause of the "everything is red" read.
  Falloff is now inverse square (`omni_attenuation` 2), and the radius no longer breathes with the burn. All three
  are `HeldFlare` knobs (`fog_energy`, `light_attenuation`, `range_breath`). The particles are rebuilt:
  - the tip burns as a steady short jet (white core to orange to red);
  - sparks and spurts are streaks aligned to their velocity;
  - the large bits are slag that falls and cools;
  - smoke is a plume of 96 faint, spinning, noise-edged puffs. Before, it was 42 round quads that read as glowing balls.
  Capture: `tools/runtime/capture_flare_night.gd` (A/B/C outside, close-up frames, inside 727).
- TPS camera look-ahead v2 (#240 stage 5). The orbit centre leads along Henry's intent (the keys' world
  direction, `LocomotionIntentCapability` published by `Player`) and fades while intent and motion disagree; it
  shrinks 2.5x faster than it grows. Sprint reversal in the corridor: the lead no longer stays 0.44 m ahead while
  Henry brakes; worst lead against motion 0.15 → 0.02 m. The tight trace gains a corridor `reverse` phase.
- TPS camera keeps Henry's eyes inside the frame's lower edge when he is off to the side (#240 stage 4 tail).
  `keep_eyes` measured the eye angle over the full distance instead of depth along the view, so off-centre eyes sat
  at the bottom edge (restroom, backing in: y 0.98). Now exact (`TpsRigShoulderLift.eyes_pitch_limit`): tight trace
  eyes at the bottom edge 70 → 0. Stage 6 (context interests) waits on hazard data: `IceField` is not placed in any
  scene and there are no edge markers.
- `test_doorway_camera` is green (#240 stage 7), two runs; it is off the known-failing list. Standing in the door and
  looking up, the camera lost Henry in every frame of the 30° sweep (and 170 of 750 at 10°). On the doorway's short
  boom the camera barely dropped, unlike outdoors (checked: 0 lost frames 5 m outside). Now it drops as far as
  Henry's middle needs to stay inside the frame's lower edge (`TpsRigPassage._drop_pitch`). It also lost him sideways
  at the soft stop, which assumed he sat mid-frame; the stop now subtracts the angle the shoulder offset puts him off
  centre. The route trace snaps the camera on its own stuck-Henry teleports, as the dev waypoints do, and skips
  those frames: the 727 route now meets all three #240 criteria (no step over 0.3 m; largest 0.28 m).
- TPS camera swings round Henry in tight space (#240 stage 4, part 2). Shot choice now scores lift caps × orbit
  swings (0, ±20°, ±40°; the view stays the player's), adds a cost for Henry's eyes off the left or right edge, and
  is off in doorways. The prediction now follows `keep_eyes`' pitch limit, the side recompose leaves and Lyra's
  feelers (`TpsRigCollision.target_shares`). Without the recompose term it chased a wrong frame in a 20-frame cycle.
  Tight-space trace vs part 1: eyes off screen 11 → 0, within 0.8 m of the eyes 1,440 → 141, faded 0, bottom edge
  81 → 70. Along walls the camera stands off to the side and shows the corridor. 727 route: no real jumps.
  Backing into the exam corner or the restroom still looks down from above.
- TPS camera picks how far to lift over Henry's shoulder in tight space (#240 stage 4, part 1). Four lift caps are
  scored on a stateless prediction of the frame and eased with hysteresis. Along walls the camera now stays at the
  shoulder instead of looking down from above. Tight-space trace: eyes off screen 57 → 11 frames, at the bottom
  edge 543 → 81, faded 10 → 0. The exam corner and the restroom still lift; authored room hints are next.
- TPS camera rig split into behaviours (#240 stage 2). `_update_rig` now runs `TpsRigFollow`, `TpsRigAutoSwap`,
  `TpsRigComposition`, `TpsRigPassage`, `TpsRigShoulderLift`, `TpsRigRecompose`, `TpsRigCollision` and `TpsRigWork`
  on one `TpsRigFrame`, each owning its state and smoothing. Behaviour is unchanged: the 727 route trace and the
  tight-space trace match their pre-refactor output byte for byte.
- `tools/runtime/trace_camera_route.gd` (#240 stage 1) measures the camera on a 727 walk. It records eyes in frame,
  fades, jumps over 0.3 m, wall share, the share of the frame Henry covers, and mouse deviation.
- Hammer held fit re-authored by the owner in the Item Fitter: right hand, offset (-0.025, 0.08, -0.005), rotation
  80° about X. `test_held_fit` now pins this fit.
- Work gloves restyled after the owner's reference: an olive back, tan leather at the knuckles and fingertips,
  a dark palm, and an insulated dark gauntlet over the sleeve (`Outfit_GloveCuff`) with a strap and a red pull tab.
  Panels are flat colours painted per face and settled by a neighbour vote so decimation leaves no specks.
- The top-right "Room air" HUD readout is gone; the 727 wall thermometer replaces it (owner, #236).
- Stove look after the owner's review of the 727 capture:
  - flames are about 40 % taller and denser, and a caught log grows to full burn in 6 s instead of 10;
  - the shelter colour grade is 12 % brighter, so the room before ignition reads (frame mean 54 to 61 of 255);
  - the stove ring sits at screen centre, 100 px down;
  - the F BACK / STOVE prompt keeps its place but drops to 60 % opacity during the session.
- Stove ritual framing (owner: "we saw nothing inside the stove or what Henry does"). The TPS camera stayed high
  behind Henry, his back hid the door, and the iron stove was lost on the dark floor. The same TPS camera now
  eases onto a work framing while the door is open (`TpsCamera.set_work_framing`), the owner's composition:
  close over Henry's right shoulder, shoulder lower left, head left, firebox mouth mid-frame, door on the right.
  From behind, Henry kneeling square to the door hid it with his back, so he now kneels 0.3 m off the door axis,
  turned to the mouth, and the door folds back 160 degrees (was 105, swinging toward the camera).
  The stove's "Use" prompt no longer shows during the ritual. The mouse orbits it a little, walls still
  shorten the boom, and F eases back to the follow rig. No separate mini-game camera.
- 727 floor lighter and warmer (owner: stove and floor merge). The floor's real material is the external
  `floor_old_wood_727.tres` (the glb's `floor_vinyl` is remapped in the import), 0.23/0.16/0.10 to 0.40/0.29/0.18
  against the 0.13 iron. The earlier glb tint (6e90bb3) changed the remapped-away colour and showed nothing;
  reverted with its tool.
- Stove ritual replaces the stove's F cycle (owner spec). Before: F opened the door, the next F loaded the whole
  armful and readied the lighter, and RMB took cold logs back. Now `[F] Stove` walks Henry to a
  `StoveInteractionPoint` in stove space (the player's own scripted walk, no teleport, refused when his capsule
  does not fit). He turns to the door, it opens, and he crouches with or without a load: a new `CrouchCarry`
  state keeps the carry arms over the crouch legs. `PlayerState` WORKING roots him, the interact key is claimed,
  and the TPS camera stays. A three-arc ring (`StoveInteractionRing`, the pickup marker's language) shows fuel
  (one tick per log of the real capacity), tinder and fire.
  - RMB lays exactly one log per press. The inventory and `HeatSource.add_logs(1)` change together when the
    act completes; a cancel moves nothing.
  - LMB lays tinder, only with a log in. The press that laid it never reaches the lighter: release, then a new
    press strikes the existing lighter, and a 3 s hold lights the stove.
  - Logs can follow the tinder. A burning stove takes logs without relighting.
  - F closes the door and stands him up.
  - Tinder is new `HeatSource` state (`tinder_prepared`). It is saved and recorded by `ShelterState`, and kept
    when Henry leaves.
  - The work pose backs down instead of standing up through its clip while Henry stays crouched.
  - New `StoveInteractionController`; `HeatSourceFeed` keeps only the acts. `test_stove_ritual` covers the 12
    owner scenarios; `test_shelter_workflow` is updated. `capture_stove` now runs in 727 (it used archived
    Graciosa). Doc: `docs/technical/STOVE_RITUAL.md`.
- Window frost forms and thaws like real fern frost (owner: not natural). Before, one mask served both
  ways: the frost edge was a noisy band at a fixed distance from the frame, so growth and thaw were the
  same rectangle moving in and out (a square hole at 50 %). Now each texel has two dissolve thresholds.
  Growth starts at the bottom edge (cold conducts along the glass edge and cold air slides down it), then
  the sides, the top last, plus a few nucleation points (scratches, dust). The reach varies round the
  rim (seamless noise in angle): frost tongues far in on one side and hugs the frame on another
  (owner: not evenly from the edges). Fern fronds lead the front:
  tapering spines with barbs at the ice's 60°, two sizes. New frost is thin and turns opaque as it
  ages. Thaw clears the warm centre first along a soft, wet front. The thick fronds and the cold bottom
  corners go last (FUTURE_INTENT §3, frost retreating to the edges). Measured on the pane mask: 50 % left
  at thaw 0.55, 10 % at 0.80. The pattern is metric (pane size from screen derivatives), so the 727's
  wide panes no longer stretch it. Fronds far from the frame point any way, which removed a rosette at
  the centre. Barbs smaller than a pixel blend to their mean instead of aliasing. Random, never preset
  (owner): the 727 draws its frost afresh each load (`growth_seed`) and a new thaw path each time the room
  starts to warm (`melt_seed`, swapped while warmth is 0 so nothing jumps). `frosted_glass` (727) thaws
  as the stove warms the room; the generated `frosted_window` uses the growth mask.
- Ground drift travels as a wave (owner note: it appeared in place, straight). Each `SnowLift` streamer is now a
  sweep: the emitter runs downwind for 1.6–2.4 s at 0.45 of the 10 m wind along a shallow arc (bow 5–9 % of
  its length, side at random), snapped to the ground, shedding its four layers into a world-space trail that
  swells in and dies out. A 12 m/s sweep is ~9 m (was a fixed 5 m patch); it ends at a kerb over 0.6 m or a
  slope. A sweep starts only when its start, middle and end are on screen and it crosses open snow (no
  footprint at either end, no canopy over the start). Both drift sources use it: the wind drift ahead of Henry
  and the blizzard flow streets (`test_snow_lift_sweep`). The head now rides the drawn snow top
  (`SnowField.get_snow_top`): it stood on the physics ground, 0.23–0.49 m under the snow at the Duval spawn
  (measured), so the grains were buried and the drift barely showed on snow. On lit snow the grey grains
  (0.8) still matched the surface, so the grains are lighter (0.95) and the sweep drags a soft cool shade
  over the snow under its trail (owner's idea from the spindrift round). The technique is a moving emitter leaving a world-space
  trail (Godot `local_coords = false`), as trail emitters do.
- The world shows finished (owner note: a square of bare snow at start that went away a minute later). The
  startup card now holds until boot work is done, through a new `BootLoadCapability` (`core/contracts/`):
  `KeyWestRealityGround` reports the chunks live at boot until their paving and snow cover are built, and
  builds them at full speed under the card; `SnowShell` reports a pending re-read of ground that streamed in
  (weather rebuilds do not count: the old window stays drawn, and in a blizzard they run all the time).
  The card waits at most 30 s and logs who was still pending. A field sample over ground that never streams
  (open sea past the chunks) is not boot work: it held the first run at the 30 s cap.
- In falling snow the sun dims with visibility (Koschmieder extinction 3.912 / visibility over a 30 m beam
  path): ~7 % of the sun in a 45 m blizzard, ~59 % in 220 m snowfall, 75 % in 400 m windy weather. The lost
  beam returns as ambient fill, 0.3 per unit of lost sun, in the sun's own colour (snow scatters it
  unchanged) and never in shelters. 1.86 in grey washed out the LUT grade (ambient 3.1 against a 0.55 base);
  the sky tint at 1.8 turned a blizzard blue; 1.2 in the sun's colour made a blizzard 132 % of clear day.
  Measured on snow at the Duval spawn (linear): 81 % of clear day in windy weather, 74 % in snowfall, 53 % in
  a blizzard, with the clear-day colour balance (blue minus red 35–38 against 33). Before, a blizzard kept full sun and hard shadows (`test_sun_steps`).
- Fort Zachary Taylor collision simplified in Blender: `tools/blender/landmark_collision.py` (Blender 5.2 `bpy`, Decimate Collapse 0.2) adds a `FortSurfaceCollision-colonly` copy of 8,238 faces (was 41,197) to the fort `.glb`; the visual mesh is byte-identical. Error from every source vertex and face centre: mean 0.8, p99 5.1, max 12.5 cm. The fort chunk's `Buildings` attach drops from 66–80 ms to 12 ms (`measure_attach_parts`, `kw_gen_-9_3`). A 1 m ray grid against the exact surface: p99 8 cm. `HeightMapShape3D` was measured and rejected (285 ms to build). New `test_landmark_collision`; method and table in `REALITY_HLOD.md`.
- **Legacy Key West island removed** (owner approval, 2026-10-15). Gone: `key_west.tscn`, `key_west_first_exit.tscn`, the `key_west_test` profile, `KeyWestFirstExit`, the legacy city (`ChunkedCityMassing`, `KeyWestCityVisuals`, `KeyWestStreetProps`, `far_city/`, `snow_chunk/`), the NOAA preview crop, six legacy-only tools and three legacy-only tests. The legacy branches in `runtime_performance_policy`, `dev_diorama_map` and `snow_shell` went with them (none ran under Reality). The CI preview job keeps its Reality captures only. `capture_quick_access` now runs on Reality; `test_world_profiles`, `test_stylized_shadows` and `test_island_terrain` check Reality or Graciosa instead. Kept on purpose: `IslandTerrain`/`IslandHeightmap` (Graciosa, the hut template generator), the terrain shader, the Reality Library sources and the NOAA sources. Record: `docs/technical/LEGACY_ISLAND_REMOVAL.md`.
- Owner tasks, 2026-10-15:
  - Facade windows on every generated building, frosted. Panes are 1.0 × 1.4 m on a 0.9 m sill, every 3.2 m along each straight facade (outline points within 0.35 m of a line), one row per storey from `levels` or the measured wall height. Material `frosted_window.gdshader`: frost from the GDExtension lab pattern, a painted sash frame and meeting rail, lit like the walls. Empty houses are 100 % frosted. The 727 glass keeps 60–80 % per window and its heated room clears to 20 % as the stove warms it. Duval St chunk: 12,891 panes on 458 houses; `test_window_frost`.
  - Snow on trees: on the up-facing tops of fronds, limbs and twigs with the live snow cover; trunks bare; windward rime (`tree_snow.gdshader`). Wires, fences and pole tops already had snow.
  - HLOD island-wide: 114 chunks, 995 clusters (was the 2×2 Old Town block).
  - East audit: Boca Chica has no houses by the extent rule; airport buildings are in the data; DEM voids are water (`docs/technical/EAST_KEY_WEST_AUDIT.md`).
  - All 459 chunks regenerated (`kw_chunk_builder.12`), chunk and HLOD digests recorded.
- Painterly wash sky rule (owner decision): the sky takes 10% of the wash in clear, windy and ordinary snowfall weather, and heavy snowfall raises it gradually to 100% (`smoothstep(0.45, 0.95, snowfall_density)`, so a blizzard washes the sky fully). `PainterlyAtmospherePass` follows the live `WeatherController` (`conditions_updated`, already blended per profile). Rule in `docs/visual_fx_shaders.md`; new `test_painterly_sky_rule` checks the curve and the live binding in the main scene. `DEV_DIORAMA_MAP.md` updated for the 90 m camera.
- Painterly wash keeps the authored sky: sky pixels (no depth) counted as the farthest distance and took the full far wash, so the parallax clouds and horizon haze went flat white (sky saturation 0.097 → 0.028, luma 142 → 213 at Duval St). New `sky_affect` uniform, as `Environment.fog_sky_affect` does for engine fog: the sky takes that share of the wash. Measured at 0 / 0.1 / 0.25: saturation 0.096 / 0.067 / 0.044. Default 0.1 pending the owner's pick; at 0 the sky is untouched but washed far buildings stand white against it.
- `capture_stylized_shadows` inside frames on the 727 room: the fixed inside camera sat at the legacy hut's stove offset, 5.43 m from Henry, but the 727 wall on that line is 4.35 m away, so `02_inside_noon` and `03_inside_stove_night` showed a wall and no Henry. The camera is now pulled in front of the first wall on the line from Henry (spring-arm rule, 0.35 m margin) once his chunk is live.
- Painterly wash (Codex, from `main`) kept to the player camera: its fullscreen quad sat on render layer 1 and its vertex shader covers the screen of any camera that draws it, so the dev diorama map drew it too, as a full far-distance wash (map luminance spread 0.171 → 0.020, a flat white sheet). The pass now lives on its own layer 18 (`RenderLayers.SCREEN_PASS`, `screen_pass`), which the map camera leaves out; the player and hub cameras still draw it (screen mean 0.632 → 0.665 with the pass). `test_dev_diorama_map` checks the map camera's mask.
- Dev diorama map: the first render at 90 m showed the map washed grey. The world's depth fog (`fog_mode` depth, default 10–100 m ramp) is opaque at 100 m, and the map camera sits 90 / sin 64° ≈ 100 m from Henry. The map camera now has its own environment without fog (flat ambient, dark background). The header shows the camera height from its constant (it still read 30 m).
- `capture_tps_doorway` on the 727 door: Henry stopped 1.4 m short of the opening on every pass. The tool aimed him from the zone centre, but the 727 door sits in a side wall, about 64° off that line, so he walked into the wall. The way in now follows the door's own axis, as `test_doorway_camera` does. A headless run is a dry run (walk and log, no PNGs); all eight moments are reached. Removal plan: step 4 (legacy branches in `snow_shell`, `runtime_performance_policy`, `dev_diorama_map`, `world.gd`) moves into the deletion change, since each branch serves only the legacy scene that still runs in CI.
- Dev diorama map framing (owner request): camera 30 → 90 m and FOV 36° → 50°, about 160 × 100 m round Henry, so the address labels within 95 m fall in view; labels keep one screen size at any height (`fixed_size`); Henry's marker is a large saturated red dot with a white rim.
- Dev diorama map on Reality: house numbers and street names now come from the Reality building index (`RealityIndex.map_label_entries`, the same entry format as the legacy city) when there is no `ChunkedCityMassing`; 30 labels around Duval St, 28 around 727 Fort St. Labels are rebuilt only when the set changes (they were freed and recreated every 0.75 s, so on a slow renderer they never drew). The map camera's fixed 30 m / 36° view covers about 20 × 12 m round Henry, so most labels sit outside it; that framing is the map's own tuning. `capture_dev_diorama_map` moves Henry to Duval St (no addresses near the fort start) and renders on Reality.
- Legacy island removal, step 3 (capture tools): `capture_sky_weather`, `capture_dev_diorama_map`, `capture_motion_matching_street`, `capture_stylized_shadows` and `capture_tps_doorway` load the Reality scene and no longer force the legacy `key_west_test` profile. New `CaptureWorldSupport` gives them ground height from either world and waits until the chunk at a point is live and the streamer quiet; the shadow capture finds the shelter and its way out from the scene's ShelterZone and door instead of the legacy bunker/shelter coordinates. `capture_sky_weather` verified on lavapipe (calm/snowfall/blizzard frames from Reality, cloud threshold 0.30 → 0.255 → 0.205; `docs/runtime_previews/sky_weather/`); the other four compile and are being rendered one by one. `capture_key_west_first_exit` films the legacy route and goes with the island; `capture_quick_access` (Codex's, from `main`) is left to Codex.
- Legacy island removal, step 2: `test_stove_world_time` and `test_doorway_camera` run on the Reality scene (the 727 stove and door). The doorway test now waits until the door's chunk is live and the streamer is quiet before its scenarios. On the 727 door the mouse-freedom checks that failed on the legacy door pass; Henry still leaves the frame in the full-turn stand sweeps, as on the legacy door, and briefly in the yaw/pitch swings (camera tuning; known-failing list updated). `test_stove_world_time` passes.
- Legacy island removal, step 1: the palm and leafless-tree meshes moved from the legacy `KeyWestStreetProps` into the shared `WinterTreeMeshes` (`scripts/world/props/`); the Reality chunk builder uses it and no longer touches legacy code, the legacy props delegate to it. Byte-identical: chunks -6:3 and -7:3 rebuild with the same digests (17fc605d…, e5f3ec47…), partial verify identical.
- New `suites` workflow: every headless suite under `tests/systems` runs on every push, report-only (`checks` stays the gate on `main`, as its header says the suites still churn). `tools/ci/known_failing_suites.txt` lists the two camera suites still failing, with reasons; `run_tests.sh` reports them without counting them and fails if a listed suite starts passing, so the list cannot go stale.
- `test_street_props_streaming` (legacy island) follows the current street props: every kind, palms, bare trees and power poles included, is filed per city chunk; it expected the earlier island-wide silhouettes and counted the merged crossings mesh as instances. It passes.
- Dev diorama map: its camera is moved in `_process`, but the project runs physics interpolation, so the map drew and projected the camera a tick behind (Henry's marker landed off the map centre). The camera now has physics interpolation off, as Godot advises for nodes moved in `_process`. `test_dev_diorama_map` also set a position before the node was in the tree and checked the projection before the shown containers had laid out; both fixed. It passes.
- Snow suites match the shipped snow shell: `test_snow_contact_pipeline` checks the game's `DeterministicSnowShell` (local 256² contact over 6.4 m) and only failed to find its unnamed contact camera, now named `ContactCamera`; `test_snow_shell` expected the base shell's packed field at 1024² and `world.gd` to build `snow_shell.gd`, while the packed field is 896² since the cost pass (`SNOW_COVER.md`) and `world.gd` builds `deterministic_snow_shell.gd`. `SNOW_COVER.md` no longer says the packed field is 1024² or that the game's contact capture is 1024².
- Fixed a stale authored passage: Henry's passage traversal kept an authored doorway (NarrowPassage or HingedDoor) after its node was freed, because unmarked-geometry detection is skipped while an authored passage is held; in the streamed world that is any door in a chunk that unloads. It now drops an authored passage whose source node is gone. `test_passage_traversal` passes (its corridor check stood inside the freed 1.45 m test door).
- Failing-suite repair, part 1 (these 10 suites failed since the start of this repository's history; Jenova once forced every Godot exit code to 0, so they looked green): `test_door_draft` drove the door's hinge transform instead of its angle state; it now sets `current_angle_rad` and lets the hinge and breach exposure follow, as the game does. `test_held_fit` and `test_held_light` pinned the pre-"flare pass 2" sideways pose; the authored fit (upright out of the fist at chest height, checked in a render) is now the reference, and the nozzle rule is "above level and never back into Henry". TPS camera: with Henry's back to a wall the shoulder recompose, built up at an earlier yaw, now lets go at the fast rate when the centre line would bring the camera closer (its documented rule); `test_tps_camera_orbit` goes from 3 to 2 failed checks, the rest is boom smoothing near the 0.25 m fade end (owner's camera tuning). `tools/runtime/capture_held_flare_pose.gd` renders the held flare from three sides with the authored or a given fit.
- The game now starts in Key West Reality: `run/main_scene` and the title menu's `game_scene` are `key_west_reality.tscn` (owner decision, proposed in #219). The legacy island still loads and is prepared for removal: the hut cabinet fade volume and dressing moved to the shared `ShelterCabinet` (the 727 shelter no longer calls legacy code), `test_key_west_first_exit` loads the legacy scene by path, and `docs/technical/LEGACY_ISLAND_REMOVAL.md` lists what blocks deletion (Reality's chunk builder still uses the legacy street-prop tree meshes), what to delete, what to keep, and the order.
- 3D physics switched to Jolt (built into Godot; the default for new projects since 4.6; ours ran GodotPhysics as an older project). The 11 ms `attach_part` in #219 was a collision rebuild, not node attachment. GodotPhysics builds a chunk's concave building collision on the main thread twice in debug builds: once when the loader's queued `shape_set_data` flushes, once in `CollisionShape3D.set_shape`. Jolt builds it once, lazily and faster. Buildings instantiate 9–18 → 2–3 ms; a frame that finishes loading a Buildings part 19–22 → 10–12 ms. The full suite shows the same 10 failures as before (they fail on current `main` too and are not in CI); the 727 loop passes; gate frame times are unchanged (p50/p95/p99 6.83/14.32/17.26 vs 6.86/14.53/17.33 ms on one machine). Revert = remove one line in `project.godot`. Henry's movement feel still needs the owner's check. Details: `docs/technical/REALITY_HLOD.md`.
- Dev teleport (F6) no longer drops Henry through the ground or into a building. Before, on an unloaded chunk it read the ground's 1.0 m fallback (Henry fell 0.95 m through the terrain at Whitehead x Petronia) and an address put him on the building's centroid (inside 727 and 907 Whitehead). Now Henry is held at the target, physics off, until the chunk under it is live (`KeyWestRealityGround.has_ground_at`), as UE World Partition waits on `IsStreamingCompleted` before a teleport ends; he is then set down on the first spot where his own capsule overlaps nothing, as `UWorld::FindTeleportSpot` does: for an address, 2 m out from the wall facing the most open ground, then rings around it. `tools/runtime/trace_dev_teleport.gd` in the real scene: 3 of 9 targets wrong → 0 (`docs/runtime_previews/key_west_dev_teleport/`); in CI.
- Reality dock: Go to now frames the whole building. In Godot 4.8 F only re-centres the editor orbit and keeps its distance (4 m on a fresh view), so a sized marker cannot fix it; Go to now centres on the building's bounds (from `editor_index.json`, shown as an unsaved box), measures one wheel notch and moves the view out or in until the bounding sphere fits. Measured in the real editor: 7.7 → 29.6 m at 907 Whitehead (needs 25.9), 7.3 → 16.0 m at 1009 Windsor Ln (needs 13.8).
- HLOD debug view: F3 in a debug build tints every proxy (Tier 1) orange and every drawn detail cluster blue, fog-free so it reads in a blizzard (`KeyWestRealityHLOD.set_tint_tiers`, off in release). The tier capture uses the same tint and now also enters Old Town from Duval St; on the owner's GPU no cluster shows both or neither, and runtime differs from all-detail on 0.11 % of pixels or less.
- Dev navigation in the Reality scene (debug builds only): F5 cycles a target through the First Exit route goals and listed addresses (727 Fort St, 907 Whitehead St, resolved through the editor index), shown as a 150 m beacon seen through buildings plus a distance and compass line; F6 teleports Henry there. `KeyWestDevWaypoints`, `test_key_west_dev_waypoints`.
- Fixed the 727 door vanishing a second after a shelter spawn: chunks prewarmed at boot were live before the far view connected, so when the far cell arrived its mesh (with 727's building prism) drew over the detailed chunk. The far view now syncs with the streamer's states on connect, as the HLOD view does. Traced with `tools/runtime/trace_727_door.gd`; guarded in `test_key_west_reality_hlod`.
- `StreamingSystem` scales with the cells near the player, not with the island: `pump()` walks only cells in QUEUED/LOADING/READY/ASSEMBLING, and `scan()` reads a 256 m grid of load bands plus the live cells. At 7,803 cells (the island in 128 m clusters) `scan()` 27–36 → 0.3 ms and idle `pump()` 13–14 → 0.003 ms on the owner's laptop. API, signals, budgets and hysteresis unchanged; `test_streaming` checks the grid against the bands; `tools/runtime/benchmark_streaming_scale.gd` reproduces the numbers.
- HLOD on the owner's GPU (Intel HD 620, LOW, 1080p): `measure_key_west_hlod.gd --all-detail` swaps every proxy for its detail scene, an A/B on one build. Draw calls fall 41–67 % as on lavapipe; FPS gives no verdict, because run-to-run noise (125–334 ms on unchanged controls) is ten times the effect. The game runs at 3–8 FPS on this GPU, bound by GPU load and script time, not draw calls. Data and reading: `docs/technical/REALITY_HLOD.md` §3c.
- Reality HLOD v1 on the Old Town sector (chunks -6:1 -5:1 -6:2 -5:2, `config/hlod.json`): generated buildings stream in 128 m cluster cells of the same `StreamingSystem` (detail within 230 m, out past 350 m), and while their chunk is loaded an offline proxy (merged by material, roof snow folded in, no collision) stands in for each cluster that is out; `KeyWestHLODBuilder` writes a deterministic manifest (stable ids, sorted sources, bounds, source hash, counts) and rebuilds only dirty clusters; Reality dock: cluster bounds, tier preview, fresh/dirty, counts, sources, Build selected, Rebuild dirty; CI rebuilds the proxies from clean, checks the digest, partial == full, missing/duplicate/orphan ids, and walks detail → HLOD → detail. Baseline, design and numbers: `docs/technical/REALITY_HLOD.md`. Proxies load when the chunk's far cell comes in (2,500 m), so the main thread never waits for one; streaming and HLOD stages are timed in the gate and in a boundary stress test.
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

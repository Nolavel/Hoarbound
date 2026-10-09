# Changelog

All notable changes to Hoarbound. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `main`

### 2026-10-09 - Pickup [F] keycap and opt-in special awareness (claudeflow)

- **`PickupMarkerUI`** (`scripts/ui/hud/pickup_marker/`, instanced in
  `player.tscn` next to `MouseCursorUI`).
  - It draws one compact screen-space `[F]` keycap: `key_size` 24 px, held
    `lift_px` 26 above the focus point, at a constant size on screen. The key
    comes from the InputMap.
  - The keycap sits over the dominant pickup only while it is actionable. It
    glides between neighbours over `transfer_seconds` 0.12 and drops in the same
    frame as `interaction_performed` for a consumed item.
  - Other noticed pickups get a faint dot (`hint_radius_px` 3, `hint_alpha`
    0.35). A dominant pickup that is not actionable, for example under a world
    target, keeps only a dot.
  - It never touches the centre Enso, brackets or gradient.
- **✓ means "notice this", nothing else.**
  - `InteractiveArea.special_awareness` (default off) joins the
    `special_awareness` group; `awareness_radius` defaults to 8 m.
  - `InteractComponent._update_awareness` runs every 0.2 s, only over that group,
    and needs head line of sight. The field does not apply, and the marked item
    does not become actionable.
  - `set_hint_state` forces HIDDEN for every other object, so ordinary loot,
    doors and stoves no longer show the check mark.
  - New `get_marker_state()`.
  - Which First Exit items deserve ✓ is the author's call: none are marked yet.
- **Fix.** `InteractComponent._is_available`/`_flat_distance_to` take Variant.
  A freed pickup passed to the typed parameter raised a script error before the
  validity check.
- **Tests.** `test_interaction.gd` checks the keycap on the dominant pickup, its
  suppression under a world target and its removal on consumption. It also
  checks that ✓ appears on a rare item 5 m behind Henry (and does not make it
  actionable) and never on ordinary loot.

### 2026-10-09 - Interaction grammar: world view channel and pickup head-attention channel (claudeflow)

- **Two channels replace `current_target`.** `InteractComponent` now keeps
  `world_target` (doors, stove, windows, seats, table food: picked by the
  player's view) and `pickup_target` (`ItemPickup`: picked by Henry's head
  attention). `InteractiveArea.get_interaction_channel()` classifies; `ItemPickup`
  returns PICKUP, everything else WORLD.
- **F arbitration.** The world target wins F. A pickup acts only when no world
  target is selected. New API: `get_world_target`, `is_world_target_in_reach`,
  `get_pickup_target`, `is_pickup_actionable`, `get_pickup_candidates`,
  `get_active_target`, `is_active_target_in_reach`. New signals
  `world_target_changed`, `pickup_target_changed`, `active_target_changed`.
  Removed `current_target`, `is_target_in_reach`, `interact_target_changed`
  (no subscribers), `get_gaze_direction`, `get_facing_direction`,
  `is_crosshair_focused`, `CHEST_HEIGHT`.
- **World channel: view-driven.** Soft cone around `TpsCamera.aim_origin/aim_direction`
  (`world_aim_cone_deg` 10, seated `seated_aim_deg` 35), widened by the new
  `InteractiveArea.focus_radius` for acceptance only. Ranking uses the true
  angle. The current target holds up to `world_exit_scale` 1.5 × the cone.
  `world_grace_seconds` 0.15 covers a line-of-sight miss only while the target
  is still under the aim. Proximity gate `intent_radius` stays. This
  deliberately reverses bf20583 for world objects (owner decision).
  `accepts_focus`/`resolve_focus` get the camera aim again.
- **Pickup channel: Henry's head attention.** Origin and direction come from
  `Player.get_attention_origin/direction`, which delegate to `HenryUALAnimation`.
  The field is ±90° (`pickup_field_deg`). Cost = attention error in degrees +
  `distance_cost_deg_per_m` 6 × distance. The dominant pickup keeps
  `switch_margin_deg` 4°. `pickup_grace_seconds` 0.15 covers a brief
  line-of-sight loss. No camera term, no torso facing, no cycling. The channel
  is empty while board placement or the Hub is open.
- **Henry attention.** `HenryUALAnimation.get_attention_origin()` is the head bone,
  low-passed (`attention_origin_smooth` 10). `get_attention_direction()` points at
  the player's aim point, clamped to `head_look_primary_limit_deg` around the
  facing and smoothed (`attention_smooth` 12). It keeps working while walking.
  The standing head look now follows the same direction. Smoothing is used only
  while updated every physics frame.
- **Aim point, not aim direction.** `Player.get_view_target()` is the nearer of
  the aim ray's solid hit and an interactable focus area the ray passes through.
  Measured in `test_shelter_workflow`: carrying the camera's aim *direction* to
  Henry's head (the old `get_gaze_direction` rule) put the attention 34° off the
  aimed nails at 0.8 m, which picked the knife. `Player.get_view_direction()` now
  uses the gameplay aim ray instead of the lens-shifted basis.
- **Consumers migrated.**
  - `RestComponent` uses the active target, so seated food still beats Wait.
  - `HeatSourceFeed._in_reach` uses the world target.
  - `MouseCursorUI` centre prompt: world target only.
  - `TpsInteractionFraming` reads the world target only; pickups never move the
    camera.
  - Legacy `ActionPrompt3D` and the frozen embodied lab only compile against the
    new API.
- **Bug fixed.** The old line-of-sight and gaze rays started at `CHEST_HEIGHT` 1.3
  above the capsule centre, i.e. 2.3 m above the floor.
- **Tests.**
  - `test_interaction.gd` rewritten for the new grammar: head-only A→B→C,
    ±2° noise, the item behind is never offered, walking keeps head attention,
    world wins F and the central prompt, a disabled target is not authoritative,
    a consumed pickup clears at once, a far item walks over.
  - `test_seated_aim.gd`: seated F acts on the viewed thing in reach; with
    nothing in reach F belongs to Wait.
  - `test_head_look.gd` adds the attention checks.
  - `test_shelter_workflow.gd` checks the channel per target and settles the
    nailing clip before the second board. It went from 22 failures on `main`
    `4677754` to PASS.
  - `test_doorway_camera` (4) and `test_passage_traversal` (1) fail exactly as
    on `main`.

### 2026-10-09 - Linux Jenova runtime rebuilt with shared libstdc++; Import gate fixed

- `Jenova/Jenova.Runtime.Linux64.so` (17.9 MB, was 20.1 MB) and
  `GodotSDK/libGodot.x64.a` come from `[jenova-frost-preview]` run
  37814389505. The runtime now needs the shared `libstdc++.so.6`. In that run
  the cold import gate passed on it. With the old static-libstdc++ runtime the
  same pass aborted with SIGSEGV in `std::regex`.
- **Verified on Windows:** in the editor on the author's machine,
  `BuildProject` compiled `frost_window.cpp` in 23 s with the local AiO MSVC
  toolchain. The frost lab scene then logged "C++ controller ready" and
  "frost pass reached 100% in 6.50 seconds".
- `tools/ci/build_jenova_project.gd` sets `jenova/editor_verbose_output` to
  standard output and waits for the settings to apply. Headless CI builds
  previously failed with no compiler output.
- `.gitignore` excludes `Jenova/~*`, the runtime copy Jenova keeps while the
  editor runs.
- **Open:** the Jenova C++ script build still fails on Linux
  (`BuildProject` returned false with no output in run 37814389505).

### 2026-10-09 - Windows Jenova runtime vendored; Linux import crash diagnosed

- **Windows binaries vendored** from CI run 37808998143 through Git LFS:
  `Jenova/Jenova.Runtime.Win64.dll` (5 MB), `GodotSDK/libGodot.x64.lib`
  (139 MB) and `JenovaSDK/Jenova.SDK.x64.lib`. In that run the frost C++ script
  compiled and the frost lab scene ran on the Windows runner. The artifact's
  GodotSDK headers matched the vendored ones except for line endings.
- **Import gate:** the cold import crashed in the Linux runtime's static
  libstdc++ (`std::regex` in `CPPScript::_get_global_name`). The Linux
  bootstrap now links the shared libstdc++. The `[jenova-frost-preview]` job
  rebuilds the runtime and runs the cold import gate on it.
- **Unverified:** the rebuilt Linux runtime is not yet confirmed by CI or
  vendored. Windows editor use needs `tools/jenova/install_msvc_compiler.ps1`;
  that has not been tried on this machine.

### 2026-10-09 - CI: the cheap gate runs on push again

- **`checks` job.** Its `if: github.event_name != 'push'` meant the import,
  input-map and filename gate never ran on a push to `main` (5 runs in the last
  60, all PR or manual). It now runs on every push and PR.
- **Path filter.** The 60-entry `push.paths` whitelist is replaced by the same
  `paths-ignore` (docs, Markdown) as pull requests. Pushes that touched no
  listed file, such as gameplay scripts, used to skip CI entirely.
- **`color-grade-preview`** ran on every untagged push and acted as an
  accidental main gate. Its 10-tag exclusion list was already stale (no
  `[cmu-retarget-preview]`, `[rokoko-retarget-preview]`). It is now
  tag-gated by `[color-grade-preview]`, like every other preview job.
- **Expected after this change:** `checks` will report the existing Import gate
  failure on every push until the cold-cache import abort is fixed.

### 2026-10-09 - Remove dead tool instances from the robot test scene

- `tests/scenes/Test_scene_robot.tscn` still instanced
  `tools/ScanFolderFiles/ScanFolderFiles.tscn` and
  `tools/InputDebugger/InputDebugger.tscn`, deleted in fc3b886. Each editor load
  logged `Failed loading resource`. The two nodes and their ext_resources are
  removed (`load_steps` 9 → 7); nothing else referenced them.
- The failing Import gate on `main` is a separate issue. The first headless
  import pass aborts (core dump) on a cold cache, so the second pass misses the
  translations and the project font. It started when Jenova was vendored. Not
  fixed here.

### 2026-10-09 - Reproducible Jenova builds for Windows and Linux

- `docs/technical/JENOVA.md` documents how Jenova works in Hoarbound:
  - pinned inputs (Jenova `63ecdcb`, dependency bundle 4.7, Godot 4.8-dev6 API,
	AiO Toolchain v1.0 with SHA-256);
  - the `Jenova/` layout;
  - Hoarbound's source patches;
  - developer setup per OS;
  - CI rebuilds and how to bring the CI artifact into the repo.
- **Windows patch.** `bootstrap_jenova_windows.ps1` now patches Jenova's
  Windows `MicrosoftCompiler` to take the compiler from
  `Jenova/Compilers/JenovaMSVCCompiler` and the SDK from `Jenova/GodotSDK`, as
  the Linux bootstrap already does. Without it Jenova looked up an MSVC package
  in its online package manager, found none, and the C++ script build failed.
- **Local compiler.** New `tools/jenova/install_msvc_compiler.ps1` installs the
  portable MSVC toolchain into the git-ignored `Jenova/Compilers/` (~0.9 GB,
  checksum-verified, junction layout, `.gdignore`). Visual Studio is not needed.
- **CI.** `jenova-windows-build` uploads the vendor package right after the
  runtime build, so a later failure still yields the DLL. It excludes
  `Jenova/Compilers/` from the package and always uploads the build logs as
  `hoarbound-jenova-windows-logs`.
- **LFS.** The Windows runtime, `libGodot.x64.lib` and `Jenova.SDK.x64.lib` are
  tracked by LFS. Linux binaries stay plain git objects, because Linux CI jobs
  check out without LFS.
- **Repo setup.** `CLAUDE.md` gains a Jenova section. LFS hooks are installed
  in the local clone.
- **Unverified:** the Windows runtime and the C++ script proof have not passed
  yet. A local Windows build on this 4 GB RAM machine was stopped for lack of
  memory, so the build runs in CI.

### 2026-10-08 - Interaction targeting by Henry's gaze (The Last of Us scheme)

- **Group.** `InteractComponent._visible_group()` collects every `interactive`
  object within `intent_radius` (seated: `seated_reach`) that passes the body
  facing cone (`facing_limit_deg`; waived within `close_override`) and chest
  line of sight. Ordering is by score. At most 1 + `max_hint_markers` members
  are kept.
- **Dominant.** The member nearest Henry's gaze wins. Score =
  `gaze_weight`·(1 − angle/`gaze_cone_deg`) + `distance_weight`·closeness +
  `focus_priority`, plus `hysteresis_bonus` for the current target.
- **Gaze (`get_gaze_direction()`).** Moving, it is the body facing. Standing or
  seated, it is the body facing turned towards `get_view_direction()` by at
  most `head_turn_limit_deg` — the same rule Henry's head look follows. Seated
  keeps the `seated_aim_deg` gate, now measured against the gaze.
- **Aim rays.** `accepts_focus`/`resolve_focus` (stove door, firebox,
  BreachBoardUp) get Henry's gaze ray from the chest, pitched to the object's
  height, instead of the camera ray.
- **Markers.** `InteractiveArea.set_hint_state(state, opacity, observer)` with
  `MarkerState` HIDDEN / DIM / DOMINANT. The target shows the bright marker
  (alongside its F prompt). Other group members show a smaller, fainter marker
  (`marker_dim_scale`, `marker_dim_opacity`). Objects outside the group show
  none. Opacity fades from `prompt_distance` to the group radius. Size, bob,
  fade and the child `Sprite3D` pickup are unchanged.
- **Removed:** the `interact_cycle` action (project.godot, InputSystems signal
  and constant), `cycle_target`, `_manual_choice`, `_cluster_around`,
  `get_cluster_position`, `cluster_radius`, the "[R] 2/3" prompt suffix and
  `InteractiveArea.action_key_label`. The camera is gone from targeting:
  `camera_weight`, `camera_cone_deg`, `_score_candidates`, `_ranked_score` and
  `_flat_view_direction`. The separate marker pass is gone too: `hint_radius`,
  `_update_hints` and its 0.1 s timer. Also removed: `facing_weight`,
  `SIGHT_CHECKS` and the seated weight constants.
- **New exports (`InteractComponent`, group Intent):** `head_turn_limit_deg` 55
  (keep equal to `HenryUALAnimation.head_look_primary_limit_deg`),
  `still_speed` 0.15, `gaze_cone_deg` 60, `gaze_weight` 1.0.
- **Changed defaults:** `distance_weight` 0.25, `hysteresis_bonus` 0.05.
- **New exports (`InteractiveArea`, group Marker):** `marker_dim_scale` 0.6,
  `marker_dim_opacity` 0.4.
- **Tests.** `test_interaction.gd` keeps "the item at Henry's back is not
  picked" and "of two close items, the one Henry turns to wins".
  `test_seated_aim.gd` now expects the head to stop at its neck limit when
  looking back-right, keeping the right target, instead of picking nothing.
- **Unverified:** nothing was run in Godot (no import, compile, test suites or
  render). Gaze feel, weights and marker readability need the author's check.

### 2026-10-08 - Interaction targeting: facing cone, angle scores, cluster cycling, small markers

- Fixes three issues from the in-game test of 6f58fa5.
- **Facing cone.** Standing, `InteractComponent` drops a candidate more than
  `facing_limit_deg` from Henry's facing, unless it is within `close_override`
  (the item at his feet). The "behind Henry and behind the camera" filter is
gone. The camera only adds score, so an item at Henry's back is no longer
picked from the middle of the frame. Seated keeps the `seated_aim_deg`
camera gate.
- **Angle scores replace dot products.** The facing score is
  `1 - angle/facing_limit_deg`, the camera score is `1 - angle/camera_cone_deg`
  (both clamped). The total is `distance_weight`·closeness +
  `facing_weight`·facing + `camera_weight`·camera + `focus_priority`, plus
  `hysteresis_bonus` for the current target. Scoring is split into
  `_score_candidates()` and `_ranked_score()`.
- **Cluster cycling.** Candidates within `cluster_radius` of the target form a
  cluster. The new action `interact_cycle` (R) steps through it in score order
  via `InteractComponent.cycle_target()`. InputSystems emits
  `interact_cycle_pressed`. A manual pick holds until Henry moves 0.5 m or the
  pick stops being eligible or visible. `ActionPrompt3D` shows "[R] 2/3" from
  `get_cluster_position()`.
- **Markers.**
  - Anchored at `get_focus_point()` + `marker_lift`, with a constant screen size
	(`fixed_size`; `pixel_size` comes from `marker_screen_size` and the camera FOV).
  - Fade from full opacity at `intent_radius` to zero at `hint_radius`.
  - Show only for the `max_hint_markers` nearest objects inside the facing cone
	with chest line of sight.
  - The 5 s shake is replaced by a continuous bob (0.03 m, 1.2 s) and a 0.2 s
	fade.
  - `InteractiveArea` now binds a child `Sprite3D` when `icon_sprite` is unset.
	43 of the 61 blockout markers were never bound and stood static and
	full-size at the Area origin.
- **Cursor prompt.** The fallback centre ray (`_ray_hits_target`) is removed
  from `mouse_cursor_ui`; it now only shows `current_target`.
- **`check_input_map.py`** parsed zero bindings because Godot writes
  `"script": null` with a space. Both regexes are fixed; it now checks 26
  bindings.
- New exports: `facing_limit_deg` 100, `close_override` 0.5, `camera_cone_deg`
  30, `distance_weight` 0.5, `cluster_radius` 0.8, `max_hint_markers` 3
  (`InteractComponent`); `marker_lift` 0.25 and `marker_screen_size` 0.025 of
  screen height (`InteractiveArea`, group Marker).
- Changed defaults: `facing_weight` 0.6 → 0.5, `camera_weight` 0.4 → 0.7,
  `hysteresis_bonus` 0.25 → 0.08.
- Removed: `icon_height_offset` (and its writes in meal_table, stove_warmer
  and HenryUALAnimation), `target_ray_length`, the shake timer and constants,
  and the old icon tween helpers.
- Tests: `test_interaction.gd` adds two checks. With the camera behind Henry,
  the item at his back stays unpicked. Two items 0.3 m apart switch with his
  body turn.
- Unverified: nothing was run in Godot (no import, compile, test suites or
  render). Marker size and fade, cluster cycling, and all weights need the
  author's in-game check.

### 2026-10-08 - Third-person interaction targeting by score around Henry

- `InteractComponent._find_best_target()` replaces `_find_crosshair_target` and
  `_find_seated_target`. Candidates come from the `interactive` group with no
  physics queries. A candidate's flat distance to `get_focus_point` must be
  within `intent_radius` (seated: `seated_reach`), and `accepts_focus` must pass.
  Score = closeness + `facing_weight`·body facing + `camera_weight`·camera aim +
  `focus_priority`, plus `hysteresis_bonus` for the current target. Line of sight
  goes from Henry's chest (+1.3 m) to the focus point, for the top 3 only.
  The object's own bodies never block it.
- Standing: a candidate behind both Henry and the camera is ignored. Seated
  (facing 0.1, camera 1.0): it must lie within `seated_aim_deg` of the camera aim.
- `HeatSourceFeed.keeps_focus()` holds the stove target while `is_acting()`.
- `InteractiveArea`: joins group `interactive` (`INTERACTIVE_GROUP`; plain `GROUP`
  would clash with `HingedDoor.GROUP`); new `focus_priority`,
  `get_focus_point()` (moved from the component), `accepts_focus()`,
  `resolve_focus()`, `keeps_focus()`, and `set_hint_state()`. The far
  check-mark marker now follows distance to the focus point, not the trigger
  Area. `shape_cast_detected` is renamed `prompt_shown`, and
  `set_shape_cast_detected` is removed (it had no callers). The marker shake
  `await` is guarded by a serial.
- Overrides replace `is` branches: `HingedDoor.get_focus_point` (nearest
  handle), `BreachBoardUp.accepts_focus` (aim on opening),
  `StoveDoorControl.accepts_focus` (aim on door) and
  `StoveDoorControl.resolve_focus` (firebox while acting).
- `TpsInteractionFraming` uses `get_focus_point` instead of its own copy.
- Removed: `_first_interactive_area_on_ray`, `_focus_hit_is_visible`,
  `_is_focus_aligned`, `_has_focus_line`, `_focus_point`, `_find_intent_target`,
  `_is_ahead` and `_resolve_focus`. Removed exports: `focus_length`,
  `focus_radius`, `focus_angle_deg` and `intent_angle_deg`. No scene overrode
  them. The embodied lab's `focus_angle_deg` assist is gone.
- New exports (starting values, to be tuned by feel): `facing_weight` 0.6,
  `camera_weight` 0.4, `hysteresis_bonus` 0.25, `hint_radius` 4.5 (marker pass
  every 0.1 s). `seated_aim_deg` (35) is kept as the seated camera gate.
- Tests: `test_interaction.gd` now checks the new contract. The item in front is
  targeted with the camera turned away, and an item behind both Henry and the
  camera is ignored. `test_shelter_workflow.gd` uses `get_focus_point` and
  `prompt_shown`, and `_aim` turns Henry towards the target.
- Unverified: nothing was run in Godot (no import, compile, test suites or
  render). Feel, weights and the eight manual scenarios need the author's
  in-game check.

### 2026-10-08 - Vendor cross-platform Jenova runtime

- Track the Jenova runtime and generated GodotSDK so clean clones can load
  `frost_window.cpp` without downloading Jenova separately.
- Add a Windows/MSVC bootstrap and an opt-in `windows-latest` artifact job,
  both using Jenova revision `63ecdcb385fbcd8a59e1ed5896a6c03e0d0aacb2` and
  Hoarbound's Godot 4.8-dev6 API.
- Store the genuine oversized Windows `libGodot.x64.lib` through Git LFS and
  validate the frost script build with the platform's native compiler model.
- Allow `workflow_dispatch` to run the existing Windows job when GitHub cancels
  a push-triggered Jenova build due to main-branch concurrency.
- Isolate long Jenova Windows runs from unrelated push-triggered checks.
- Validate the frost scene after the Jenova BuildProject harness produces its C++ module.
- Preserve existing Windows files when regenerating the Linux runtime and SDK.

### 2026-10-08 - Jenova frost Linux build fixes

### 2026-10-08 - Jenova frost Linux build fixes

- `tools/ci/bootstrap_jenova_linux.sh` links the static curl IDN2 dependency into
  the Jenova runtime.
- `tools/ci/build_jenova_project.gd` resolves the editor plugin dynamically so the
  harness can parse before GDExtension class registration.

### 2026-10-08 - world_key_west: living Key West world-attribute registry

- `docs/world/world_key_west.md`: single registry of the Key West world attributes —
  geographic source-of-truth ([geo]) plus authored game attributes ([game]) with slots
  for author decisions. Built up over development alongside the route and profile docs.
- Embodied / motion-matching stack fully frozen for now: #198 epic joins the already
  frozen #197/#199/#201/#202/#203 (`status: frozen`), sequenced to build-plan step 10.

### 2026-10-08 - Direction reset: 10-step build plan, First Exit A spine

- `docs/BUILD_PLAN.md`: single ordered build sequence (10 checkpoints) replacing the
  scattered backlog, plus a one-year plan to the summer-2027 vertical slice. Grammar
  rule written down: no system ships unless it visibly changes a survival decision.
- ADR: the interaction crosshair is a readability aid only, decoupled from the
  embodied-interaction condition (#198) — presentation never gates whether an
  interaction is possible.
- Embodied / motion-matching work sequenced to the end of the path (step 10). Issues
  #197, #199, #201, #202, #203 frozen (`status: frozen`), preserved not cancelled.
- `PRD.md`, `README.md`: link the build plan as source of truth.

### 2026-10-07 - Motion Matching gate C: six styles, leg-roll diagnosis (#202)

- One B4 retarget setup on eight 100STYLE clips (Neutral, Rushed, StartStop,
  Crouched, BentForward, Old):
  - no knee bends backwards;
  - no hyperextended elbows (the source has up to 177 frames);
  - knee plane follows the source.
- Henry's thigh and calf axial roll (~18°) is the performer's own; the
  retarget matches it within a degree.
- Opt-in `STAGE_LEG_PLANE` removes the calf roll.
- `test_rig_contract.py` checks the limb +Y axis contract.
- Results in `docs/motion_matching/gate_c.md`.

### 2026-10-07 - Motion Matching retarget backend comparison (#202)

- `MotionRetargeter` gets three opt-in stages (off by default, database unchanged):
  - `STAGE_NEUTRAL_POSE`: relaxed standing retarget pose from the source's and Henry's idle, with a straight-elbow blend for flexed arms;
  - `STAGE_TWIST_SPLIT`: forearm roll on the lowerarm;
  - `STAGE_SPINE_CHAIN`: spine sampled by chain length.
- `UALSkeletonModel.mean_pose()` gives Henry's mean pose over a clip.
- Profiles: `source_dir` and standing clip per family; `cmu_bvh_v2()` with `hand ← L/RFingerBase` for diagnostics; the 100STYLE conventions are now measured.
- `ModifierRetargetBackend` runs Godot's `RetargetModifier3D` as a comparison backend. `dump_retarget_layers.gd` and `capture_retarget_quad.gd` take named variants (`MM_DUMP_VARIANTS`, `MM_DIAG_VARIANT`).
- Results in `docs/motion_matching/retarget_backends.md`.

### 2026-10-07 - Motion Matching mocap data request (#202)

- `docs/motion_matching/mocap_data_request.md` specifies the data production
  Motion Matching needs:
  - licence rules and a manifest per folder;
  - 100STYLE Neutral now, then 100STYLE state styles;
  - the gaps to source elsewhere;
  - a manifest for the owner's existing Drive set;
  - a full shot list for a dedicated capture session (performer in a winter coat).

### 2026-10-07 - Motion Matching layer bisection tools and findings (#202)

- Anatomy metrics from joint positions (`tools/motion/`): signed knee/elbow
  flexion and bend plane, trunk/neck, arm abduction, forearm and hand twist,
  wrist, feet; BVH and glb FK oracles; layer and in-game trace reports.
- `MotionRetargeter.stages` switches retarget stages off one at a time (default
  all; database unchanged). `dump_retarget_layers.gd`, `capture_retarget_quad.gd`
  (front/side/rear/feet or hand) and `MM_POSE_TRACE` in the player capture.
- Findings in `docs/motion_matching/retarget_bisection.md`:
  - the core retarget and the CMU bone map break arms, hands and spine;
  - the foot-lock IK flips knees backwards;
  - the gaze layer throws the head back.

### 2026-10-07 - Motion Matching frozen after the visual review of #206 (#202)

- The author rejected Motion Matching visually on `main` `3f67c9b` (torso lean,
  pinned arms, running, knees bending backwards). It stays off by default and
  frozen; `docs/motion_matching/acceptance_gates.md` lists gates A-G, each
  passed only by the author's visual approval.
- CMU retarget profile: `verified = false`, new `visual_approval` and
  `frozen_reference`. The builder still rebuilds `root-space-v10` as a
  regression reference; the game is unchanged.
- `retarget_audit.md` corrected: CMU frame 0 is not an all-zero pose, the
  clavicles never move, and `L/RHand` is forearm twist (wrist bend is the
  unmapped `L/RFingerBase`).

### 2026-10-07 - Motion Matching walks without the limp: mirrored walking (#202)

- Straight forward walking is baked as captured and mirrored (author decision):
  CMU subject 39's left-long gait no longer sets Henry's rhythm. Steady walking
  in game: step length symmetry +6.7% -> -0.3%, step time +8.7% -> -0.9%,
  pelvis 8.5 mm lower over the left leg -> 1.0 mm (AnimationTree: -0.5%,
  -1.2%, 2.1 mm). Skating unchanged (0.438 -> 0.435 m/s).
- `BVHClip.mirrored()` and the builder's `MIRRORED_ROLES`; database
  `root-space-v10` (16 636 samples, 10.7 MB). New suite
  `tests/systems/test_bvh_mirror.gd`.
- `tools/runtime/capture_motion_matching_street.gd`: production review on
  Southard Street in the real Key West scene (walk, sprint, stop).

### 2026-10-07 - Gait symmetry: measured limp, retarget stance-height fix (#202)

- `MotionRetargeter` levels the planted feet: a source subject's unequal legs
  no longer leave one of Henry's stance feet lower. Each side's planted ball
  height is measured and removed from the pelvis while that foot carries the
  weight. Database `root-space-v9` (same 12 490 samples, audit clean); in-game
  skating unchanged (0.438 -> 0.439 m/s).
- `capture_motion_matching_player.gd`: `MM_PROGRAM=walk`, `MM_GAIT_TRACE=1`
  and `MM_FOOT_LOCK=0` for gait-symmetry captures.
- The reported left-leg limp is measured (step length +6.7%, step time +8.7%,
  pelvis 8.5 mm lower over the left leg) and traced to the walking source, CMU
  subject 39; see `docs/motion_matching/integration_plan.md`. Resolved by the
  mirrored walking entry above.

### 2026-10-07 - Movement owns its dynamics; fatigue tuning neutral (#202 hardening)

- `MovementController` offers dynamics profiles (`LocomotionDynamicsProfile`,
  `data/characters/henry_dynamics_data_matched.tres`) through
  `request_dynamics_profile` / `release_dynamics_profile`; it applies one only
  in grounded walking. Motion Matching asks for `data_matched` and no longer
  writes `accel_rate`, `decel_rate` or `Player.turn_rate`. Without a request
  walking computes the same rates as before. New suite
  `test_locomotion_dynamics_profile.gd`.
- Sprint fatigue defaults are neutral (`exhausted_sprint_ramp_factor` 1.0,
  `winded_sprint_share` 1.0): the sprint is the old one until the author picks
  the tuning. The proposed values (×2.0, winded below 30%, 40% share) are in
  `docs/motion_matching/integration_plan.md` and covered by
  `test_sprint_fatigue.gd`.

### 2026-10-07 - Motion Matching handovers and held props (#202 follow-up 6)

- Stopping into the tree's idle no longer slides: settling freezes the search
  and holds both feet, which stay planted (leash of a leg's reach) while the
  tree stands Henry still. Stop 0.58 → 0.23 m/s, standing 0.13 → 0.05 (tree
  0.26 / 0.08).
- From standing, Motion Matching takes over by inertialization instead of a
  crossfade (start 90° 0.66 → 0.56); from motion it still crossfades.
- A held prop keeps only its arm on the tree's held pose; Motion Matching walks
  the rest (new suite `test_motion_matching_hold_layer.gd`). Whole in-game
  program 0.474 → 0.438 m/s (tree 0.507).

### 2026-10-07 - Sprint build-up and top speed follow tiredness (#202 follow-up 5)

- `MovementController`: the sprint can build up more slowly as energy runs
  out (`exhausted_sprint_ramp_factor`), and below a stamina share the top
  sprint can fade to a laboured jog (`winded_sprint_share`) instead of running
  at full speed into a wall at zero. Rested with stamina to spare nothing
  changes (90% speed after 1.87 s either way). New suite
  `tests/systems/test_sprint_fatigue.gd`. Defaults made neutral in the
  hardening pass above.

### 2026-10-07 - Motion Matching: run data, honest trajectory ends (#202 follow-up 5)

- 36 CMU run trials join the database (`root-space-v8`, 12 490 samples,
  8.1 MB); Motion Matching now covers up to 3.58 m/s and keeps most of the
  sprint (skating 2.63 → 1.45 m/s). Whole in-game program 0.539 → 0.474
  (tree 0.507).
- Future trajectories past a clip's end continue at its end velocity instead of
  faking a stop (UE5 Pose Search extrapolation); the audit's feet-above-pelvis
  check now judges the supporting foot, so running strides pass.

### 2026-10-07 - Snow and wading with Motion Matching (#202 follow-up 4)

- `FootContactSensor` takes the animation's own contacts when it has them:
  Motion Matching registers as `contact_source` and its database contacts
  replace the height guess, which read low real-gait swings (1–2 cm clearance)
  as plants. Snow print slide with Motion Matching fell 1.0 → 0.35 m/s while
  walking (tree 0.46); extra footprints and footsteps are gone. The tree path is
  unchanged.
- `capture_motion_matching_player.gd`: snow captures are reproducible (seeded
  weather, rebuilds that finish in one step), report print slide, depth and
  wade, and `MM_PROGRAM=drift` crosses TestScene's deepest drift. The CI
  Motion Matching job runs the drift A/B.

### 2026-10-07 - Airtime and landings (#202 follow-up 3)

- Walk starts no longer hop: `MovementController` drops `start_jump_impulse`,
  whose only effect was one tick off the floor and a 1.17 s landing clip on
  every start. The AnimationTree's own foot skating fell 0.682 → 0.507 m/s over
  the in-game program (start from idle 1.09 → 0.60).
- `HenryUALAnimation` enters AirLoop after a 0.15 s fall timeout or a jump, and
  picks the landing by touch-down speed: soft landings walk on, hard ones play
  `Land` standing or the new `LandMoving` (impact, then the walk) on the move.
  Motion Matching follows these states instead of its own airtime timers.
- New suite `tests/systems/test_landing.gd`.

### 2026-10-07 - Motion Matching: retargeted feet stand on the ground

- `MotionRetargeter` removes each clip's median ground error (Henry's lower
  ball joint against its flat-foot rest height) from the pelvis. CMU subjects
  02, 07, 08 and 113 stood 2.5–3.5 cm above the floor on Henry; every range
  now has a median of 0 (max 2 cm on sub-ranges). Database rebuilt as
  `root-space-v7` and recommitted.
- In-game A/B over four stick scales (new `MM_STICK_SCALE` in
  `capture_motion_matching_player.gd`): whole run 0.625 → 0.594, walk after
  sprint 1.22 → 0.92; stop 0.44 → 0.49 within the run-to-run spread.

### 2026-10-07 - Data-matched body rates only while walking (#202 follow-up 2)

- `MotionMatchingLocomotion` applies the data-matched acceleration, braking and
  turn rate only in plain grounded walking; sprint (and its build-up), air,
  crouch, carry and actions keep the production rates. Sprint stop from
  4.35 m/s went 2.67 m → 0.49 m (production value); walking is unchanged.

### 2026-10-07 - Scripted walks brake onto their target (#202 follow-up 1)

- `Player._walk_direction` limits the commanded speed to √(2·a·d) at the
  body's braking rate (`MovementController.get_braking_rate()`), so interaction
  approaches and the door step-out stop on target at any braking rate.
  Rest error with the data-matched body 0.272 → 0.012 m; production
  0.019 → 0.012 m with unchanged timing. New suite
  `tests/systems/test_scripted_walk_braking.gd` fails on the old code.

### 2026-10-06 - Motion Matching: foot locking and a feature-flagged Player layer (#202)

- Foot locking on database contacts (`MotionFootLock`, Holden contact_update
  with inertialized transitions, drag instead of a hard unlock) and a two-bone
  leg solve shared with `SnowFootModifier` (`LegTwoBoneIK`, identical output).
  Lab: drawn planted slide 0.184 → 0.032 m/s with unchanged matching.
- `Player/MotionMatchingLocomotion`, off by default (`HOARBOUND_MOTION_MATCHING=1`
  or the export): the body stays authoritative, the matched pose is blended over
  the AnimationTree, which keeps actions, carry, sit, crouch, air, sprint and
  long idle. Additive hooks in `MovementController` and `HenryUALAnimation`.
- 31 CMU walks at game pace and the standing capture `111_28` join the
  database (11.3 k samples, audit clean); UE5-style steering of the root.
- `capture_motion_matching_player.gd`: deterministic in-game A/B on TestScene,
  also run headless by the existing Motion Matching CI job.
  Found: every walk start plays the jump-landing clip in production (start
  impulse lifts the body for one tick) — left for the jump rework.
- The runtime core moves from `scripts/experimental/motion_matching/` to
  `scripts/systems/motion_matching/`; the lab scenes stay experimental.
- Author decisions: the baked database is committed
  (`data/motion_matching/henry_cmu_locomotion.res`, 7.3 MB compressed, CMU only)
  and the audit fails when it no longer matches a rebuild; `data_matched_body`
  is on while Motion Matching runs. Known conflicts (scripted walks overshoot
  0.27 m, global rates while the flag is on) and follow-ups are listed in
  `docs/motion_matching/integration_plan.md`.

### 2026-10-06 - Motion Matching lab: root-space retarget, curated CMU database, simulation-led playback (#202)

- Replace the CMU/100STYLE retarget glue with per-family `SourceRetargetProfile`s,
  a pure-data `BVHClip` and `MotionRetargeter` (model-space rest delta as in
  `RetargetModifier3D` global mode, Holden simulation root, flat-foot and
  arm/leg reference matching, scaled pelvis translation).
- Fix root causes found by measurement: CMU unit was 0.0254 instead of
  0.0254/0.45 (walks at 45% speed, lateral clips never qualified); poses carried
  the capture's world yaw (Henry spun on every cross-clip switch); range ends
  froze the pose; #476's horizontal Henry came from an un-reset proxy skeleton.
- Curate up to 360 s of real CMU ranges with transitions, excluding source
  marker glitches; 100STYLE is staged but refused until its profile is verified
  (the session network cannot reach its host).
- Matcher: per-quantity normalization (pose positions share one scale),
  range-tail exclusion and UE-style pose-jump threshold. Playback: spring
  simulation drives the CharacterBody; the animated root follows by root
  motion with velocity-limited adjustment and clamping; two-slot crossfade.
- New `MotionRetargetAudit`, `audit_motion_dataset.gd` (headless gate) and
  `capture_motion_retarget_diagnostics.gd` (raw / normalized / Henry columns).
  Removed the obsolete CMU segmenter, multi-clip builder, BVH skeleton source,
  retarget lab scene and unused playback controller.
- Proof capture is a 26.5 s continuous analog program; CI job also runs on
  `claudeflow`. Production locomotion is untouched.
- Follow-up: live/baked foot-contact features, UE-style pose reselect history
  against tail ping-pong, and audit-failing frames cut out of baked ranges.
- Author decision: `neck_01`/`Head` are left to the production head-look
  layer at playback; baked data keeps the source gaze.

### 2026-10-04 - Remove duplicate high-tier footprint decals

- FootprintSystem now subscribes to foot plants only on the low snow tier.
  Medium/high use the deformable SnowShell as the single footprint renderer;
  the former duplicate decals could appear beside pressed tracks.

### 2026-10-04 - Restore mapped city props and authored shadow brush (#173)

- File power poles and wires into the existing streamed city chunks, retaining
  their collision and keeping wire shadows disabled. The temporary global prop
  builder previously freed both visual layers immediately after indexing.
- Restore palms, bare trees, storage tanks and terrain-following crossings lost
  through the same temporary-node path; crossings are now meshed per chunk.
- Re-enable the configured dry-brush shadow mask by restoring its blend range.
  The former zero-width clamp silently ignored `stylized_shadow_brush_mix = 1`.
  Runtime appearance and performance await the author's HD 620 comparison.

### 2026-10-04 - Restore opt-in console performance capture (#173)

- Restored `World.print_runtime_debug_stats` and once-per-second PerfMeta/PerfJSON
  output for author-run HD 620 comparisons. The city mesh-surface traversal
  remains retired; viewport timing is collected only while the toggle is on.

### 2026-10-03 - Retire performance audit tooling before commit preparation

- Removed the A/B controller and its production scene binding, temporary
  capture scripts, C# benchmark and opt-in CPU scopes after the author's audit.
- Removed console PerfJSON/city diagnostics and their mesh-surface readbacks.
  StatsDisplay retains the lightweight wall-clock FPS panel; city streaming,
  snow, sky and wind production changes remain in place.
- Preserved the measurement report and local evidence. Retired tooling and
  pre-cleanup source copies are archived under ignored
  `shots/issue173_audit/retired_diagnostics/` and are not part of the commit set.

### 2026-10-03 - HD 620 runtime diagnosis and bounded C# comparison (#173)

- Added opt-in CPU scopes, render configuration metadata, per-frame diagnostic
  captures and an isolated C# baked-depth prototype. Two graphical runs exposed
  blocking city-stat mesh reads, expensive local snow rendering, and synchronous
  multi-second snow-topology builds. Production render features stay enabled.
- Recorded the A/B matrix, raw-evidence locations, C# output equivalence and
  limits in `docs/technical/PERFORMANCE_AUDIT_2026_10_03.md`. Quiet stationary
  control measured 5.63–5.76 FPS; diagnostics-on measured 3.37–3.68 FPS.
- Moving snow transitions remain unaccepted: the audit's low spawn placement
  did not establish floor contact, so its attempted street walk is invalid.

### 2026-10-03 - Stream city massing, far sectors, helpers, and snow sampling follow-up

- The author's new frame showed dark patches and an intermittent square at
  Henry's snow window. Restored the SnowShell shadow-caster exclusion from
  `decee6a`, which a later uncommitted snow edit had accidentally removed.
  The far-cover window mask now switches after the replacement local texture
  and mesh are prepared. Packed tint, roughness, rim, normal and glint now fade
  with the near mesh's existing edge blend instead of retaining a local-snow
  material across the handoff; the thin-cover cut matches the far shader at
  the exact edge. The separate near/far coverage and height seam
  is still subject to the author's visual check; these source fixes are not
  proof that every square edge is gone.
- The 30 s baseline in the new log contained only 6.43 s between sample events
  because a startup stall overshot warmup and the A/B timer counted that
  overshoot as sample time. The harness now starts a full sample interval at
  `sample_begin`. This run is diagnostic, not an accepted paired #173 result.
- Removed all-city massing creation from `build_stream_ring0()` and chunk
  activation. RuntimePerformancePolicy now creates ring-0 massing only for the
  nearby city neighbourhood and releases sectors outside that range.
- Added 117 baked ultra-low OBJ sectors covering all 12,354 city proxies plus
  chunked low-detail road and airport strips. Existing StreamingSystem owns their
  residency; GeometryInstance3D ranges overlap local massing and use hysteresis.
- Moved supplemental sidewalks, coast, piers, barriers, towers, airport areas,
  and runway markings into per-chunk visual nodes. Long line features and airport
  areas are clipped to their owning chunk; street props remain indexed by chunk.
- Removed the island-wide Ring-0 road mesh; local streets stream with their chunk,
  while the far OBJ sectors carry the simplified road network.
- A previous status note said streamed exact-building and street-prop collision
  bodies had been tagged and excluded from SnowShell classification. Source
  review found no such group/tag in the current implementation; that earlier
  fix claim was inaccurate.
- The author's latest run still showed the snow defect and square cuts by walls.
  Removed my raster-footprint hard cut, terrain-only sampler, and calculated
  shell bounds; restored Claude's physical wall/deck/roof classifier and culling
  setup. The later velocity-lead increase did not fix the reported morph and
  has been returned to Claude's 0.9 s / 4 m settings.
- History review found the local 6 m snow-window handoff deliberately changes
  static detail from the chunk base to SnowField geometry; only the boundary is
  guaranteed to match. Key West now derives visible near and far settled
  geometry from the same terrain, baked city wind field and world position.
  Packed tracks remain local; current gusts no longer rotate settled ridges
  when the window moves. Settled cover can rebuild while Henry stands still.
  The city's exact OSM polygons classify house walls before detail colliders
  load. Streamed CityCollision bodies are ignored by settled-snow rays.
  Far-cover triangles are now clipped against those same contours rather than
  removed as 2 m square cells, including buildings inside one cell. The authored
  First Exit shelter registers its outline in the same snow index after its OSM
  replacements are excluded.
- Key West now instantiates the existing WindGusts effect directly. The First
  Exit template that previously held it is freed after transplant, so its
  wind streaks and ground drift were absent despite the blizzard profile.
- These snow and wind changes are source-only. Near/far terrain tessellation and
  the wall handoff still need the author's runtime visual review; no claim of
  a fully invisible transition or FPS gain is made without that evidence.
- The supplied performance log reports about +1 FPS, but it is marked `baseline`
  with no mutations, so it cannot isolate this pass. It reports 52 resident far
  city sectors, 4 detail chunks, 7 nearby massing chunks, and about 2,452 detail
  buildings; no additional gain is claimed from the log.
- Python syntax and baked sector counts were checked. Godot was not launched;
  HLOD transitions and the moving snow surface still require the author's
  runtime walk and silhouette review.

### 2026-10-03 - Restore the parallax sky shader path

- The author's log pinpointed an unsupported early `return` in `sky()` as the
  shader compilation error; the null shader-version report followed it.
- Replaced the early exit with explicit branch control flow so the half-resolution
  sky result composites and the cubemap/background paths both assign `COLOR`.
- The runtime shader was not launched here; the author will confirm compilation
  and cloud visibility in the next run.

### 2026-10-03 - Bind diagnostics to city streaming

- The supplied 30-second Fort Street sample averaged about 3.3 FPS, 214.8 ms
  total GPU and 194.8 ms in `/root`; it showed four active city detail chunks
  while the policy's `exact_owner` stayed empty.
- `World.gd` constructs systems with `Script.new()` as direct children, so
  `StreamingSystem` lookup by `Node.name` was not reliable. The existing policy
  now binds the direct child by its script type and reports `streaming_bound`.
- The one-owner pruning pass dropped exact neighboring buildings and collisions
  at a chunk edge, replacing them with non-colliding massing boxes. That pass has
  been removed; StreamingSystem now retains overlapping detail chunks with at
  least its authored 140 m load margin and 120 m unload hysteresis.
- Diagnostics report the active city stream IDs. This correction is source-only
  until the author's next runtime check; no game or benchmark was run.

### 2026-10-03 - Issue #173 performance candidates

- Kept the existing SnowShell shadow-caster exclusion, two-split directional
  shadow policy, city caster policy, and realtime sky setup.
- Reduced directional shadow filtering to Soft Low, blur to 1.1, and map size
  to 2048. These remain visual/performance candidates pending matching HD 620
  captures.
- Tightened SnowShell's culling bounds from current field samples and its
  displacement limits. Kept the 3 cm near-foot grid and increased spacing only
  beyond the 3.5 m near region.
- Added a cheaper atmosphere-only cubemap path with reduced integration samples;
  the visible Freeman/parallax background remains unchanged.
- Disabled 3D MSAA and enabled FSR 1.0 at 0.77 render scale while retaining
  screen-space AA. This global project default needs author visual review.
- The supplied PerfJSON is a baseline without a matching before/after camera
  pair. No runtime, capture, or benchmark validation was run in this pass.
- `detail_radius_m` is consumed only by the currently unreferenced `set_focus()`
  path; active detail residency is owned by StreamingSystem, so the city ring
  was not altered based on an inactive setting.

### 2026-10-03 - SnowShell outer grid contour

- The author reported a visible rectangular edge around Henry. Source review
  found the outer grid spacing was growing 8% per step, making the already
  rectangular 25.6 m SnowShell's outer triangles much coarser. Restored the
  previous 2.5% growth while retaining the 3 cm near-foot spacing and the 25 cm
  far-spacing cap.
- This is a source-based corrective candidate; visual confirmation still needs
  the author's next close-up capture. No Godot run was performed.

### 2026-10-03 - Stable snow response at streamed city walls

- History review traced the movement-dependent result to the incremental ground
  cache introduced in `5558446`: only newly exposed strips are sampled, and
  those samples used to classify whichever streamed city colliders happened to
  be loaded at that moment. The baked city wind map already owns static city
  shelter and lee response.
- Source review found the earlier status report about tagging streamed city
  collision bodies was not reflected in code; SnowShell still raycasted the
  live physics world. The later raster-mask/terrain-only attempt introduced
  square cuts at walls and has been reverted to Claude's classifier. The author
  still needs to review the resulting runtime behavior.
- Static review only. The author requested no game launch and will confirm the
  street walk in the next runtime capture.

## [Unreleased] — `codex`

### 2026-10-01 - Doorway camera: compose before the jamb, never fade (claudeflow, after #170)

- Author's direction: "360° freedom of view != 360° physical orbit". `TpsCamera`
  splits the **view** (where the player looks; only the mouse turns it) from the
  **orbit** (where the camera body may stand). In a doorway the body is held in a
  cone derived from the opening; the view may look past it only while Henry stays
  in frame. Outside doorways both are the same, as before.
- Passage data is authored, not guessed:
  - `PassageInfo` describes it: plane, axis, clear width and height, wall depth,
	shoulder side, and optional yaw limit, distance and FOV.
  - It comes from a new `NarrowPassage` marker or from an open `HingedDoor`
	(new `wall_thickness_m`).
  - The raycast guess stays as the fallback. It now finds the door plane and wall
	depth; before, its centre moved with Henry.
- `PassageTraversalComponent`:
  - Walking at a passage engages it; standing in its frame does too. With no key
	held, an approach lets go after 0.5 s.
  - Past the threshold the traversal commits. Released keys carry Henry on until
	his capsule is 0.3 m clear of the wall, then he stops. S reverses, and
	sideways input is dropped.
  - Without a key at the threshold nothing moves him. Neither the Hub, actions nor
	scripted walks commit; `Player` passes that in.
- Doorway framing, all derived from the passage:
  - **Pre-compress.** The frame starts closing 1.0 m (plus a speed lead, more on a
	slanted approach) before Henry's capsule reaches the wall. It stays closed
	while the boom behind him crosses the frame. It closes at rate 8 and opens at
	rate 3. A camera leading Henry backwards frames the door before he reaches it.
  - **Shoulder.** Kept within half the free opening round the centre line, so it
	slides inward or across when Henry is off-centre. Your shoulder choice is never
	changed.
  - **Boom.** 1.4 m less any wall depth beyond 0.2 m, at least 1.0 m.
  - **Rise and FOV.** Rise is at most half the room under the lintel. FOV is +5°,
	capped at 80°.
  - **Cone.** Yaw room comes from the clear width, Henry's offset and the depth to
	the far wall face; pitch room comes from the lintel and the floor. The cone
	closes at once as Henry walks in, opens at the release rate, and ramps in over
	0.5 m as the boom tip nears the wall.
  - **Mouse.** Eases into a soft stop over 10°; looking back in is never eased.
	The fixed ±35° stop and the hard mouse block are gone. Pitch stays free until
	Henry would leave the frame.
  - **Automatic turns.** Off in a doorway, and any standing offset glides out.
- Recompose before fade: closer than 1.1 m to the eyes, the shoulder gives way to
  the centre line, plus +3° FOV, if same-frame casts say that gives the boom room.
  It never does so with Henry's back to a wall, where it would bring the camera
  closer. The body fade is now the last resort.
- `framing_pivot_share` puts the orbit pivot anywhere between the shoulder joints
  (0, default, 1.40 m) and the coat (1, 1.52 m), for the author's pivot study.
- Tests (not run here, the author runs them):
  - New `test_doorway_camera` drives 12 scenarios through the real Key West
	shelter door. It checks: no dither, no camera in a wall, no near clip, head
	never occluded or off screen, no pops, FOV under 45°/s, control yaw only from
	the mouse, Henry clear of the frame after a traversal, full mouse freedom
	after the door. `-- <label> [pivot=<share>]` writes per-frame traces.
  - `test_passage_traversal` adds: a key released in the door, and authored
	passages at 1.45 × 2.20 and 1.60 × 2.30.
- Baseline before this pass (Key West door, standing in the plane, 360° mouse
  sweep at 144 fps): Henry dithered in 192 of 432 frames (max 0.79), the camera
  came within 0.33 m of his head, and one 0.63 m single-frame pull-in.

### 2026-10-01 - Henry's measured body, doorway traversal (claudeflow, #170)

- `HenryMetrics` (`data/characters/henry_metrics.tres`) holds Henry measured
  from the model the game loads. `tools/runtime/measure_henry_metrics.gd`
  CPU-skins the dressed `henry_outfit.glb` through the live skeleton and
  averages 16 idle and crouch-idle poses. Standing: crown 1.79 m, eyes 1.62,
  shoulder joints 1.40, coat over the shoulders 1.52, width 0.60, chest depth
  0.36, pack +0.32 behind the coat. Crouched: eyes 0.90, shoulders 0.86.
  Capsule: radius 0.5, height 2.0 / 1.3.
- `TpsCamera` drops ADT's `EYE_RATIO`, `SHOULDER_RATIO` and `body_height`. The
  pivot sits on the shoulder joints, fades read the eyes, and the stance blend
  follows the capsule between its measured heights. ADT's crouch scaling had
  put the eyes 0.20 m too high. The pivot on the coat (0.10 m under the eyes)
  hid Henry with his back to a wall; `test_tps_camera_orbit` caught it.
- Framing heights are added after the follow lag, so a crouch or a doorway is
  smoothed once, by its own exponential damp.
- `PassageTraversalComponent` on Henry: a short doorway is found from facing
  jamb rays (a corridor is not a doorway). While a key pushes along it, Henry
  is steered onto its centre line and through; S brings him back out. There is
  no teleport, and walking and animation stay as they are.
- Doorway framing in `TpsCamera`:
  - boom down to 1.4 m, shoulder to 25 %, +0.15 m rise, +6° FOV;
  - the view stays within ±35° of the passage axis, and the mouse cannot push
	past it;
  - the frame closes at rate 12 and opens back out at rate 3.
  - The body fade stays only as a fallback.
- `test_passage_traversal`: a 1.2 m door taken 35° off, the frame closing fast
  and reopening softly, backing out with S, and a 1.4 × 8 m corridor that is no
  doorway.
- `tools/runtime/capture_tps_doorway.gd` grabs the shelter door at entry, middle
  and exit. Its floor ray now starts inside the opening; from above, it landed
  on the lintel.

### 2026-10-01 - TPS camera review fixes: control yaw, prop chains, sway-free aim (claudeflow, #170)

- Review of `ae305d8` found that automatic turns rewrote `_yaw`, which
  `get_yaw()` hands to WASD. The test only passed because I had switched its
  check from "heading against the mouse yaw" to "heading against the view".
  Now control and view are split, Unreal's ControlRotation versus camera
  modifiers. `_yaw` changes only with the mouse; room search, recentring and
  whiskers move a view offset. Mouse travel folds that offset into the control
  look, so the view never jumps; steering keys glide it back out.
  Measured: control yaw moved by automatic turns 0°; W heading against the
  mouse yaw 0° (was 74° before #170).
- `TpsBoomProbe` passed at most 4 thin colliders, then returned "path free",
  which a fifth prop before a wall would breach. It now passes up to 16 and
  counts the next as a wall (fail-safe). `overlaps()` reports only blocking
  bodies; thin ones the camera sits inside fade instead of snapping it.
- Breathing sway is presentation only: `TpsCamera.aim_origin()` and
  `aim_direction()` turn the last sway back out of the camera's real
  transform. A camera posed by hand, as in `test_shelter_workflow`, still aims
  where it points. `InteractComponent`,
  `BedrollComponent`, `BreachBoardUp` and `MouseCursorUI` use them for their
  centre rays.
- The space rods run every frame and cover only the camera's half of the
  circle, plus the ceiling. A wall in front of Henry no longer shortens the
  boom, and the 10 Hz steps are gone.
- The body fade weighs each fragment by its distance to the camera: head,
  shoulder and pack dither, and the legs a metre out stay. Non-stylized meshes
  are capped at 70 %.
- `test_tps_camera`:
  - adds "control yaw unchanged after an automatic turn", 5 and 20 poles before
	a beam, and "gameplay ray ignores an 8° sway";
  - each check fails on a mutation of the bug it guards.
- `trace_tps_camera.gd` measures heading against the mouse yaw again.

### 2026-10-01 - TPS camera rig: safe origin, feelers, player priority, fades (claudeflow, #170 T3–T9)

- Rig rebuilt after Lyra and Cinemachine: a safe point inside Henry's capsule →
  a swept shoulder → a swept camera. The centre sweep snaps the boom in at
  walls, six feelers (±16°, ±32° yaw, ±20° pitch) ease it in, and every
  release eases it out. The shoulder is a real offset; `h_offset` is gone.
- Stance comes from Henry's capsule: crouching lowers the camera by 0.50 m (it
  stayed put), and under a 1.5 m slab the camera stays below it.
- Author decisions: walls snap; thin colliders (middle extent < 0.6 m),
  characters and unfrozen rigid bodies let the boom pass and fade to 70 %
  transparency on the camera-to-eyes line.
- `TpsAutoLook`: automatic turns wait 0.9 s after the mouse rests. Room search
  works standing; recentring follows W or a scripted walk, not strafing or
  backing up; Daedalic whiskers steer away from walls while moving. `get_yaw()`
  is the view, so WASD always matches the screen.
- Henry dithers out (`camera_fade`, Bayer 4×4 in
  `stylized_environment_body.gdshaderinc`) from 0.8 m to 0.25 m, instead of a
  hard cull at 0.3 m.
- Rods weight the camera's side and ignore thin props; looking up shortens the
  boom to 60 % before the ground does.
- Measured in TestScene: over 360° sweeps at 8 poses (doorway, corner, walls,
  window, open), frames with Henry cut out went from 1865 to 0; he dithers
  instead. Near-plane clips on the door jamb 36 → 0. Thin-pole pops 3 → 0.
  Head hidden under a slab 31 % → 0. A sideways door pass no longer cuts Henry
  out for 246 frames. Model and numbers: `docs/technical/TPS_CAMERA.md`.
- Tests: `test_tps_camera` adds crouch, low ceiling, thin pole and
  mouse-priority checks. `test_tps_camera_orbit` now asks for fading instead of
  an instant swing. New `tools/runtime/capture_tps_camera.gd` for stills.

### 2026-10-01 - TPS camera follows the mouse every frame (claudeflow, #170 T2)

- Measured first with `tools/runtime/trace_tps_camera.gd` (TestScene, real
  Henry, 144 fps against 60 Hz physics): the camera turned on 42 % of frames,
  trailed the mouse by 30 ms and needed 76 ms for 90 % of a 13° flick; walking,
  camera and body stood still on 84 of 144 frames.
- Cause: look and pose lived in `_physics_process`, physics interpolation was
  off, and `look_smoothing` filtered the mouse on top.
- `physics/common/physics_interpolation` is on. `TpsCamera` runs in `_process`
  on Henry's interpolated transform; mouse look is applied as it arrives with
  no filter. Follow lag now trails only the orbit centre (16 across the ground,
  10 in height), so the orbit answers the mouse at once.
- `InputSystems.consume_look_delta()` replaces `get_look_delta()` and reads
  `screen_relative`: the viewport stretch no longer rescales mouse look (0.75×
  on a 2560×1440 screen, 19× in headless).
- `TpsCamera.snap_to_target()`; a target jump over 1.5 m in one frame snaps
  the camera too. Spawn, sitting down and save load reset Henry's
  interpolation. Snowfall emitters, moved per frame, opt out of it.
- After: 100 % of frames turn, lag 0, a flick lands on the next frame (7 ms),
  walking camera step cv 1.18 → 0.008, a teleport no longer flies for 1.3 s.
  `test_dev_diorama_map`, `test_door_draft` and `test_shelter_workflow` fail
  identically on the base commit; all other suites pass.

### 2026-10-01 - Review angles for #156 rendered against predictions (claudeflow)

- `capture_stylized_shadows.gd -- review` renders physical/dry pairs for normal
  daylight, heavy snow, a Duval Street block, the shelter exterior and a 16:30
  low sun, with the clock and Henry frozen. Predictions were recorded in
  `LIGHT_AND_SHADOW_DIRECTION.md` before the render.
- Held: snow and street shapes, facades keeping strokes beyond the ground fade.
  Off: heavy-snow contrast drops 13 % (predicted 6–10 %); low sun is dimmer and
  flatter but less than predicted (lit snow L* 62, contrast 31 against noon 99
  and 63).
- Found: the shelter wall's soft eave shadow becomes hatching, as designed. At
  low sun, faint penumbrae from thin distant casters become full mid-tone
  strokes on open snow. A fix candidate is recorded, not applied: jitter scaled
  by penumbra depth.

### 2026-10-01 - Dry brush strokes are the default shadow spray (claudeflow)

- Author's pick after the Key West A/B: `stylized_shadow_brush_mix = 1` with
  `shadow_brush_dry.png` in `project.godot`. Penumbras now break into scratchy
  35° strokes instead of value-noise islands; lit and core tones are unchanged.
  Flat stays in the repo; mix 0 brings the noise back.
- `capture_stylized_shadows.gd` restores the project's spray after a brush run,
  and `-- shimmer` renders each spray from the TPS pose and shifted half a pixel
  sideways, with clock, snowfall and Henry frozen.
- Shimmer measured in Key West. The far band matches physical for every spray.
  Near the camera, dry flips 1.18 % of pixels beyond physical (noise 0.45 %).
  Every flip is on a world-locked stroke edge (0.49 per edge pixel against 0.67
  for geometry edges), with no isolated popping: crawl along unantialiased
  edges, not shimmer. The capture tool no longer errors if its output folder
  disappears before the report is written.

### 2026-10-01 - Brush-stroke masks for the shadow spray, off by default (claudeflow)

- `tools/art/generate_shadow_brush_masks.py` stamps two tileable placeholder
  masks (1024² = 1.5 m, strokes at 35°): `shadow_brush_dry.png` and
  `shadow_brush_flat.png`. An artist's baked or painted mask replaces them.
- The shadow spray can read a mask instead of value noise: triplanar in world
  space (model space on Henry), selected by the globals
  `stylized_shadow_brush_mask` and `stylized_shadow_brush_mix` (0 keeps noise).
- Calculated before rendering: mipmaps alone do not fade a stroke mask (std
  0.47–0.71 left at a 4.8 cm pixel, where the noise is gone), so the mask fades
  on the noise's base-octave window. Predictions and the Key West A/B:
  `docs/art/LIGHT_AND_SHADOW_DIRECTION.md`. `capture_stylized_shadows.gd -- brush`
  renders physical, noise twice, dry and flat for each view.
- Measured in Key West at noon, all four predictions held. Only penumbra
  pixels change (shelter: 0.29–0.44 % of the frame against a 0.02 % floor).
  Nothing changes beyond ~8.5 m on the ground. The masks impose one stroke
  direction (agreement 0.50–0.86 against 0.20–0.58 for noise). Flat reads as
  broad strokes, dry as hatching. Recommended: flat, once surfaces are painted;
  the default stays noise until the author decides.
- Found: a sun sliver narrower than the penumbra is all penumbra. The shelter
  floor sliver keeps 49 % of its length with the shipped noise, 79 % with flat.

### 2026-10-01 - Stove light leaves through the door, not all around (claudeflow)

- The shelter stove's room light was an omni 0.41 m above the cooktop, lighting
  every direction. `StoveVisual` now places it in the fire, 0.16 m behind the
  door, aimed out through it. `Flame` is a `SpotLight3D` (65°, range 9 m,
  falloff 0.5). The firebox walls and door bars are its shadow mask: closed, the
  light leaves only through the bars; open, a floor pool appears.
- Predicted from the stove and room geometry before rendering, then measured.
  The wall behind the stove went from L* 41 to 21. The ceiling shows bar stripes
  at ΔL* 23 (predicted ≈ 20). Henry's silhouette on the far wall rose from
  ΔL* 6.6 to 17 (predicted ≈ 15).
- `LIGHT_AND_SHADOW_DIRECTION.md` adds the measured cause of Henry's weak
  shelter shadow, the cloud-shadow calculation (today's sky covers ~2 %, so
  sky-matched shadows would show nothing within the fog's 100 m), the snowfall
  coverage inversion it found, and brush-stroke sources with licences.

### 2026-10-01 - Day palette: key over a sky-blue fill, air unchanged (claudeflow)

- Day key 1.12 → 1.5, colour (1.0, 0.98, 0.95) → (1.0, 0.97, 0.92). Fill
  0.92 → 0.55, colour (0.58, 0.64, 0.70) → (0.46, 0.58, 0.86). Shadows on snow
  read blue instead of grey. Before, the fill was nearly as strong as the sun
  and the same hue.
- New `DayNightSettings.day_atmosphere_light_energy` (1.12): the sun energy the
  volumetric fog and the cloud lighting see. Without it the stronger key
  brightened the air; with a warm key it turned the fog beige. Measured: fog/sky
  unchanged, shadow core under Henry 88/93/91 → 70/78/89 sRGB.
- Night values are unchanged. Values and comparison:
  `docs/art/LIGHT_AND_SHADOW_DIRECTION.md`.

### 2026-10-01 - Henry on the stylized shadow contract, with a rim (claudeflow)

- Henry's body, garments, Kenny and his strap, the pack, and the carried logs and
  boards use `StylizedEnvironmentMaterial.make_character()` instead of
  `StandardMaterial3D`. Shadows falling on him now break up like the world's.
  Wetness still darkens the garments, now through the shader's `albedo_color`.
- The shared opaque material gains character settings, all off by default: a
  rim on the lit silhouette edge (0.6), a third of the shadow-lookup offset for
  thin limbs, and shadow noise in model space so the breakup rides with the body.
- The camera stays third person; `LIGHT_AND_SHADOW_DIRECTION.md` now describes
  "2.5D" as a look, not a camera, and drops the isometric-camera items.
- `capture_stylized_shadows.gd` adds close frames of Henry: outside at noon,
  and backlit by the stove.

### 2026-10-01 - Light and shadow direction: research and roadmap (claudeflow)

- `docs/art/LIGHT_AND_SHADOW_DIRECTION.md`: what Disco Elysium, The Long Dark
  and Diablo IV do, what painters and technical artists say about shadow
  colour, edge hierarchy, massing, brushwork, character readability and
  grounding, and where Hoarbound stands on each. Includes the 2.5D camera
  implications and a prioritised roadmap with the decisions it needs.
- New evidence in `docs/art/stylized_shadows/`, including a key/fill colour
  comparison. Shadows only turn blue once the key dominates (~4:1); today's day
  fill is nearly as strong as the sun.
- Sub-pixel camera-shift test: the world-space noise adds no shimmer at
  distance. Hard tone-cut edges near the camera flip 0.37 % of pixels
  (0.15 % physical). Recorded in `STYLIZED_SHADOWS.md`.

### 2026-10-01 - Stylized shadows rebuilt on stock Godot, shelter included (claudeflow)

- Author decisions: no engine fork; stylize the shadows only.
- The old contract edited `ATTENUATION` only inside a few-centimetre penumbra,
  with 2–18 m noise: on a replica of the reference it rendered as physical
  shadows. It is replaced, not tuned.
- New `stylized_shadow.gdshaderinc`: every light's shadow lookup moves by
  world-space noise in the surface plane (`LIGHT_VERTEX`), tearing cast
  silhouettes; the directional shadow is cut into three tones with
  noise-jittered cuts, so the penumbra breaks into a halo of mid-tone islands.
  N·L stays physical; noise octaves fade before they alias.
- Sun `shadow_blur` 3.3 widens the penumbra the halo is cut from. The
  directional soft-shadow filter is Soft High (16 taps): Soft Low's per-pixel
  PCF dither turned into speckle once cut into tones. Quality also scales the
  filter radius (2/3/4 for Low/High/Ultra), so blur was lowered to keep the
  width. Real-GPU cost still to be checked.
- Shelter: the stove `Flame` casts shadows; the house is no longer converted
  with stylization off; local lights get the torn lookup.
- Removed the patched-engine sampler path, `tools/engine/*`, its doc, eight
  unused shader globals and an unreferenced noise texture.
- `capture_stylized_shadows.gd` adds shelter interior frames (noon, stove at
  night, each LUT). Model and measurements: `docs/technical/STYLIZED_SHADOWS.md`.

### 2026-10-01 - Dev map marker aligned to Henry's geographic position (codex)

- Fixed the primary marker drift: SubViewportContainer stretch can resize the live SubViewport, but the marker conversion incorrectly scaled Camera3D output against the initial 640×360 allocation a second time.
- Marker projection now converts from the live SubViewport size to the actual displayed map rect instead of a hardcoded render size.
- Henry's exact X/Z is projected onto the live IslandTerrain height; worlds without terrain fall back to the bottom of Henry's collision capsule instead of a point above his body.
- Existing dev-map regression coverage now checks live viewport-to-panel projection, ground projection and X/Z tracking after movement.
- Dev-map capture records a second full frame after Henry moves so positional alignment can be visually reviewed.

### 2026-10-01 - Runtime performance panel moved into World developer tools (codex)

- `StatsDisplay` now shows FPS, frame time, process time, physics-process time and engine-session uptime directly in the panel.
- `World` owns the panel through its existing UI composition path with `enable_runtime_debug_panel = true` by default.
- Added `print_runtime_debug_stats = false`; when enabled, the same visible snapshot is mirrored to stdout.
- Removed manual StatsDisplay instances from World-based scenes so the panel has one lifecycle owner.

### 2026-10-01 - Color-grade import-gate parser fix (codex)

- Declared the existing `WorldEnvironment.environment` reference in the color-grade harness; current `main` used an undeclared local `environment`, which the clean import gate correctly rejected.
- Gameplay/runtime behavior is unchanged.

### 2026-10-01 - Project identity renamed to Hoarbound (codex)

- Renamed the Godot/.NET project identity, solution and project files to `Hoarbound`.
- Replaced the former project title in current product, licence, UI and technical documentation.
- Replaced the long README with a compact bilingual EN/RU overview focused on genre, setting and the First Exit goal.
- Stable internal `HFN_*` / `hfn/*` technical identifiers are intentionally unchanged in this pass to avoid resource/API churn.

### 2026-10-01 - Engineering contract raised to production quality bar (codex)

- Expanded `AGENTS.md` with root-cause-first engineering, research before
  implementation, engine-native/proven techniques, and a ban on surrogate
  mechanics or compensating patch stacks.
- Clarified that tests protect settled decisions: unstable mechanics use the
  cheapest useful runtime evidence first, while permanent regression tests and
  expensive CI are added only after the mechanic and method have stabilised.
- Codex remains on `codex`; permanent agent branches are reused, with
  fast-forward sync preferred when a branch is only behind `main`.

### 2026-10-01 - Snow: RDR2-style wading, snow on boots, prints keep up with a run, synthesised footsteps (main)

- Prints vanished while running: the 25.6 m window rebuilds at 4 ms/frame and
  fell behind, leaving Henry in its 6 m faded rim. It is now built 0.9 s ahead of
  his travel and rebuilds at up to 12 ms/frame near the rim. A run landing also
  packs up to 55 % of the give at once, so running prints are not shallow.
- Knee-deep snow: 38 % speed, 45 % acceleration, a speed dip on every plant
  (surging gait), knee drive on the swing, the shin ploughing the lower half of
  deep snow, clods thrown ahead of a ploughing toe.
- `BootSnowComponent`: clods pack onto the toe caps after deep steps (wet snow
  most), shake off on brisk steps and melt in warmth.
- Footsteps are synthesised by `tools/audio/generate_snow_footsteps.py`
  (crumpling model after Fontana & Bresin 2003, heel-toe particles after Cook
  2002) into seven banks, including a pull-out; the CC0 recordings are removed.

### 2026-10-01 - Snow: narrow prints, broken edges, straight knees, depth-aware footsteps (main)

- Bent knees at spawn: idle feet were treated as swinging (the step sensor only
  plants moving steps) and lifted onto the snow while the hips followed 60 %.
  Standing still both boots now rest in their prints; hips follow fully.
- The wide furrow: the toe drag followed the walk clip's foot under the snow and
  ploughed every swing. It now follows the visible, lifted boot. Wall slopes are
  65° powder / 84° crust instead of a 40° cone that doubled print width.
- Broken print edges: noise-jagged outlines (crust more than powder), blue cut
  walls with snowfall strata, crack seams out from crust lips, sparkle on breaks.
- Footsteps by snow depth, softness and air temperature (crunch deepening with
  sink, muffled deep powder, cold squeak below −8 °C, dull wet snow, pull-out of
  deep prints). `SoundSystem.play` takes an optional gain and pitch factor.

### 2026-10-01 - Doors: back to a kinematic hinge; Henry pushes with his hand (main)

- The RigidBody3D leaf from `cbafe26` was thrown out of its frame on F (contact
  depenetration against the joint). The door is a scripted hinge again, now
  symmetric both ways, and stops against Henry instead of passing through him.
- The door opens inward only (sign of `open_angle_deg`; `swings_both_ways` for
  saloon doors); the frame stops it and a firm push into the frame latches it.
- F reads where Henry stands: outside it cracks the door inward, inside it
  pulls it wide (the leaf eases him aside); on an open door he pushes the face
  or pulls the handle, whichever way the leaf moves, and it swings shut and
  latches, waiting if he stands in its path. Walking into an unlatched leaf,
  his left hand plants on it and the leaf keeps ahead of the palm.
- A fully open door no longer creeps shut: the open stop only damps (no spring
  back) and the hinge has stiction, so wind and brushes do not move a resting leaf.
- The leaf never shoves Henry: it stops short of his actual capsule; when F
  swings it towards him (pull open from inside, pull shut) he steps out of its
  arc by the shortest way and it follows. Doors play no generic reach clip.
- New `DoorPushComponent` (made by Player) and `DoorHandIK` (last skeleton
  modifier): two-bone arm solve, braced elbow, palm laid flat from the finger roots.
- `test_hinged_door.gd` rewritten for the kinematic model. Not run by Claude.

### 2026-10-01 - Snow that behaves like snow: displaced rims, walls that slump, legs with weight (main)

- Model after Sumner, O'Brien & Hodgins 1999 (*Animating Sand, Mud, and
  Snow*): a boot compresses part of the snow and pushes the rest onto a rim
  outside the sole, heaped towards its travel (30 % in powder, 5 % in crust).
  The packed field is now signed; negative texels are that heap.
- Walls collapse for real: one mass-conserving erosion step per accumulation
  pass sheds any wall steeper than the snow holds into the pit, crumbling in
  random bits. Powder slumps to 40°, crust stands at 78°; a wall a boot still
  touches holds. The drawn slope uses the same two angles instead of 40° for all.
- Prints: the sole is heel + forefoot pads (a boot's waist); the heel digs on
  strike and the ball on push-off, so prints are deep at both ends. Toe-off in
  powder flicks a burst of grains ahead.
- Legs (RDR2-style): boot lift runs on a damped spring, a planted boot is
  pinned against the clip's glide (up to 10 cm, then slides), hips dip on each
  plant by snow depth. Deep snow also cuts acceleration to 45 %.
- Track tiles store signed bytes (zero at 32) so rims survive window moves;
  older saves are lifted on load.
- Not verified in engine by Claude (author tests in the open editor).

### 2026-09-30 - Snow prints without stair-steps; legs lift only as far as the snow needs (claudeflow)

- Stair-steps came from the drawn slope: a max over five rings 9 cm apart made
  terraces, and nearest-texel contact made the rim saw-toothed. The ground now
  reads a shaped copy of the packed field: a separable dilation by the repose
  cone along x then y (true 40° walls, no rings), then a 5x5 Gaussian
  (`snow_shape.gdshader`, three passes after accumulation). Stored packing,
  track tiles and collapse still use the raw field.
- Legs: WadeModifier no longer lifts the knee a fixed 48°; SnowFootModifier
  lifts a swinging boot exactly to clear the snow under it (+3 cm) and keeps a
  planted boot on the print floor. Torso lean starts at 0.3 m of snow, not 0.1.

### 2026-09-30 - Smoother prints: no stair-stepping (claudeflow)

- Contact is read with four sub-texel taps, so a boot edge presses part of a
  texel part-way and print outlines are smooth rather than stepped.
- The drawn slope samples twelve bearings turned per point (no polygon facets),
  and pit shading comes from the smooth packed field clamped to the repose
  slope instead of per-triangle derivatives.

### 2026-09-30 - Henry's body is a capsule: no more stalling by the shelter (claudeflow)

- Henry's collider was a cylinder. On the HeightMapShape terrain its flat rim
  caught cell edges: by the shelter logs he walked in place and was pushed
  sideways with no reported collision. It is now a capsule of the same size
  (r 0.5, h 2.0); crouch scaling and the veranda traversal probe follow it.

### 2026-09-30 - Stylized shadows run on stock Godot again (claudeflow)

- `stylized_shadow.gdshaderinc` no longer requires the patched editor: the
  default path is the stock LIGHT_VERTEX warp plus torn ATTENUATION (as before
  #148). The two-lookup `sample_directional_shadow` path stays behind the
  commented-out `HFN_PATCHED_SHADOW_SAMPLER` define. Call sites use
  `HFN_LIGHT_INDEX` and `HFN_STYLIZED_SHADOW_WARP`, which switch with it.
- `test_stylized_shadows` checks the stock path is the default.

### 2026-09-30 - Snow with weight: boots sink, crust holds, walls shed clumps (claudeflow)

- A planted boot presses in over its stance (`sink_time_s`, 0.22 s to ~63%)
  instead of dropping to the ground at once: SnowShell lowers the sole to
  `snow_top - sink` each frame.
- SnowFootModifier lands the boot on the snow top and lets it sink with the
  pack; the hips follow the lower boot (two-bone solve, no clip change). The
  foot contact sensor reads the clip's foot, not the lifted one.
- Snow softness varies (0.4 wind crust to 1.0 powder): scoured ground holds a
  boot, lee drifts let it sink, with 3 m patches between; stored in the field
  image B channel and capping packing. Print floors carry 2 cm of lumps.
- Lifting out of a print deeper than 10 cm sheds 6 clumps from its rim and
  raises the floor in lumps by up to 18% of its depth.

### 2026-09-30 - Trench slope drawn in the shader, not simulated (claudeflow)

- The slumping pass in the packed-snow accumulation is gone: it grew a crater
  around each step over several frames. The ground shader now draws walls no
  steeper than `repose_deg` (40°) at once, from up to 0.45 m of neighbours;
  the stored packing stays exactly what the foot pressed.

### 2026-09-30 - Packed snow persists in world tiles (claudeflow)

- SnowTrackStore keeps packed snow that leaves Henry's window as 3.2 m tiles
  at 10 cm (one byte per texel, 5 mm steps) with the fill clock they were
  stored at. The clock sums -ln(1 - fill) per frame, so a restored trail comes
  back already filled in for the weather it waited through: exp(-Δclock).
- On each window move the leaving tiles are read back and filed; the new window
  restores stored tiles where it has no previous packing. A fresh window or a
  load restores every texel. Up to 4096 tiles; the most filled go first.
- SnowShell saves the tiles and clock under `snow_tracks`.

### 2026-09-30 - Weather-driven storm snow layer (claudeflow)

- SnowPresentationSystem keeps a storm share (0 old prevailing base, 1 fresh
  storm snow) and writes the new `snow_storm_share` global. Falling snow pulls
  it toward wind/14 m/s at 0.2 per hour of whiteout; once the snow stops it
  settles back to the calm base (0.4, today's look) at 0.05 per hour. Saved.
- SnowField caches prevailing and storm wind factors apart and mixes them per
  rebuild, so a storm reshapes the drifts without resampling the ground; the
  window rebuilds in place when the share moves by 0.05. Chunk snow reads the
  global per pixel.

### 2026-09-30 - Trench walls slump to the angle of repose (claudeflow)

- Packed-snow accumulation lets no texel sit deeper than its neighbours by more
  than tan(repose) per texel (`SnowShell.repose_deg`, 40° default): steep
  footprint walls slump into sloped sides one texel per frame.

### 2026-09-30 - Swept shelter stairs, slowed walk in deep snow (claudeflow)

- The shelter's stair ramp is in the `snow_swept` group: no snow lies on the
  steps, so Henry climbs them at full speed instead of wading.
- Below walking speed (deep snow, heavy load) the walk clip plays slowed
  instead of blending with idle, so feet keep pace and the torso stays upright.

### 2026-09-30 - Street props stream per city chunk (claudeflow)

- Small props (benches, hydrants, signs, gates, cars, boats, scrub, vaults,
  golf markers, lamps) are filed per chunk and instanced only while their
  chunk is streamed in. Palms, bare trees, power poles, wires and tanks stay
  island-wide silhouettes. Transforms are computed once and stay deterministic.
- Frame load on lavapipe: 40 M → 22 M primitives; draw calls 1542 → 1499
  (Fort Street). Reference frames unchanged.

### 2026-09-30 - Separate contact and packed snow resolutions (claudeflow)

- SnowShell.contact_res sizes the per-frame contact capture apart from the
  packed field. High stays 1024/1024; the reference frames are unchanged.
- New `medium` snow tier: contact 512, packed 1024. On lavapipe it gains
  nothing measurable (walk frame 131 vs 133 ms, CPU-bound); a real GPU must
  confirm it before it is recommended. SnowField.quality() reads the tier.

### 2026-09-30 - Cached, frame-sliced chunk snow (claudeflow)

- SnowChunkCover keeps the finished mesh of the last 12 chunks (weather-free),
  so a chunk streamed back in gets its snow at once.
- Uncached chunks build in 4 ms per-frame slices; chunks within 256 m of
  Henry's snow window, and any queued chunk the window reaches, finish at once.
- SnowShell.live_window publishes the window, since reading shader globals
  back fails outside the editor.

### 2026-09-30 - Incremental, frame-sliced SnowField rebuild (claudeflow)

- SnowField keeps a 20-cell apron of cached, wind-independent layers (ground,
  bed blur passes, wall share, city factor, grain). A window move samples only
  the newly exposed strips: 3 904 ground rays instead of 16 384.
- While walking, a move is rebuilt within a 4 ms per-frame budget and switched
  in whole; the old window stays live. First window and teleports stay immediate.
- Measured on lavapipe: window move 500–860 ms → no hitch; walking physics frame
  max 23.5 ms, p95 7.3 ms. Tests pin full == incremental and sliced == whole.
- Window-edge cells now see real neighbours instead of clamped ones; the author
  approved the smoother edge seen in the Old Town reference frame.

### 2026-09-30 - Answer the #139 post-merge audit: layers, budget, snow tier (claudeflow)

- Render layers are reserved in `RenderLayers` and named in `project.godot`:
  layer 19 `snow_contact`, layer 20 `dev_map_label`. Snow contact and dev map
  labels no longer share layer 20, and the dev map camera skips snow contact.
  `test_render_layers.gd` locks this in.
- Measured the snow budget: `SnowField.rebuild` takes 0.5–0.9 s per window move and
  `SnowChunkCover.build` about 0.3 s per chunk (`docs/technical/SNOW_COVER.md`).
- The ~65 MiB wind field image is shared by every SnowField. Pickups are tagged
  once and on spawn instead of by a full-tree scan on every window move.
- New setting `hfn/snow/quality` (`high` default, `low`): low builds no snow
  window, no contact passes and no chunk cover.
### 2026-09-30 - Integrate stylized shadows across production rendering (codex)

Changed
- Replace the standalone shadow-material experiment with a shared stock-Godot
  lighting contract: solid physical shadow core plus a noise-broken perimeter.
- Wire the contract into IslandTerrain, local/chunk snow, Key West city/roads/
  airport/street props, masked sea ice and opaque First Exit shelter materials.
- Add restrained Omni/Spot support without allowing local-light stylization to
  brighten above physical distance falloff.
- Preserve transparent/unshaded VFX and interaction-preview materials on their
  existing paths instead of forcing them through opaque shadow lighting.

Validation
- Add a headless material/shader contract test.
- Extend the existing Key West CI render job (no second pipeline) with a
  `[stylized-shadows]` mode that captures three matched physical/stylized PNG
  pairs and uploads them as `hoarbound-stylized-shadows`.


### 2026-09-30 - Gate the developer map behind World and M (codex)

Changed
- Add exported `World.enable_runtime_dev_map`, default false. Authorized debug
  worlds start with the map hidden and physical M toggles it; disabled worlds
  ignore the same edge completely.
- Route M through InputSystems as `toggle_dev_map`, preserving the project's
  single input reader. The map only processes while visible.
- Preview capture enables the export explicitly so CI keeps validating the tool.

### 2026-09-30 - Make the developer map follow-only and label the city (codex)

Changed
- Remove FREE, RECENTERING, drag, wheel and map buttons. The main TPS scene has
  no free cursor, so the developer map now always follows Henry at 30 m.
- Surface local OSM address numbers and unique road names from the frozen city
  dataset. Labels are capped, refreshed around Henry and rendered above roofs.

Isolation
- Address/street text lives on map-only render layer 20. The debug map camera
  includes it while the TPS camera masks it out, so labels never leak into the
  production view.

### 2026-09-30 - Add debug diorama map foundation (codex)

Added
- Debug-only 500 × 320 upper-left diorama map using a live shared-world
  SubViewport camera: 30 m default height, 36° FOV, 64° pitch and 12° yaw.
- FOLLOW, FREE and RECENTERING modes; drag enters free pan, wheel zooms from
  18–60 m, CENTER smoothly returns to Henry, and a gold marker tracks him.
- A focused headless state test plus an existing-workflow preview job that
  captures full placement and map-only PNGs without running the GIS pipeline.

Notes
- The tool self-removes from release builds and owns no gameplay/streaming state.
  Its perspective camera creates the trapezoid; the viewport image is not warped.

### 2026-09-30 - Make agent pre-task sync mandatory (codex)

Changed
- Require every agent to synchronize current `main` into its permanent working
  branch before each new task or substantial pass, not merely once per session.
- Require agents to verify ancestry before editing or expensive CI and to inspect
  already-integrated fixes before treating recurring failures as unresolved.
- Strengthen Claude Code's charter with the same per-task `main -> claudeflow`
  sequence and explicit `merge-base --is-ancestor` check.

### 2026-09-29 - Add an inspector toggle for the shelter start (codex)

Changed
- Export World.spawn_at_shelter, default false. True selects the Fort Street
  shelter entrance; false keeps the authored Whitehead bunker scenario.
- Transplant the existing First Exit entrance marker into Key West, preserving
  its orientation and placing it above the NOAA terrain. Select it before world
  lifecycle notifications so camera, terrain and city streaming use the start.
- Weather and Continue restoration retain their existing behavior. Continue the
  author-approved main workflow for this related startup edit.

Validation
- Clean Godot import and compilation of all 217 project scripts passed.
  Real-world checks passed for both false
  (Whitehead, 3 ACTIVE chunks) and true (Fort Street entrance, 4 ACTIVE chunks):
  player grounded, matching terrain, 148 registered city chunks, initial blizzard.
- The shelter mode rendered a non-black Vulkan frame without script errors.

### 2026-09-29 - Start in Key West and archive Graciosa (codex, author-approved main pass)

Changed
- Set F5 and the title-menu game target to the complete Key West world scene.
  Pin its world profile in the scene so startup needs no HFN_WORLD override.
- Commit the real 2 m NOAA crop, source metadata and frozen city/enrichment/ocean
  mask snapshot. Preserve source receipts; normal startup needs no GIS downloads.
- Move the Graciosa scene, terrain/source images and WorldData to archive/graciosa.
  Preserve image bytes and scene UID; pin the archived scene to its own profile.
  Update dependent capture/bake tools, tests and docs to the archived paths.
- Keep the shared First Exit bunker/shelter and gameplay systems in place. Key West
  retains the Whitehead-to-Fort-Street route, blizzard and city streaming. Clear
  references to the discarded template owner before transplanting its nodes.
- Match HeightMapShape3D collision spacing to the dataset resolution. The 2 m
  Key West surface previously had 1 m collision patches and allowed falling
  below the rendered ground. Preserve real elevation through uniform scaling.
- Update the CLAUDE.md heightmap-source path and current product/world documents.
  The author explicitly requested this pass directly on main; branch conventions
  remain unchanged for subsequent work.

Validation
- Project script compilation, startup presentation, input-map and archived streaming
  checks passed. Graciosa source/runtime heightmap hashes match the previous commit.
- Final lossless Image import and 217-script compilation passed. World profiles,
  Key West First Exit, startup presentation and stove/world-time suites passed.
- Real Vulkan startup with no HFN_WORLD override registered 148 city chunks
  (3 ACTIVE), started blizzard at Whitehead, and rendered a non-black frame.
  With physics active, the player settles on the visible terrain instead of
  falling underneath. Raycast checks passed for both 1 m Graciosa and 2 m Key West.
- The complete NOAA DEM matches its original S3 multipart ETag; every packed
  heightmap pixel equals the committed 16-bit crop. Receipts use Git-stable LF.
- Full-suite success remains unverified: the unchanged nightly stove-act and
  shelter-focus fixture failures are documented in GODOT_AI_INTEGRATION.md.
  Godot-generated import metadata retains its normal blank line at EOF.

### 2026-09-29 - Resolve Godot AI installation conflicts and integrate main (codex)

Changed
- Replace the mixed v3.2.1/migration-only addon with the complete Godot AI 4.2.3
  release. All 313 vendored files match the supplied inventory; retain MIT license
  and record archive provenance in docs/technical/godot_ai_vendor_receipt.json.
- Resolve four add/add conflicts with one coherent release, enable the editor
  plugin and its game helper, and remove superseded v3 files/migration archives.
- Merge main into codex, preserving PR #137 stove/door/pickup fixes and PR #140
  Key West First Exit. Add the ten generated UID companions for Key West scripts.
- Update the world-profile test for configured Key West paths and missing-terrain
  readiness; document the conflict decision in GODOT_AI_INTEGRATION.md.

Validation
- Godot 4.8 dev6 .NET build and repeat import passed; 217 project and 155 addon
  scripts compiled. Input map and filename/UID checks passed. TestScene rendered
  a non-black Vulkan frame without script errors.
- Ten focused suites passed. Two unchanged main fixtures (stove act and shelter
  focus) fail against the nightly guaranteed-strike/external-presentation contract;
  details are recorded in GODOT_AI_INTEGRATION.md. Full-suite success is unverified.
- Vendored EOF whitespace is preserved; diff check ignores only blank-at-eof.

### 2026-09-29 - Complete the pickup requested before walking (codex)

Fixed
- Use the ItemPickup captured by F to complete an approach at arm's reach. Camera
  movement can change live crosshair focus without discarding the requested item.
  Other interaction types retain their live focus requirement.
- Cancel a pending pickup when WASD takes over, the target is removed/disabled,
  it leaves the intent radius, movement becomes blocked, or the approach times out.
- The previous pickup fix covered animation and inertia, but left the arrival
  condition dependent on current crosshair focus; this addresses that condition.

Validation
- Statically traced F selection, approach, focus loss, arrival and cancellation
  against Player's movement loop and ItemPickup's inventory acceptance path.
  git diff --check passed; Godot and test suites were not launched, as requested.

### 2026-09-29 - Keep Henry still during successful pickups (codex)

Fixed
- Play the pickup action only after the item has entered the inventory. Refusals
  retain their message and world item without playing a misleading success clip.
- Stop a scripted approach before acting at arm's reach. Clear horizontal velocity
  when a stationary action starts, and lock movement from the OneShot FIRE request
  through the active clip instead of waiting for the AnimationTree's next update.
- The movement controller clears inertia, sprint and armed jump release while
  rooted, preserving gravity. Repeated F cannot replace a locking action.
- Consumed or disabled approach targets also stop Henry's scripted walk.

Validation
- Reviewed pickup acceptance/refusal, chopping ownership, approach teardown and
  pending/active animation locks. Pickup root translation is zero in the source GLB.
  git diff --check passed; Godot and test suites were not launched, as requested.

### 2026-09-29 - Guard freed interaction targets (codex)

Fixed
- Clear invalid focus references before target selection, and check instance validity
  before the active-stove type test. A removed target can no longer reach `is` through
  the stove focus latch or its neighboring focus/ownership helpers.
- Reject removed/queued targets on F and return no reach/focus for dead nodes.
- Reviewed target clearing, lookup and input paths; git diff --check passed. Godot
  and test suites were not launched, as requested by the author.

### 2026-09-29 - Start with both ignition supplies in Quick Access (codex)

Changed
- Keep the starter lighter in Quick Access slot 2 and add one tinder portion to
  slot 3 (left thigh pocket), as requested by the author. The stove already draws
  the lighter and consumes tinder directly from their owning pockets.
- Update the walkthroughs; Continue retains saved equipment without refilling it.

Validation
- Reviewed pocket ids, capacity and Quick Access ordering. git diff --check passed;
  Godot and test suites were not launched, as requested by the author.

### 2026-09-29 - Correct Quick Access starter item to the lighter (codex)

Fixed
- Correct the earlier misinterpretation: the author requested the lighter, not
  tinder. Replace the right coat pocket starter item with `lighter`, Quick Access
  slot 2, and update the walkthroughs. Continue keeps saved pocket contents.
- Checked the catalog item and pocket mapping; git diff --check passed. Godot
  and tests were not launched, as requested by the author.

### 2026-09-28 - Start with tinder in Quick Access (codex)

Changed
- Per the author's instruction, new games start with one tinder portion already in
  the right coat pocket, Quick Access slot 2. Stove preparation uses that owned
  pocket item directly; it need not be drawn or moved through the Hub.
- Starter equipment accepts worn-pocket paths after equipping the starter garments,
  using normal fit/occupancy checks and slot signals. Pocket save/load remains the
  authority; Continue does not refill the starter tinder.
- Localize the tinder item name and update the shelter/route walkthroughs to show
  the current F-load, automatic kneel and held-LMB controls.

Validation
- Reviewed starter initialization order, right coat pocket capacity, Quick Access
  ordering and stove pocket consumption. git diff --check passed. Godot and test
  suites were not launched, as requested by the author.

### 2026-09-28 - Resolve stalled stove transfer presentation (codex)

Fixed
- Stove loading explicitly enables its presenter and advances the transfer through
  TimeCostedActionSystem each frame, rather than only polling another node's timer.
  External presentation skips the system's automatic tick, preserving one clock,
  completion callback, partial cancellation cost and resource commit owner.
- A lost/replaced action clears the stove's busy state and offers retry; it can no
  longer wait indefinitely for an action that is absent. Zero-duration work modifiers
  complete staged actions instead of turning them into endless manual actions.
- Loading shows its log count and percentage as the main prompt, with F cancellation
  below it. Logs remain owned by the hands until the completion callback commits them.
- Guard PlayerState lookup when cancellation occurs after scene teardown; the author's
  existing runtime log showed this error while returning from the game to the title.

Validation
- Reviewed external versus automatic ticking, completion into ignition, cancellation,
  missing-action recovery and item commits. git diff --check passed. Godot and test
  suites were not launched. The cause of the shared timer's runtime stall could not
  be confirmed from the screenshot/log alone; the new explicit tick still needs the
  author's gameplay confirmation.

### 2026-09-28 - Stove loading and ignition refusal fixes (codex)

Fixed
- Count tinder in worn pockets as well as the pack, and consume it from its owning
  storage exactly once when ignition succeeds. A drawn owned lighter no longer
  blocks stove loading/preparation; stow it before attaching the stove strike prop.
- Missing prerequisites appear as the main prompt without an unusable F offer.
  Idle loaded stoves offer "Light stove"; active preparation shows its progress
  and F cancellation. A missing ignition item cannot hide the successful log load.
- Bind player storage/animation even when the stove becomes ready before Henry.
  Use live reach checks and start approached actions only inside actual reach.
- Keep the selected stove authoritative across its body and moving door; check
  door visibility up to its plane, so a wall behind an open door does not cancel work.

Validation
- Reviewed loading/ignition branches, hand ownership, pocket resource commits,
  action cancellation and prompt transitions. git diff --check only; no Godot,
  rendering or test-suite execution, as requested by the author.

### 2026-09-28 - Intuitive stove flow and shelter test start (codex)

Changed
- New games temporarily start outside the shelter entrance, facing the house,
  for the author's interaction tests. Layout, saved scene, initial player transform
  and resolved metadata agree; existing saves retain their player positions.
- F in an open firebox loads the complete armful that fits, showing the count in
  advance. Transfers commit wood at completion; uncommitted logs no longer appear
  in the firebox while still held.
- Surplus wood automatically becomes an ordinary saveable pile, checking clear
  floor ahead and on both sides. Blocked placement preserves the surplus in hands
  and explains how to put it down; already loaded fuel remains in the stove.
- Cold loading automatically draws the owned lighter and enters Fixing_Kneeling.
  AnimationTree plays to 2.6 seconds, holds the work pose and resumes the remaining
  clip on completion/cancellation. The torch pose and repeated full-body strike
  animations no longer compete with the kneeling pose.
- LMB is enabled after the pose settles and always produces a strike, sound,
  sparks and flame. Three uninterrupted held seconds ignite tinder exactly once.
  Release/pause resets the hold; F cancels. Hot refueling never prepares ignition.
- Body, firebox and door keep the same stove focus during work. Other targets,
  lost reach and removed sources cancel. RMB explicitly returns up to two intact
  cold logs, cancelling ignition first; mouse loading and implicit return mode are removed.
- Player movement obeys the action system's WORKING mode for the entire transfer,
  including multi-log loading after its short presentation clip ends.
- English/Russian prompts and the shelter walkthrough describe the new sequence.
  Missing tools preserve the cold load; fuel saves and gradual warmup keep their
  existing HeatSource ownership.

Validation
- Static review covers input ownership, staged transitions, resource commits,
  hand/pose cleanup and overflow persistence. git diff --check is the only command check.
- Per the author's request, Godot, renders and test suites were not run. Existing
  automated stove assertions describe the previous controls; this revision's
  visual/gameplay acceptance remains the author's manual run.

### 2026-09-28 - Door gap snow and staged stove controls (codex)

Changed
- The shelter door is an operable opening with 5% closed leakage, rather than a fifth
  repairable breach. Four windows retain boarding; door boards/prompts are removed
  from the scene and generator, and old boarded-door saves no longer lock it.
- Snow drafts subtract the moving leaf from the actual opening. Both aperture snow
  and exterior snowfall stop at leaf/frame contacts, including swept shader contacts
  that prevent fast particles from crossing a thin leaf between simulation steps.
- F on the stove door/handle opens or closes it. Aiming inside the open firebox gives
  LMB one-log and RMB up-to-two-log transfers, two seconds and 0.5 game minutes per
  log. Cold whole logs can return to the existing visible carry system; return mode
  remains selected until focus changes or a separate F action ends it. Completion
  owns all resource changes, so cancellation cannot lose or duplicate wood.
- F with free hands prepares the lighter. Each LMB press makes one strike, with a
  55% chance and a guaranteed sixth attempt. A short 0.25-second animation interval
  replaces the previous five-second lockout. Sparks, hand movement and the CC0
  SamsterBirdies strike recording accompany every accepted attempt.
- Successful lighter flame/light last only while LMB stays held. Three uninterrupted
  seconds ignite the tinder once; shorter holds do not accumulate. Release, focus
  loss, cancellation and paused menus extinguish the lighter immediately.
- HeatSource owns an optional 20-second stove startup ramp and recoverable-log count.
  Flame, light, point warmth, room heating and cooking use the same intensity. Saved
  warmup resumes, sleep/accelerated time advance it, and legacy burning saves start
  fully developed. Other sources retain immediate full output.
- Stove context consumes mouse input before Quick Access. English/Russian prompts
  describe the current target, transfer mode, available logs and G to free hands.

Fixed
- Notify authored world roots through the existing world-ready lifecycle: the main
  scene's day/night manager now drives the canonical simulation clock. Visible stove
  startup requests fine realtime slices temporarily; sleep/action steps stay bounded.
  Flush older buffered time before ignition and release the fine-step request at zero.

Validation
- All 58 system suites passed their assertions and returned success, including real
  mouse-input/focus workflows, save round trips, cancellation and accelerated time.
  Existing ice duplicate-signal diagnostics and intentional negative-test diagnostics
  remain separate from the assertion results.
- Clean resource import and generator validation passed (4323 nodes, 83 footprints).
  Generated and committed scenes both pass the door and First Exit route checks.
- Identical sealed/closed/open blizzard comparison: closed-gap penalty 0.422 C,
  below the required 1 C. Native Vulkan captures show the actual gap stream and
  blocked exterior snow; disabling both barriers reproduces snow through the leaf.
- Native Graciosa/WASAPI run captured sparks, held flame, release, kindling and fully
  developed fire, with a nonzero indoor SFX recording and a video containing audio.
  Evidence and replay commands: docs/validation/stove_draft_2026-09-28.md.

### 2026-09-28 — Correct Day / Dusk LUT green-axis packing (codex)

Fixed
- The Day and Dusk LUT atlases added in `3c0a290` stored the green axis upside down:
  black mapped to bright green and white to magenta. Reverse the atlas rows to match
  the existing Texture3D import layout, preserving every authored color value.
- Add neutral-ramp and primary-axis checks to the color-grading suite. Texture
  dimensions and profile-switching checks alone did not detect the inversion.

Validation
- New color checks reject the original atlases with 130 failures and pass all four corrected profiles.
- Godot 4.8 dev6 clean reimport passed; Forward+ captures of the production Graciosa scene
  reproduce the green/magenta failure before the fix and restore normal colors afterward.

### 2026-09-28 — Manual lighter ignition ritual (codex)

Changed
- Stove ignition is now event-driven: F prepares the lighter and each deliberate LMB press performs
  one strike instead of the old automatic five-second catch.
- A rapid accidental double-click starts a five-second input lockout. During lockout clicks produce
  no strike animation, spark or light and cannot ignite the stove.
- Normal strikes have authored first/second-attempt chances and are guaranteed by the third clean
  strike by default, keeping occasional third-attempt catches without allowing endless bad luck.
- Every accepted strike produces a short local spark/light VFX at Henry's hand socket when available,
  with the stove interaction anchor as a fallback. A successful strike adds a slightly stronger,
  longer lighter-flame flash before the stove takes over.
- `TimeCostedActionSystem` now supports event-driven actions through `start_manual_action()` and
  `complete_active()`; the declared game-time cost is billed only when gameplay reports success.
- Stove visuals no longer grow a fake pre-ignition flame on a timer.

Tests
- manual actions do not complete or bill from elapsed real time and bill exactly once on explicit completion;
- stove ignition stays in WORKING until a successful lighter strike;
- double-click lockout lasts five seconds and emits no strike effect;
- lockout clicks cannot ignite; three clean post-lockout strikes guarantee the configured catch;
- successful ignition restores PlayerState and bills the existing authored ignition time.

### 2026-09-28 — Staged one-log stove refueling (#131 PR D follow-up) (codex)

Changed
- Runtime stove feeding no longer auto-loads every carried log that fits.
- With the stove door open, one interaction starts one short `WORKING` TimeCostedAction and commits
  exactly one physical log only after the action completes.
- Repeating the interaction deliberately adds a second log if another full fuel-unit slot is free.
- A cold empty stove loads one log first; once any cold fuel exists, ignition is prioritised even if
  Henry still carries more logs. Extra logs can be added after the fire catches.
- Cancelling the feed action consumes no log and bills no unearned action time.
- A stove refuses to spend a full log unless at least one complete log's fuel value fits; fractional
  remaining capacity never destroys an item.
- The door stays open after a successful feed so a second log can be added; when no full log fits,
  the next interaction closes the door.
- One log still represents the existing `hours_per_fuel_unit` value (2 game hours by default);
  full stove capacity remains the existing 6 game hours.

Tests
- cold one-log load is staged and does not ignite;
- ignition is prioritised after cold fuel exists;
- hot refuel consumes one log per completed action;
- cancellation preserves inventory/fuel;
- near-full stove does not waste a log;
- after one log burns, exactly one top-up is accepted;
- after two logs burn, two sequential top-ups are accepted;
- each feed action enters/restores `PlayerState.WORKING`.

### 2026-09-28 — Shelter gameplay action adoption (#131 PR D) (codex)

Changed
- Stove-top cooking and snow→water now intentionally advance game time through the shared
  `TimeCostedActionSystem` instead of relying only on passive manual/test fuel advancement.
- `StoveWarmer` keeps recipe ownership: raw item / `warms_into`, partial heat progress, result
  transformation and save data remain in the warmer; the action layer owns only time/progress/cancel.
- A full stew cook or snow melt keeps the existing 0.5 h recipe cost and presents it as one staged
  WORKING action. Simulation is billed in one-minute slices.
- If the fire goes out, the action cancels with partial recipe progress preserved. After relighting,
  interacting with the ring resumes only the remaining heat/time.
- HeatSource now emits `heat_elapsed` for the time fuel actually burned, so a coarse simulation
  slice cannot grant more cooking/warming than the remaining fuel.
- Stove ignition, window boarding and shelter-table dismantling explicitly enter
  `PlayerState.WORKING` through their existing TimeCostedAction requests and restore the previous mode afterward.
- The real shelter workflow test now owns a SimulationClock + TimeCostedActionSystem, so boarding
  no longer passes through the legacy no-action fallback during integration tests.

Validated consumers
- stove ignition → TimeCostedAction;
- cooking / hot stew → TimeCostedAction;
- snow → warm water → TimeCostedAction;
- board placement → TimeCostedAction;
- shelter furniture dismantling → TimeCostedAction.

Deferred
- Generic garment/item repair is not marked adopted because Hoarbound currently has no real repair
  interaction, repair material/tool contract or gameplay owner. `EquipmentComponent.repair_garment()`
  remains the simulation seam for a later concrete repair verb rather than inventing a fake recipe here.

Tests
- invalid/obstructed board placement bills no time; a valid board bills exactly its authored cost;
- board placement and stove ignition enter WORKING;
- cooking/melting bill exactly 0.5 game hours and matching fuel;
- fire-out cancels early using actual burned fuel time, preserves partial progress and can resume;
- snow melt and stew use distinct action ids/reasons and restore PlayerState on completion.

### 2026-09-28 — Clothing layers and per-instance garment state (#131 phase 5) (codex)

Added
- Layered Henry equipment layout with explicit base / mid / outer clothing slots per body region.
- Explicit legacy slot migration for old `head / torso / legs / feet` equipment saves into the new
  `*_outer` slots; unknown legacy layer ids are warned and refused rather than guessed.
- Immutable garment definition data for body region, layer, base insulation, windproofing,
  waterproofing, drying rate and maximum condition.
- Runtime `GarmentInstanceState` containing normalised wetness and condition; shared `GarmentData`
  Resources remain unchanged at runtime.
- Two non-starter layered garments (`thermal_shirt`, `wool_sweater`) so torso base/mid/outer
  behavior is represented by real catalog data without changing Henry's starting loadout.
- Equipment aggregate APIs for effective insulation, wind protection, water protection and
  average clothing wetness.
- Outside-in moisture propagation per body region: outer waterproof/condition reduces penetration
  to mid/base layers; each garment dries by its own authored rate.
- Stateful garment transfer through InventoryComponent. Non-stackable inventory entries may carry
  optional instance state, including through inventory save/load.

Changed
- `EquipmentComponent` save key remains `equipment`, extending the old
  `{ body, pockets }` payload with optional `garment_states`.
- Old equipment saves without `garment_states` load garments dry and at full condition.
- `InventoryComponent` save key remains `inventory`; optional instance state is additive and only
  used for physical non-stackable items.
- `ThermalManager` now consumes effective insulation and wind protection from EquipmentComponent,
  and delegates clothing wetting/drying to the per-garment model.
- The old `thermal.wetness` value remains as a compatibility/presentation mirror while clothing
  wetness is now derived from EquipmentComponent when equipment is present.
- Condition lowers insulation / windproofing / waterproofing but does not destroy an item;
  `damage_garment()` / `repair_garment()` are the public seams for later time-costed repair.

Tests
- base + mid + outer can occupy the same body region simultaneously;
- legacy slot aliases and old save paths migrate explicitly;
- outer layers measurably protect inner layers from moisture;
- wetness lowers effective insulation;
- condition lowers insulation, wind and water protection;
- state survives equipment save/load and unequip → inventory save/load → re-equip;
- old saves default to dry/full-condition;
- invalid old layer slots do not silently migrate;
- runtime wetness/condition never mutate shared GarmentData;
- ThermalManager reads effective clothing protection rather than inspecting garments itself.

### 2026-09-28 — Status / Affliction layer (#131 phase 4) (codex)

Added
- Player-owned `AfflictionComponent` with persistent runtime `AfflictionState` and immutable
  `AfflictionDefinition` resources.
- Initial conditions are intentionally limited to hypothermia, dehydration and exhaustion.
- Named modifier aggregation for `movement_speed_multiplier`, `fatigue_rate_multiplier`,
  `recovery_rate_multiplier` and `work_duration_multiplier`.
- Dedicated additive save key `afflictions`; old saves with no status payload load with an empty set.

Changed
- Thermal stage owns hypothermia truth; HydrationComponent owns dehydration threshold truth;
  FatigueComponent owns exhaustion threshold truth. AfflictionComponent stores persistence and consequences.
- AfflictionComponent binds ThermalManager through `on_world_ready(context)` instead of Player.gd
  manually gluing the two systems together.
- Movement, Fatigue and TimeCostedAction consumers read named modifier contracts rather than statuses
  directly mutating their internal tuning.
- Hypothermia severity scales consequences continuously: severity 1/2 applies half of the configured
  max penalty, severity 2/2 applies the full definition.

Tests
- Activation/recovery edges are idempotent.
- Save/load preserves active severity and elapsed time; missing old-save payload is safe.
- Modifier composition is deterministic regardless of activation order.
- Hypothermia severity interpolation is monotonic and exact for the authored definition.
- WorldContext binding activates/recover hypothermia from ThermalManager without Player glue.
- Real Hydration/Fatigue/Thermal thresholds drive the corresponding afflictions.
- Movement, fatigue drain and time-costed work duration consume named modifiers without presentation nodes.

### 2026-09-28 — Split BioMonitor into Hunger / Hydration / Fatigue (#131 phase 3) (codex)

Changed
- `HungerComponent`, `HydrationComponent` and `FatigueComponent` are the only owners of their
  runtime values, previous values, critical state and per-track drain/recovery rules.
- `BioMonitorManager` is now a compatibility facade / SimulationClock coordinator / save adapter:
  legacy properties, methods and HUD signals proxy the three components instead of storing a second copy.
- Production metabolism has exactly one ticking path: `SimulationClock → BioMonitorManager.advance_simulation()`.
  The old DayNight `dn_manager/_on_time_changed` path and scene overrides were removed.
- Fatigue reads an optional status-modifier contract without compiling against the Affliction layer,
  keeping phase 3 independent from phase 4.

Compatibility
- Save key remains `bio`.
- Save payload remains exactly `{ calories, hydration, energy }`; old payloads load into the new
  components without a save-version bump.
- Existing HUD and gameplay callers can continue using BioMonitorManager's legacy properties/signals.

Tests
- Real player composition proves the facade resolves the three sibling components.
- Legacy save shape/round-trip is unchanged.
- 24 × 1 h and 96 × 0.25 h metabolism are equivalent.
- Carry load affects Fatigue only; adding calories does not mutate Hydration.
- Sleep still bills Hunger/Hydration while restoring Fatigue.
- One SimulationClock hour produces exactly four quarter-hour updates and no legacy DayNight tick exists.

### 2026-09-28 — Time-costed Action System (#131 phase 2) (codex)

Added
- World-scoped `TimeCostedActionSystem` and runtime `TimeActionRequest`: one lifecycle for
  long actions with declared game-time cost, presentation duration, deterministic simulation
  slices, progress, completion/cancellation callbacks and optional stop predicates.
- Controlled actions block ordinary realtime clock advancement while active, preventing double
  billing when a staged action converts real presentation seconds into game hours.
- Headless lifecycle coverage for exact billing, deterministic early stop, staged progress,
  cancellation, non-interruptible actions, PlayerState mode ownership and callback semantics.

Changed
- Sleep and seated wait now use the common action contract over `SimulationClock`.
- Sleep enters `PlayerState.SLEEPING`; wait enters `PlayerState.WORKING`; prior mode is restored
  after completion or cancellation without introducing a second state enum.
- SleepPrompt closes its modal menu before starting the sleep action, so action state is not hidden
  behind `MENU`.
- The action layer queries an optional work-duration modifier contract without compiling against
  the future Affliction implementation; resource/tool/recipe rules remain owned by gameplay code.

### 2026-09-28 — First Exit systemic-pressure pass (#134) (codex)

Changed
- Carried weight now has a readable physical cost before the 30 kg hard limit: movement begins
  slowing above 40% load and reaches 78% speed / 82% acceleration at full load. The existing
  BioMonitor fatigue multiplier remains authoritative above half load.
- The shelter door and doorway now share one exposure value. Open = full draft, a closed damaged
  door = 20% draft, and fully boarded = zero. ThermalZone and snow-draft particles therefore agree.
- A closed damaged door explicitly says that the frame still leaks instead of looking like a particle bug.
- Player Hub now reports load state, movement/fatigue cost, clothing wetness stage, whether clothing
  is currently drying, and the percentage of dry insulation still working.

Added
- Public wetness state/drying/insulation readback on ThermalManager and energy-drain explanation on
  BioMonitorManager; presentation reads these values instead of copying simulation formulas.
- Headless #134 regression coverage for heavy-load movement/fatigue, wetness readability and Hub
  readback; hinged-door tests now assert closed/open/boarded exposure.

Validation
- Pending pull-request CI. This pass deliberately does not claim a human 10–15 minute run while the
  owner has no local PC access; automated checks cover the new contracts only.

### 2026-09-28 — Time-aware ColdAsh grading and weather-driven clouds (codex)

Added
- Added dedicated 33³ `HFN_ColdAsh_Day` and `HFN_ColdAsh_Dusk` LUTs alongside the existing
  `HFN_ColdAsh_Night` and `HFN_ColdAsh_Shelter` profiles.
- Added a production colour-grade capture path that renders the real Graciosa main scene at the
  First Exit shelter: Day/Dusk/Night share one exterior camera, Shelter uses an interior camera.
- Added a narrow codex-only CI preview job that imports once, captures all four PNGs in one Godot
  process and uploads one short-lived artifact instead of running the full checks job for preview pushes.

Changed
- `ColorGradeController` now selects Day / Dusk / Night by game hour while Shelter remains a temporary
  interior override; leaving the shelter restores the outdoor LUT appropriate for the current time.
- Weather state changes now adjust outdoor grade and cloud presentation without forwarding gust noise
  into the sky every frame.
- Cloud drift is slower and derived from sustained `WeatherProfile` wind direction/speed; snowfall
  adjusts coverage/density/opacity only when the active weather profile changes.
- Noon lighting was lifted from the previous permanently dark Night-LUT presentation, and default
  cloud coverage/opacity were reduced for a more readable overcast day.
- Updated grading/shelter tests to cover all four LUTs and the Day ↔ Dusk ↔ Night ↔ Shelter transitions.

Validation
- GitHub Actions run #36362626414 passed the clean import gate, production-scene capture and artifact
  upload. Final review frames use calm weather, no UI/debug overlays, one fixed exterior shelter angle
  for Day/Dusk/Night, and a separate interior Shelter angle.

### 2026-09-28 — Restore history and bunker start; retain the author's supplies (codex)

Fixed
- Restored the complete claudeflow changelog entries 10–1 and earlier from the
  last intact revision. The merged placeholder did not preserve this history
  on main. Existing implementation entries and Grok's planning documents remain.
- Removed the unused OrganicWhoosh editor scene/script and Disney wind-line
  HTML draft at the author's request. Existing runtime wind, snow and weather
  effects remain authoritative; no new wind system is introduced.
- New Game starts at the bunker, facing the water tower, through the generated
  SpawnPoint and terrain height sampling. The following camera adopts the final
  spawn heading through its existing API; previously it kept the scene's old
  heading. Existing saves retain their saved start.
- Author correction: preserve every existing pickup, its position and count,
  including shelter bonus stacks and the second starter kit. The current supply
  budget remains 33 boards, 66 nails and 12 logs; no scarcity reduction is applied.

Documentation
- Aligned README, PRD, First Exit and the vertical-slice status with the already
  implemented held supplies, stove, weather beat and consumed-pickup ledger.
- Prepared the continuous 10–15-minute stranger-run observer guide. Require a
  fresh New Game, record any intervention, and verify sleep/save/reload. Current
  retained stock does not prove the historical reduced-stock balance.

Validation
- Pending focused checks and a startup capture. A continuous human playthrough
  is not claimed; it remains the acceptance gate for First Exit A.

### 2026-09-27 — Physical Quick Access supplies, G wood drops and protected meal ritual (codex)

Fixed
- Quick Access draws knives, flasks, tins, the new hatchet and other small supplies
  into Henry's existing bone socket. Wheel-click draws first; LMB/next wheel-click
  uses the held item. Source pockets remain authoritative, including when an
  identical item is also in the pack. Slot changes, Hub entry and ownership loss
  clear the hand prop without deleting the stored item.
- Held flasks have readable volume marks on both sides and persistent consumed/
  remaining amounts. Four 250 ml portions retain the same pocket and an empty
  container; empty tins explain how to stow them. Upright grips are fitted to the
  new supplies only, preserving the hammer and held/thrown flare transforms.
- Pineapple now opens into a saved, visibly open tin on the first Use/F with an
  owned reusable knife. The next Use/F eats it. Opening supplies no calories.
- Author correction: the cloth-covered meal table is protected. Only the two
  benches initially holding supplies offer timed hammer dismantling. A drawn
  safely stowable tool no longer prevents the table's seated food ritual.

Added
- Author-requested G (`drop_carried`) puts a whole log/board armful on clear
  ground in front of Henry, with a floor ray, path occlusion and full-pile volume
  check. Walls, insufficient floor and blocked clearance preserve the load;
  service trigger Areas do not intercept placement. F recovers all units.
- A separately pickable hatchet on the generated shelter tool bench. Draw it,
  aim at a loose board pile and F chops for four seconds: one board becomes one
  log. Without the drawn hatchet boards remain ordinary pickups; interrupted
  chopping preserves them. Loose wood uses primitive save data and the pickup
  ledger, with deferred restoration supporting either participant order.
- Updated controls and shelter walkthrough. Action prompts follow the selected
  game locale; the author's Russian explanation is provided in chat.

Validation
- Fifteen related suites pass, including real-player/input/pocket/hand tests,
  finite drinking, two-step pineapple, refusals, floor/wall/clearance checks,
  axe conversion/cancellation, loose-pile save restoration, protected meal F,
  and the existing stove/boarding/flare/entry workflows. New tests keep locomotion
  fixed and skip action clips while exercising the actual interaction/storage path.
- Headless editor import and input-overlap check pass. Local Compatibility
  captures show held knife, flask (including walking pose), closed/open tins
  and hatchet; they exposed and corrected grip direction and back-face markings.
  An unrestricted island playthrough and Forward+ visual verification are not
  claimed by these checks. Existing isolated-player fixture diagnostics remain.

### 2026-09-27 — Water, pineapple, knife, furniture salvage and closed roof (codex)

Added
- Read all 25 GitHub issue bodies, including 13 closed issues, before implementation;
  applied the inventory, Use, survival and pickup-save decisions. Dated inventory:
  `docs/audits/2026-09-27-shelter-supplies-issue-review.md`.
- A second visible supply bench holds a one-litre flask, two pineapple tins and
  two stew tins. A reusable knife sits beside the hammer/nails/lighter. All are
  separate F pickups retained by the scene generator and explicit test layout.
- Flask Use drinks 250 ml, restores hydration and leaves the partly filled or empty
  container. Pack/pocket rows show remaining volume; selection and drink feedback
  show drunk/remaining/capacity. Catalog fill-state IDs retain the existing save
  format and keep other flasks independent; pocket Use restores the same pocket.
- Pineapple Use/F explicitly opens and eats one tin only when Henry carries the
  knife. It supplies 300 calories and eight hydration points, leaves an empty tin,
  and retains the knife. Missing-knife and empty-flask refusals explain the next step.
- With the hammer drawn, F deliberately dismantles the tool bench, supply bench
  or meal table over four seconds into three floor logs. Uncollected supplies block
  the action. Saved destruction and the pickup ledger prevent duplicated salvage;
  restoration handles either participant order and earlier uncollected saves.

Fixed
- Intact bungalow roof apertures now have front/back timber gables, side eave
  closure and a ridge cap with solid collision shapes; damaged variants retain damage.
- Supply pickup prompts retain item names alongside their water/tool information.
- The meal cloth presents each carried kind before filling spare slots with
  duplicates, so a stack of tins cannot hide the flask or pineapple.
- The recovery fixture now checks changed trends within their sampling window and
  confirms they clear in the next steady window, avoiding expired-marker assertions.

Validation
- Real-player/TPS/F workflow passes pickup, nutrition/tool refusal, four drinks,
  container save round-trip/pocket replacement, roof rays and all three tables,
  plus the previous boarding/stove/table/flare sequence. Twelve other related
  suites pass; headless editor import reports no script/import errors.
- Local Compatibility captures show the benches, closed roof, meal props and
  readable partially filled flask status. A continuous human island playthrough
  and Forward+ verification remain separate from these automated checks.
- Updated scenario and finite-supply limits: `docs/gameplay/shelter_test_walkthrough.md`.

### 2026-09-27 — Playable shelter supply and work rituals (codex)

Fixed
- Dropped burning flares now fall from the actual hand in a rigid body, inherit
  movement velocity, and settle against terrain/floor while continuing to burn.
- Hammer and nails were below the generated house floor (0.55 m versus 0.90 m).
  Hammer, a visible 66-nail box and a reusable lighter now occupy separate spots
  on a tool bench; logs/planks have recognizable full-size pickup geometry.
- Inventory counts sum all stacks, including the second nail stack. The centre
  prompt refreshes after an action and displays refusals instead of retaining old
  copy. Pickup ground rings no longer obscure objects on the bench.
- Window focus covers the visible aperture, including a camera inside its trigger.
  F stages boards, then draws the owned hammer and one offhand board; camera aim
  moves the ghost and LMB consumes two nails per placement. Esc loses no material;
  obstacles prevent placement. Staged planks lie on the actual interior floor.
- Stove input now explicitly opens, loads up to three cold logs, and ignites with
  a lighter over five seconds. Missing ignition tools preserve the loaded wood.
  Cold fuel remains visible/savable; restored ignition state is published before
  fuel observers save it. Flames and a room-air readout show the result.
- The cloth table offers a seat entry, explains occupied hands, and lays out food
  for F consumption. Seated aim uses the actual projected centre ray and occlusion.

Changed
- Explicit temporary test pickups provide 33 route boards (27 near/inside the
  shelter), 66 nails and nine nearby logs. Layout and generated scene agree.
- The generated shelter retains up to two extra degrees in its fully leaky state;
  boarding raises that ceiling toward eighteen. Heating remains gradual and uses
  the existing ThermalZone model. The HUD distinguishes room air from body heat.
- Longer contextual instructions wrap within the existing prompt face.

Validation
- Added a real-player/input/TPS-projection workflow covering floor/tool pickup,
  two board trips and five placements, cancel/obstruction/same-frame camera turn, three-log cold loading,
  missing lighter, timed ignition, room warmth/readout, table eating/standing and
  flare gravity/settling. Updated stove and route expectations for the new steps.
- The workflow and 21 related system suites pass; the traversal fixture also
  climbs the veranda and enters the house through generated collisions.
- Full scenario and limitations: `docs/gameplay/shelter_test_walkthrough.md`.
- Local compatibility captures show the bench, board ghost and lit stove/readout;
  they do not establish Forward+ island performance or manual traversal.

### 2026-09-27 — Shelter test start and visible-object interaction (codex)

Changed
- The island uses the generated shelter-facing spawn beyond the veranda steps.
  Extra packed bedroll and road flare pickups sit separately beside the approach;
  original bunker supplies remain. Heights and placement stay in the layout generator.
- Only the held flare receives a 90-degree local correction, pointing the spark
  jet forward and upward rather than at Henry's legs; shared tool sockets and
  dropped-flare placement keep their existing transforms.

Fixed
- Generated interaction triggers are self-contained and preserve their box or
  small sphere shapes after packing, instead of reverting to the 6 m template.
- Explicit focus anchors and weak solid-owner bindings let the stove and cabinet
  resolve to their actions without treating their own bodies as occluders.
- Unfocused overlapping Areas no longer hide a valid target farther along the
  centre ray. Walls still occlude selection, and consumed targets clear immediately.
- Generated Areas establish their proximity signals once at runtime; mattress
  focus sits above the floor rather than being occluded by its supporting slab.

Validation
- Coverage uses the saved shelter's stove body, door, cabinet, seat and mattress,
  plus overlapping triggers, wall occlusion, lighting and pickup focus clearing.
- Route coverage checks packed trigger sizes, spawn orientation and separated
  test supplies; held-light coverage checks nozzle direction standing and walking.

Branch integration
- Merged current main into codex, retaining the current IslandTerrain baseline,
  input map and survival UI instead of the obsolete Terrain3D compatibility changes.
  Author edits to key hints were preserved; the edited spawn marker is replaced
  by the shared generated marker as requested.

### 2026-09-25 — Bunker road flare made part of the opening (codex)

Added
- One recognisable unlit road flare now lies beside the bunker bedroll instead
  of the opening route starting without an emergency light.
- Route coverage locks its placement, count and item-specific world visual.

Changed
- The flare burns for 75 real seconds: 30 minutes on First Exit's 3600-second
  game-day clock, matching a real long-burning road-flare rating in game time.
- Controls now document the existing pocket flow: `F` to collect, wheel to
  select, wheel-click to strike, and wheel-click again to drop it burning.

### 2026-09-25 — First Exit buildings made physically enterable (codex)

Fixed
- Re-anchored each bungalow to the ground at its own veranda approach instead
  of the lowest point of the whole lot; northern decks no longer sink into the
  terrain.
- Replaced the decorative single veranda block with visible timber steps over
  a shallow ramp collider, because Henry has no automatic step-up.
- Widened house and shed openings, raised lintels and the veranda lean-to roof,
  leaving real clearance around Henry's 1 m x 2 m collision body.

Added
- Standing houses and sheds now carry a physical hinged door that opens and
  closes on `F`. Boarding the shelter doorway closes and locks that leaf.
- Regression coverage checks all eleven bungalow approaches, door dimensions,
  matching door collision and the open / close / board interaction lifecycle.

Removed
- The generic `InteractiveArea` template no longer silently spawns a test
  flashlight. The TestScene flashlight now opts into that prop explicitly, so
  generated repair prompts cannot place an invisible blocker in a doorway.

### 2026-09-25 — Restrained startup title (codex)

Changed
- The engine boot is now a plain `#101010` field instead of the old illustrated
  splash.
- The playable island opens under a centered `Hoarbound` / `ALPHA 0.1`
  title card in soft white, then reveals the scene with a short fade. Capture
  tools that instantiate the island directly skip the card.

Removed
- The obsolete `Splash_testing.png` asset and its import metadata.

Tested
- Added `test_startup_presentation.gd` to lock the boot colour, wording,
  version label, main-scene wiring and removal of the legacy image.

### 2026-09-25 — Drifting snow made readable (claudeflow)

Changed
- `SnowLift` (Codex's surface-transport rework): grains are now soft round-edged
  streaks instead of hard quads, in a muted off-white. They are larger, and the
  layers sit 5 cm above the surface so they no longer sink into it.

Added
- A thin ground haze layer that the streamer drags along, so the drift reads
  from eye height.

### 2026-09-25 — Snow lifted by gusts (claudeflow)

Added
- `scripts/vfx/snow_lift.gd`: a one-shot puff of grains lifted off the surface.
  They leave about 10 degrees above flat along the wind, curve steeper under an
  upward pull and fade out. The grains are tinted a shade off the snow so they
  read against it.
- WindGusts lifts snow on the ground under each streak, found with a raycast.

### 2026-09-25 — Wind gusts in First Exit (claudeflow)

Added
- `scripts/vfx/wind_gusts.gd`: WindStreak loops in front of the camera, running
  with the wind. None below 6 m/s, one every ~2.6 s in `windy`, and one every
  ~0.6 s in `blizzard`. Never shown while sheltered. A five-streak burst plays
  when the weather turns.
- WeatherBeat owns one WindGusts and fires the burst on `beat_started`.

### 2026-09-25 — WindStreak VFX (claudeflow)

Added
- `scripts/vfx/wind_streak.gd`: a cartoon wind streak. A line draws itself,
  curls into one closed self-crossing loop, runs on straight and fades from the
  tail. The heading turns exactly 360 degrees under a gaussian curvature bump, so the loop
  always closes. Camera-facing ribbon, tapered and alpha-faded towards the tail.

### 2026-09-25 — First Exit A playtest kit (#80) (claudeflow)

Added
- `docs/playtest/FIRST_EXIT_A_RUN.md`: what the observer says (and must not),
  the beat timeline with what to watch and what to ask, the retelling that
  decides pass, and the failure pass.
- `tools/runtime/capture_first_exit_frames.gd`: the six publisher frames of the
  #80 table from the real scene (exile, route clutter, weather turn, boarding,
  lit stove, seated with Kenny) into `docs/art/issue80/`.

### 2026-09-25 — Breach drafts; one weather controller (#80) (claudeflow)

Added
- `BreachDraft` on every `ShelterBreach`: snow blows in through an open breach,
  as dense as `get_exposure_against(wind)` times the wind speed, so the player
  sees which side to board first; a lee-side hole stays quiet and a boarded one
  stops. `test_breach_draft`, `tools/runtime/capture_breach_draft.gd`, frame
  `docs/art/issue80/01_snow_through_windward_breach.png`.

Removed
- The empty `WeatherController` node in `WorldEnvironmentSystem.tscn` and the
  unread `WorldEnvironmentController.weather_controller` export: the world's
  system controller is the only one.

### 2026-09-25 — Game time: 60 real minutes a day, start at noon (#42) (claudeflow)

Changed
- Author decision for First Exit A: a full game day is a stable 60 real minutes
  (`day_duration` + `night_duration` = 1800 + 1800 s, was 72 + 72), with no
  dynamic coefficients. One game hour = 2.5 real minutes.
- `DayNightManager.start_hour` (default 12.0): a new game starts at noon so a
  10–15 minute run reaches late afternoon and dusk; a save overrides it.
- Knock-on: one log (2 h) now burns 5 real minutes, warming on the stove
  (0.5 h) 75 s; the weather beat's 180 s storm is about 1.2 game hours.

### 2026-09-25 — Authored weather turn on the First Exit route (#78) (claudeflow)

Added
- `WeatherBeat` (placed by the First Exit builder, saveable): holds `calm` on the
  way out; once per run, when Henry is 200 m from his start (or after 300 s real
  as a fallback so the door cannot be waited out), and never while he is
  sheltered, it drives the one WeatherController into `blizzard` for 180 real
  seconds, then `windy` (never straight back to calm), then the scheduler.
  Beat length is in real seconds because the game clock runs a day in 144 s.
- `WeatherController.set_weather(id, instant, duration_h, then_id)`: an authored
  beat can pin a duration and the profile that follows; `then_id` is saved.
- The beat finds the populated WeatherController itself: the environment scene
  carries an empty leftover controller, and this scene gets no on_world_ready.
- `test_weather_beat`, `tools/runtime/capture_weather_beat.gd`, frame
  `docs/art/issue78/calm_then_storm.png`.

### 2026-09-25 — Consumed world pickups stay consumed (#79) (claudeflow)

Added
- `ItemPickup.world_id`: a stable id for authored pickups; the First Exit
  builder sets it from the layout id (all 11 route pickups).
- `PickupLedger` (one per built world, saveable, key `pickup_ledger`): records
  taken world ids and, on load, removes those pickups from the rebuilt world.
  Stores ids only; the items themselves stay in the inventory save. Stack pickups
  stay atomic; dropped items (no world id) are untouched.
- `test_pickup_ledger`: pick up boards/tinder/firewood/food → save → rebuild →
  load; items stay in the inventory, the pickups are gone, others remain.

### 2026-09-25 — Lighting the stove as an act (#42) (claudeflow)

Changed
- F on the stove is a staged act on top of `HeatSourceFeed` (no new survival
  architecture): tinder and a log go in at once, Henry kneels and holds still
  (`Player.hold_still()`), the door swings open and a weak flame grows; only
  after 5 s does the fire take, burn and heat. A log on a live fire is the short
  act (door, log, door; 2 s) and needs no tinder. The prompt reads "Light the
  stove" or "Add a log". `feed()` stays the instant path for systems and tests.
- `StoveVisual` shows as many logs as a full load holds (6 h / 2 h = 3), not 4;
  the log going in shows during the act. Balance is unchanged: 1 log = 2 h,
  6 h max, so a full night still needs tending.
- `test_stove_act`; frame `docs/art/issue42/07_lighting_act.png`.

### 2026-09-25 — Controls audit (#76) (claudeflow)

Removed
- Input actions nothing consumed: `open inventory` (I), `open map` (M),
  `open health_panel` (H), `open craft_panel` (K), `select item slot 5–8`,
  `reload` (R), `secondary action` (RMB), `drop item` (G), `toggle camera view` (V),
  `use_ability_gizmo_2` (X), `orbit_left`/`orbit_right` (, .), `DEBUG` (Enter).

Added
- `docs/technical/CONTROLS.md`: every key, and the context rules for F (one verb,
  resolved by what is in front of Henry) and Esc (always one step back), with the
  rules new features follow. `test_quick_access` guards against the dead actions returning.

### 2026-09-25 — Full pack inspection (#75) (claudeflow)

Added
- `PlayerHubComponent.open_inspection()`: a separate, slower Hub state. From the
  Hub ("Take the pack off") the pack comes off and stands in front of Henry,
  fully open, Kenny beside it; the camera looks down into it from past his left
  shoulder. Closing puts it back on. Seated by the stove, F on the set-down pack
  ("Go through the pack") opens inspection where it stands; afterwards it stays
  there, ajar.
- Extension point for sorting, sections, repair and crafting:
  `inspection_opened(pack)` / `inspection_closed`, and the panel lists the pack's
  sections in inspection mode.
- `test_pack_inspection`; frame `docs/art/issue68/10_full_inspection.png`.

### 2026-09-25 — Seated reach: warm and eat from the seat (#42) (claudeflow)

Changed
- Seated, `InteractComponent` picks the F target by where the camera looks
  (within 35° of the view) and reaches 2 m instead of 0.9 m: Henry leans to the
  stove's cooking ring and to the table, and never walks off to a target. Warming
  and eating off the stove now work from the seat.
- `test_seated_aim`.

### 2026-09-25 — Warming on the stove top (#42) (claudeflow)

Added
- `StoveWarmer` on the shelter stove's cooking ring. F with a warmable item
  carried puts one on the ring ("Warm up: Tinned stew"); it warms over 0.5 game
  hours, only while the stove burns (also through a seated wait); then F eats or
  drinks it straight off the stove ("Eat: Hot stew"), with steam while ready.
  Saved with the world.
- Items `tinned_stew_hot` (warms Henry, −0.8 °C cost) and `warm_water` (−0.3 °C,
  versus +0.35 °C for raw snow); `ItemResource.warms_into` names the warmed form.
- `HeatSource.heat_elapsed(hours)` for things warming on a fire;
  `ConsumptionController.consume_from_world()` for food that is not carried.
- `test_stove_warmer`; frames in `tools/runtime/capture_stove.gd`.

### 2026-09-25 — Stove ritual UX pass (#42) (claudeflow)

Changed
- Food on the meal table is real: one `TableFood` target per kind ("Eat: Tinned
  stew ×2", "Drink: …"); F eats one through ConsumptionController. Seated, F goes
  to whatever is at arm's length and only waits when nothing is; the seat is not
  a target while Henry sits on it.
- `1`–`4` only select a pocket; the wheel click uses it (no accidental eating).
- A wait starts at 1 hour (sleep keeps its own last choice) and says why it
  ended early: "Warm and dry" / "The stove went out".
- Waited time bills hunger and thirst including part-hours
  (`BioMonitorManager.pass_awake_hours(float)`); a 15-minute wait was free before.
- Drying steam: thin wisps from the chest and shoulders, lower while seated.
- The pack set down by the stove stands ajar (`PackRig.Openness.AJAR`): top and
  side flaps lifted a little.

### 2026-09-25 — Meal table by the stove (#42) (claudeflow)

Added
- `MealTable`: a small table with a cloth beside the rest crate. While Henry sits
  by it, the food and drink he carries (pack and pockets) is laid out on the
  cloth — a tin per stew, a snowball per handful of snow — and it follows what
  is eaten or moved; standing up clears it. Eating stays Hub/pocket Use (the
  seated clip is chair-sitting, so the cloth is on a table, not the floor).
- `test_shelter_recovery` covers the layout; frame `docs/art/issue42/04_meal_table.png`.

### 2026-09-25 — A real stove in the shelter (#42) (claudeflow)

Added
- `StoveVisual` around the shelter's HeatSource: legs, an ash pan with a draught
  vent and pull, a firebox with floor, walls and a front frame, a slotted door on
  a hinge with a knob, a cooktop with a cooking ring, and a flue. One log shows
  per fuel unit left (up to 4); the ember bed and an inner light glow through the
  door slots only while it burns, with a gentle flicker.
- The builder places it and keeps a collision hull; `test_stove_visual`,
  `tools/runtime/capture_stove.gd`, frame `docs/art/issue42/03_stove_states.png`.

### 2026-09-25 — Waiting seated; pack and Kenny set down by the stove (#42) (claudeflow)

Added
- Seated, `F` opens the sleep dialog in wait mode ("WAIT BY THE FIRE"): the same
  hour picker, no sleep, no save. `SleepController.try_wait()` advances the world
  and stops early once Henry is dry and warm or no fire warms him;
  `BioMonitorManager.pass_awake_hours()` bills the waited hours.
- On sitting Henry takes the pack off and stands it on his left; Kenny is set on
  his right, facing the pack. Both go back on when he stands
  (`HenryUALAnimation.set_pack_down()` / `pick_pack_up()`).
- A seated hint: "F — wait · move — stand up".

Changed
- Seated, `F` waits instead of standing up; Esc or any move input stands.
- Drying steam is thinner.

### 2026-09-25 — Recovery by the stove: sitting, trend marks, drying steam (#42) (claudeflow)

Added
- `RestSpot` (F — Sit down) and `RestComponent`: Henry sits on the seat facing
  its -Z; F, Esc or any move input stands him up. Sitting gives no bonus (author
  decision): the stove warms and dries, sitting only holds him still.
- `HenryUALAnimation` sit states: `Sitting_Enter` → `Sitting_Idle` loop → `Sitting_Exit`.
- First Exit shelter: a crate to sit on by the stove (`RestCrate`, via the builder).
- Vital HUD: a trend mark on the warmth cell and a wetness water-fill on the
  figure with its own mark (green when it helps Henry, red when it hurts).
- `DryingSteamComponent`: soft steam off wet clothes near a burning HeatSource,
  thinning with wetness.
- `tests/systems/test_shelter_recovery.gd`; sit states in `test_henry_animation`;
  `tools/runtime/capture_shelter_recovery.gd`, frame `docs/art/issue42/`.

### 2026-09-25 — Quick access from pockets; L key removed (#68, #73/#74) (claudeflow)

Added
- `QuickAccessComponent` on the Player: mouse wheel (`quick_next`/`quick_prev`)
  cycles worn pockets with a short readout; wheel click (`quick_use`) uses the
  selected pocket's item through the Use contract; `1`–`4` (existing
  `select item slot N`) pick and use a pocket directly. Q/E stay free for leaning.
- `PlayerHubComponent.use_from_zone()`: a pocketed item passes through the pack to
  its user and returns to the pocket if nothing could use it.
- `HeldLightComponent.release_held()`: the next quick-access click drops the burning flare.
- `ConsumptionController` joins the Use contract: food and drink are eaten through
  Hub Use or a pocket click. Nothing in gameplay called it before, so Henry could not eat.
- `tests/systems/test_quick_access.gd` (pockets, flare, eating).

Removed
- `toggle_flashlight` (L) action and its handler.

Fixed
- `tools/ci/check_input_map.py` ignored mouse-button events and quoted action
  names (e.g. `open hub`), so their overlaps went unchecked.

### 2026-09-25 — Use action; bedroll via preview, B key removed (#68, #74) (claudeflow)

Added
- Item Use contract: `PlayerHubComponent.can_use()/use_item()` hand an item to the
  sibling component whose `can_use(id)` accepts it. Hub panel has a Use button.
- Bedroll Use: the Hub closes and a see-through roll follows in front of Henry;
  `F` lays it there, `Esc` cancels (nothing is spent until placed).
- Flare Use: lights it into the hand (same `HeldLightComponent.light()`; `L` stays for now).

Removed
- `lay_bedroll` (B) input action and its handler.

Fixed
- The bedroll was laid behind Henry (+Z); it now lands in front (-Z).

### 2026-09-25 — Hold-F manual placement (#68) (claudeflow)

Added
- Holding F (0.35 s, `PlayerHubComponent.HOLD_TIME`) through a pickup opens the
  Hub in placement mode (`open_placement`): the pack opens fully, the item sits
  under the cursor, the pack and pockets it fits are lit (by `SizeClass`), LMB
  drags it and releasing drops it there and closes the Hub. A drop outside a lit
  pocket leaves it in the pack. Tap F stays the quick stow.
- `test_player_hub` covers the hold and the drop; frame `docs/art/issue68/07_hold_placement.png`.

### 2026-09-25 — Tap-F quick stow through the top flap (#68) (claudeflow)

Added
- `ItemPickup` hands its mesh to `PlayerHubComponent.stow_visual()`: the item
  lifts, drops into the pack's top flap (`TOP_ONLY`) and the pack shuts once it
  lands. The inventory gets the item at once; the flight is presentation only.
  Armfuls (`carried_in_hands`) still go to the hands.
- `test_player_hub` covers the stow; frames `docs/art/issue68/04–06`.

### 2026-09-24 — Player Hub foundation: four-flap pack and Quick Access (#68) (claudeflow)

Added
- `PackRig`: the backpack on Henry is a tray with four hinged flaps (top, bottom,
  left, right) over an inner attachment field. `TOP_ONLY` opens the top flap
  (future quick stow); `FULL` opens it like a book. Kenny rides the bottom flap.
- `PlayerHubComponent` on the Player (`Tab`, the existing `open hub` action):
  roots Henry, blends to a camera facing the pack, opens it fully. It reads
  `InventoryComponent` and worn pockets and stores nothing itself.
- Quick Access zones = pockets on worn garments (pack main compartment excluded).
  Items move pack → pocket → pack with no duplication; size class gates pockets.
- `PlayerHubPanel`: temporary localised readout (pack list, zones, weight, refusals).
- `tests/systems/test_player_hub.gd`, `tools/runtime/capture_player_hub.gd`,
  frames in `docs/art/issue68/`.

Fixed
- Pocketed items now count toward carried weight (`EquipmentComponent.get_carried_weight`).

### 2026-09-24 — First Exit split: land night vs Coast / Thin Ice (#24) (claudeflow)

Changed
- `docs/world/FIRST_EXIT.md`: First Exit (milestone A) is the land night only;
  the ice route moves to milestone B, Coast / Thin Ice.

### 2026-09-24 — Bedroll: sleep in the field (#63) (claudeflow)

Added
- `bedroll` item, found at the bunker (First Exit layout `bedroll_bunker`).
- `BedrollComponent` on the Player. `B` (`lay_bedroll`) spends the bedroll
  into a roll laid along Henry's facing, with a kneel. The roll offers
  F — Sleep through the same `SleepSpot`, so `SleepController` still refuses
  unsafe cold or wet, and a Roll-up prompt at its head returns it to the
  inventory. A laid roll is saved and restored (`saveable`). `B` stands in
  until the inventory has a Use action.
- `test_bedroll.gd`.

### 2026-09-24 — Flare pass 2: raised hand, spark fountain, breathing light (claudeflow)

Changed
- UAL `Idle_Torch` raises the *left* hand, so the shared hand socket and the
  held pose moved to `hand_l`. The flare is carried at chest height, tipped
  out of the fist.
- Sparks are a gravity fountain that spits in uneven spurts: more particles,
  higher speed during a spurt, and a colour ramp from orange-white to red.
  The light's reach breathes with the burn and swells on each spurt.
- Includes Codex's polish `f3ee73f`: soft spark billboards, warmer smoke,
  4.5 m / 2.8 indoor-friendly light.

### 2026-09-24 — Road flare in Henry's hand (#57) (claudeflow)

Added
- A shared held-item socket: `HenryUALAnimation.get_hand_socket()`, a
  BoneAttachment on `hand_r`. `hold_in_hand()` / `release_hand()` move props
  in and out of it. It is the one hand path for flares and later lights.
- A held pose: the right arm eases into `Idle_Torch` through a bone-filtered
  Blend2 over any locomotion, so the legs keep walking.
- `HeldLightComponent` on the Player. `L` (`toggle_flashlight`) spends a
  `road_flare` from the inventory into the hand. A second `L` drops it burning
  at Henry's feet. A spent flare lingers 3 s for its smoke, then goes. It
  forwards WorldContext, so the smoke gets live WeatherController wind.
- The `road_flare` item, a `test_held_light.gd` suite, and
  `tools/runtime/capture_held_flare_ingame.gd` (a night, windy capture in
  the main scene). Frames are in `docs/art/issue57/`.

### 2026-09-24 — Sleep is an interaction, not a key (claudeflow)

Changed
- There is no global sleep key. `SleepSpot`, an InteractiveArea, offers
  "F — Sleep" on a bed, mattress or bedroll. F opens the sleep dialog through
  the existing InteractComponent path, and a refusal (cold, wet, unsafe) shows
  on the spot. Inside the dialog, the mouse wheel or ← → change the hours,
  F or Enter sleeps and saves, and Esc cancels.
- `SleepPrompt` lost the hold-S charge and its widgets; `request_open()`
  checks `SleepController.can_sleep()` first.
- The First Exit shelter has a mattress by the west wall.

Removed
- Input actions `sleep`, `sleep_hours_less` and `sleep_hours_more` (S/A/D
  clashed with movement), with their InputSystems signals. Their allowlist
  entries are gone, so CI now rejects any new overlap with WASD.

### 2026-09-24 — Build hygiene from the #58 review (claudeflow)

Added
- `tools/ci/import_gate.sh`: the CI import now fails on load errors (second
  pass, after cold-cache ordering noise) and compiles every project script
  (`tools/ci/compile_scripts.gd`). This replaces `--import --quit || true`.
- `tools/ci/check_input_map.py`: two actions on one key fail CI unless
  `tools/ci/input_overlap_allowlist.txt` gives the reason.

Changed
- README rewritten after ADT's layout: what is in, run, controls, layout, docs,
  agents, licence. Engine is 4.8-dev6, not 4.5.
- `AGENTS.md` / `CLAUDE.md` now share one branch rule: agents merge `main`
  into their own branch freely, and integration into `main` needs the author.
- `docs/THIRD_PARTY_NOTICES.md` credits Godot and Quaternius UAL, and flags the
  audio files whose source is unrecorded. `ual/NOTICE.md` now says UAL2 is used.

Removed
- `project.godot` noise: the 5 s boot splash, the low-processor sleep, the
  orphan cursor hotspot, explicit defaults, the orphan `[debug_draw_3d]`
  section, and the unused `use_ability_gizmo_1` action (it clashed with Z).
- Orphans: `experimental_location/exp/` (HTerrain data), the unreferenced
  `player_test_model` FBX with a broken texture path, and the empty skeleton
  folders `autoloads/`, `levels/`, `systems/`, `ui/`.

### 2026-09-24 — Issue #56: carry firewood, cabinet, working actions (claudeflow)

Added
- `CarryComponent` on the Player. An item flagged `carried_in_hands` (firewood)
  puts Henry in a `Carry` state. Walking plays UAL2 `Walk_Carry`; standing keeps
  the idle legs with the carry arms. The armful is a real prop on a
  `spine_03` BoneAttachment. The carry ends when the last log leaves the
  inventory, for example into the stove.
- `Cabinet` (an InteractiveArea) with a door on a real hinge. It requests
  `chest_open` and swings the door after a 0.45 s hand delay, and refuses input
  while the door moves. Built into the First Exit shelter against the east wall.
- `tools/runtime/capture_shelter_slice.gd`: an in-scene demo of pickup, carry,
  stove, cabinet and window repair through the normal approach path, rendered
  through its own SubViewport. Frames are in `docs/art/issue56/`.

Changed
- Merged Codex's approved animation layer from #51 (`1ccccf8`).
- Working actions (`interact`, `pickup`, `fix`, `chest_open`) root Henry until the
  clip ends. The existing breach repair now reads as `Fixing_Kneeling` with no
  sliding.

### 2026-09-24 — Coat skirt no longer lets the thighs through (claudeflow)

Fixed
- The coat's skirt cross-section is the larger of an ellipse and the body's
  measured outline, so it never sits inside the hip at rest.
- The hem follows the thighs up to 90%: each side follows its own leg, and the
  centre line follows both legs' average.
- The skirt's top tucks under the coat, which closes the gap at the waist.
- Idle, walk and sprint renders show no thigh through the cloth.

### 2026-09-24 — Outfit pass 2: longer coat, placket, seams (claudeflow)

Changed
- The coat reaches mid-thigh. A flared skirt is skinned to the pelvis and
  partly to each thigh, so it swings with the legs instead of splitting into
  shorts.
- Sleeves reach the knuckles. The beanie is smaller, with a thinner cuff.
- The coat stops at the waist, which removes the bulge at the crotch.

Added
- A front placket with a zip, and seams at the shoulders, cuffs and waist.
  They are ribbons ray-cast onto the coat's surface and skinned like the
  nearest coat vertex (`Outfit_Trim`).
- `HenryUALAnimation` gives every garment surface its own wet-darkening
  material, so the zip keeps its colour.

### 2026-09-24 — Henry's outfit from Blender (claudeflow)

Added
- `tools/blender/build_henry_outfit.py` builds a jacket with a rolled hood,
  trousers, boots with soles and a beanie with a cuff around the UAL mannequin.
  Each piece is cut from the body, smoothed, pushed out and thickened, so it
  keeps the body's skin weights and bends at the elbows and knees.
  Output: `assets/characters/henry/henry_outfit.glb`, with renders in
  `docs/art/`.
- Skin under each garment is split into `Skin_<item>` meshes. They are hidden
  while that item is worn, so clothes never clip and removing one leaves no
  hole.

Changed
- `HenryUALVisual` uses the outfit GLB; the same skeleton and the 45 clips.
- `HenryUALAnimation` groups the outfit meshes per garment for equipment and
  wetness, and no longer builds greybox primitives (`GARMENT_PIECES` removed).

### 2026-09-24 — Terrain stage 4: Terrain3D removed (claudeflow)

Removed
- The Terrain3D addon, its editor plugin entry, its CI download and cache key,
  and the `.gitignore` rule for its binaries.
- The Graciosa Terrain3D region data (25 MB), `dump_island_heights.gd` and
  `export_heightmap.py`; the heightmap PNG is now the only terrain source.
- Capture tools that needed the Terrain3D node (`capture_freemans_sky.gd`,
  `capture_island_visual_fx.gd`, `capture_production_snow.gd`) and
  `terrain3d_stylized_capture.gdshader`.

Changed
- `capture_first_exit.gd` and `island_report.py` work only on the heightmap.

### 2026-09-24 — Terrain stage 3: the main scene runs on IslandTerrain (claudeflow)

Changed
- Graciosa's main scene uses `IslandTerrain` in place of `NavigationRegion3D`
  and Terrain3D; the nav mesh was empty and unused. It follows the Player,
  which now starts at the spawner. The lavapipe crash is gone: 600 frames of
  the main scene, and full-scene captures in 2 of 2 runs.
- The blockout builder samples the heightmap instead of Terrain3D.
- `capture_first_exit.gd` renders the mesh terrain by default.

Fixed
- Generated interactives (pickups, board-up and stove prompts) saved their
  body signals twice and logged "already connected" at load. The route test
  now checks for exactly one connection.

### 2026-09-24 — Terrain stage 2: IslandTerrain from the heightmap (claudeflow)

Added
- `IslandTerrain` + `IslandHeightmap`: the island ground built from the
  heightmap. It has 128 m chunks with 1/4/16 m levels of detail, skirts, and
  HeightMapShape3D collision near the focus; `get_height` matches the Python
  tools exactly. The terrain shader colours by height and slope, with the
  shared snow cover on top.
- `tools/world/bake_terrain.py` writes `world/terrain/graciosa_height_la8.png`,
  the game-readable copy of the source (Godot drops 16-bit PNGs to 8-bit).
- `test_island_terrain.gd`.

Changed
- Heightmap export adds a sea bed that shelves from the coast instead of
  Terrain3D's flat 0 m plane. The source PNG was re-exported.

Found
- The full Graciosa scene no longer crashes under lavapipe once Terrain3D is
  swapped for IslandTerrain (3 of 3 runs, 7 shots each).

### 2026-09-24 — Terrain heightmap becomes the source of truth, stage 1 (claudeflow)

Added
- `world/terrain/source/graciosa_height.png` (+ `.json`): the island as a
  16-bit 1 m heightmap, −16…+48 m, exported from Terrain3D with at most
  0.5 mm error (8 MB against 25 MB of Terrain3D regions).
- `tools/blender/heightmap_import.py` / `heightmap_export.py`: Blender round
  trip. Import the whole island or a window as a grid, sculpt, and write back
  only the changed heights. Verified headless with `bpy`.
- `tools/world/heightmap.py`; `island_report.py` and `route_metrics.py` read
  the PNG directly. See `docs/world/TERRAIN_HEIGHTMAP.md`.

Fixed
- `route_metrics.py` crashed drawing pickups (no footprint size).

### 2026-09-24 — First Exit: the working loop moved into the route (claudeflow)

Added
- The shelter lot now carries the TestScene loop: an interior ThermalZone,
  five ShelterBreach openings with board-up prompts, and a stove (HeatSource +
  feed). Sleep and save work there through the existing SleepController.
- Layout `pickups`: boards, tinder, firewood and food placed per route with
  deliberate scarcity (5 openings, 3 boards; tinder only at the fort or in the
  collapsed house). `test_first_exit_route.gd` guards the loop and the
  scarcity.

### 2026-09-24 — First Exit: route clutter, Kenny on the pack, visible clothes (claudeflow)

Added
- Visible greybox clothes. Hat, coat with sleeves, trousers and boots are
  built on the UAL bones and shown per equipment slot through the garments'
  `mesh_node_name`. They darken with the thermal model's wetness
  (`HenryUALAnimation.set_wetness`, wired in `Player.on_world_ready`).
- Route clutter from the layout: cars, pickups, a van and a bus (overturned,
  sunk in drift, doors open), bins and dumpsters. Placed per route to break
  sprint lines and create choke points (Grok, #42).
- Kenny: item `kenny` (3 kg) on the back fixture from the start, with a plush
  silhouette strapped to the pack. Carried non-garments now count toward the
  carry weight (`EquipmentComponent.get_carried_weight`).
- `ItemResource.attached_mesh_node_name` shows a mesh on Henry for a
  non-garment in a body slot. `EquipmentComponent.starter_slot_items` places
  non-garments at start.

### 2026-09-24 — First Exit: suburb on the old road, human speeds (claudeflow)

Changed
- Greybox reworked per the author (PR #43). It is now an old coast road with
  a gravel bed, shoulders, ditches, broken asphalt, a junction and a lane to
  the jetty, and leaning or broken street lamps. Eleven lots face the road,
  each with a driveway, a fenced plot with a gate, a shed, a water tank, and
  winter retrofits (boarded, vestibule, stovepipe, insulation, snow fence).
  Some lots are roofless or collapsed. Houses have gable roofs. Resolved
  footprints are written to `docs/world/first_exit_resolved.json`.
- Walk 4 → 1.5 m/s, sprint 8 → 4.5 m/s. Locomotion blend points follow.
  The ice drain and sprint multiplier are rescaled so per-tile damage is
  unchanged.

Removed
- The inland salt lagoon proposal. Ice moves to the real coast later.

### 2026-09-24 — First Exit: island analysis and greybox (claudeflow)

Added
- `docs/world/FIRST_EXIT.md`: where the game starts on Graciosa, island
  metrics, buildable sites, measured routes, tropical reference typology and
  the author decisions the milestone needs (lagoon, walk speed, distance).
- `tools/world/dump_island_heights.gd`, `island_report.py`, `route_metrics.py`:
  heightfield dump, height/slope maps with buildable sites, route length /
  ice / coast-exposure metrics and landmark visibility.
- `data/world/first_exit_layout.json` and `tools/world/build_first_exit_blockout.gd`:
  data-driven greybox (bunker door, redoubt, battery, sheds, bus stop,
  bungalows, water tower, church, jetty, 36 dead palms) placed on terrain
  heights; instanced in the main scene.
- `tools/runtime/capture_first_exit.gd`: greybox renders.

Changed
- `FirstSpawner` faces the water tower; `World` now applies the spawner's yaw.

### 2026-09-24 — Dead player layer removed (claudeflow)

Removed
- The hidden Genesis8 Henry (skeleton, meshes, materials) embedded in
  `player.tscn`: 1.7 MB -> 4 KB. The UAL mannequin is the only body.
- Old HUD: `InGameUI`, `vital_signs.gd`, `CombatHUD` and its weapon slots, debug
  labels; `BioMonitorManager` no longer pokes a UI.
- Gizmo (the pre-Kenny robot): scene, scripts, the C# flashlight duplicate,
  test model and icons.

### 2026-09-24 — Audio system and a cheaper CI gate (claudeflow)

Added
- `SoundSystem` autoload with `SoundEvent` (variations, jitter, voice limits,
  cooldown) and `SoundLayer` (parameter-driven loops); bus layout with an
  interior low-pass. `WorldAudioBinder` feeds wind, shelter and footsteps.
  See `docs/technical/AUDIO.md`.

Changed
- CI is one `checks` workflow on pull requests to `main`: import, filename
  check, headless suites. The lavapipe render and both visual-FX preview
  workflows are gone; render locally with `tools/ci/render.sh`.
- `run_tests.sh` kills a hung suite after `SUITE_TIMEOUT` seconds (180) and
  counts it as failed.

### 2026-09-24 — Solid vital cells, a quiet figure, and a compile fix (claudeflow)

Changed
- Vital pentagons are a solid translucent backing; the level fill is gone.
- A plain grey standing figure sits between the top cells, above the health bar.

Fixed
- `VitalCluster` failed to compile on `main`: `draw_texture_rect_region` arguments
  were swapped and the glyph atlas SVG had no `.import`, so the HUD never loaded.

### 2026-09-24 — Original HFN vital glyphs and threshold morphs

Changed
- Replaced the four legacy bitmap glyphs inside `VitalCluster` with one original
  HFN SVG atlas: stomach, droplet, closing eye and falling thermometer.
- Each glyph has eight baked frames. A 0.35 s morph plays only when the value
  crosses 50% or 10%, reverses on recovery and never loops while idle.
- At 50% and above indicators stay off-white; below 50% the icon, outline and
  level fill turn muted yellow; below 10% they turn muted red.
- The always-running critical breathing was removed. Critical cells retain a
  static inset and stronger opacity, so danger remains legible without motion.
- Glyphs render at 30 px with a dark keyline for both snow and dark interiors.

Tests
- `test_vital_cluster.gd` now locks the exact 50% and 10% boundaries and the
  final critical morph frame.

### 2026-09-24 — Remove legacy map and portrait cameras

Removed
- The Graciosa island debug minimap pipeline: its SubViewport, regional overhead
  camera, MapDebug UI and inline minimap script.
- Henry's old front-face HUD camera pipeline: its SubViewport, CameraFaceHenry,
  portrait UI subtree and dedicated controller script.

Kept
- The gameplay TPS PlayerCamera, survival HUD, combat HUD, StatsDisplay and the
  remaining island debug labels.



### 2026-09-23 — Cold Ash color grading profiles

Added
- Two weak 33×33×33 display LUTs: `HFN_ColdAsh_Night` for the outdoor default
  and `HFN_ColdAsh_Shelter` for safe interiors.
- `ColorGradeController` owns only the existing Environment adjustments and
  exposes explicit outdoor, shelter and interior-initialization entry points.
- A deterministic standard-library LUT generator, a focused headless test and
  a same-camera TestScene capture tool.

Kept
- Day/night, weather, Freeman sky and parallax clouds retain their existing
  ownership. Automatic shelter detection is deliberately deferred until the
  gameplay system has one authoritative interior-state hook.

### 2026-09-23 — Weather-driven snowfall promoted to production

Added
- Production `SnowfallVFX` as a Node3D world-system under
  `scripts/systems/world/weather/`, registered next to WeatherController in
  `WORLD_SYSTEM_SCRIPTS`. Headless runs skip GPU VFX construction entirely.
- The VFX resolves the authoritative WeatherController from WorldContext; it
  does not create or own a second weather state.
- Local `SnowHeightFieldService` follows Henry by coarse 8 m cells, using a
  48×24×48 m / 256² GPUParticles height field only while snow is active.
- World snow is fixed at 3072 particles and 30 Hz simulation; foreground snow
  is capped at 32 rare flakes. Validated flake sizes and streak strength are
  frozen for this production pass.
- High-wind velocity stretch is render-only on the small world flakes; it does
  not add another emitter and does not enlarge particle collision.
- One island regression capture remains under `tools/runtime/`; the synthetic
  experimental snow scene, production-scene detour and old capture harness are removed.

Performance
- HeightField no longer follows the camera every frame.
- The validated llvmpipe preview showed no meaningful frame-time difference
  between snowfall, windy and blizzard stages; absolute llvmpipe FPS is not a
  target-GPU measurement.

### 2026-09-23 — Freeman atmosphere + parallax clouds promoted to runtime

Changed
- `WorldEnvironmentSystem` now assigns the combined Freeman + HFN parallax-cloud
  shader to `DayNightManager`; it is no longer capture-only.
- Cloud volume is slightly heavier: depth 2.35, coverage threshold 0.34 and
  opacity 0.92, while retaining the existing noise, wind and parallax controls.
- Freeman's physical sun direction is now independent from the scene's
  `DirectionalLight`. The latter can continue to become moonlight at night
  without being interpreted as the atmospheric sun.
- Runtime atmosphere uses the cold maritime tuning validated in the preview and
  12/4 view/sun samples to keep the production path bounded.

Kept
- `simple_overcast.gdshader` remains in the repository as the old implementation;
  the production scene no longer selects it.
- The existing shared CI/render workflow is unchanged.

## [Experiment] — `codex`

### 2026-09-23 — Freeman's Sky controlled island preview

Added
- Official CC0 full-resolution and quarter-resolution Freeman's Sky shaders from
  Niwl Games.
- A capture harness that renders the same Henry eye-line view at 06:15, 12:00,
  17:45 and 19:00 on the authored Graciosa island scene.
- Cold maritime parameter tuning lives in the harness, not gameplay code, so the
  experiment can be rejected without touching the current overcast day/night stack.

Performance choice
- The quarter-resolution variant is retained for the intended Forward+ runtime.
  The capture harness can use the full-resolution variant with its explicit
  manual-sun fallback when a headless runner cannot expose LIGHT0 correctly.
- No dedicated Freeman CI workflow is added; the project keeps the existing
  shared render/test pipeline.

## [Unreleased] — `claudeflow`

### 2026-09-23 — Vital HUD: X layout, quieter cells

Changed
- Cells turned 45° into an X with a wider centre; the health band starts from
  the centre of the X and runs right beneath the cells.
- No coloured fill at rest: neutral translucent level, rust only when low.
  Cells sit at 45% opacity and go opaque while draining, refilling or critical.
- A drain now draws the cell toward the centre instead of pushing it out.

### 2026-09-23 — Experimental vital HUD: pentagon diamond and health band

Added
- `VitalCluster`: four pentagons in a diamond, tips to the centre — warmth top,
  water left, food right, sleep bottom. Level fills from the outer edge; a drain
  nudges the cell out and flashes it dull red, a refill grows it for ~2 s with a
  green-gold edge, under 15% it breathes and sits out. Warmth has its own
  cold scale. Procedural, all sizes/colours/timings exported.
- `HealthStrip`: the old red HUD band, smaller, as the health bar — same
  `BG_indicatorSURV` shader and fade, cut to current health, with a pale damage
  trail that catches up.

Changed
- The old vital icons (`vital_signs_enabled = false`) and the wide red band are
  hidden, not deleted, for easy rollback.

### 2026-09-23 — Colour grade follows the shelter; Cold Ash LUTs retuned

Added
- `ShelterGradeBinder` world system: `ThermalManager.sheltered_changed` drives
  `ColorGradeController.initialize_for_interior()`; the grade module still knows
  nothing about shelters. `test_shelter_grade.gd` walks Henry in and out of
  the real test shelter.

Changed
- Cold Ash LUTs regenerated from `generate_cold_ash_luts.py`. Night no longer
  darkens the frame (−5% instead of −18%) and puts the cold where #31 asked:
  shadows go from warm to graphite-teal, highlights and snow stay neutral, warm
  sources keep their colour. Shelter warms darks and mids and keeps bright
  openings cool.
- Preview PNGs are now live in-engine captures, not LUTs sampled over an old
  screenshot.

### 2026-09-23 — ADT head look; shelter edge signal for the colour grade

Added
- ADT's procedural head look on the UAL mannequin: standing, the `Head` bone
  eases toward where the camera looks (up to 55° each way); walking, the clips
  own the head and the look fades out. The UAL head rests ~13° off the body,
  so the limits are asymmetric to make the turn equal both ways.
  `test_head_look.gd` measures the turn through a BoneAttachment3D.
- `ThermalManager.sheltered_changed(is_sheltered)`: one edge per real change
  of being inside an interior zone, for #31's LUT switch.

### 2026-09-23 — Smart camera against walls

Fixed
- With Henry's back to a wall, turning the camera into it put the camera
  through the wall: the ADT 0.7 m minimum boom overrode the wall probe.

Added
- Wall assist in `TpsCamera`: when the boom behind Henry lacks ~0.9 m, it
  searches angles along the wall (up to 90°) and a little above (up to 30°),
  judging each by where the camera would really sit (shoulder shift and wall
  clearance included), and glides there; it glides back once the mouse angle
  has room. It keeps the side it chose so it does not flip.
- The camera goal is cleared of walls before the follow, and the post-contact
  restore is faster (5.0), so a sweep along a wall does not leave the camera
  hugging the head. As a last resort only, the main camera stops drawing the
  body when closer than 0.3 m to the eyes (the HUD portrait is unaffected).
- `test_tps_camera_orbit.gd`: back to a wall, a full 360° mouse sweep never
  enters the wall, never settles closer than 0.55 m and never hides Henry.

### 2026-09-23 — Camera in tight spaces; the backpack is an item

Changed
- `TpsCamera`: the shoulder offset shrinks with the boom (to 20% in the
  tightest space), a side sphere cast keeps the shoulder/lean shift out of a
  wall beside Henry, the near boom is 0.95 m and closing in is softer (2.5).

Added
- `backpack` item: a garment for the `pack` slot with a BULKY main
  compartment and a lid pocket, worn from the start. `GarmentData.mesh_node_name`
  now drives the body: the pack box shows only while the backpack is worn.

Fixed
- Interaction and camera tests stepped on idle frames and could miss physics
  ticks under load; they now step on physics frames.

### 2026-09-23 — Cursor ring carries stamina again

Fixed
- The ADT ring port had dropped this project's movement dot, stamina-coloured
  sprint arcs and jump-charge arc; they are back around the centre ring.

### 2026-09-23 — Interaction ported from ADT; cursor ring back

Added
- `InteractComponent` (ADT): a focus cast ahead, then a 2.5 m / 240° intent
  cone pick the target; F acts within 0.9 m, otherwise Henry walks over and
  acts on arrival (WASD cancels). Replaces `InteractionManager`.
- `Player.move_to_position()` / `stop_moving()` / `movement_stopped`.
- ADT's dynamic cursor ring at screen centre, brightening over interactables.
- Refusals are said on the object: no boards, no firewood/tinder, too heavy.

Changed
- `InteractiveArea` visuals are driven by the component: marker when targeted
  far, prompt and ground ring within 2 m. `can_interact()` now means only
  "offers itself"; the stove stays targetable while it can take fuel.
- Prompt text is localised and shows the bound key.

### 2026-09-23 — TPS camera: the rest of ADT's framing; ADT key layout

Added
- Over-the-shoulder framing from ADT: 0.85 m shoulder offset split 60/40
  between lens shift and camera move, Z swaps shoulders (`TpsShoulderState`).
- Q/E lean of the camera, breathing sway on pitch, ADT lead smoothing and
  start pitch. Pivot and probes use ADT body ratios from the feet, not the
  capsule centre (the old pivot sat a metre too high).

Changed
- Keys follow ADT: interact F, lean Q/E, shoulder Z; flashlight moved to L;
  unused `use_ability_henry` action removed.

### 2026-09-23 — Grey UAL mannequin, backpack placeholder, fonts, menu pointer

Changed
- Player visual is the Quaternius UAL mannequin from `UAL1_Standard.glb`,
  painted flat grey; UAL2 clips are added as library `UAL2`. The Henry glbs
  (`henry_ual`, `henry_test_model`) and their hidden nodes are removed.
- A box on `spine_03` stands in for the backpack.

Added
- CGF Locust Resistance font from ADT with its licence note; font table in
  `docs/THIRD_PARTY_NOTICES.md`. BlackRock stays ADT-only.

Fixed
- Quitting to the title left the mouse captured: releasing look capture now
  always shows the pointer, and the title menu releases it on open.

### 2026-09-23 — Debugger warnings cleaned

Changed
- Triple-quoted "docstrings" in `BioMonitorManager` and `vital_signs.gd`
  (standalone-expression warnings) became `##` doc comments in English.
- Unused parameters prefixed with `_`; `load_profiles_from` no longer shadows
  the `profiles` export; dead `shake_intensity` local removed.

### 2026-09-23 — Picked-up items no longer crash the interaction scan

Fixed
- `InteractionManager` kept a freed pickup in `detected_areas` and errored
  every physics frame after a pickup; freed areas are now dropped first.

### 2026-09-23 — TPS camera replaces the cursor camera; pickups fixed

Added
- `TpsCamera` (`scripts/systems/camera/tps_camera.gd`), ported from ADT's
  on-foot camera without view toggle, lock-on, aim or lean: captured mouse
  look, follow smoothing, sprint pull-back, movement lead, sphere-cast wall
  clamp. New: eight rods plus a ceiling ray judge how open the space is and
  ease the boom between 1.2 m (doorways, rooms) and 3 m (open ground).
- `InputSystems.get_look_delta()` / `set_look_capture()`; pause frees the mouse.

Changed
- Movement is camera-relative and Henry turns to face where he walks.
  `RotationController` and `MouseCursorUI` are removed from the player scene
  (files kept for reference). `PlayerCamera.gd` deleted; the scene is now
  `tps_camera.tscn` (node name `PlayerCamera` kept for `World`).

Fixed
- Interact (E) never reached placeholder pickups, board-up or stove feed: the
  shape cast hit the `InteractiveArea` itself, which was not counted.

### 2026-09-23 — #24: existing systems start costing each other

Added
- `IceField` save contract (key `ice`, group `saveable`): holes survive
  sleep-save; loading never emits `tile_broke`.
- Carry weight has a cost: `IceGaitBinder` scales ice drain by pack load,
  `BioMonitorManager` raises fatigue above half load.
  `InventoryComponent.get_load_fraction()` / `find_in()` are shared hooks.
- `ThermalManager` dries clothes by felt temperature (0 °C none, 25 °C full)
  anywhere out of precipitation.

Changed
- `VERTICAL_SLICE.md` now describes the route experience; stale pillar table removed.

### 2026-09-23 (15) — Snow A+: rime from edges, settled snow as state, prints on slopes

From the author's review and the Grok and Codex reviews in #16.

Changed
- **Rime grows from edges, corners and the cold base of an object**, not as
  uniform noise across a face. The author called the old spread amateurish, and
  it was. `frost_weight()` takes an edge factor; as `frost_amount` rises the
  front moves inward, and noise only breaks up that front. Real assets bake an
  `edge_mask`; placeholder boxes set `box_half_extents` / `box_center_offset`
  for the **whole surface**, so seams between pieces of one wall do not read as
  edges.
- **Settled snow is world state, not a weather mirror.** `snow_cover` used to
  jump to the active profile's level; a blizzard's 1.0 fell to calm's 0.35 the
  moment it stopped. It now builds with snowfall, settles slowly (about a day
  from blizzard to calm), melts above 0 °C, and is saved under `snow`.
- **Rime grows and sheds over hours** instead of snapping across a threshold.
- **`foot_planted` carries the ground normal**, and prints lie along it: on a
  slope a print sits on the slope instead of hovering flat above it or cutting
  into it. Heel-to-toe runs along the ground.

Added
- A test that fails if anything but `SnowPresentationSystem` writes the snow
  globals.
- `SNOW_COVER.md`: the settled-snow model, rime from edges, quality tiers, a
  material checklist for the slice, and why decals are the low tier rather than
  persistence.
- `THIRD_PARTY_NOTICES.md`: the ADT foot-print asset, alongside the code port.

### 2026-09-23 (14) — Pickups you can see, prompts that highlight

Fixed
- Every pickup and shelter prompt from #17 logged "interactive_mesh не
  назначен". Not only noise: `InteractiveArea` sizes its highlight ring from
  that mesh, so none of them highlighted, and pickups had no body in the world
  at all — only a floating icon.
  - `ItemPickup` builds a small placeholder crate until items have meshes.
  - `BreachBoardUp` rings under the breach's boards; `HeatSourceFeed` under the
	stove's body.
  - The base class is untouched; each subclass supplies its mesh before
	`super()._ready()`.

### 2026-09-23 (13) — Snow step 3: foot contact and footprints

Added
- **`FootContactSensor`** on `player.tscn` reads Henry's animated `foot_*`,
  `ball_*` and `ball_leaf_*` bones and emits `foot_planted(side, point, forward,
  speed)` each time a foot lands: the ball of the foot within 6 cm of the ground
  after lifting past 9 cm, on the floor, moving. The ground is found by a short
  ray, so any surface works. The shared source for footprints, and later for
  footstep audio and ice load.
- **`FootprintSystem`** in the composition root stamps pooled decals: the left
  or right print cropped from the ADT stamp, toe along heel→toe, tinted as
  compressed snow. Snowfall buries them — 240 s calm, 25 s in a whiteout. No
  geometry is deformed; terrain stays untouched.
- `assets/textures/snow/footprint_left.png` / `_right.png`.

Found
- Henry's walk clip plants a foot every 1.3–2.7 m at 4 m/s, so he glides. That
  is a locomotion blend matter in `HenryUALAnimation`, documented in
  `SNOW_COVER.md`, not patched here.

Tests
- `tests/systems/test_footprints.gd`: one print per stride; none standing still
  or in the air; the real rig has every bone; the toe points where the foot
  points; each foot leaves its own print; a full pool reuses the oldest; a
  blizzard buries a trail a calm minute keeps.

### 2026-09-23 (12) — Snow step 2: the shared snow and rime surface

Added
- `shaders/environment/snow/snow_surface.gdshaderinc` — the terrain-agnostic
  response any spatial material includes. Settled snow on up-facing surfaces,
  reaching steeper slopes as `snow_cover` rises; rime on steep and vertical
  faces, patchy, grown by `frost_amount`. Edges are broken up with cheap
  world-space value noise, so no texture is required.
- `shaders/environment/snow/snow_prop.gdshader` — a plain base (colour,
  texture, roughness, metallic) with snow and rime on top, for placeholder
  geometry now; real assets include the `.gdshaderinc` in their own material.
- The test shelter's walls and roof use it, so `TestScene` shows the weather.

Fixed along the way
- Rime first came out as vertical stripes: world XZ noise only varies along one
  axis on a wall. Frost now samples noise in the wall's own plane.

Tests
- `test_shelter_scene.gd` checks the shelter carries the snow shader.

### 2026-09-23 (11) — Snow step 1: the weather → shader contract

Issue #16, Phase A, reassigned to `claudeflow` by the author. Terrain3D is a
placeholder, so the snow layer is terrain-agnostic from the start.

Added
- `WeatherProfile.snow_cover` (calm 0.35 → blizzard 1.0), blended by
  `WeatherController` like every other field; `get_snow_cover()`.
- `ThermalManager.get_outdoor_air_c()` — the air outside, before wind, shelter
  or fires, which is what frost on the world responds to.
- **`SnowPresentationSystem`**, one more line in the composition root and the
  only writer of the `snow_cover` and `frost_amount` shader globals. Writes on
  change only, never reads back.
- `[shader_globals]` declared in `project.godot`.
- `docs/technical/SNOW_COVER.md` — names, ranges, the one-writer rule.

Tests
- `tests/systems/test_snow_presentation.gd`: every profile has sane cover and a
  blizzard beats calm; cover follows a profile switch; frost is zero above
  freezing, partial at −14 °C, full in deep cold; both globals are declared;
  the composition root builds the system.

Fixed
- `test_streaming.gd` failed once in a full run and passed alone. Chunks load
  on a worker thread and the test pumped 200–400 times back to back with no
  wall time, so on a busy machine it could finish before the thread did.
  `_settle()` now pumps with real time between calls, up to a deadline, and
  stops once the states stop changing. Verified green under CPU load.

### 2026-09-23 (10) — A test shelter: the whole loop by hand in TestScene

Every slice system was in `main`, yet no scene let anyone play the loop.

Added
- `scenes/environment/shelter/test_shelter.tscn` — placeholder-box shelter:
  a west window facing into the blizzard (a `ShelterBreach` with a board-up
  prompt), a door in the lee, a `ThermalZone` interior, and a stove that starts
  cold with a feed prompt and a flame light.
- **`ItemPickup`**, the third `InteractiveArea` subclass. No pickup in the game
  put anything into the pack before; firewood and boards could not be had.
  All or nothing: a stack too heavy for the pack stays on the ground.
- `HeatSource.flame_light` and `ShelterBreach.boarded_visual`, so a lit stove
  and a boarded window read at a glance and on a render.
- `World.streaming_enabled`. Off in a scene that brings its own floor, so the
  island's chunks do not stream on top of it.
- Interaction prompts on the new interactables go through localisation.

Changed
- **`TestScene` is now a `World`** (streaming off), with the shelter at
  (0, 0, 14) and firewood ×2, tinder, boards and a tin on the path to it. The
  cold, sleep, save, pause and weather all run there now.

Tests
- `tests/systems/test_shelter_scene.gd` loads the real scene and checks its
  wiring, not the classes alone: prompts find their breach and stove, the
  window faces the blizzard, boarding and lighting spend real items and flip
  the visuals, pickups go into the pack or refuse. It caught the window facing
  downwind on the first draft.
- `test_world_composition.gd`: streaming off means no chunks.

### 2026-09-23 (9) — Minimal shell: title, Continue, pause

The last non-content item on #7's must-have list: title → New / Continue →
Quit, and a pause with Resume / Quit to title.

Added
- `scenes/ui/menu/title_menu.tscn` — New game, Continue from last sleep
  (disabled with a note when no sleep is saved), Quit. Bare on purpose; how it
  looks is the author's call.
- `scenes/ui/menu/pause_menu.tscn`, one more line in `WORLD_UI_SCENES`. Esc
  pauses through `PlayerState`. No save here: the game saves only when Henry
  sleeps, and the pause menu says so.
- `localization/strings.csv` (English + Russian), registered in
  `project.godot`. The project had **no translation table at all** — every
  refusal key (`SLEEP_REFUSED_TOO_COLD` and the rest) would have shown raw.

Fixed — Continue would have been a lie
- A sleep save held weather, body temperature and shelter state, and nothing
  else. **Time of day, where Henry lay down, hunger/thirst/energy and the pack
  were not saved.** Loading would have put him at the spawn marker at dawn,
  fed and empty-handed.
  - `SessionState` (composition root): game clock and player position; resets
	the thermal and weather hour trackers so a loaded clock jump is not billed
	as time spent in the cold.
  - `BioMonitorManager` implements the save contract.
  - `SaveManager` adopts contract implementers inside the player, so inventory
	and equipment are saved at last.
- `SaveManager.pending_load_slot` carries Continue from the title scene into
  the world; applied deferred, after every system adopted its scene state.

Not changed
- `run/main_scene` is still `TestScene`, per the author's convention. Point it
  at `res://scenes/ui/menu/title_menu.tscn` when the slice should boot to the
  title.

Tests
- `tests/systems/test_shell.gd`: a save round trip restores clock, position,
  hunger and pack; the pending load lands on the next frame, not before; Esc
  pauses and resumes; Esc does not stack a pause over the sleep dialog.

### 2026-09-23 (8) — Ice retune: sprinting the bay is a real gamble

Author's decision in issue #7: thinner ice and a heavier sprint, no crouch.

Fixed
- **Sprinting was never riskier than walking.** Sprint moves twice as fast and
  had exactly twice the load multiplier, so both put the same load on every
  metre of ice. `sprint_multiplier` 3.2 → 8.0.
- **Mid-bay ice could not break at all.** At 0.18 it was thicker than a sprint
  drains from one tile. Bay profile: `solid_until_m` 12 → 8,
  `thinnest_from_m` 90 → 26, `minimum_thickness` 0.18 → 0.11,
  `drain_per_second` 0.055 → 0.0375 (so walking keeps a margin).
- **Thin ice sat cracked before anyone stepped on it.** The creak/crack ladder
  compared absolute integrity, so 0.11 ice started below the crack threshold and
  the warning that must come first never sounded. Stages are now a share of the
  tile's own natural thickness.
- `capture_ice_map.gd` simulated a 5.5 m/s sprint; the controller runs at 8.

Tests
- `test_ice_field.gd` crosses the bay at both gaits: a sprint breaks through
  mid-bay (more than 20 m in), a walk does not.

### 2026-09-23 (7) — Phase B step 3: a fire you have to light and feed

`HeatSource.refuel()` had no caller anywhere — the same shape `add_calories`
had before Phase A. Fuel did burn on the game clock, and `burn_duration_h` is
deliberately shorter than a night, so every fire went out and nothing the
player did could stop it. The sleep prompt already warned about it; now the
warning has an answer.

Added
- Items `firewood` (bulky, heavy — carrying it should cost space) and `tinder`
  (spent only to start a dead fire).
- **`HeatSourceFeed`** — the second `InteractiveArea` subclass that does
  something. A dead fire costs tinder and wood; a burning one costs wood. A full
  fire refuses, and nothing is spent on any refusal.
- `HeatSource.can_refuel()` and `restore_fuel(hours, burning)` — the second for
  saves only; gameplay goes through the capped `refuel()`.
- **`ShelterState` remembers fires** next to boards, so sleeping beside a
  half-burnt stove does not wake up to a full one. Fires are found under their
  zone in the scene; no new system.

Not done, deliberately
- A placeable stove. Free placement is a new system, and #7's scope lock says
  no new systems. An authored stove that starts unlit gives the same verb.

Tests
- `tests/systems/test_fire.gd`: tinder only for a dead fire, a full fire spends
  nothing, feeding carries a fire past its own burn duration, a dead fire stops
  warming the room, and fuel survives a save round trip at the exact level.

### 2026-09-23 (6) — Phase B step 2: a shelter you have to prepare

A shelter was a flat safe zone: step inside and the wind stopped, and a fire
warmed a holed ruin exactly as well as a sealed cabin. This is the mechanism
behind the core verb in issue #4 — preparing shelter rather than finding it —
and the one item on #7's must-have list that is not content.

Added
- **Wind has a direction.** `WeatherProfile.wind_direction_deg` plus a jitter
  angle, and `WeatherController.get_wind_direction()`. Bearings blend as
  vectors, so crossing 0/360 turns the short way instead of sweeping back
  through every intermediate quarter; the wander is sampled from the gust noise
  at an offset, so direction and speed are not the same number twice.
- **`ShelterBreach`** — a hole in a shelter, child of the `ThermalZone` it lets
  the weather into. Severity, a facing taken from the node's own basis (the
  author turns it in the editor; nobody fills in a vector), and
  `board_up()` / `tear_open()`.
- **`ThermalZone` derives its protection from its breaches.** `wind_exposure`
  is now the base leak of a sealed shelter, not the final number.
  `get_wind_exposure(wind_direction)` adds each unboarded hole weighted by how
  squarely it faces the wind — a hole in the lee costs almost nothing, the same
  hole turned windward costs its full severity.
- **A fire cannot heat a hole.** `get_sealed_fraction()` scales
  `max_heated_offset_c`, so a holed room never reaches a useful temperature
  however long it burns, and tearing boards off mid-night drops the warmth
  already stored. That is what makes boarding up worth the trouble.
- **`ShelterState`** — a composition-root system remembering which breaches are
  boarded, keyed by zone and breach name. Shelters live in streamed chunks, so
  the state cannot live in the zone.
- **`BreachBoardUp`** — the first `InteractiveArea` subclass in the project that
  does anything. Spends one `boards` item and closes the hole; refuses rather
  than boarding for free.

Fixed
- **Confirming sleep also triggered whatever you were standing next to.**
  `InteractionManager._input()` read `"interact"` raw, bypassing `InputSystems`,
  and the sleep dialog confirms with the same key. The prompt now claims the key
  while it is open and the manager honours the claim — which is what the claim
  contract was ported from ADT for.
- `test_world_composition.gd`'s new check was aborting on a null `world.player`
  before asserting anything, so the suite passed without running it. The player
  export is only resolved by `initialize()`; the scene node is the handle that
  early.
- `vital_signs.gd` connected the thermal signals twice when the scene had
  already wired a manager.

Tests
- `tests/systems/test_shelter.gd`: a breachless zone behaves exactly as before,
  a windward hole costs more than the same hole in the lee, boarding restores
  the base leak, a fire cannot pass a holed room's ceiling, boards cost an item,
  the state survives a save round trip, and a night in a holed shelter ends
  colder than the same night sealed.
- Thirteen suites green. `TestScene` and the island both render with no warnings
  from the survival systems.

Known, not mine
- `test_ice_field.gd` prints a duplicate `tile_broke` connection error. It
  predates this branch's changes; left alone rather than widened into here.

### 2026-09-23 (5) — Phase B step 1: the cold actually runs

The thermal stack was built, tested and driven by nothing. It is in the
composition root now, which means the survival simulation runs in the game
rather than only in the suites.

Added
- `ThermalManager` and `SleepController` are two more lines in
  `WORLD_SYSTEM_SCRIPTS`, as the composition root promised. Both implement
  `on_world_ready(context)` and find what they need — clock, weather, equipment,
  biomonitor, save manager — so no scene wires them by hand.
- `ThermalManager` rides with the player and builds its own `ZoneProbe` when
  the scene supplies none. Without a probe no shelter ever counted, so sleep
  would have refused everywhere.
- `WorldContext.find_in_scene()` — one scene-tree search shared by every
  system, searching the world root first. A headless harness that adds a scene
  to the SceneTree root leaves `current_scene` null, which the bespoke search in
  `WeatherController` could not survive; that copy is deleted.
- `_notify` now offers the hook to a node **and its subtree**, so a HUD
  indicator inside `player.tscn` can ask for what it needs. `vital_signs.gd` and
  `sleep_prompt.gd` use it: the thermometer and the S-hold dialog find the live
  systems themselves.

Fixed
- **The starting weather profile was never activated.** `WeatherController._ready()`
  ran `initialize()` before the world handed over clock and profiles; it returned
  early at the empty-profiles check, and the later call no-opped on the
  `_gust_noise` guard. `initialize()` is now idempotent *per concern* rather than
  gated by one boolean, in both `WeatherController` and `ThermalManager`.
- Same class of bug in `ThermalManager`: the clock was never connected, so body
  temperature never ticked in a real scene.
- Awaiting `process_frame` to defer past `_ready` does not work here — a
  coroutine resumed by that signal and a node connecting to it during the same
  emission both run in one pass. Both systems are structurally correct instead.

Tests
- `test_world_composition.gd` gains the check that would have caught all of
  this: both systems present, each reference resolved, a probe built, and the
  thermal model following the player rather than sitting at the origin.
- Twelve suites green. `TestScene` and the island both render with **no warnings
  from the survival systems at all**, which has not been true before.

### 2026-09-23 (4) — Phase A step 3: the survival loop closes

Closes issue #6. The two ends of the loop that were stubs now meet.

Added
- `BioMonitorManager.rest_sleep()` is no longer a `pass`. A night restores
  energy, charges its own metabolism (the clock jump skips the hourly tick),
  and rests worse on an empty stomach — `get_rest_quality()` takes the worse of
  hunger and thirst and never drops below a floor.
- `ConsumptionController` — eating reaches the body at last. Finds the item in
  the inventory or in a garment pocket, spends one, pushes calories, hydration
  and energy onto the biomonitor, charges `body_heat_cost_c` to the thermal
  model, and puts whatever is left behind back where it fits.
- Items `empty_tin` and `snow_handful`. Snow is water bought with body heat,
  which is the first content that exercises the heat cost.
- `EquipmentComponent`, `InventoryComponent` and `ConsumptionController` are
  now nodes on `player.tscn`, wired to the existing `BioMonitorManager`, so the
  loop runs in game and not only in tests.

Tests
- `tests/systems/test_survival_loop.gd` — eight checks: sleep restores, sleep
  costs, a starved night restores less, eating from the inventory and from a
  pocket, the empty tin, snow costing heat, and the four refusals.
- Eleven suites green; `TestScene` renders with no new errors.

Not done here
- `ThermalManager` and `SleepController` are still not in the composition root,
  so nothing yet drives them at runtime. That is the head of Phase B.

### 2026-09-23 (3) — Phase A step 2: items, equipment, inventory, and clothing that matters

Ported from ADT with permission; the full record of what crossed over, what was
dropped and what was added is in `docs/technical/PORTED_FROM_ADT.md`.

Added
- `core/items/` — `ItemTraits`, `GarmentData`, `ItemResource`, `ConsumableData`,
  `ItemCatalog`. Items are Resources authored as `.tres` now, not an inner class
  that could never be edited. The catalog loads **by path, never by scanning**:
  an exported build hides `.tres` behind a `.remap` and a `DirAccess` scan finds
  nothing.
- `core/equipment/` — `EquipmentSlotDefinition`, `EquipmentLayout`.
- `scripts/actors/player/henry/components/equipment_component.gd` — body slots
  are fixed by a layout resource, **pockets are brought by the garment**. Take
  the coat off and its pockets, and their contents, go with it. `equip()` into an
  occupied slot refuses rather than swapping; `unequip()` refuses while the
  garment's own pockets hold anything.
- `.../inventory_component.gd` — loose carry, gated by weight.
- `data/items/` and `data/equipment/player_layout.tres` — a worn coat, knit hat,
  work trousers, worn boots and a tin of stew; slots `head`, `torso`, `legs`,
  `feet`, `pack` and `back_fixture` (Kenny's, excluded from auto-stow).
- `tests/systems/test_equipment.gd`.

**The point of the exercise**
- `GarmentData.insulation_c` and `EquipmentComponent.get_total_insulation_c()`
  — the axis ADT's garments do not have. `ThermalManager` now reads what Henry
  is actually wearing, falling back to its exported constant when no equipment
  is wired, so every earlier test kept passing untouched. Fully dressed is about
  11 °C against the old flat 6 °C, and a test asserts a dressed Henry cools
  measurably slower than a bare one and that removing the coat is felt at once.

Removed
- `InventoryManager.gd` and its node in `player.tscn`. It was never wired
  (`setup()` had no callers), `Item` was an inner class that could not be
  authored, `_create_item_by_id()` returned null so loading restored nothing,
  and `_input()` read raw keycodes including `KEY_E`, colliding with `interact`.

Verified
- Ten suites pass; `TestScene` and the island both render after the removal;
  the filename gate is clean.

### 2026-09-23 (2) — Phase A step 1: player state and the interact claim

Both ported from ADT with permission; see `docs/THIRD_PARTY_NOTICES.md`.

Added
- `core/player_state/player_state.gd` — autoload, the single source of truth for
  what the player is doing: `ON_FOOT`, `WORKING`, `SWIMMING`, `SLEEPING`, `MENU`.
  **`MENU` is reachable only through `open_menu()`/`close_menu()`**; `set_mode(MENU)`
  push_errors, and so does any mode change while a menu is open, so pause and
  mode can never diverge. Pause is set **before** the signal fires, so every
  listener sees a consistent tree. A menu opened while swimming returns to
  swimming.
- The **interact claim** in `InputSystems`. While a claim is held the key
  belongs entirely to the claimant and `interact_pressed/held/released` stay
  silent — one owner decides what the key means instead of subscribers racing.
  The claimant duck-types `on_interact_claimed()` plus optional
  `on_interact_held(duration)` / `on_interact_released(duration)`. This is what
  Phase B's "hold to seal a breach" will use.
- `tests/systems/test_player_state.gd` — the pause coupling, mode restoration,
  movement blocking, and the claim taking and returning the key.

Changed
- `InputSystems` now gates on `PlayerState`: `get_move_axis()` returns zero and
  `is_sprinting()` returns false whenever the mode holds the player still, so
  no caller has to check. Gameplay edges are suppressed in `MENU`, except the
  cancel key, which must still reach the menu that is open.
- `SleepPrompt` no longer sets `get_tree().paused` itself — it calls
  `PlayerState.open_menu()`/`close_menu()`. Pause has one owner now.

Notes
- `_tick_interact()` level-polls `Input` as a safety net: if the release event
  never arrives (a Control ate it, focus was lost, the claimant was freed) the
  key would otherwise read as held forever. The test presses the key for real
  rather than working around that net.

Verified
- Nine suites pass; `TestScene` renders; the filename gate is clean.

### 2026-09-23 (1) — The project's own licence

Fixed
- **`/LICENSE` was an unrelated third party's MIT** — `Copyright (c) 2023
  mohsenph69`, the author of the Godot-MTerrain addon. It arrived in commit
  `5496269` alongside terrain experiments and was never replaced, so the whole
  game was formally published under MIT, granting everyone the right to copy,
  modify, sublicense and sell it, attributed to someone unconnected to the
  project. Not Terrain3D's licence either — that one ships separately at
  `addons/terrain_3d/LICENSE.txt`. Replaced with the project's own terms,
  modelled on ADT's. See issue #5.

Added
- `docs/THIRD_PARTY_NOTICES.md` now records the licensing history, so the change
  is explained rather than silently rewritten, and the author's permission to
  port code from `Nolavel/ADT` (whose licence requires written permission from
  the copyright holder, who owns both projects and granted it).


### 2026-09-22 (12) — Fix CI: the environment, not the code

The first CI run on PR #2 went red. Every cause was in the harness I wrote.

Fixed
- `setup_env.sh` was invoked as `sudo -E`, so the **whole** script ran as root
  and created `$HOME/.local` root-owned. Every later unprivileged step then
  failed to write `user://`, which is why the save tests could not create a
  slot. Root is needed for apt and nothing else, so the script now asks for it
  itself and the workflow calls it unprivileged.
- The artifact step ran `find` over a directory that does not exist when no
  render was produced, and `bash -e` turned that into a failed job even under
  `if: always()`. It tolerates a missing directory now.
- `HeatSource.get_offset_at()` read `global_position` without checking
  `is_inside_tree()`, flooding the log with engine errors on every headless
  temperature calculation. Guarded.
- Two suites dereferenced a null `FileAccess` when `user://` was unwritable, so
  a broken environment surfaced as a crash instead of a reason. They now report
  what could not be written and why.

Changed
- **All eight suites now run from the first frame** rather than `_initialize()`.
  Three of them had been relying on a node outside the tree returning a zero
  transform that happened to equal the origin — luck, not correctness. This is
  the same Godot trap recorded in `WORLD_ARCHITECTURE.md` §8, and it is now
  handled consistently everywhere. The engine-error flood in the logs is gone
  with it (from hundreds of lines to zero).

Verified
- Eight suites pass, `TestScene` renders, the workflow's step list is intact.


### 2026-09-22 (11) — ASCII filenames and the orphaned uid

Closes §3.10 of the commercial assessment.

Renamed
- `scenes/game/Сhunks/` → `scenes/game/chunks/` — the old directory began with
  **U+0421 CYRILLIC CAPITAL ES**, visually identical to a Latin `C` and quietly
  fatal to every grep, glob, path comparison and export filter written against
  it. Nine chunk scenes moved.
- `Warning sign101х86.png` / `Warning sign60х51.png` → `warning_sign_101x86.png`
  / `warning_sign_60x51.png`. Those `х` were Cyrillic too.
- The island scene's own node names with them: `FM_Сhunks` → `FM_Chunks`,
  `Сhunk_*` → `Chunk_*`.

Removed
- `scripts/systems/world/Debug_Accelerator.gd.uid`, orphaned when the script was
  renamed to `debug_accelerator.gd`. It kept handing out `uid://cjj38qmk6jo8p`,
  which `WorldEnvironmentSystem.tscn` still referenced — the scene loaded by
  text path with a warning on every boot. The scene now points at the real
  `uid://dgvkrwulefgho` and the warning is gone.

Added
- `tools/ci/check_filenames.sh`, wired into CI ahead of the tests: fails the
  build on any non-ASCII tracked path and on any `.uid` whose script is gone.
  Neither problem can come back silently.

Verified
- Eight suites pass; `data/world_data.tres` regenerated from the normalised
  scene (9 chunks, every content scene resolved); both the island and
  `TestScene` render; the gate reports clean.


### 2026-09-22 (10) — Data-driven streaming

Closes the last item `AGENTS.md` had against this project: chunk definitions
are data now, not code.

Added
- `core/world/resources/chunk_data.gd` and `world_data.gd` — mirroring ADT's
  `BlockData`/`WorldData`: id, display name, location, position, radius and the
  two ring scene paths.
- `tools/world/generate_world_data.gd` — **generates** `data/world_data.tres`
  from the authored island scene. Position comes from each `Area3D`, radius is
  measured from its `CollisionPolygon3D`, the display name from its `Label3D`,
  and content scenes are matched by naming convention rather than a table. Nine
  chunks came out with every content scene resolved and nothing re-authored by
  hand. It matches both spellings of `Chunk_`, so the Cyrillic homoglyph in the
  authored names is handled rather than tripped over.
- `core/world/streaming_system.gd` — the pipeline, reading the resource and
  nothing else. **No per-chunk variable and no per-chunk `match` arm exists in
  the file.** ADT's cell machine (`UNLOADED → QUEUED → LOADING → READY →
  ACTIVE`, with rollback), ADT's budgets (2 concurrent loads, 1 instantiation
  per frame), and its non-optional `_packed_cache`.
- `tests/systems/test_streaming.gd` — generated data, approach and activation,
  hysteresis, the instantiation budget, rollback, and reset.

Removed
- `experimental_location/scripts/WorldStreamManager.gd` (558 lines), replaced
  rather than patched. `CHUNK_DEFINITIONS` and `LOCATION_AREAS` go with it; the
  authored `Area3D` markers stay as the generator's source of truth.

Fixed (found by the new tests)
- A chunk whose background load landed **after** the player had walked away was
  still instantiated, because the pump activated anything `READY` without
  re-checking distance. Both the poll and the activation now re-check the band,
  and the packed scene stays cached for the next approach.

Deliberate difference from ADT
- The load band is **per chunk** — its own authored radius plus a margin — not
  one flat radius. Our chunks range from 190 m to 312 m across, so a single
  number would either thrash the small ones or load the big ones far too late.
- `StreamingSystem` is not an autoload. It has one owner and one lifetime, which
  is what `WORLD_SYSTEM_SCRIPTS` is for.

Open
- Ring 0 is built but empty: no silhouette scenes exist yet, so
  `silhouette_scene_path` is blank on every chunk. The island's terrain is the
  floor in the meantime, as in ADT after its own island move.

Verified
- Eight suites pass. The island boots through the composition root with the
  pipeline live (`[World] initialized with 3 systems`) and renders.


### 2026-09-22 (9) — Composition root, WorldContext and InputSystems, from ADT

Read `Nolavel/ADT` and ported its architectural spine. Details and the full
list of what was and was not taken: `docs/technical/WORLD_ARCHITECTURE.md`.

Added
- `world/world.gd` — the composition root. Three declarative lists
  (`WORLD_SYSTEM_SCRIPTS`, `WORLD_3D_ENTITY_SCENES`, `WORLD_UI_SCENES`) say what
  exists; the loops that build them are fixed, so **the file does not grow as
  systems are added**. Adding anything is one line.
- `core/world/world_context.gd` — `WorldContext`, the "almost DI": player,
  camera, stream container and the live systems, with `get_system(Class)`.
  Systems stop being hand-wired through `@export` NodePaths in the scene.
- `on_world_ready(context)` — duck-typed lifecycle hook, checked by
  `has_method()`. `SaveManager` adopts the systems list through it;
  `WeatherController` finds the day/night clock and loads its profiles.
- `core/input/input_systems.gd` — first autoload in this project, and the only
  file that reads `Input`. Edges come from events, levels come from polls, and
  `Input.is_action_just_pressed()` is banned outright.
- `tests/systems/test_world_composition.gd`.

Changed
- The island scene now carries `world.gd`, has a `StreamContainer`, and its root
  is `World`. `GameRouter.gd`'s one job — move the player to the marker and free
  it — is `_place_player()`.
- **Save contract converged on ADT's**, since two codebases by the same author
  should not disagree: `save_id()` → `get_save_key()`; partial implementations
  are now skipped all-or-nothing; and an unrecognised save version is **refused
  outright** rather than passed through with a warning. A half-applied save from
  a future build is worse than a refused one.

Fixed
- `WeatherController` dereferenced `get_tree()` without checking it, which is
  null outside the tree.

Recorded, not done
- By ADT's naming rule, `BioMonitorManager`, `StaminaManager`,
  `InventoryManager` and `ThermalManager` are all **Components** — attached to
  one owner, owning no collection. Renaming touches scenes as well as scripts,
  so it is written down rather than half-applied.
- The streaming port is specified in `WORLD_ARCHITECTURE.md` §6 as four concrete
  steps. `CHUNK_DEFINITIONS` being a hardcoded dictionary is the gap
  `AGENTS.md` already names; the generator and the rewrite land together or not
  at all.

Verified
- Seven suites pass; the island boots through the composition root and renders
  (`[World] initialized with 2 systems`).


### 2026-09-22 (8) — Gait wired to the ice

Added
- `scripts/systems/ice/ice_gait_binder.gd` — reads `MovementController` and the
  body's horizontal velocity and pushes the resulting gait into `IceField`, so
  sprinting across the bay now costs 3.2x what standing still does. Written as
  an adapter: `MovementController` is not edited and stays in nobody's way.
- Tests: gait classification (still / walk / sprint), that vertical velocity is
  not mistaken for movement, and that a sprint through the binder loads the ice
  harder than a walk.

Finding
- **The project has no crouch.** No input action, no controller state. The
  profile's 0.45 crouch multiplier is therefore unreachable, and the careful way
  across the ice does not exist — the player's only options today are walk or
  gamble. `IceGaitBinder` reports `CROUCH` only when someone binds
  `crouch_action`, and a test asserts it is never reported until then, so this
  cannot be forgotten silently.

Verified
- All six suites pass; `TestScene` still renders.


### 2026-09-22 (7) — The frozen sea

Added
- `scripts/systems/ice/ice_profile.gd` — all ice tuning as a Resource.
- `scripts/systems/ice/ice_field.gd` — the frozen sea. Sparse tile grid,
  thickness from distance to the island outline, gait-scaled load, recovery,
  and the creak → crack → break ladder.
- `scripts/systems/ice/cold_water_immersion.gd` — falling through soaks the
  player, drains body heat on the game clock, and refuses to let them climb out
  until they have thrashed. The trap is a story beat, not a reload.
- `ThermalManager.apply_body_temperature_delta()` — public seam for events the
  ambient model does not cover.
- `resources/ice/bay_ice.tres`, `tests/systems/test_ice_field.gd`,
  `tools/runtime/capture_ice_map.gd`, `docs/technical/ICE_SYSTEM.md`.

Guarantees the tests hold
- **Audio lands before visuals**: the first stage emitted walking a tile down is
  `CREAKING`, never `CRACKING`. The player always gets a warning they can act on
  before one they can only react to.
- **Cost is constant**: the active window stays 5×5 whether the player is 60 m
  or 4 km offshore.
- A tile breaks exactly once and stays broken; abandoned tiles recover but never
  past their natural thickness.

Level-design finding
- The map tool reports that on the illustrative bay the shortcut saves 54 % of
  the distance but **a sprinted crossing survives** — thinnest ice on the route
  is 0.74. The shortcut is free, so the ice mechanic would never fire. This is
  the risk `VERTICAL_SLICE.md` §4 predicted, now measured. Two levers are
  documented in `ICE_SYSTEM.md` §7; both are design decisions, not code ones.

Note
- GDScript lambdas capture local primitives **by value**, so a counter
  incremented inside a signal handler lambda silently stays zero. Cost one
  debugging round; the test now uses a reference type.


### 2026-09-22 (6) — Campfire fuel and the hold-to-sleep UI

Added
- `HeatSource` fuel now actually burns: `advance_all_fuel()` is ticked by
  `ThermalManager` on the game clock, `refuel()` feeds and relights a fire, and
  `heats_zone` links a source to its room so a fire going out stops heating it
  with no scene wiring. Default burn is six hours — deliberately less than a
  full night.
- `scripts/ui/hud/sleep_prompt.gd` + `scenes/ui/hud/sleep_prompt.tscn` — hold S
  for one second, A/D choose 1–8 hours, E sleeps and saves, Esc cancels.
- Input actions `sleep` (S), `sleep_hours_less` (A), `sleep_hours_more` (D),
  `sleep_cancel` (Esc).
- `tools/runtime/capture_sleep_prompt.gd` — renders both UI states for review.
- `tests/systems/test_sleep_prompt.gd` — fuel burn-down, a dead fire cooling its
  zone, refuel capping, the hold gate, hour clamping, and the fuel warning.

Key conflicts, resolved rather than fudged
- **S was already `move_backward`.** The hold only charges while sleeping is
  possible and no movement action is held, so walking backwards can never start
  it. A test asserts S does nothing in the open.
- **E was already `interact`.** Opening the dialog pauses the tree while the
  prompt runs with `PROCESS_MODE_ALWAYS`, so `InteractionManager` never sees the
  press. No edits to its file and no input-order guessing.

Fixed
- The fuel warning is real: `fire_outlasts_sleep()` checks every fire warming
  the spot against the chosen duration, so the player learns they will wake up
  cold before committing.
- **A node-reference `@export` on a scene root cannot resolve to its own
  children** — root properties are applied before children exist. This produced
  a dialog that never appeared. `resolve_nodes()` now fills in any widget the
  scene left null.

Closed
- The "shelter is too safe" tuning problem raised by the thermal chart: fuel
  running out during sleep is now the pressure that makes banking wood a real
  decision.

Verified
- All five suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders; both sleep UI states captured.


### 2026-09-22 (5) — Save system and sleep-to-save

Added
- `scripts/systems/save/save_manager.gd` — participant registry, atomic slot
  writes, slot metadata for a load menu, and a real version-migration seam.
- `scripts/systems/save/sleep_controller.gd` — the only path to a save. Gates on
  shelter, felt temperature and tiredness, returning a typed `Refusal` with a
  localisation key rather than a bare bool.
- `ThermalManager` and `WeatherController` now implement the save contract
  (`save_id` / `get_save_data` / `load_save_data`), matching the convention
  `DayNightManager` already used.
- `tests/systems/test_save_system.gd` — round trip, metadata, corrupt files,
  out-of-range slots, the sleep gate, and the two guarantees below.
- `docs/technical/SAVE_SYSTEM.md`.

Design decisions
- **Sleeping is not a free reset.** `try_sleep()` steps the thermal model
  through the night in quarter-hour increments, so a shelter that goes cold
  still costs body heat while asleep. A test asserts it. This is the hook the
  "shelter is too safe" problem needs.
- Saves are plain JSON while the project is in development: a save can be read
  and diffed. `metadata` sits outside `payload` so a load menu can list slots
  without deserialising game systems.
- Writes go to `slot_N.json.tmp` and are renamed, so a crash mid-write cannot
  corrupt an existing save.

Fixed (found by the new tests)
- `SaveManager` originally discovered participants only through the `saveable`
  group, which returns nothing until the scene tree settles — so it silently
  wrote an **empty save file** and reported success. A save that contains
  nothing is the worst failure a save system can have: the player believes they
  are safe. It now refuses to write an empty save, explains why, and offers
  explicit `register()` alongside the group.
- Corrupt slots are reported as `corrupt` in `list_slots()` rather than hidden,
  so a damaged save is visible to the player instead of vanishing.

Verified
- All four suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders.


### 2026-09-22 (4) — HUD thermometer bound to the model; metabolism fix

Added
- `vital_signs.gd` now drives the temperature indicators from `ThermalManager`:
  icon opacity tracks body temperature, the warning sign follows the hypothermia
  stage, and the upper/lower indicators flash on real change — the same pattern
  hunger and thirst already use. Assign `thermal_manager` on the HUD node.
- `tests/systems/test_vital_signs_binding.gd` — asserts the HUD follows the
  model and survives having no manager assigned.
- `tools/runtime/capture_thermal_debug.gd` — charts one worsening night twice,
  exposed and sheltered-at-hour-5, to a PNG. This is the tuning instrument.
- `ThermalManager.basal_heat_c` — metabolic heat production.
- A test asserting a lit shelter returns a chilled player to `NORMAL`.

Fixed
- **The survival loop could not close.** The model had no metabolic heat term,
  so `effective` temperature never beat bare-skin comfort: a lit shelter at
  -18 °C ambient slowed the cooling but never reversed it, and every run ended
  at the lethal floor. Found by the new debug chart, which showed both the
  exposed and the sheltered curve flatlining. `basal_heat_c` (12 °C) fixes it;
  `cooling_coefficient` retuned to 0.075 to keep the night's pace.
- `vital_signs.gd` seeded the thermometer inside `initialize_ui_state()`, which
  returns early when no `BioMonitorManager` is assigned — so the thermometer
  silently never seeded. Moved to `initialize_thermal_state()`.
- `vital_signs.gd` dereferenced unassigned `TextureRect` exports in its
  device-visibility loop; now null-guarded.

Open for the author
- With a lit fire the sheltered curve holds a flat 36.6 °C straight through a
  blizzard — shelter is currently too safe. `HeatSource.burn_duration_h` is the
  intended answer but is not used anywhere yet.

Verified
- All three suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders.


### 2026-09-22 (3) — Thermal model, weather state machine, first test suites

Added
- `scripts/systems/survival/thermal_manager.gd` — body temperature simulation:
  ambient curve, weather, wind chill, shelter zones, heat sources, exertion and
  clothing wetness, integrated per in-game hour into a hypothermia stage ladder
  (NORMAL → CHILLED → COLD → HYPOTHERMIC → CRITICAL → death).
- `scripts/systems/survival/thermal_zone.gd` — static Area3D volumes for
  interiors and wind shadows, with warmth the player accumulates by burning fuel.
- `scripts/systems/survival/heat_source.gd` — point heat with distance falloff
  and a fuel timer; sampled from a static registry, not via physics overlap.
- `scripts/systems/survival/weather_profile.gd` — Resource holding one weather
  state's tuning, so designers edit `.tres` rather than code.
- `scripts/systems/survival/game_hour_tracker.gd` — converts the day/night
  clock's hour-of-day into deltas, handling the midnight wrap.
- `resources/weather/{calm,snowfall,windy,blizzard}.tres` — the four states.
- `tests/systems/test_thermal_model.gd` and `tests/systems/test_weather_profiles.gd`
  — the project's first automated tests.
- `tools/ci/run_tests.sh`, wired into the CI workflow ahead of the render step.
- `docs/technical/THERMAL_MODEL.md` — architecture, the formula, the weather
  table, how interiors work, and an honest cost breakdown of the snow/ice
  presentation layer.

Changed
- `scripts/systems/world/WeatherController.gd` — was an empty stub, now the
  global weather state machine: weighted scheduling, blended transitions,
  seeded simplex gusts, and `conditions_updated` / `weather_changed` signals for
  VFX and audio to listen on.

Fixed (found by the new tests)
- `ThermalZone.priority` collided with the native `Area3D.priority`; renamed to
  `zone_priority`.
- `HeatSource` kept freed instances in its static registry. A single stale
  source aborted every subsequent temperature calculation and silently froze the
  felt temperature at its last value.
- `_ready()` does not run until the first frame, so headless-constructed systems
  stayed uninitialised. Each system now has a public `initialize()` that
  `_ready()` calls — also the seam save-game loading will need.

Verified
- `tools/ci/run_tests.sh`: both suites pass, exit code 0.
- `TestScene` still imports and renders after the change.


### 2026-09-22 (2) — Sync with main, Terrain3D provisioning, slice definition

Changed
- Merged `origin/main` (Codex HEAD `4ba97eb`) into `claudeflow`. Conflicts:
  `AGENTS.md` kept Claude's roles table on top of Codex's rules; `global.json`
  took `main`'s version (`8.0.400` + `rollForward` + `allowPrerelease`).
- `tools/ci/setup_env.sh` now fetches the pinned Terrain3D `v1.0.1-stable`
  GDExtension binaries. They are not vendored — `addons/terrain_3d/bin/` is
  gitignored — so a clean checkout is reproducible without adding 40 MB to a
  repository that already has no LFS.
- `CLAUDE.md`: single-branch rule made explicit, plus a "Staying in sync"
  protocol (fetch, merge `main`, re-render, report in issue #1) and the list of
  recurring conflict files.

Added
- `docs/game_design/VERTICAL_SLICE.md` — the agreed next target: a *Long Dark*-style
  night on the frozen island, with the breaking-ice mechanic specified (per-tile
  integrity, creak → crack → break, cold-water survival rather than instant death),
  a pillar-by-pillar cost table, an explicit out-of-scope list and open questions.

Findings
- `scenes/game/Сhunks/` uses a Cyrillic С homoglyph (U+0421), as do the node
  paths in `WorldStreamManager.gd`. Logged as §3.10 of the assessment.
- Body temperature is not simulated anywhere; `vital_signs.gd` only displays it.
  This is the slice's core pillar and is the first system to build.

Verified
- After the merge, `TestScene` imports and renders clean: Henry's UAL rig is
  textured and posed, the day/night HUD reports live values, Terrain3D loads.


### 2026-09-22 — Agent infrastructure and headless render pipeline

Added
- `CLAUDE.md` — Claude's charter as technical director: role, branch ownership,
  engine baseline, comment policy (English, `##`, max 2 lines), GDScript style.
- `AGENTS.md` — adopted from `codex`, extended with a roles table and handover rules.
- `CHANGELOG.md` — this file.
- `tools/ci/setup_env.sh` — provisions Godot 4.8-dev6 mono, Mesa/lavapipe,
  Xvfb and .NET 8 in a clean container.
- `tools/ci/screenshot.gd` — `SceneTree` harness: boots a scene, runs N frames,
  writes the viewport to PNG.
- `tools/ci/render.sh` — one-line CPU render of any scene to PNG.
- `tools/ci/render_smoke.tscn` — minimal lit scene proving the render path.
- `.github/workflows/render-smoke.yml` — CI job importing the project and
  rendering the smoke scene on every push.
- `docs/technical/COMMERCIAL_ASSESSMENT.md` — commercial-readiness review of the
  prototype with a prioritised backlog.

Changed
- `global.json` — SDK pin `8.0.407` relaxed to `8.0.0` + `rollForward: latestFeature`,
  so the project builds on any installed .NET 8 SDK instead of one exact patch.

Verified
- Godot 4.8-dev6 mono runs Forward+/Vulkan on lavapipe (llvmpipe) under Xvfb.
- `res://tests/scenes/TestScene.tscn` boots and renders a frame headlessly.

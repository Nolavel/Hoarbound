# First Exit A compass — qualitative proximity and inertial marker

Status: **implementation candidate on `codex`, pending Claude's real-scene validation and owner acceptance for `main`**.
Owner design decision: 2026-11-11, extending issue #293. Applicable **only** to the known 727 landmark in the First Exit A / `key_west_reality` profile. No universal POI manager, no new HUD ownership, no map or navigation path.

## Experience contract

The tape still follows camera yaw (not Henry's body) and reveals the bearing to a **known** place. The player still selects their own route through road, shore and ruins; no route choice, street turn, map reveal, numerical meters or pathfinding is exposed. Proximity is *Euclidean XZ distance to the canonical Fort Street entrance bearing anchor*; it is **not** proof of path accessibility or of an entrance through a wall.

One status word, five possible values. Color and ring cadence always describe absolute proximity; the single status word describes the current most useful message. Normally COLD / WARM / HOT; a validated movement event temporarily replaces it with WARMER / COLDER (RU ХОЛОДНО / ТЕПЛО / ГОРЯЧО / ТЕПЛЕЕ / ХОЛОДНЕЕ). Never display both proximity and trend words together. The internal 727 identifier is not displayed; the upper slot alternates a shelter icon and the street name.

The tape retains its bearing, circular marker and edge chevron beyond ±50°. Hub/Tab and pickup suppression remain handled by `GameplayUI`.

## Tuning defaults (NOT canonical geography)

| Proximity | Enter while approaching | Leave while retreating | Pigment |
| --- | --- | --- | --- |
| COLD | > 295 m after warm | WARM at <= 280 m | `#B2C1BF` |
| WARM | <= 280 m | COLD at >= 295 m; HOT at <= 65 m | `#E1B777` |
| HOT | <= 65 m | WARM at >= 75 m | `#F0A177` |

Initial target selection evaluates current distance directly (no stale default state); large teleports do likewise. Level transitions have hysteresis. Color blends with 0.5 s exponential time constant.

Separate time constants: compass tape 0.08 s (unchanged), marker 0.22 s; max marker yaw lag 8°. A latch within ±8° around the directly-behind angle prevents side-chevrons from flickering at ±180°. Movement ring lasts 0.95 s. Proximity sampling is 4 Hz. A validated 8 m directional change earns a movement word for at most 2.5 s. Same-direction repeats have a 6 s cooldown; progress earned during repeat cooldown is discarded, not replayed. Reversal of 0.75 m from the current radial extreme cancels the old word immediately at the next sample; the opposite word requires 8 m of new progress and ignores the previous direction's cooldown. Radial idle (<=0.32 m/s for 0.5 s) cancels the word, even when walking tangentially. Band changes cancel progress and have 1.25 s reading priority; progress restarts after the hold. These are tuning candidates for Claude.

## Code / responsibilities

- `scripts/world/first_exit_bearings.gd` remains the sole owner of known/visited/active-target and derives categorical proximity and trend from the real player and fixed landmark coordinates. It updates independently of HUD visibility. `proximity_state`, `trend_state`, and monotonically increasing `trend_serial` are transient only. Do not save progress/smoothing/cooldown.
- `scripts/ui/hud/compass_strip.gd` draws the shelter identity, single search word and state color; interpolates marker angle/color and handles one-shot pulse/edge behavior. It does not own target knowledge, compute distances or drive world state.
- `scenes/ui/hud/gameplay_ui.tscn`, `scripts/ui/hud/gameplay_ui.gd`, player scene, original thermal probe / arrival event, main UI visibility contract and main game scene are unchanged.
- `first_exit_landmarks.geojson` continues to supply `bearing_local_xz` (Fort Street entrance); loaded world chunks do not determine bearing.
- Changing the active target, loading a save, or teleporting resets transient proximity/trend. `known`, `visited`, `active_target_id`, R recall and arrival clearing retain their existing save/lifecycle semantics.

## Acceptance for Claude (lightweight CI + real-world review)

1. Godot 4.x project import / script parse and `tests/systems/test_first_exit_bearings.gd` headless run, including new threshold/hysteresis/trend/cooldown/reset checks. Green checks are not sufficient for visual acceptance.
2. In real `scenes/world/key_west/key_west_reality.tscn`, launch the scenario with `spawn_at_shelter=false` (capture-only override). Battery Osceola starts around 620 m from 727: COLD + valid bearing. Travel toward 727: approach feedback before WARM; crossing 280 m changes color/word; 65 m changes to HOT; no completion by distance alone.
3. Reverse while WARMER is visible: cancel after 0.75 m radial reversal, then show COLDER after 8 m without waiting for the previous direction cooldown. Stop or move tangentially: return to the band word within 0.5 s of radial idle. Move sideways < 8 m net, rotate camera or stand still: *no* progress pulse.
4. Cross thresholds back and forth, including 280/295 and 65/75 m. No state flicker; no color/text contradiction. Test respawn/teleport and loading a save near 727: no giant fake progress event.
5. Rotate past yaw 359→0°, through ±50° visible boundaries, and exactly behind ±180°. Marker never disappears, jumps erratically or reports the wrong side from tiny camera jitter. Check marker vs tape lag during fast turn, with its <= 8° upper bound.
6. On actual entry into 727, mark clears even though HOT was displayed earlier; leaving does not re-arm; R recalls an already-known location. Validate new-world save/load after visit and with manually re-marked home.
7. Inspect 960x540 and 1920x1080 (blizzard-white snow, dim 727), both English and Russian locale if available: text legible, edge chevron and label unclipped, no overlap with temperature, HUD, pickup feedback, no blue glare.
8. Check no active target still yields plain N/E/S/W tape, Hub/Tab suppresses layer, pickup suppresses layer, other world profiles do not grow this navigation system.

Existing capture harness `tools/runtime/capture_compass_preview.gd` and existing `.github/workflows/` checks should be reused **for real-scene acceptance**; do not create or dispatch another pipeline as part of this change. Claude may execute local engine tests and provide screenshots/video separately.

## Refusal criteria / risks

Reject if the marker feels like a GPS route; a word implies exact entrance; a bright pulse looks like danger/loot; delayed arrow misdirects navigation; back-edge flickers; Russian text lacks Cyrillic glyphs; threshold crossing chatters; pickup suppression regresses; a saved or reloaded mark vanishes unintentionally. Only adjust tuning constants after visual A/B evidence. Full-game mental 3D map (#294) remains outside scope.

## Branch integration note

The persistent `codex` branch had diverged significantly from `main` before this work. For a **focused main PR**, the integration commit uses the latest `main` tree plus only the compass files/docs/tests. The previous codex tip remains a parent of that merge commit and its experimental history is recoverable; historic experimental file changes are **not promoted to main** or included in the new branch tip. This baseline reconciliation must be explicitly inspected before merging any later codex experiments.


## Artistic revision, owner feedback (2026-11-11)

The initial marker was visually rejected as flat. A later two-word prototype was also rejected: the approved interaction is **one word at a time**, with absolute proximity conveyed by color and ring cadence even when a transient movement word replaces it. Crossing a band wins over progress; stop, reversal, recall, load and teleport invalidate stale words.

The central marker is now a small drawn circle with an ink-outline and dot, a faint soft halo, **periodic expanding/fading ring** (cold period 5.8 s, warm 3.8 s, hot 2.6 s) and one-shot outward approach / inward retreat ripples. Off-strip direction remains a clear chevron beside the circle. No perpetual attention-grabbing scale pumping. Color palette moved from muted grey to higher-contrast mineral chalk `#B2C1BF`, honey `#E1B777` and warm copper `#F0A177`, avoiding status-danger red.

Typography: `IMFellEnglishSC-Regular.ttf` (project default) for cardinals, `AveriaLibre-Bold.ttf` for English proximity, `SpecialElite-Regular.ttf` for English movement feedback. The fonts in `assets/fonts` are **Latin-only** (verified cmap), so a temporary engine fallback draws Cyrillic, rather than rendering missing glyph boxes. Follow-up artwork can supply a native Cyrillic-capable companion if Russian becomes a shipping locale.

Quick visual gate produces six cheap real Godot Control PNGs, including a Russian `ХОЛОДНЕЕ` retreat case, plus focused headless tests; it does not verify full-world visibility or motion feel. Claude remains responsible for production scene acceptance.


## Player-facing shelter identity (owner decision, 2026-11-11)

The internal label 727 remains for existing data and diagnostics, but is no longer drawn. The upper slot normally shows an open-bottom, pitched-roof house outline. Every six seconds it briefly switches to the plain mixed-case street name `Fort St.` (Averia Libre Regular, existing asset). House interval 4.5 s, street interval 1.5 s, sequential 0.18 s fades at the boundaries: no house/text overlap. The clock is local presentation only, independent of absolute proximity, progress, and camera rotation; starts again when the target is acquired or cleared. Color, circle, edge direction, rings, and the one-word lower slot are unchanged. The canonical address/anchor, target ID, save data and arrival logic remain unchanged.

The existing quick CI additionally captures 90 frames at 12 fps (7.5 s) of the actual Control on a neutral dark backdrop, then checks that the house/street/house cycle completes. This is a UI-only preview, not a real-world camera/lighting acceptance test. The existing six stills remain available.


### Arrival gate for integration

The compass is not a mission banner: on a fresh physical overlap with a thermal area under `KeyWest727Shelter`, the owner records the visit and clears the target. Both identity variants, the circle, expanding rings, edge chevron and the lower word disappear together; the ordinary cardinal tape remains. HOT outside does not complete the objective. Leaving the completed site, waiting through another identity cycle, or restoring the completed save cannot resurrect the marker. Explicit R recall remains the existing intentional re-pin operation; the pre-existing contract for an explicitly pinned save inside the shelter remains unchanged.

The quick gate now exercises the real Area3D probe signal against a minimal physics fixture using production `ThermalZone` and `KeyWest727Shelter` types, then compares the actual rendered viewport bytes against the bare-tape baseline at identical yaw. It checks arrival during house, street and off-strip street phases and after a cycle, save-data round trip and exit. This is not the authored 727 interior geometry or a full Key West walkthrough; those remain separate scene QA.


## NavigationTarget / NavigationCatalog / NavigationState (foundation, 2026-11-11)

The 727-only hardcoded metadata was replaced by an authored, **small** NavigationCatalog of `.tres` NavigationTarget resources:
- `fort_st_shelter.tres` — existing 727 target ID remains `kw:building:osm:w339414849`, internal label 727, player-facing Fort St., SHELTER_ZONE arrival.
- `battery_osceola.tres` — `kw:first_exit:battery_osceola`, authored location anchored to the real Fort Zachary Taylor footprint override, display Battery Osceola, EXPLICIT arrival for future author event. It is **NOT** automatically discovered or selected in gameplay.
- Each target resource stores its stable `id`, `feature_id`, `world_role`, labels, icon kind, completion policy and qualitative thresholds. Real XZ anchors remain exclusively in `first_exit_landmarks.geojson`. The catalog validates feature/role pairs and binds those anchors at runtime, not from streamed scene nodes, duplicative coordinates or the 13,376-entry editor index.

`NavigationState` is the independent owner of `known`, `visited`, `active_target_id`. `FirstExitBearings` stays the existing WorldContext/save-compatible, UI-compatible adapter for First Exit A and delegates generic operations: `discover_target(id)`, `select_target(id)`, `clear_target()`, `mark_arrived(id)`, `known_targets()`, `get_target(id)`. Selecting requires previous discovery; a catalog entry alone does not reveal it to the player. A trusted scene event calls `mark_arrived`, never distance thresholds. Arrival at a different known location does not clear the selected destination. All selection changes reset transient proximity/inertia. Old `first_exit_bearings` save key and active 727 feature ID are unchanged. R remains a shelter-only recall; first-exit intro remains a one-time assignment.

`CompassStrip` is **unchanged**: it still calls `active_xz()`, `active_street_label()`, and reads the same state. The latter legacy-named method now returns the authored `compass_title` of the active target, not literally a street in every case. The two current entries are shelters (Fort St. and the former Battery Osceola bunker), so the existing small house-outline art is still appropriate. Future non-shelter icon variants require a separate presentation decision; no universal map/POI renderer was enabled.

For the eventual mental map (#294): the map can read `known_targets()` and call `select_target(id)`. The future map itself determines whether selection is appropriate; world events call `discover_target(id)`. Neither view can invent locations or mark arrival by proximity. This refactor does **not** implement the M menu, automatic discovery, random POI loading or a new UI.

Minimal regression under existing `test_first_exit_bearings` checks two distinct Reality anchors, no auto-disclosure, invalid/unknown rejection, switch in both directions using the *unmodified* CompassStrip class, per-target proximity reset, arrival isolation, selected-target completion, R, and save/load. Reuse the `[compass-quick]` tag on the existing checks workflow, no new CI pipeline/heavy render.


**Authoring entrypoint:** `data/world/key_west/navigation/catalog.json` is the sole ordered list of allowed `NavigationTarget` resource paths. Adding an author-approved location adds its `.tres` and a line in the JSON manifest, **not a GDScript change**. `NavigationCatalog` fails closed for duplicate paths/IDs/roles, unmatched canonical Reality features, missing anchors or invalid threshold ordering. This file is an allow-list, not an automatic exporter of buildings or a fog-of-war generator.

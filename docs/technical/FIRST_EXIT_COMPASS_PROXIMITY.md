# First Exit A compass — qualitative proximity and inertial marker

Status: **implementation candidate on `codex`, pending Claude's real-scene validation and owner acceptance for `main`**.
Owner design decision: 2026-11-11, extending issue #293. Applicable **only** to the known 727 landmark in the First Exit A / `key_west_reality` profile. No universal POI manager, no new HUD ownership, no map or navigation path.

## Experience contract

The tape still follows camera yaw (not Henry's body) and reveals the bearing to a **known** place. The player still selects their own route through road, shore and ruins; no route choice, street turn, map reveal, numerical meters or pathfinding is exposed. Proximity is *Euclidean XZ distance to the canonical Fort Street entrance bearing anchor*; it is **not** proof of path accessibility or of an entrance through a wall.

Two separate signals:
1. **Proximity**: persistent word below the marker and its pigment. COLD / WARM / HOT (Russian locale: ХОЛОДНО / ТЕПЛО / ГОРЯЧО). Color is never the sole carrier.
2. **Progress**: brief signed feedback when Henry has actually changed distance by >= 8 m; approach = 8% increase then settle, retreat = 8% decrease then settle. No pop for camera rotation, idle or small sideways steps. No endless pulsing or numerical display.

Current layout keeps the thin compass and one '727' marker; an on-strip diamond becomes an edge chevron beyond ±50°. Words stay clamped inside the 400 px compass area. Hub/Tab and pickup suppression remain handled by `GameplayUI`.

## Tuning defaults (NOT canonical geography)

| Proximity | Enter while approaching | Leave while retreating | Pigment |
| --- | --- | --- | --- |
| COLD | > 295 m after warm | WARM at <= 280 m | `#8999A0` |
| WARM | <= 280 m | COLD at >= 295 m; HOT at <= 65 m | `#C9A05F` |
| HOT | <= 65 m | WARM at >= 75 m | `#DE7950` |

Initial target selection evaluates current distance directly (no stale default state); large teleports do likewise. Level transitions have hysteresis. Color blends with 0.5 s exponential time constant.

Separate time constants: compass tape 0.08 s (unchanged), marker 0.22 s; max marker yaw lag 8°. A latch within ±8° around the directly-behind angle prevents side-chevrons from flickering at ±180°. Pulse lasts 0.65 s. Proximity sampling runs in the world owner every 0.25 s; trend pulses require >= 8 m net distance change and have a 6 s cooldown. Distance accrued during cooldown is discarded at its end to prevent stale pulses. These numbers are deliberately **initial A/B parameters** for Claude.

## Code / responsibilities

- `scripts/world/first_exit_bearings.gd` remains the sole owner of known/visited/active-target and derives categorical proximity and trend from the real player and fixed landmark coordinates. It updates independently of HUD visibility. `proximity_state`, `trend_state`, and monotonically increasing `trend_serial` are transient only. Do not save progress/smoothing/cooldown.
- `scripts/ui/hud/compass_strip.gd` draws the label, proximity word and state color; interpolates marker angle/color and handles one-shot pulse/edge behavior. It does not own target knowledge, compute distances or drive world state.
- `scenes/ui/hud/gameplay_ui.tscn`, `scripts/ui/hud/gameplay_ui.gd`, player scene, original thermal probe / arrival event, main UI visibility contract and main game scene are unchanged.
- `first_exit_landmarks.geojson` continues to supply `bearing_local_xz` (Fort Street entrance); loaded world chunks do not determine bearing.
- Changing the active target, loading a save, or teleporting resets transient proximity/trend. `known`, `visited`, `active_target_id`, R recall and arrival clearing retain their existing save/lifecycle semantics.

## Acceptance for Claude (CI unavailable / no Actions budget)

1. Godot 4.x project import / script parse and `tests/systems/test_first_exit_bearings.gd` headless run, including new threshold/hysteresis/trend/cooldown/reset checks. Green checks are not sufficient for visual acceptance.
2. In real `scenes/world/key_west/key_west_reality.tscn`, launch the scenario with `spawn_at_shelter=false` (capture-only override). Battery Osceola starts around 620 m from 727: COLD + valid bearing. Travel toward 727: approach feedback before WARM; crossing 280 m changes color/word; 65 m changes to HOT; no completion by distance alone.
3. Walk away > 8 m after cooldown: retreat feedback. Move sideways < 8 m net, rotate camera or stand still: *no* progress pulse.
4. Cross thresholds back and forth, including 280/295 and 65/75 m. No state flicker; no color/text contradiction. Test respawn/teleport and loading a save near 727: no giant fake progress event.
5. Rotate past yaw 359→0°, through ±50° visible boundaries, and exactly behind ±180°. Marker never disappears, jumps erratically or reports the wrong side from tiny camera jitter. Check marker vs tape lag during fast turn, with its <= 8° upper bound.
6. On actual entry into 727, mark clears even though HOT was displayed earlier; leaving does not re-arm; R recalls an already-known location. Validate new-world save/load after visit and with manually re-marked home.
7. Inspect 960x540 and 1920x1080 (blizzard-white snow, dim 727), both English and Russian locale if available: text legible, edge chevron and label unclipped, no overlap with temperature, HUD, pickup feedback, no blue glare.
8. Check no active target still yields plain N/E/S/W tape, Hub/Tab suppresses layer, pickup suppresses layer, other world profiles do not grow this navigation system.

Existing capture harness `tools/runtime/capture_compass_preview.gd` and existing `.github/workflows/` checks should be reused **when the owner restores Actions budget**; do not create or dispatch another pipeline as part of this change. Claude may execute local engine tests and provide screenshots/video separately.

## Refusal criteria / risks

Reject if the marker feels like a GPS route; a word implies exact entrance; a bright pulse looks like danger/loot; delayed arrow misdirects navigation; back-edge flickers; Russian text lacks Cyrillic glyphs; threshold crossing chatters; pickup suppression regresses; a saved or reloaded mark vanishes unintentionally. Only adjust tuning constants after visual A/B evidence. Full-game mental 3D map (#294) remains outside scope.

## Branch integration note

The persistent `codex` branch had diverged significantly from `main` before this work. For a **focused main PR**, the integration commit uses the latest `main` tree plus only the compass files/docs/tests. The previous codex tip remains a parent of that merge commit and its experimental history is recoverable; historic experimental file changes are **not promoted to main** or included in the new branch tip. This baseline reconciliation must be explicitly inspected before merging any later codex experiments.

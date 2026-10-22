# Stove ritual

Production path: the stove in the 727 Fort St shelter (Key West Reality,
`scenes/world/key_west/key_west_reality.tscn`, built by `KeyWest727Shelter` from
the shelter template). It replaced the F cycle of 2026-09/10, in which F opened the
door, the next F loaded the whole armful and readied the lighter, and RMB took
cold logs back. That cycle is gone; the internal log and lighter code is reused.

## Sequence

```text
OUTSIDE --F--> APPROACHING --> OPENING_DOOR --> ENTERING_CROUCH --> WORKING --F--> EXITING --> OUTSIDE
                                                                     |  RMB  one log
                                                                     |  LMB  tinder (needs a log)
                                                                     |  LMB  new press: lighter strike, hold 3 s
```

1. `[F] Stove` (firebox or door). `StoveInteractionController.request_enter()`
   refuses when Henry's capsule does not fit on `StoveInteractionPoint`.
2. Henry walks there with the player's own scripted walk (`Player.move_to_position`,
   braking onto the spot; never a teleport). WASD gives the walk back; a stalled
   walk ends with "unreachable". Already on the spot, the walk is skipped.
3. He turns to the door (10 degree tolerance), the door swings open, and he
   crouches (`Player.set_work_crouch`), logs in his arms or not: with a load the
   base state is `CrouchCarry`, the carry arms frozen over the crouch legs.
4. `PlayerState` goes WORKING: no WASD, sprint, jump or pickups. The interact key
   is claimed through `InputSystems.claim_interact`, so F only ends the ritual.
   The camera stays the TPS camera; as the door opens it eases (about 0.7 s) onto
   a work framing (`TpsCamera.set_work_framing`), the owner's composition: close over
   Henry's right shoulder, the shoulder in the lower left, his head left, the firebox
   mouth mid-frame and the open door on the right. Henry kneels 0.3 m off the door
   axis, turned to the mouth, and the door folds back 160 degrees along the front, so
   neither his back nor the door hides his right hand at work. The mouse orbits it up to 25
   degrees in yaw and 12 in pitch; a wall between Henry and the eye shortens the
   boom. F hands the view back to the follow rig at the same rate.
5. The ring (`StoveInteractionRing`) appears beside the stove.
6. F cancels any act that has not committed, closes the door, hides the ring,
   stands Henry up and returns `PlayerState` to ON_FOOT.

## Acts (`HeatSourceFeed`)

| Input | Act | Needs | Commits |
|---|---|---|---|
| RMB press | `insert_fuel()`, 1.6 s, 0.5 game min | a carried fuel item, room in the firebox, hands free of other things | one item leaves the inventory and `HeatSource.add_logs(1)` in one step at the end; a cancel moves nothing |
| LMB press | `insert_tinder()`, 1.1 s, 0.25 game min | a log in the firebox, a cold stove, no tinder laid, tinder owned | one tinder spent, `HeatSource.set_tinder_prepared(true)` |
| LMB release | the lighter comes out (`prepare_lighter()`, the existing work pose) | tinder laid, the lighter owned | nothing |
| new LMB press, hold | the existing lighter: `attempt_lighter_strike()`, 3 s hold | as above | `HeatSource.start_loaded_fire()`, which spends the tinder |

- One press is one act: a held RMB sends no more presses, presses during an act
  are refused (BUSY).
- The press that lays the tinder never reaches the lighter. The controller waits
  for its release, and only a new press strikes.
- Logs can go in after the tinder; the tinder stays.
- A burning stove takes logs through the same `add_logs()`, which never relights.
  Neither the warm-up nor the heat simulation restarts.
- Fuel ids are `fuel_item_id` plus `extra_fuel_item_ids`, real inventory items.
  There is no abstract fuel resource.
- Time goes through `TimeCostedActionSystem`: staged acts for logs and tinder, the
  manual act for the lighter. It restores the WORKING mode the ritual set.

## State and save

- `HeatSource` is the only source of truth: logs (`get_loaded_log_count()`,
  capacity from `burn_duration_h / hours_per_fuel_unit`, 3 in the shelter),
  `is_tinder_prepared()` and the fire.
- `get_fire_save_data()` carries `tinder_prepared`. `ShelterState` records it on
  `tinder_changed` as it does fuel.
- The ritual mode is not saved: a loaded game starts outside it.

## Ring (`StoveInteractionRing`)

Display only. It reads the feed and the source each frame and holds no gameplay
state.

- Layout: the pickup marker's three arcs (top, lower right, lower left) in its
  cream colour.
- Fuel (top) has one tick per log of the real capacity. Tinder is lower left, fire
  lower right.
- States: inactive (dotted), available (brighter track plus RMB/LMB hint), in
  progress (the fill), done (solid plus check), spent (the tinder after the fire,
  dimmed).
- A refusal flashes red on the arc it concerns, with a cross and the reason.
  An empty firebox flashes the fuel arc.

## Tests and capture

- `tests/systems/test_stove_ritual.gd` runs the real shelter with the real player
  (physics on) and pushed input. It covers entry without auto-loading, carrying,
  one log per press, tinder refused for an empty firebox, the long-press gate, the
  lighter (early release, full hold), a log after the tinder, exit and return,
  save data, a burning refuel, an unreachable spot, quick F, pause, lost tools or
  fuel, and a vanished stove.
- `tests/systems/test_shelter_workflow.gd` checks the shelter contract (F, three
  RMB logs, F out).
- `tools/runtime/capture_stove.gd` drives the ritual in 727 through the TPS camera
  and writes named stages plus a continuous frame run for a video.

## Log fire presentation

`HeatSource` still owns all fuel, capacity, ignition, warm-up and heating. `StoveVisual`
reads `get_loaded_log_count()` and the existing fuel/burning/intensity signals. It keeps
only visual slot identities, catch time and consumed fractions, so adding a log does
not reset the appearance of an older one. Fuel decreases age the oldest visible slot;
when the authoritative count decreases that slot disappears. No extra fuel or heat
simulation is introduced. A short residual-coal fade has no thermal effect.

`StoveLogVisual` fits the isolated study's irregular split-log method to the existing
0.54 m length and 0.05 m radius. The source study's environment is not imported.
Charcoal cracks and ignition smoke are local to each log. Flame and smoke use closed
3D meshes, with depth testing against the firebox and door, rather than camera-facing
cards. The original room SpotLight and firebox glow remain under `StoveVisual`.

The runtime proof uses the real Key West Reality scene, Henry and `TpsCamera` work
framing. `capture_stove.gd` extends the original ritual with steady burn, a burning
refuel, a closed-door view, accelerated fuel exhaustion through the public
`HeatSource.advance_fuel()` API, residual coals and cooling. This accelerates the
render demonstration only; it does not change production fuel duration. Every saved
frame is rendered by Godot's viewport using `RenderingServer.force_draw`; run the
capture with `--disable-render-loop` to skip redundant draws between samples. Video
sampling remains separate from the fixed 30 Hz game step.

Visual limitation: per-log ages are presentation metadata, not saved gameplay
identities. A loaded aggregate fuel state cannot reconstruct the exact insertion
history of individual logs. No new save schema or per-log gameplay authority is
introduced for this visual integration.

Runtime evidence: [`key_west_727/stove_fire`](../runtime_previews/key_west_727/stove_fire/).
The `baseline/` PNGs are the original main `5a4976c6` under the same 960×540,
13:00 calm-weather production setup. `partial/` is the inspected first integration
pass (547 frames, 54.7 s at 10 fps), ending after the closed-door view; it does **not**
prove cooling or camera orbit. The original reentry targeted the cooking pot;
the capture now reenters using the real stove controller, and drives the public
TPS look API because unattended mouse motion did not move the workspace camera.

Both baseline and candidate use Godot 4.8-dev6 Mono, graphical X11/Xvfb,
OpenGL Compatibility / Mesa 25.0.7 llvmpipe (LLVM 19.1.7, 256 bits). Scene lighting
and WorldEnvironment are retained. OpenGL reports unsupported scene fog;
Forward+/Vulkan production color and performance remain unverified. The fallback
is evidence of real integration, not renderer parity with the production target.

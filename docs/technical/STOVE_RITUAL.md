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
   neither his back nor the door hides his right hand at work. The mouse tilts it up to 12
   degrees in pitch; yaw is locked, since a sideways orbit brought the eye into
   Henry's head and faded him out. A wall between Henry and the eye shortens the
   boom. F hands the view back to the follow rig at the same rate.
5. The ring (`StoveInteractionRing`) appears at the screen centre, 100 px down
   (`center_drop_px`). The centre prompt's brackets part to the screen edges at
   60 % opacity (`session_prompt_alpha`), each with half the yellow strip: `[F] BACK` by the
   left one, `STOVE` by the right. The feed sits in `active_work_session` from
   the door opening to F, and `MouseCursorUI` reads its
   `get_session_prompt_data()`.
6. F cancels any act that has not committed, closes the door, hides the ring,
   stands Henry up and returns `PlayerState` to ON_FOOT.

## Acts (`HeatSourceFeed`)

| Input | Act | Needs | Commits |
|---|---|---|---|
| RMB press | `insert_fuel()`, 2.2 s, 0.5 game min | a carried fuel item, room in the firebox, hands free of other things | one item leaves the inventory and `HeatSource.add_logs(1)` in one step at hand contact (64%); return follows; pre-contact cancellation moves nothing |
| LMB press | `insert_tinder()`, 1.8 s, 0.25 game min | a log in the firebox, a cold stove, no tinder laid, tinder in Quick Access or actually held | one tinder spent from its exact pocket/hand source at contact; visible bundle and saved ignition surface |
| LMB release | the lighter comes out (`prepare_lighter()`, at Henry’s actual pocket/hand) | tinder laid, the lighter owned | nothing |
| new LMB press, hold | the existing lighter: `attempt_lighter_strike()`, reach followed by 3 s at the tinder | as above | `HeatSource.start_loaded_fire()`, which spends the prepared tinder; tinder flame precedes log ignition |

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

## Addressed hand action and placement

`HeatSourceFeed` owns the action/transaction; `StoveHandReach` poses Henry’s right arm
and spine through the existing two-bone solve (`DoorHandIK`). The original crouch,
working point and TPS ownership stay unchanged. This is an addressed pickup,
orientation, insertion, release and return trajectory, not `Fixing_Kneeling` claimed
as a placement clip. The visible prop follows the solved palm, not a separate proxy
hand. A pending item remains in its owning storage until contact. Cancellation after
contact never refunds it. Restoring fire state cancels transient actions and exits
the ritual before applying saved fuel, preventing a delayed second transfer.

**Contact is a point on the act's timeline, not a measured palm distance.** The transfer
commits at 64 % of the act and the hold counts once the reach has arrived. The solved
palm only presents it. The first port gated both on the IK palm being within 4.5 cm of
the target. In the 727 shelter workflow the arm stopped 0.44 m short, so a log was never
laid and nothing was reported. Simulation state must not depend on a presentation result.

Logs enter endwise and take bounded, reproducible poses in three floor-supported
lanes. Their resting height comes from the actual wood mesh. A released log starts
at the held prop transform and settles with gravity-timed acceleration from one log diameter above its rest pose. Existing logs never sort or move
when another burns away or a new one is added. Each keeps its char age and ignition
origin. Fuel/count/heat authority remains solely `HeatSource`.

All geometry targets use the `StoveVisual` local frame and its world transform.
The production visual root is 0.10 m below `HeatSource`; the fuel owner’s origin
is not interchangeable with the geometry/contact frame.

The two cooking plates sit toward Henry's near interaction edge of the stovetop,
away from the rear flue. A frying pan on one plate points its handle toward Henry;
the handle and pan body must leave the other plate clear for a second vessel.
`Warmer` and `Warmer2` use matching positions and separate save keys.

The tinder arc and action share the same accessibility predicate: an actual held
item or a worn Quick Access pocket, excluding pack-only ownership. Contact spends
exactly that source via `HeldOwnership`; it never silently falls back to the pack.
The shared `SurvivalItemVisual` bundle is used in hand and in the stove. Its point
is chosen beside a laid log, stored in stove space and reserved clear of later logs.

The lighter strikes at its own nozzle and moves to that saved point. Hold time
advances once the reach has arrived (`_light_reach`); early release retracts the hand while keeping laid tinder
and fuel. Successful ignition first shows the tinder flame, then spatially delayed
log catches. Each log transforms the source into its mesh coordinates for the shared
arrival field. Refuel catches from a nearby existing burning log without resetting
older char. Tinder chars and disappears on total exhaustion; residual coals outlast
flame. Existing room lights and WorldEnvironment are retained.

## Persistent presentation

`ShelterState` adds optional `presentation` to each fire record: ordered visual
cohorts, their resting poses, consumed/catch stages, individual ignition origins,
placement sequence, tinder position and ignition age. It snapshots live presentation
when saving, as well as on fuel/tinder events. Loading checks the authoritative log
count, restores only valid poses and cancels old settling tweens. Legacy records
without presentation receive safe deterministic placement and a reachable tinder
point when prepared. This metadata never creates fuel or heat and the ritual mode
is not saved.

Readability corrections keep the existing production light color, energy, placement
and WorldEnvironment: smaller/dimmer orange coals, lower crack emission, larger warm
flame silhouettes with asymmetric tapered geometry, and opacity height normalized
to the current flame strength so shrinking tongues do not become opaque round caps.
Visual acceptance remains subject to review of the game-camera footage and a
Forward+ run; this software Compatibility capture does not establish production readiness.

## Runtime visual evidence

Codex's fire-only and partial captures stayed on the `codex` branch; they were not
brought into `main` (about 11 MB). The extended `capture_stove.gd` drives the real Key West Reality scene
and Henry through actual input, pocket availability, early release, save/load,
ignition, refuel, exit/reentry and cooling. A closer view uses the same production
`TpsCamera.set_work_framing()` pipeline with its normal collision and easing, never
an independent capture camera. Video samples every third fixed 30 Hz step (10 fps).
`review` after the output path saves stages without a video for bounded checks.
Every image comes from Godot’s real viewport via `RenderingServer.force_draw()`.

OpenGL Compatibility / llvmpipe under Xvfb is a fallback verification path. It does
not prove Forward+ production color or performance. Unsupported scene fog, existing
room-light balance at late embers and scene-teardown warnings must be reported with
the capture, not concealed by postprocessing. Visual acceptance still requires
review of actual game-camera footage.

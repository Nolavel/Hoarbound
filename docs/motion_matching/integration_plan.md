# Motion Matching — Player integration (#202)

Status: integration layer implemented behind a flag, **off by default**.
Production locomotion (`HenryUALAnimation` AnimationTree + `MovementController`
+ `Player`) is unchanged while the flag is off.

## Switching it on

- `Player/MotionMatchingLocomotion.enabled` (export), or the environment
  variable `HOARBOUND_MOTION_MATCHING=1`.
- The node loads the committed database
  `data/motion_matching/henry_cmu_locomotion.res` (8.1 MB compressed, CMU only;
  author decision, 2026-10-07). Without it, it rebuilds from staged CMU sources
  (development only); failing that it logs `unavailable` and the AnimationTree
  keeps locomotion.
- `tools/runtime/audit_motion_dataset.gd` rebuilds from the sources and exits 4
  when the committed file differs from the rebuild; `MM_WRITE_DATABASE=1`
  rewrites it. The CI Motion Matching job runs that check.
- `data_matched_body` is on (author decision, 2026-10-07): while the node runs
  it requests `MovementController`'s `data_matched` dynamics profile, under
  which walking accelerates at 3 m/s², brakes at 3.5 m/s² and turns at rate 4
  (see "Dynamics contract"). `HOARBOUND_MM_DATA_BODY=0` keeps the production
  dynamics for A/B work.

## Runtime ownership

```text
Player._physics_process
  input -> MovementController (velocity) -> move_and_slide -> body is authoritative
           owns all tuning; applies a requested dynamics profile in walking only
  HenryUALAnimation.update_animation_blend/state/head_look (unchanged)
        |
MotionMatchingLocomotion._physics_process (child of Player, runs after it)
  AnimationTree.advance(dt)                       tree pose first (MANUAL mode)
  gate: plain locomotion (the tree's verdict: no air or landing state, no
        action/carry/sit/crouch), speed <= covered speed, not standing still > 0.6 s
  handover in: from standing, inertialized (matching owns the pose at once,
              the tree's difference decays, halflife 0.1 s); from motion, 0.25 s
  handover out: 0.25 s; settling to stand freezes the search and holds both
              feet, which the tree's idle then keeps standing on
  held prop: the socket arm stays the tree's held pose (layer by hold weight)
  requests the movement dynamics profile while the tree reports plain locomotion
  controller.follow(dt, prediction, target velocity)
    query    = live pose before the foot lock + the body's own future
    search   = all frames, no role gate
    root     = follows the body: root motion + adjustment + UE5-style steering
               (<= 2 rad/s) + clamp (0.15 m, 90 deg)
    pose     = all bones except neck/head, slerped over the tree pose by weight;
               bone translations at rest (as baked)
    feet     = contact lock + two-bone leg IK (presentation only)
        |
Skeleton modifiers (unchanged order): FootPoseProbe, Wade, SnowFeet, DoorHand,
HeadLook. Footprints and audio see the locked feet.
```

The tree keeps: actions and work poses, a held prop's arm (`hold_pose`), carry, sit,
crouch, jump take-off, airtime and landing (its air states after the 0.15 s fall
timeout), sprint above the covered speed (3.58 m/s, database p99), and idle after
0.6 s standing still.
Neck and head stay with the tree clip and the `LookAtModifier3D` head look
(author decision).

Prediction mirrors the production body exactly: `MovementController`'s
constant-rate approach to its target velocity and `Player`'s exponential turn
at `MovementController.get_turn_rate()`. Additive hooks only:
`MovementController.get_target_velocity()` / `get_velocity_rate()`, the
dynamics contract below and `HenryUALAnimation.is_plain_locomotion()`, which
now also covers the air and landing states (follow-up 3).

## Dynamics contract (hardening pass)

Motion Matching no longer writes `MovementController.accel_rate` /
`decel_rate` or `Player.turn_rate`. The movement layer owns every tuning value
and decides where a profile applies; Motion Matching only asks for one by id.

```text
LocomotionDynamicsProfile (Resource)      id, walk_accel_m_s2, walk_decel_m_s2, turn_rate
  data/characters/henry_dynamics_data_matched.tres   data_matched: 3.0 / 3.5 / 4.0
MovementController.dynamics_profiles      profiles it offers (export, movement-owned)
  request_dynamics_profile(id, requester) -> bool    false: no such profile
  release_dynamics_profile(requester)                only the holder can release
  get_applied_dynamics_profile() -> id    the profile that governed the last tick, or &""
  get_turn_rate(base) / get_braking_rate() profile-aware; Player and _walk_direction use them
MotionMatchingLocomotion
  requests data_matched while the tree reports plain locomotion; releases otherwise,
  on exit and when the node is freed (a freed requester never holds a profile)
```

A requested profile governs only grounded walking: on the floor, not crouching,
no sprint build-up, movement not locked. Sprint, air, crouch, carry and actions
keep `MovementController`'s own rates. One requester at a time; a new request
replaces the old one. Without a requester the code path computes the same rates
as before (`accel_rate · max(walk_speed, 1)`, in m/s²).

`tests/systems/test_locomotion_dynamics_profile.gd`: measured walking rates are
12 / 18 m/s² without a request and 3.0 / 3.5 m/s² with `data_matched`; the
profile stays off in sprint, crouch and air; a stranger cannot release it, a
freed requester loses it; with Motion Matching on, matched walking runs on the
profile for 120 of 120 ticks and `accel_rate`, `decel_rate` and `turn_rate`
are unchanged after walking and sprinting.

## Foot locking

`MotionFootLock` follows Holden's `contact_update` (Motion-Matching
`controller.cpp`): the database contact bit locks the ankle's ground point;
lock and unlock transitions decay by inertialization (halflife 0.1 s). Instead
of a hard unlock at 0.2 m, the point is dragged at that radius (the
`SnowFootModifier` lock-reach policy) and pulled when the leg cannot reach it,
so a planted boot slides rather than snapping. Height stays the animation's, so
heel and toe roll survive. `LegTwoBoneIK` is the two-bone solve shared with
`SnowFootModifier` (identical output on 200 random poses).

Lab proof, identical matching with and without the lock (59 switches):

| | lock off | lock on |
| --- | --- | --- |
| drawn planted-ankle slide (DB contacts), mean | 0.184 m/s | 0.032 m/s |
| steady (no switch within 0.3 s) | 0.149 m/s | 0.020–0.03 m/s |

The data itself slides 0.075 m/s on forward walking; the lock goes below it.
Remaining: a 0.2 m drag when the animated root is clamped far from the body
(sharp reversal), visible in the top-down traces.

## In-game measurement (TestScene, real Player)

`tools/runtime/capture_motion_matching_player.gd` drives the real Player with
one deterministic 30 s analog program (`--fixed-fps 30`, bare ground: the snow
shell's GPU readback is not deterministic headless). The TpsCamera stays the
input camera; a side view renders in a SubViewport. Metric: foot skating after
Zhang et al. 2018 (MANN) — ball-joint speed weighted by
`clamp(2 - 2^(h/0.025), 0, 1)`; the raw CMU database scores 0.27 m/s on it, so
only relative values matter.

Matching is chaotic: one program is one sample (a sub-centimetre data change on
the clips in play moved one run's "stop" from 0.26 to 0.64). Numbers are means
over four stick scales (`MM_STICK_SCALE` = 1.0, 0.97, 0.94, 0.91), database
`root-space-v7`, per-state body rates, after follow-up 3 removed the walk-start
hop (it also made the tree play its landing clip on every start):

| segment | tree | MM, production body | MM + data-matched body (default) |
| --- | --- | --- | --- |
| idle (tree owns idle) | 0.009 | 0.009 | 0.009 |
| walk forward (start from idle) | 0.604 | 0.702 | 0.671 |
| smooth curve left | 0.555 | 0.576 | 0.542 |
| walk | 0.537 | 0.491 | 0.465 |
| stop | 0.260 | 0.422 | 0.493 |
| start 90 deg right | 0.815 | 0.769 | 0.673 |
| sharp reversal | 0.676 | 0.773 | 0.586 |
| walk after sprint | 0.724 | 0.722 | 0.935 |
| half stick | 0.332 | 0.275 | 0.274 |
| stop, idle | 0.082 | 0.117 | 0.117 |
| whole run | 0.507 | 0.549 | 0.539 |

Before follow-up 3 the tree scored 0.682 on the whole run (walk forward 1.09,
start 90° 1.52) and Motion Matching looked better overall; most of that lead was
the tree's landing clip. Motion Matching now wins continuous walking and turning
(walk, curve, start 90°, reversal, half stick) and loses every handover with the
tree (start from idle, stop, walk after sprint): the 0.25 s crossfade slides
planted feet (1–4 m/s at ground height during the blend). Inertialized handovers
are follow-up 6.

With Motion Matching keeping idle (`idle_to_tree_seconds = 0`) the start from
idle scores 0.569 but idle itself 0.185: CMU standing ranges are short and the
matcher hops between them and pivot-capture standing frames (111_28 alone is
0.005–0.012 in the data).

## Findings

1. **Body dynamics vs. captured humans.** The production body accelerates at
   12 m/s², brakes at 18 m/s² and starts a 90° turn at ~15 rad/s; the CMU data
   is at 1.8 / 1.9 m/s² (p95) and 2.7 rad/s (p99). No real motion matches a
   0.07 s stop, so starts, stops and reversals clamp and drag (Holden, "code vs
   data driven displacement"). Resolved by the author: `data_matched_body` on.
2. ~~**Production defect found on the way:** every walk start applies
   `start_jump_impulse`, the body leaves the floor for one tick and the tree
   plays AirLoop → Land (~1.3 s landing clip while walking).~~ Fixed
   (follow-up 3), see below.
3. ~~**Sprint** stays with the tree (no run data).~~ Run data added
   (follow-up 5): Motion Matching keeps sprint up to 3.94 m/s; the tree's own
   sprint skates at 2–5 m/s in this metric.
4. ~~**Snow and wading** with Motion Matching are untested.~~ Measured and
   fixed (follow-up 4), see "Snow and wading".
5. **Retargeted feet floated** 2.5–3.5 cm on CMU subjects 02, 07, 08 and 113
   (their proportions differ from Henry's). Fixed in `MotionRetargeter`: each
   clip's median ground error (lower ball joint against its flat-foot rest
   height) is removed from the pelvis; every range now has a median of 0.
   Walk after sprint 1.22 → 0.92, whole run 0.625 → 0.594 (four-scale means).

## Known conflicts with `data_matched_body` on

Measured on TestScene unless marked computed. All of them exist only while the
Motion Matching flag is on; production with the flag off is unchanged.

1. ~~**Scripted walks overshoot.**~~ Fixed (follow-up 1): `Player._walk_direction`
   now commands at most √(2·a·d) at the body's braking rate. Rest error went
   0.272 → 0.012 m (3 m walk) and 0.146 → 0.008 m (0.3 m) with data rates,
   0.019 → 0.012 m in production; `tests/systems/test_scripted_walk_braking.gd`.
2. ~~**The override is global while the node runs.**~~ Fixed (follow-up 2):
   data rates apply only while walking (grounded plain locomotion, no crouch,
   no sprint build-up); sprint, air, crouch, carry and actions keep production
   rates. Sprint stop from 4.35 m/s: 2.67 m with global data rates, 0.49 m now
   (production 0.49 m). Walking segments are unchanged.
3. ~~**Snow multiplies the reduced acceleration.**~~ Not a defect (computed
   over a step cycle): a deep-snow start takes ~0.42 s against 0.5 s on bare
   ground, so snow still slows Henry by the same share; at full wade the
   per-step surge dips 17% less deep (0.37 against 0.33 m/s at the bottom),
   mean speed unchanged.
4. **Not a uniform win** (four-scale means, v7): reversal 0.82 → 0.61, curve
   and half stick improve; start at 90° worsens 1.04 → 1.21; stop and walk are
   unchanged.
5. ~~**The start hop** (finding 2) stays.~~ Fixed (follow-up 3); Motion
   Matching now follows the tree's air and landing states.
6. **Branches:** `.github/workflows/checks.yml` (Motion Matching job and path
   filter) will conflict when `codex` next merges `main`; keep both sides' jobs.

## Airtime and landing (follow-up 3)

Measured on a flat floor with a 0.3 m step (production, flag off):

| case | before | after |
| --- | --- | --- |
| walk start | 2 ticks airborne, AirLoop, Land 1.17 s while walking | stays Grounded |
| 0.3 m step-down while walking | Land 1.15 s while walking | soft landing, walks on |
| jump while walking | Land 1.15 s while the body walks on (~1.7 m, computed) | LandMoving: impact, walk after 0.35 s |
| standing jump | JumpStart, Land 1.15 s | unchanged |

- `MovementController` no longer adds `start_jump_impulse` (0.1 m/s up on every
  walk start; its only effect was the false airtime).
- `HenryUALAnimation` judges airtime once: AirLoop only after the 0.15 s fall
  timeout (Unity Starter Assets `FallTimeout`) or a jump; a landing plays only
  after real air. Touch-down speed picks it: below `hard_landing_speed`
  (3 m/s, a ~0.46 m drop) Henry blends straight back to locomotion; above it,
  standing plays `Land`, moving plays `LandMoving` (the first 0.6 s of
  `Jump_Land`, then a 0.25 s blend to the walk), as Lyra hands a moving landing
  back to locomotion.
- `MotionMatchingLocomotion` dropped its own airtime grace and landing timer and
  follows those states.
- `tests/systems/test_landing.gd` covers the four cases and fails on the old code.

Left for the author: `jump_velocity` 5 m/s gives a 1.28 m apex and 1.0 s of
airtime (a standing human jump is about 0.4–0.5 m); the UAL set has no fall
loop, so `AirLoop` replays `Jump_Start` from the take-off when Henry walks off a
ledge.

## Snow and wading (follow-up 4)

Measured with `MM_KEEP_SNOW=1` on TestScene's snow (0.15–0.19 m along the main
program) and with `MM_PROGRAM=drift` through its deepest drift (0.34–0.40 m,
wade ~0.18). In snow MANN undercounts (the boot rides on the snow top), so the
capture also reports `snow_print_slide_m_s`: ball speed while the snow holds
the boot on its print.

Snow captures were not reproducible: the field rebuilds within a wall-clock
budget (`Time.get_ticks_usec`) and `WeatherController` picks its profile with
the unseeded global RNG, so depth differed between runs before Henry moved
(0.145–0.216 m at spawn). The capture now seeds the RNG and lets field rebuilds
finish in the step they start; two runs are identical.

Found: `FootContactSensor` plants a foot by height alone. Real gait clears the
ground by 1–2 cm, so a Motion Matching swing passing 2 cm over the floor read
as a plant at 4–5 m/s, and a low swing never rose enough to re-arm: the snow
pinned swinging boots to false prints, and footprints, footstep audio and ice
load got extra steps (15 plants in "walk forward" against the tree's 8). The
UAL clips swing high, so the tree never showed it; their stance feet also
glide close to body speed in sprint, so no speed rule separates stance from
swing for both systems.

Fixed at the source: while Motion Matching owns most of the pose it registers
as the sensor's `contact_source`, and the database contacts behind the foot lock
(Holden's contact labels) replace the height guess. A contact flickering inside
a 0.1 m print (the `SnowFootModifier` lock reach) is the same step; the print
holds until the foot has left it. The tree path is untouched: its plants are
identical per segment and its numbers below unchanged.

Print slide in TestScene snow, four-scale means, m/s:

| segment | tree | MM before | MM after |
| --- | --- | --- | --- |
| walk forward | 0.443 | 1.008 | 0.348 |
| smooth curve left | 0.480 | 1.139 | 0.348 |
| walk | 0.458 | 0.974 | 0.379 |
| stop | 0.224 | 0.618 | 0.553 |
| start 90 deg right | 0.778 | 1.259 | 0.607 |
| sharp reversal | 0.749 | 1.054 | 0.375 |
| walk after sprint | 0.623 | 1.091 | 0.573 |
| half stick | 0.261 | 0.773 | 0.243 |

Plants on bare ground (tree / MM before / MM after): walk forward 8 / 15 / 9,
curve 4 / 9 / 6, walk 3 / 7 / 4, walk after sprint 6 / 11 / 6.

In the drift Motion Matching keeps the pose (weight 0.99 while walking at
~0.85 m/s), the wade gait engages as with the tree (0.18–0.19), and print
slide matches the tree (0.34 / 0.36 against 0.32 / 0.40 in and out); planted
slide is lower (0.32 / 0.37 against 0.36 / 0.44). Stops stay worse (handover).

Left: during a tree ↔ Motion Matching handover the crossfaded pose can drag a
foot fast enough for the height rule to plant twice (3 extra plants at the
sprint handover); inertialized handovers (follow-up 6) remove the cause. Deep
open snow does not exist in the game (settled cover tops out at 0.25 m); wading
happens in drifts, which the drift program covers.

## Run data (follow-up 5, part 1)

- 36 CMU run trials staged with their index titles (`run_pool`, `run_turn_pool`
  in `prepare_cmu_sample.sh`): 02_03, 09_01–09_11, 16_08/16_57 (sudden stop),
  16_35–16_56 jog/run and veers, 35_17–35_26. They cross the capture volume in
  1.1–2.2 s at 2.0–4.1 m/s.
- The curator labels forward running from 2.2 m/s (`run_f`, `turn_run`; too
  fast only above 5 m/s) and keeps a whole short capture of at least 1 s as one
  window; the builder no longer drops such whole ranges.
- **Future trajectories were faked as stops** at every clip end:
  `track_index` clamps, so the last 0.8 s of each source (556 samples, 4.8% of
  v7, mostly the game-pace walks) had a shrinking future. The baker now uses
  `MotionRetargeter.root_position_at`, which continues past the end at the last
  0.25 s velocity (UE5 Pose Search root-motion extrapolation; slower than
  0.1 m/s counts as standing). Lab at 0.55–1.0 m/s, v7 → v8 without runs: drawn
  0.057 → 0.043, animated 0.198 → 0.173 m/s.
- **The audit refused every run**: `feet_above_pelvis` compared the hips with
  the higher foot, and a running swing heel kicks up to within 0.4 m of them.
  Rendered diagnostics (09_01, 35_25, 16_45) show clean strides. The check now
  keeps the supporting (lower) foot a leg below the hips and fails any foot
  above them. 16_55 is still cut (leans past 35°).
- Database `root-space-v8` (v9 since the gait fix): 12 490 samples, 86 ranges (29 running), 8.1 MB,
  covered speed 3.58 m/s (was 1.75).

Four-scale in-game means (data-matched body):

| segment | tree | MM v7 | MM v8 + runs |
| --- | --- | --- | --- |
| walk forward | 0.604 | 0.671 | 0.652 |
| smooth curve left | 0.555 | 0.542 | 0.530 |
| walk | 0.537 | 0.465 | 0.466 |
| stop | 0.260 | 0.493 | 0.579 |
| start 90 deg right | 0.815 | 0.673 | 0.694 |
| sharp reversal | 0.676 | 0.586 | 0.558 |
| sprint | 2.628 | 2.514 | 1.454 |
| walk after sprint | 0.724 | 0.935 | 0.686 |
| half stick | 0.332 | 0.274 | 0.275 |
| whole run | 0.507 | 0.539 | 0.474 |

Motion Matching's share of the sprint segment went 0.10 → 0.76 and the
sprint-to-walk handover mostly disappeared. Stops stay worse (idle handover).

## Sprint build-up and fatigue (follow-up 5, part 2)

Production gameplay, flag on or off. Before, tiredness never touched the sprint:
it built up the same at any energy and ran at full speed until stamina hit
zero, then stopped. `MovementController` (group "Sprint and fatigue") now has
the mechanism:

- the build-up time constant grows with tiredness (`FatigueComponent`
  energy): ×1 rested, ×`exhausted_sprint_ramp_factor` at no energy;
- below `winded_stamina_ratio` stamina the top sprint fades towards
  `winded_sprint_share` of the sprint's extra speed, so Henry slows into a
  laboured jog before stamina runs out instead of hitting a wall.

**Tuning awaits the author.** The defaults are neutral (factor 1.0, share 1.0):
the sprint is the old one at any energy and stamina. The proposed values are
×2.0 build-up at no energy, winded below 30% stamina, 40% of the extra speed
left on an empty tank.

Measured (`tests/systems/test_sprint_fatigue.gd`, real Player, 8 s sprints):

| state | defaults: 90% after / top | proposed: 90% after / top |
| --- | --- | --- |
| rested, full stamina | 1.87 s / 4.50 m/s | 1.87 s / 4.50 m/s |
| no energy | 1.87 s / 4.50 m/s | 3.77 s / 4.45 m/s |
| winded, 10% stamina | — / 4.50 m/s | — / 3.30 m/s |

The reference is The Long Dark, where fatigue shortens and weakens the sprint.

## Handovers and held props (follow-up 6)

Measured first: one in-game run split by phase (MANN skating, data body, v8):

| phase | frames | mean m/s | share of skating |
| --- | --- | --- | --- |
| tree ↔ Motion Matching handover | 3% | 1.42 | 12% |
| switch crossfade inside matching | 45% | 0.25 | 29% |
| steady matching | 29% | 0.38 | 29% |
| tree | 23% | 0.51 | 30% |

Handovers were the worst frames by far; switch crossfades were not worse than
steady playback, so they stay. Causes and fixes:

- **Stop into the tree's idle.** During the fade-out the matcher kept
  switching; the new clip released a planted foot, which slid at 1.4–3.2 m/s
  at ground height while the poses blended. Then the lock's 0.2 m leash
  (Holden's, meant for moving feet) dragged a held foot towards the tree
  idle's stance, which is farther away. Now, settling to stand freezes the
  search and locks both feet (standing still is two planted feet); while the
  tree stands Henry still, `hold_feet` keeps them on their spots with a leash
  of a leg's reach (0.5 m); an action, carry or jump releases them through
  the lock's inertialized decay; matching taking over again keeps them.
  Henry stands where he stopped.
- **Start from standing.** A matched swing foot crossfaded with the idle's
  planted foot dragged low over the ground. From standing, matching now takes
  the pose at once and the tree's difference decays (Bollo's inertialization,
  Gears of War; Holden's `inertialize_pose_transition`). From motion (after a
  tree-owned sprint) the inertialized entry was worse (walk after sprint
  0.69 → 0.84), so that handover keeps its crossfade.
- **Held props** no longer hand the whole body to the tree: the socket arm's
  bones (the held-pose filter) stay the tree's by the hold weight, matching
  walks the rest. `tests/systems/test_motion_matching_hold_layer.gd`: with a
  held light the weight stays 1.0 (was 0.0) and the hand stays raised
  (lowest 1.38 m against 0.84 m swinging).

Four-scale in-game means (data body):

| segment | tree | MM before | settle + hold | + entry (default) |
| --- | --- | --- | --- | --- |
| idle | 0.009 | 0.009 | 0.002 | 0.001 |
| walk forward | 0.604 | 0.652 | 0.629 | 0.628 |
| smooth curve left | 0.555 | 0.530 | 0.530 | 0.582 |
| walk | 0.537 | 0.466 | 0.466 | 0.501 |
| stop | 0.260 | 0.579 | 0.306 | 0.227 |
| start 90 deg right | 0.815 | 0.694 | 0.661 | 0.558 |
| sharp reversal | 0.676 | 0.558 | 0.558 | 0.600 |
| sprint | 2.628 | 1.454 | 1.454 | 1.497 |
| walk after sprint | 0.724 | 0.686 | 0.685 | 0.685 |
| half stick | 0.332 | 0.275 | 0.275 | 0.275 |
| stop, idle | 0.082 | 0.126 | 0.047 | 0.047 |
| whole run | 0.507 | 0.474 | 0.439 | 0.438 |

Settle and hold change only standing segments. The entry's direct effect is
start 90° (it starts from standing): 0.66 → 0.56; curve, walk and reversal come
much later and differ by a changed clip chain (±0.05). `HOARBOUND_MM_INERTIAL_ENTRY=0`
restores the crossfade for A/B.

## Gait symmetry: the left-leg limp (after #205)

Reported on a manual Key West review: Henry seems to limp on the left leg in plain
walking. Measured with `capture_motion_matching_player.gd`, `MM_PROGRAM=walk`
(9 s out, 9 s back) and `MM_GAIT_TRACE=1` (per-frame feet, pelvis, clip, locks),
four stick scales, about 100 steps per run set.

| metric (steady walking) | AnimationTree | Motion Matching v8 | v9 |
| --- | --- | --- | --- |
| step length SI, planted-foot positions | -0.5% | **+6.7%** | +6.3% |
| step time SI, stance starts | -1.2% | **+8.7%** | +7.5% |
| half-stride time SI, pelvis minima | +1.1% | **+9.5%** | +9.7% |
| pelvis peak over left minus right | -2.1 mm | **-8.5 mm** | -8.8 mm |
| stance ankle height left / right | | 101.0 / 103.6 mm | 101.1 / 101.6 mm |

SI = 200 (L - R) / (L + R). Positive: the step onto the left foot is longer and
slower, and the body rides lower over the left leg: a mild left limp.

Where it comes from:
- **Not the runtime.** With the foot lock off (`MM_FOOT_LOCK=0`) pelvis and
  timing are identical; matching, crossfades and the lock carry the motion as is.
- **Not the retarget's timing or placement.** Offline, Henry's planted-foot
  positions match the source within 0.5 points of SI for every clip.
- **The source.** All steady walking at Henry's 1.5 m/s plays CMU subject 39.
  Measured on the raw BVH, 13 of its trials are left-long: step length +3.1%,
  step time about +7.7% on average (per-trial spread about 4 points).
- **A retarget leak, now fixed (v9).** Subject 39's skeleton has a left leg
  4.9 mm shorter. The retarget copies the pelvis height onto Henry's equal legs,
  so his left stance foot stood lower. `MotionRetargeter` now measures each
  side's planted ball height and shifts the pelvis by its offset, blended by
  which ankle carries the weight. Offline, subject 39's stance-height gap fell
  from 2-5 mm to 0.2-1.6 mm and its pelvis asymmetry from -6.4 to -3.8 mm. In
  game the stance feet are level; the limp itself is the source gait above.
- A survey of 138 CMU walking trials (`MM_GAIT_TRACE` metrics on the raw BVH,
  steady straight spans) found no subject at that pace symmetric in timing,
  step length and pelvis bob at once. Subject 16 steps evenly but its pelvis
  bob differs by about 15 mm side to side.

Open for the author: the remaining asymmetry is the recorded person's gait.
Removing it needs data, not a pose edit: mirrored walking cycles (standard in
Motion Matching pipelines, currently ruled out), or a different walking subject.

## Follow-up fixes, in order

1. ~~Distance-based braking for scripted walks.~~ Done.
2. ~~Per-state dynamics.~~ Done: data rates for walking only (author may tune
   sprint/air/carry separately later).
3. ~~Jump rework, including the walk-start hop and real landing ownership.~~
   Done (see "Airtime and landing"); jump height and feel stay with the author.
4. ~~Snow and wading with Motion Matching.~~ Done (see "Snow and wading").
5. ~~Run data and sprint build-up with fatigue.~~ Done (see "Run data" and
   "Sprint build-up and fatigue").
6. ~~Inertialization for switches and handovers; an arm layer for held
   props.~~ Done (see "Handovers and held props").
7. ~~Hardening: movement-owned dynamics, neutral fatigue defaults.~~ Done
   (see "Dynamics contract" and "Sprint build-up and fatigue").

## Not covered yet

- Sprint above 3.94 m/s (CMU's fastest run is ~4.1 m/s; Henry sprints at 4.5),
  crouch, carry, slopes, stairs.
- Gait-specific normalization or databases (UE5 Pose Search chooser): with run
  data in the same database the walking lab drifts back to its v7 level.
- Inertialized switches inside Motion Matching: their 0.2 s crossfades skate
  less than steady playback in this metric (0.21–0.26 against 0.38 m/s), so
  they were left as they are.
- 100STYLE (host blocked from this environment).

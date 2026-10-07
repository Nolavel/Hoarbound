# Motion Matching — Player integration (#202)

Status: integration layer implemented behind a flag, **off by default**.
Production locomotion (`HenryUALAnimation` AnimationTree + `MovementController`
+ `Player`) is unchanged while the flag is off.

## Switching it on

- `Player/MotionMatchingLocomotion.enabled` (export), or the environment
  variable `HOARBOUND_MOTION_MATCHING=1`.
- The node loads the committed database
  `data/motion_matching/henry_cmu_locomotion.res` (7.3 MB compressed, CMU only;
  author decision, 2026-10-07). Without it, it rebuilds from staged CMU sources
  (development only); failing that it logs `unavailable` and the AnimationTree
  keeps locomotion.
- `tools/runtime/audit_motion_dataset.gd` rebuilds from the sources and exits 4
  when the committed file differs from the rebuild; `MM_WRITE_DATABASE=1`
  rewrites it. The CI Motion Matching job runs that check.
- `data_matched_body` is on (author decision, 2026-10-07): while the node runs,
  the body accelerates at 3 m/s², brakes at 3.5 m/s² and turns at rate 4.
  `HOARBOUND_MM_DATA_BODY=0` restores the production dynamics for A/B work.

## Runtime ownership

```text
Player._physics_process (unchanged)
  input -> MovementController (velocity) -> move_and_slide -> body is authoritative
  HenryUALAnimation.update_animation_blend/state/head_look (unchanged)
        |
MotionMatchingLocomotion._physics_process (child of Player, runs after it)
  AnimationTree.advance(dt)                       tree pose first (MANUAL mode)
  gate: plain locomotion (the tree's verdict: no air or landing state, no
        action/carry/sit/crouch), speed <= covered speed, not standing still > 0.6 s
  weight -> 1 / 0 over 0.25 s (handover)
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

The tree keeps: actions and work poses, held props (`hold_pose`), carry, sit,
crouch, jump take-off, airtime and landing (its air states after the 0.15 s fall
timeout), sprint above the covered speed (1.75 m/s, database p99), and idle after
0.6 s standing still.
Neck and head stay with the tree clip and the `LookAtModifier3D` head look
(author decision).

Prediction mirrors the production body exactly: `MovementController`'s
constant-rate approach to its target velocity and `Player`'s exponential turn.
Additive hooks only: `MovementController.get_target_velocity()` /
`get_velocity_rate()` and `HenryUALAnimation.is_plain_locomotion()`, which now
also covers the air and landing states (follow-up 3).

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
3. **Sprint** stays with the tree (no run data in the database yet); its foot
   skating is 2–5 m/s in this metric.
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

## Follow-up fixes, in order

1. ~~Distance-based braking for scripted walks.~~ Done.
2. ~~Per-state dynamics.~~ Done: data rates for walking only (author may tune
   sprint/air/carry separately later).
3. ~~Jump rework, including the walk-start hop and real landing ownership.~~
   Done (see "Airtime and landing"); jump height and feel stay with the author.
4. ~~Snow and wading with Motion Matching.~~ Done (see "Snow and wading").
5. Run data and sprint build-up with fatigue (`StaminaManager`).
6. Inertialization for switches and handovers; an arm layer so held props do
   not hand the whole body back to the tree.

## Not covered yet

- Run/sprint data, crouch, carry and held-prop arm layering, slopes, stairs.
- Inertialization instead of crossfade for switches and handovers.
- 100STYLE (host blocked from this environment).

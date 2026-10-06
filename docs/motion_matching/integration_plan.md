# Motion Matching — Player integration (#202)

Status: integration layer implemented behind a flag, **off by default**.
Production locomotion (`HenryUALAnimation` AnimationTree + `MovementController`
+ `Player`) is unchanged while the flag is off.

## Switching it on

- `Player/MotionMatchingLocomotion.enabled` (export), or the environment
  variable `HOARBOUND_MOTION_MATCHING=1`.
- The database is built from the staged CMU sources
  (`tools/ci/prepare_cmu_sample.sh`) and cached in
  `tests/motion_matching/_runtime_cache/` (both ignored by Git). Without it the
  node logs `unavailable` and the AnimationTree keeps locomotion.
- Shipping the baked database (~11 MB, derived from CMU, "free for all uses")
  is an open decision for the author: commit the derived resource, or bake it
  in the build pipeline.

## Runtime ownership

```text
Player._physics_process (unchanged)
  input -> MovementController (velocity) -> move_and_slide -> body is authoritative
  HenryUALAnimation.update_animation_blend/state/head_look (unchanged)
        |
MotionMatchingLocomotion._physics_process (child of Player, runs after it)
  AnimationTree.advance(dt)                       tree pose first (MANUAL mode)
  gate: grounded (airtime <= 0.2 s), plain locomotion, speed <= covered speed,
        not standing still > 0.6 s
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
crouch, jump take-off and real airtime (landing plays 0.4 s), sprint above the
covered speed (1.75 m/s, database p99), and idle after 0.6 s standing still.
Neck and head stay with the tree clip and the `LookAtModifier3D` head look
(author decision).

Prediction mirrors the production body exactly: `MovementController`'s
constant-rate approach to its target velocity and `Player`'s exponential turn.
Additive hooks only: `MovementController.get_target_velocity()` /
`get_velocity_rate()` and `HenryUALAnimation.is_plain_locomotion()`.

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

| segment | tree | MM | MM + data-matched body |
| --- | --- | --- | --- |
| idle (tree owns idle) | 0.009 | 0.009 | 0.009 |
| walk forward (start from idle) | 1.137 | 0.849 | 0.782 |
| smooth curve left | 0.603 | 0.689 | 0.671 |
| walk | 0.594 | 0.598 | 0.626 |
| stop | 0.298 | 0.473 | 0.255 |
| start 90 deg right | 1.411 | 0.928 | 1.135 |
| sharp reversal | 0.649 | 0.992 | 0.553 |
| walk after sprint | 1.082 | 0.933 | 0.841 |
| half stick | 0.344 | 0.220 | 0.341 |
| whole run | 0.680 | 0.614 | 0.578 |

With Motion Matching keeping idle (`idle_to_tree_seconds = 0`) the start from
idle scores 0.569 but idle itself 0.185: CMU standing ranges are short and the
matcher hops between them and pivot-capture standing frames (111_28 alone is
0.005–0.012 in the data).

## Findings that need the author

1. **Body dynamics vs. captured humans.** The production body accelerates at
   12 m/s², brakes at 18 m/s² and starts a 90° turn at ~15 rad/s; the CMU data
   is at 1.8 / 1.9 m/s² (p95) and 2.7 rad/s (p99). No real motion matches a
   0.07 s stop, so starts, stops and reversals clamp and drag. This is Holden's
   "code vs data driven displacement" choice and a game-feel decision:
   `data_matched_body` (opt-in) tries 3 / 3.5 m/s² and turn rate 4.
2. **Production defect found on the way:** every walk start applies
   `start_jump_impulse`, the body leaves the floor for one tick and the tree
   plays AirLoop → Land (~1.3 s landing clip while walking). Visible in the
   in-game video. Not fixed here: it belongs to the jump rework.
3. **Sprint** stays with the tree (no run data in the database yet); its foot
   skating is 2–5 m/s in this metric.
4. **Snow and wading** with Motion Matching are untested (next stage).

## Not covered yet

- Run/sprint data, crouch, carry and held-prop arm layering, slopes, stairs.
- Inertialization instead of crossfade for switches and handovers.
- 100STYLE (host blocked from this environment).

# Motion Matching — progress and regression ledger (#202)

Evidence-based status. A green workflow alone never moves an item up.

## Visually rejected by the author (after #206, 2026-10-07)

- CMU → Henry UAL retarget (`SourceRetargetProfile.cmu_bvh` + `MotionRetargeter`)
  and Motion Matching on top of it: wrong torso lean, pinned arms, poor running,
  twitching legs, knees bending backwards. Six clips side by side and a clean
  `MotionRetargetAudit` were not enough. The profile is now `verified = false`.
- Mirrored walking (`root-space-v10`): fixed the limp metric, not the motion.
  Frozen as a regression reference; not a baseline.
- Work is frozen until the gates in `acceptance_gates.md` pass.

## Mechanically working (no visual acceptance)

- Root-space pose storage: no yaw pops on cross-clip switches (#477 defect).
- All-frame brute-force search returning exact `clip @ time` + sample index,
  no role gate; trajectory and facing are independent query channels.
- Pure playback of one range reproduces the data's own foot slide
  (0.075 vs 0.079 m/s) — playback/root motion are consistent.
- Foot locking (`MotionFootLock` + `LegTwoBoneIK`): lab A/B with identical
  matching, drawn planted slide 0.184 → 0.032 m/s; top-down ankle traces and
  side-by-side video. Query reads the pose before the lock.
- Brisk walking coverage: 31 CMU natural walks at 1.4–1.75 m/s (index titles),
  database p99 root speed 1.75 m/s (was 1.05), audit clean.

## Mechanically working, visually disputed

- Run #477 (`cefe6a1`, 100STYLE + CMU at the wrong unit): green Action, rejected
  by the owner; root causes found (unit, world yaw in poses, segment-end
  freeze). Kept here as the regression reference.

## Regressed / rejected

- Holden's hard unlock at 0.2 m: the foot snapped back ~20 cm in ~0.2 s.
  Replaced by a drag at the radius plus a reach pull.
- IK length buffer applied to an already straight leg: it lifted idle feet by
  ~1 cm. The buffer never shortens an animated leg now.
- Rotation adjustment limited only by the clip's own angular speed: in game the
  visual stayed 63° off the body for seconds on a straight sideways clip.
  Added UE5-style steering (≤ 2 rad/s while the clip moves).
- Matched pose over the AnimationTree without resetting bone translations:
  idle feet floated 2–3 cm (the tree's `root` translation leaked in).
- Global `RetargetModifier3D` via an un-reset proxy (#476): Henry horizontal.
  Cause: proxy poses never reset to rest, not the global formula.
- Lab body via `move_and_slide()` outside the physics tick: body moved 2–3×
  slower than the simulation, clamping dragged the animation.
- Query trajectory predicted from the animation's own velocity: lag loop, no
  backward transition. Replaced by the simulation-led query.
- Per-axis feature normalization: near-constant pelvis x/z dominated the cost,
  Henry stuck in idle. Replaced by per-quantity normalization.
- 4 s role windows: no direction transitions in the data. Replaced by 8 s
  windows with transition budget.

## Experimental

- Spring simulation + adjustment/clamping playback, two-slot crossfade,
  pose-jump threshold, pose reselect history, contact features (lab).
- Curated 11.3 k-sample CMU database (rebuilt from staged sources, not in Git).
- 100STYLE profile (unverified, refused by the builder).

## Integrated behind a flag (off by default)

- `MotionMatchingLocomotion` under Player: body authoritative, tree owns
  actions/carry/sit/crouch/air/sprint/long idle, neck/head with head look.
  Loads the committed `data/motion_matching/henry_cmu_locomotion.res` (audit
  fails when it drifts from a rebuild); `data_matched_body` on by author
  decision. In-game numbers, known conflicts and follow-ups: `integration_plan.md`.

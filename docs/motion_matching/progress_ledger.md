# Motion Matching — progress and regression ledger (#202)

Evidence-based status. A green workflow alone never moves an item up.

## Proven working (code + data + visual evidence)

- CMU → Henry UAL retarget (`SourceRetargetProfile.cmu_bvh` + `MotionRetargeter`):
  six clips checked side by side (raw / root-normalized / Henry) and by
  `MotionRetargetAudit`; feet on the ground (median error within ±3 cm).
- Root-space pose storage: no yaw pops on cross-clip switches (#477 defect).
- All-frame brute-force search returning exact `clip @ time` + sample index,
  no role gate; trajectory and facing are independent query channels.
- Pure playback of one range reproduces the data's own foot slide
  (0.075 vs 0.079 m/s) — playback/root motion are consistent.

## Mechanically working, visually disputed

- Run #477 (`cefe6a1`, 100STYLE + CMU at the wrong unit): green Action, rejected
  by the owner; root causes found (unit, world yaw in poses, segment-end
  freeze). Kept here as the regression reference.

## Regressed / rejected

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

## Experimental (lab only)

- Spring simulation + adjustment/clamping playback, two-slot crossfade,
  pose-jump threshold, pose reselect history, contact features.
- Curated 9.2 k-sample CMU database (rebuilt from staged sources, not in Git).
- 100STYLE profile (unverified, refused by the builder).

## Ready for integration

- Nothing yet. See `integration_plan.md` for the proposed layer and open
  decisions (gaze ownership, foot locking, 100STYLE).

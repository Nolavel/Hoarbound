# Motion Matching — acceptance gates (#202)

Status (2026-10-07): **frozen**. The author reviewed Motion Matching on `main`
`3f67c9b` (PR #206) and rejected it visually: wrong torso lean, arms pinned to
the body with almost no swing, running worse than the AnimationTree, twitching
legs, knees that sometimes bend backwards, physically wrong poses and
transitions. Symmetry and slide metrics are not acceptance.

Rules while frozen:

- Motion Matching stays **off by default**; nothing new reaches `main` without
  the author's visual approval.
- No new database version, no wider mirroring, no matcher cost work.
- `root-space-v10` is a frozen regression reference, not a baseline.
- Work happens in `claudeflow` only.

## How a gate is passed

A gate passes only on the author's explicit visual approval, recorded below with
date, commit SHA and a link. CI and metrics are supporting evidence only. A
matching segment direction never counts without roll/twist and joint-plane
(pole) agreement.

Every gate review ships:

- a quad video (front, side, rear, close-up of the feet at knee height);
- the source and Henry side by side or overlaid;
- `metrics.json` from `MotionAnatomyMetrics`;
- a checklist of the author's defects: torso lean, clavicles, shoulder roll,
  elbow plane, arm swing, hands; hip twist, knee plane, shin roll, ankle,
  ball/toe, heel strike, knee never backwards.

## Gates

| Gate | What is checked | Input | Exit |
| --- | --- | --- | --- |
| A | Source: the raw capture is a normal human walk | raw BVH/FBX + FK oracle | author approves the clip |
| B | One clip retarget-only: no matcher, switching, mirroring, crossfade, inertialization, foot lock, IK, steering or root adjustment | one approved clip | author approves Henry |
| C | ≥ 5 clips through one retarget setup, no per-clip tuning | approved clips | author approves; then `verified = true` with `visual_approval` |
| D | Matcher, walking only: idle → walk → stop | walk-only database | author approves |
| E | Directions: back, strafes, diagonals, pivots | directional clips | author approves |
| F | Run and jog | run clips | author approves; must not be worse than the tree |
| G | Production Key West: the author plays it, A/B against the AnimationTree | full database | author approves enabling |

## Record

| Gate | Date | SHA | Approval |
| --- | --- | --- | --- |
| — | — | — | none yet |

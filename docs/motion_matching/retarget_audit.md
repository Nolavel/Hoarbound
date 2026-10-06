# Motion Matching — source retarget audit

Issue: #202. Owner of the conventions in code: `SourceRetargetProfile`
(`scripts/experimental/motion_matching/source_retarget_profile.gd`).

Every source family has its own measured profile. There is no shared flag set
that "almost works" for several skeleton families.

## Pipeline

```text
BVH file ──BVHClip (parse + FK, profile units)──► source model space (meters)
   │
   ├─ yaw alignment: measured reference forward → UAL forward (+Z)
   ├─ simulation root (Holden): hips projected on the ground, Savitzky–Golay
   │  0.5 s / order 3; heading = across-vector (hips + shoulders) × up,
   │  Savitzky–Golay 1.0 s / order 3
   ├─ root-space source pose: every joint expressed relative to that root
   ├─ rotations: model-space rest delta, per mapped bone
   │      T_k = S_j · R_j⁻¹ · G_k
   │  (S = source global, R = aligned source reference global,
   │   G = UAL global rest) — the formula of Godot RetargetModifier3D global
   │  mode (`cache_bone_global_rests`), without proxy skeleton or signal copy
   ├─ reference matching: arms/legs segment-aligned to the UAL T-pose;
   │  feet calibrated flat-to-flat from measured stance frames
   ├─ pelvis translation: UAL rest + leg-length-scaled source hips offset
   │  (sway and height); bone lengths stay Henry's
   └─ root motion scaled by Henry leg / source leg
          │
          ▼
canonical Henry UAL pose stream (root space, Henry meters)
```

Unmapped source joints (CMU `Neck`, `LHipJoint`; 100STYLE `Chest3`) still
contribute, because each target bone reads its source *global* rotation.

## Families

### CMU Graphics Lab (BVH conversion `una-dinosauria/cmu-mocap`) — VERIFIED

| Property | Value | Evidence |
| --- | --- | --- |
| Units | 1/0.45 inch → `0.0254 / 0.45 = 0.056444` m | ASF `units length 0.45`; all 51 staged clips give hips 0.81–1.02 m, walks 0.6–1.3 m/s |
| Axes | Y-up, right-handed | reference toes point +Z, left hip at +X |
| Forward | +Z in the reference pose | measured agreement ≥ 0.999 on every clip |
| Channels | root 6 (`Xposition Yposition Zposition Zrotation Yrotation Xrotation`), joints 3 (`ZYX`) | header |
| Rotation composition | `R = Rz · Ry · Rx` (channel order, column vectors) | BVH convention |
| Root translation | absolute capture position, floor ≈ y 0 | toe heights in stance ≈ 0 |
| Reference pose | frame 0 = synthetic T-pose (all rotations 0, legs vertical via the conversion) | legs 1° from vertical, arms 8° below horizontal on all 51 clips |
| Frame 0 | not motion; motion starts at frame 1 | as above |
| Hierarchy | 31 joints: Hips, L/RHipJoint, Up/Leg/Foot/ToeBase, LowerBack, Spine, Spine1, Neck, Neck1, Head, L/R Shoulder/Arm/ForeArm/Hand + finger/thumb ends | header |
| Known data artifact | occasional 1–3 frame toe/foot marker glitches (e.g. `09_12` 7.80 s, toe −45°) | raw channel trace; curator excludes ±0.25 s around any > 20 rad/s joint jump |

Gaze is task-contaminated in the "navigate" captures: head forward tilt
(Head → End Site against the heading frame) is 50–88° for subject 41
(41_02, 41_05), 24–42° for subject 40, 5–33° for subject 09 and 6–10° for the
standing subject 111. The subjects watched floor marks; this is source truth,
not a retarget error, and is reproduced faithfully on Henry. Author decision:
the production head-look layer owns `neck_01`/`Head` at playback; the baked
data keeps the source gaze.

Rest deltas against UAL (model space, degrees): thigh 1.1, calf 4.7,
upper arm / forearm 8.0 (aligned by the profile); foot ankle→ball pitch differs
by joint placement only and is calibrated flat-to-flat from stance data.

### 100STYLE (Ian Mason, CC BY 4.0) — NOT VERIFIED

CI run 37431589341 (diagnostics only, never baked) measured on the real files:
mapping matches, reference forward agreement 1.000, zero-rotation pose is a
T-pose (upper arm 1.0°, thigh 0.4°, calf 4.7° from UAL), scale 0.954.
`Neutral_SW` passes the audit (ground median −0.5 cm); `Neutral_TR1` has 12
`not_upright` samples (torso > 35° from vertical) still to be inspected.

The profile in code (`style100_bvh`) records the *assumed* conventions:
centimetres, zero-rotation offsets as reference, frame 0 is motion, joint names
Hips/Chest…Chest4/Neck/Head/Collar/Shoulder/Elbow/Wrist/Hip/Knee/Ankle/Toe.
It is marked `verified = false` and the database builder refuses it.

Reason: this environment cannot reach the source host (`drive.google.com`,
`zenodo.org` are blocked by the session network policy), so neither the
hierarchy nor the reference pose could be measured here. The earlier claim
that the local retarget "proved" 100STYLE is withdrawn; the horizontal Henry
of run #476 was caused by the old proxy skeleton never being reset to its rest
pose (UAL `root` bone at identity instead of −90° X), not by global retarget.

To verify: stage the two pinned files, run
`tools/runtime/capture_motion_retarget_diagnostics.gd -- 100STYLE:Neutral_SW
100STYLE:Neutral_TR1` (the diagnostics tool ignores `verified`), compare
columns 1-2-3 and the audit, run `audit_motion_dataset.gd` with
`MM_ALLOW_UNVERIFIED=1`, and only then flip `verified`.

### Rokoko / FBX

Not part of the Motion Matching database. The `rokoko_ual_retarget_lab` spike
remains a separate import experiment.

## Structural audit (`MotionRetargetAudit`)

Per 30 Hz sample of every baked range: finite values, unit quaternions,
orthonormal bases (det ≈ 1), unchanged UAL bone lengths, head above pelvis
(> 0.35 m), feet below pelvis (> 0.40 m), torso within 35° of vertical, pelvis
tilt < 45°, chest yaw within 75° of root forward, feet not collapsed (> 6 cm),
no knee bending backwards, per-bone angular speed < 20 rad/s, and ground error
of the lowest ball joint (median within ±6 cm, 5th percentile above −8 cm).
Thresholds are anatomical limits, not fitted to a clip.

`tools/runtime/audit_motion_dataset.gd` runs the gate headless;
`tools/runtime/capture_motion_retarget_diagnostics.gd` renders the three
columns (raw source / root-normalized source / Henry) per clip.

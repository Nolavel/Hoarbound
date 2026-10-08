# Motion Matching — retarget backend comparison (#202, Phase 2)

One clip per source, retarget-only (no matcher, lock, IK or root motion), 30 Hz,
the same metrics and quad captures as Phase 1 (`retarget_bisection.md`).
Henry's own clips (`Walk_Loop`, `Jog_Fwd_Loop`) are the reference envelope.

## Backends

| | What | Code |
| --- | --- | --- |
| B1 | Current custom retarget (`STAGE_ALL`), the path behind the frozen v10 database | `MotionRetargeter` |
| B2 | Godot `RetargetModifier3D`, global mode: source `Skeleton3D` built from the BVH with the profile reference as rest, proxy with Henry's rests, heading taken out of the source root as in B1 | `scripts/experimental/motion_matching/retarget_backends/modifier_retarget_backend.gd` |
| B4 | Custom v2: B1 plus `STAGE_NEUTRAL_POSE`, `STAGE_TWIST_SPLIT`, `STAGE_SPINE_CHAIN` (all off by default) | `MotionRetargeter` |
| B3 | Blender offline retarget: not run. B4 output can be baked to Henry-native animations inside Godot | — |

B4 stages and the technique each follows:

- **`STAGE_NEUTRAL_POSE`** — the retarget pose of UE's IK Retargeter.
  - Arms and trunk use a relaxed standing pair as the reference: the source's standing clip (100STYLE `Neutral_ID`, frames from `Frame_Cuts.csv`) and Henry's own `Idle`, both averaged, heading removed.
  - Henry's arm clearance around his coat, bent elbows, wrist and neck carriage therefore come from his own data, not from constants.
  - Fingers keep Henry's standing hand.
  - The elbow and hand also have a straight-elbow reference on the same standing shoulder. The standing elbow bend is blended out as the source elbow flexes towards the anatomical limit (145°), so running arms are not over-bent.
- **`STAGE_TWIST_SPLIT`** — twist distribution for rigs without twist bones. Forearm roll moves from the hand onto the lowerarm (Henry's own clips keep the hand within ±2° of the forearm); the hand's global rotation is unchanged.
- **`STAGE_SPINE_CHAIN`** — UE FK chain "Interpolated". Each spine bone samples the source trunk at its own share of the chain length, so different spine bone counts and proportions do not bend the back.

## 100STYLE `Neutral_FW` (walk, 20 s)

| metric (median unless noted) | source | B1 | B2 | B4 | Henry `Walk` |
| --- | --- | --- | --- | --- | --- |
| arm abduction L / R | 6.7° / 5.6° | 6.7° / 5.6° | 6.8° / 5.6° | 20.1° / 23.2° | 16.7° / 16.8° |
| elbow flexion | 4.2° | 4.2° | 6.1° | 31.3° | 36.2° |
| wrist bend | 7.5° | 8.3° | 7.3° | 26.9° | 28.9° |
| right hand twist on forearm, p5..p95 | — | −20..−15° | −20..−15° | ≈ 0° | −2..−1° |
| neck vs neutral | 23.8° | 23.8° | 23.8° | 7.6° | 9.1° |
| trunk lean vs neutral | 2.2° | 2.0° | 2.0° | 6.5° | 7.8° |
| knee flexion p95 / bend plane p95 | 60.4° / 23.8° | 60.4° / 23.9° | 64.7° / 23.7° | 60.4° / 23.7° | 85.0° / 5.9° |
| hyperextended elbow frames L / R | 4 / 11 | 4 / 11 | 2 / 4 | 0 / 0 | 0 / 0 |

## 100STYLE `Neutral_FR` (run, 20 s)

| metric | source | B1 | B4 | Henry `Jog_Fwd` |
| --- | --- | --- | --- | --- |
| elbow flexion | 107.5° | 107.5° | 118.8° (137° without the straight-elbow blend) | 89.3° |
| arm abduction L / R | 15.8° / 17.9° | 15.9° / 17.8° | 32.2° / 39.3° | 49.5° / 42.8° |
| neck vs neutral | 38.0° | 38.1° | 21.6° | 24.2° |
| hand twist on forearm | — | up to −15° | ≈ 0° | ≤ 5° |

## CMU `39_04` (diagnostic family)

- **`CMU_V2` (`hand ← L/RFingerBase`).** Restores the wrist bend: 2.4° → 25.2° relative to neutral (source 21.3°).
- **Twist split.** Hand twist drops from ±58° to ≈ 0°; the forearm carries the 63° roll.
- **Spine chain.** Spine-bend error drops from 11.7° to 4.2°.
- **No neutral pose.** CMU has no standing clip of the same subject, so its arms stay at 0–2° abduction. CMU remains diagnostic only.

## Findings

1. **B2 is not an alternative.** Godot's `RetargetModifier3D` (global) is the same formula as B1's core and reproduces B1's defects: arms in the coat, hand twist, bowed head. It also skips B1's foot calibration (knee +4°).
   - Local mode measured the same on 100STYLE.
   - The defects come from the reference pose and the bone mapping, not from the solver.
2. **B4 puts Henry's upper body inside his own envelope** while keeping the source's motion relative to its standing pose. Legs are identical to B1.
3. **Still open:**
   - Thigh and calf roll range ~18–19° comes from the source's hip and tibial rotation (Henry's keyframed clips: 0–2°); to be judged on video.
   - 100STYLE walking is slow: 0.73 m/s median against Henry's 1.5 m/s.
   - CMU arms need a neutral pose from the same subject.

## Recommendation

B4 on the 100STYLE family as the retarget for gate B. If the author approves it:
- bake retargeted clips into Henry-native animations offline;
- have the Motion Matching baker read those clips instead of BVH.

Gate B is the author's visual decision (`acceptance_gates.md`).

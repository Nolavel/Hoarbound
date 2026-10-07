# Motion Matching — which layer breaks Henry first (#202, Phase 1)

After the author's visual rejection of #206 (`acceptance_gates.md`), every
layer between the source capture and the drawn Henry was measured with the
same anatomy metrics. Everything below is on `claudeflow` after `c1baff8`.

## Tools

| Tool | What it gives |
| --- | --- |
| `tools/motion/anatomy.py` | Metrics from joint positions in a per-frame body frame (no local axes): signed knee/elbow flexion and bend plane, trunk lean, neck, spine bend, arm abduction/flexion, hand clearance, forearm roll, wrist bend, foot pitch, ball bend; `_rel` variants against the rig's own neutral pose; bone twist about +Y for the UAL rig. `test_anatomy.py`: 5 synthetic checks. |
| `tools/motion/bvh_fk.py` | Independent BVH FK oracle with End Sites. `BVHClip` agrees to 0.00 mm on `39_04` and `69_01`. |
| `tools/motion/gltf_fk.py` | glb FK: Henry's own UAL clips as the reference envelope. |
| `tools/runtime/dump_retarget_layers.gd` + `tools/motion/layer_report.py` | Retarget-only layers L1–L4 against the source (L0) and Henry's `Walk_Loop`/`Jog_Fwd_Loop`. |
| `MotionRetargeter.stages` | `STAGE_SEGMENT_SWING`, `STAGE_FOOT_PITCH`, `STAGE_GROUND`, `STAGE_STANCE`; default `STAGE_ALL`, so baking is unchanged. |
| `capture_motion_matching_player.gd` `MM_POSE_TRACE=<path>` + `tools/motion/trace_report.py` | In-game anatomy per program segment, limit breaks, twitch. |
| `tools/runtime/capture_retarget_quad.gd` | Front / side / rear / feet (or `MM_CLOSEUP=hand`) quad of a retarget-only clip (`CMU:<clip>`), Henry's own clip (`UAL:<clip>`) or an in-game pose trace (`TRACE:<path>`). |

Layers: L0 source, L1 core `S·R⁻¹·G`, L2 + segment swing, L3 + foot pitch,
L4 full `retarget_at` (= the baked database: the audit rebuild matches the
committed v10 bit for bit), L6 + foot lock and `LegTwoBoneIK`, L7 matcher and
crossfades (in game, lock off), L8 in game as shipped.

## Retarget only (CMU `39_04` / `69_01`)

| metric (median unless noted) | source | Henry L4 | Henry `Walk_Loop` |
| --- | --- | --- | --- |
| arm abduction | 1.9° / 2.8° | 1.9° / 2.8° (L1 10°) | 16.7° |
| hand twist on forearm, p5..p95 | — | −58..+50° / −14..+15° | within ±2.2° |
| forearm twist range | — | 0.4° / 0.1° | 28.5° |
| wrist bend vs neutral | 21.3° / 28.6° | 2.4° / 3.0° | 15.4° |
| spine bend vs neutral | −6.6° / 10.0° | 5.3° / 1.4° | 3.7° |
| knee flexion p95 | 73.9° / 54.5° | 73.9° / 54.5° | 85.0° |
| knee bend plane p95 | 11.1° / 11.6° | 11.1° / 11.7° | 5.9° |
| knees bending backwards | 0 | 0 | 0 |

- Legs survive L1–L4: flexion, bend plane and hip swing match the source.
- `STAGE_FOOT_PITCH` moves the relative foot pitch by 5.8° on `69_01`, by design (flat-to-flat).
- Arms, hands and spine are already wrong at L1:
  - **Arm abduction.** The source's absolute arm direction (0–3° from the body) puts Henry's arms into his coat. His own clips hold them at ~17°.
  - **Hand mapping.** The profile maps `hand ← LeftHand`, which is CMU's forearm-twist joint. Pronation becomes a hand-on-forearm twist (candy wrapper), and Henry's forearm never rolls.
  - **Wrist and fingers.** Wrist bend (`LeftFingerBase`) and the fingers are not mapped, so the hand stays straight, flat and open.
  - **Spine.** It is mapped by orientation only: curvature is off by 8–12°.

## In game (TestScene program, 30 s, `--fixed-fps 30`)

| | AnimationTree | MM, lock off | MM as shipped |
| --- | --- | --- | --- |
| knees backwards (moving frames) | 0 | 0 | 6 (left), off-plane 11 / 8 |
| walk: arm abduction | 17.6° | 3.4° | 3.4° |
| walk: hand twist range | 1.0° | 84.9° | 84.9° |
| walk: neck vs neutral | +9.2° | −8.9° | −8.9° |
| walk: trunk lean vs neutral | 7.8° | 3.9° | 3.9° |
| sprint: trunk lean / arm abduction | 28.9° / 47.7° | 14.1° / 9.9° | 14.1° / 9.9° |
| sprint: hip flexion range | 89.5° | 64.3° | 66.5° |

**Knees bending backwards (L6).** At 15.33–15.47 s (`start, 90 deg right`, a clip switch):
- with the lock, the left knee goes +22° → −22° → +20°;
- with the lock off, it stays at +20°;
- worst in that segment: −62°.

`LegTwoBoneIK.reach` takes the bend side from the current knee relative to the hip→**target** line. When the lock holds the foot away from the animated foot, the knee falls on the other side of that line and the solve mirrors it. Standard solvers take the bend plane from a pole: UE Two Bone IK joint target, Godot `TwoBoneIK3D` pole.

**Head thrown back (L8).** The gaze layer writes rest rotations to `neck_01`/`Head`. The head therefore follows the retargeted chest instead of keeping the gaze level.

**Switching.** 33 switches in ~23 s of motion; 40% of moving frames are inside a crossfade. Knee and ankle jerk is not higher near switches than in steady playback, so this metric does not show switches as the source of the twitching.

## First breaking layer

- **L1** (core retarget and the CMU bone map) breaks the arms, hands and spine.
- **Legs** stay correct until **L6** (foot-lock IK).
- **L8** presentation throws the head back.
- **Running** is additionally limited by the CMU run data.

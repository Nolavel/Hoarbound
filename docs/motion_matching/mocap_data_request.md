# Motion Matching — mocap data request (#202)

What production Motion Matching for Henry needs, in the order it is used. Raw
third-party files never go into this repository: they are staged in the
owner's Google Drive (`Hoarbound/Mocap/<source>/`), which Claude reads through
the Drive connector. This session's proxy refuses public `drive.google.com`
and Zenodo, so public download links do not work here.

## Rules for every file

- **License.** Commercial use must be allowed: CC0, CC BY, CMU terms, Mixamo in-project use, or a purchased license.
  - Never: non-commercial, no-derivatives or engine-locked data (LAFAN1, Bandai Namco Research, AMASS, Epic Game Animation Sample / UE-only content).
- **Originals only.**
  - Real root motion, not in place.
  - 60 fps or more where the source has it.
  - No retiming, no mirrored copies, no rotated copies: left and right are separate takes.
- **One performer per source family** for the base locomotion set.
- **`manifest.csv` per folder:** `file, source_url, license, attribution, performer_id, fps, units, up_axis, skeleton, tpose_frame, role, notes`.
- **Batches as one `.zip`** next to the files (BVH text compresses ~5×).
- **Henry's speeds:** walk 1.0–1.6 m/s, jog 2.5–3.5 m/s, sprint 4.5–5 m/s.

## Batch 1 — now (retarget pipeline comparison, gates B/C)

100STYLE, Neutral style (Ian Mason, CC BY 4.0, Xsens, 60 fps, one performer),
https://www.ianxmason.com/100style/:

- `Neutral_BR.bvh`, `Neutral_BW.bvh`, `Neutral_FR.bvh`, `Neutral_FW.bvh`, `Neutral_ID.bvh`, `Neutral_SR.bvh`, `Neutral_SW.bvh`, `Neutral_TR1.bvh`;
- `Frame_Cuts.csv` and `Dataset_List.csv`.

## Batch 2 — 100STYLE styles for Hoarbound's states

Same performer and skeleton, so one retarget profile covers them all.
- The names below are candidates: check them against `Dataset_List.csv`, and skip a missing one rather than substituting another.
- Take every locomotion file the style has (`BR`, `BW`, `FR`, `FW`, `ID`, `SR`, `SW`, `TR*`).

| Style | Hoarbound use |
| --- | --- |
| `StartStop` | starts and stops |
| `Crouched` | crouch locomotion |
| `HandsInPockets`, `ArmsFolded` | cold |
| `BentForward` | walking into wind, exhaustion |
| `Heavyset` | heavy load |
| `Old`, `Depressed` | low vitals |
| `LimpLeft`, `LimpRight` | injury |
| `InTheDark` | careful walking at night or on ice |
| `Rushed` | hurried walking |

## Batch 3 — what 100STYLE does not cover

Find commercial-use sources; propose each with link and license before anything is bought.

1. Planned starts from idle and stops to idle in 8 directions, walk and jog.
2. Pivot turns of 90° and 180°, left and right, at walk, jog and run.
3. Turns in place of 45°, 90°, 135° and 180°, left and right.
4. Circles left and right at walk, jog and run, radius 1–4 m.
5. Jog, run and sprint, with acceleration from walk and deceleration to a stop.
6. Stairs up and down; slopes of 10–30° up and down.
7. Carry: a heavy load in two hands; a lantern or torch in one hand, left and right separately.
8. Deep snow: high-stepping slow walk.
9. Ice: careful balance walk, slip and recovery, stumble.
10. Jumps from standing, walking and running.

Candidate sources:
- **Mixamo** through the owner's account: FBX Binary, "In Place" off, 30/60 fps.
- **Rokoko Motion Library.**
- **Fab or other marketplace mocap locomotion packs** whose license is not limited to Unreal Engine.

## Batch 4 — the owner's existing Drive set

The 38 FBX in `Hoarbound/` need a `manifest.csv` with origin and license per
file:
- especially the `*_ERJA-mvn*` series (which dataset, which license?);
- the `*_MIXAMO_769`, `*_HUMANIK_*` and `*_WHS` exports.

`TongeTwister_HUMANIK_WHS.fbx` is 0 bytes.

## The ideal: one dedicated capture session (owner's decision)

If an inertial suit (Rokoko, Xsens) or an optical studio is possible, this shot
list replaces batches 2–3 for the base set.

- **Performer.** Build close to Henry's. Wears a bulky winter coat and boots: Henry's own clips hold the arms ~17° out to clear his coat, while mocap in light clothes gives 0–3° (Phase 1, `retarget_bisection.md`).
- **Hands.** Gloves or hand tracking, so wrist rotation is real. Fingers are optional.
- **Calibration.** T-pose, A-pose and a range-of-motion take (knees, elbows, wrists, shoulder and hip rotation, spine twist). Record height, leg length and shoulder width.
- **Recording.** 120 fps (60 at least), real root motion, flat floor with marked lines.
- **Takes** (each direction recorded separately):
  1. Neutral idle, 60 s; cold idle (arms hugging, shivering), 60 s.
  2. Walk forward at 1.0 and 1.5 m/s, 2 × 30 m each; backward; strafe left; strafe right; four diagonals.
  3. Starts and stops in 8 directions, walk and jog.
  4. Pivots of 90° and 180°, left and right (walk, jog, run); turns in place of 45–180°, left and right.
  5. Circles left and right, radius 2 m and 4 m, at walk, jog and run.
  6. Jog at 3 m/s; run at 4.5 m/s; sprint from walk with acceleration, then deceleration to a stop.
  7. Two or three "dance card" takes of 2–3 min: walk, jog, stop and turn on called directions.
  8. Crouch idle and crouch walk in all directions; heavy two-handed carry; lantern in the left hand, then in the right.
  9. Stairs up and down; slope up and down; high-step walk; careful ice walk; stumble.
  10. Jumps from standing, walking and running.

## How each batch is used

| Batch | Use |
| --- | --- |
| 1 | Retarget pipeline comparison (Phase 2), gates B and C |
| 2–3, session | Gates D (walk matcher), E (directions), F (run), then state layers |

Nothing enters a production database without the author's visual approval
(`acceptance_gates.md`).

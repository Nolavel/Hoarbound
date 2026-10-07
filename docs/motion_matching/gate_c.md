# Motion Matching — gate C (#202): one retarget setup, six styles

Author's gate B decision (2026-10-07): **conditional pass**.
- B4 is accepted as the upper-body retarget candidate.
- The lower body stays open.
- No Motion Matching database bake and no gate D until the legs are closed; mirroring v10 stays untouched.

## Setup

**Source:** 100STYLE, one performer, eight clips: `Neutral_FW/FR`, `Rushed_FW/FR`, `StartStop_FR`, `Crouched_FW`, `BentForward_FW`, `Old_TR1`.
- Window: 10–30 s of each clip.
- `StartStop_FW` and `Old_FW` are over the Drive connector's 10 MB limit, so their run and transition takes stand in.

**One configuration for every clip**, with no per-style offsets:
- `STAGE_ALL | NEUTRAL_POSE | TWIST_SPLIT | SPINE_CHAIN` (B4), plus `LEG_PLANE` as a variant;
- the standing reference for all styles is `Neutral_ID`, so a style shows as motion relative to the performer's neutral stance.

## Rig contract

`tools/motion/test_rig_contract.py`: in Henry's rig the child joint of `upperarm`, `lowerarm`, `thigh` and `calf` (both sides) lies on the bone's local +Y within 0.1°.

That makes the twist stages pure rolls of the bone:
- `TWIST_SPLIT` rolls the lowerarm about its +Y;
- `LEG_PLANE` rolls the calf about its +Y.

Joint positions do not move.

## Legs: source or retarget?

The anatomy tools now measure the source's own thigh and calf axial roll: relative to the parent, about the segment axis, from the reference pose — the quantity measured on Henry.

On `Neutral_FW`:

| | thigh roll | calf roll |
| --- | --- | --- |
| source | 18.4° | 19.7° |
| Henry B4 | 18.4° | 19.4° |

The knee bend-plane deviation is also the source's (23.8° against 23.7°). So the retarget reproduces the performer's hip and tibial rotation; it does not add it.

Henry's own `Walk` keeps 0–2° roll and a 6° bend plane because it is keyframed.

`STAGE_LEG_PLANE` (opt-in):
- removes the calf's roll on the thigh (Henry's knee becomes a pure hinge);
- the thigh keeps the source hip rotation, which shows in where the knee points;
- joint positions and the foot's global rotation are unchanged;
- the roll moves into the ankle: foot-on-calf twist range 11° → 17°, against 15° in Henry's own `Jog`.

## Results

Units: degrees.
- **Columns:** arm abduction, elbow, wrist, hand twist on the forearm, neck and trunk lean relative to the rig's neutral pose, knee flexion p95, knee bend-plane deviation p95 (L / R), thigh and calf roll range.
- **Last column:** frames with knees bending backwards / elbows hyperextended.

| clip | variant | arm abd | elbow | wrist | hand twist |p95| | neck rel | lean rel | knee p95 | knee plane p95 L/R | thigh roll | calf roll | back knees / elbows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BentForward_FW | source | 9 | 18 | 7 | — | 71 | 37 | 66 | 20 / 23 | 17 | 24 | 0 / 0 |
| BentForward_FW | B4_full | 43 | 40 | 30 | 0 | 55 | 40 | 66 | 21 / 23 | 17 | 24 | 0 / 0 |
| BentForward_FW | B4_legplane | 43 | 40 | 30 | 0 | 55 | 40 | 66 | 21 / 23 | 17 | 0 | 0 / 0 |
| Crouched_FW | source | 6 | 16 | 12 | — | 52 | 28 | 68 | 19 / 23 | 14 | 19 | 0 / 0 |
| Crouched_FW | B4_full | 29 | 41 | 25 | 0 | 35 | 32 | 68 | 20 / 22 | 14 | 18 | 0 / 0 |
| Crouched_FW | B4_legplane | 29 | 41 | 25 | 0 | 35 | 32 | 68 | 20 / 22 | 14 | 0 | 0 / 0 |
| Neutral_FR | source | 17 | 107 | 19 | — | 38 | 14 | 75 | 21 / 21 | 20 | 19 | 0 / 0 |
| Neutral_FR | B4_full | 36 | 119 | 29 | 1 | 22 | 18 | 75 | 22 / 20 | 20 | 18 | 0 / 0 |
| Neutral_FR | B4_legplane | 36 | 119 | 29 | 1 | 22 | 18 | 75 | 22 / 20 | 20 | 0 | 0 / 0 |
| Neutral_FW | source | 6 | 4 | 7 | — | 24 | 2 | 60 | 24 / 16 | 18 | 20 | 0 / 15 |
| Neutral_FW | B4_full | 22 | 31 | 27 | 0 | 8 | 7 | 60 | 24 / 18 | 18 | 19 | 0 / 0 |
| Neutral_FW | B4_legplane | 22 | 31 | 27 | 0 | 8 | 7 | 60 | 24 / 18 | 18 | 0 | 0 / 0 |
| Old_TR1 | source | 12 | 64 | 13 | — | 71 | 33 | 41 | 14 / 13 | 15 | 14 | 0 / 0 |
| Old_TR1 | B4_full | 46 | 80 | 30 | 0 | 54 | 36 | 41 | 15 / 12 | 15 | 14 | 0 / 0 |
| Old_TR1 | B4_legplane | 46 | 80 | 30 | 0 | 54 | 36 | 41 | 15 / 12 | 15 | 0 | 0 / 0 |
| Rushed_FR | source | 21 | 48 | 19 | — | 47 | 20 | 90 | 27 / 24 | 26 | 28 | 0 / 0 |
| Rushed_FR | B4_full | 54 | 68 | 35 | 0 | 31 | 24 | 90 | 30 / 23 | 26 | 27 | 0 / 0 |
| Rushed_FR | B4_legplane | 54 | 68 | 35 | 0 | 31 | 24 | 90 | 30 / 23 | 26 | 0 | 0 / 0 |
| Rushed_FW | source | 19 | 22 | 12 | — | 34 | 10 | 71 | 25 / 25 | 24 | 27 | 0 / 177 |
| Rushed_FW | B4_full | 43 | 50 | 36 | 0 | 18 | 14 | 71 | 28 / 23 | 24 | 27 | 0 / 0 |
| Rushed_FW | B4_legplane | 43 | 50 | 36 | 0 | 18 | 14 | 71 | 28 / 23 | 24 | 0 | 0 / 0 |
| StartStop_FR | source | 14 | 21 | 12 | — | 47 | 15 | 66 | 23 / 17 | 20 | 18 | 0 / 0 |
| StartStop_FR | B4_full | 39 | 47 | 32 | 0 | 30 | 19 | 66 | 24 / 18 | 20 | 18 | 0 / 0 |
| StartStop_FR | B4_legplane | 39 | 47 | 32 | 0 | 30 | 19 | 66 | 24 / 18 | 20 | 0 | 0 / 0 |

## Reading

- **No knee bends backwards in any clip.**
- **Hyperextended elbows are gone.** The source has 15 such frames in `Neutral_FW` and 177 in `Rushed_FW`.
- **Knee flexion and bend plane follow the source per clip.**
- **Hand twist on the forearm is 0–1° everywhere.**
- **Arm abduction is above the walk reference** in bent and hunched styles (`BentForward` 43°, `Old` 46°) and in `Rushed_FR` (54°; Henry's own `Jog` 43–50°). To be judged on the videos.

Gate C is the author's visual decision.

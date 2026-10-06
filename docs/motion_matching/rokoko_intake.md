# Rokoko Motion Intake

Source of truth: private Google Drive folder supplied by the project owner.

This file tracks animation coverage for Motion Matching Lab #2 (#202). Source FBX files are intentionally **not committed** to the public repository. They are ingested from the owner's asset storage, retargeted to UAL/Henry in Godot, and only project-owned metadata/code lives here.

## Intake v1 — 38 FBX observed

### Base locomotion candidates

| Source file | Role | Status | Notes |
| --- | --- | --- | --- |
| `02-walkforward.fbx` | Walk F | candidate | Primary neutral forward-walk ingest test. |
| `20210715_s202_walk_track_tk01_ERJA-mvn325.fbx` | Walk F / trajectory reference | candidate | Standard humanoid names (`Hips`, `LeftUpLeg`, `Spine...`); separate mocap source family but compatible with Godot retarget intake. |
| `10-WalkCycle_01_MIXAMO_769.fbx` | Walk F alt | candidate | Evaluate cadence/foot sliding against Henry. |
| `09-SlowWalkForward_MIXAMO_769.fbx` | Slow Walk F | candidate | Useful for slow/deep-snow locomotion domain later. |
| `01walkforward_walkspline.fbx` | Curved/trajectory walk | reference | Useful for trajectory analysis; not a replacement for authored directional loops. |
| `03-walkspline.fbx` | Curved/trajectory walk | reference | Useful for trajectory analysis; not a replacement for authored directional loops. |

### Idle candidates

These are ambient idles rather than a clean neutral locomotion idle. Keep for later pose diversity, but **neutral Idle is still missing**.

- `Idle_LookingAround_MIXAMO_769.fbx`
- `Idle_LookingAround02_MIXAMO_769.fbx`
- `Idle_WatchingSomething_Loop_MIXAMO_769_segment.fbx`
- `Idle_Chatting_MIXAMO_WHS.fbx`
- `Idle_Chatting02_MIXAMO_WHS.fbx`
- `Idle_Conversation_Loop_MIXAMO_769_segment-2.fbx`
- `Idle_Pointing_MIXAMO_769.fbx`
- `Idle_ListeningtoMusic_MIXAMO_WHS.fbx`
- `Idle_LeaningonWall_MIXAMO_WHS.fbx`
- `Idle_Arguing_MIXAMO_WHS.fbx`

### Later locomotion domains / useful secondary data

| Source file | Later domain |
| --- | --- |
| `20210715_s219_walk_limpCycle_tk01_ERJA-mvn344.fbx` | injured locomotion |
| `20210715_s229_walkDrunk_tk01_ERJA-mvn356.fbx` | impaired/stylized locomotion |
| `20210715_s229_walkDrunk_tk02_ERJA-mvn357.fbx` | impaired/stylized locomotion |
| `20210715_s230_walkZombie_tk01_ERJA-mvn358.fbx` | stylized locomotion / reject for base domain |
| `20210714_s165_walkCarry_leftShoulder_tk01_ERJA-mvn237.fbx` | carry locomotion |
| `20210714_s166_walkCarry_rightShoulder_tk01_ERJA-mvn238.fbx` | carry locomotion |
| `20210715_s040_walkUp_angle_35Degree_tk02_ERJA-mvn320.fbx` | slope locomotion |
| `20210715_s211_walk_jumpOneHanded_tk01_ERJA-mvn329.fbx` | traversal/action |
| `20210715_s211_walk_jumpOneHanded_tk04_ERJA-mvn332.fbx` | traversal/action |
| `20210715_s213_walk_reveal_tk01_ERJA-mvn333.fbx` | contextual action |
| `20210715_s213_walk_reveal_tk02_ERJA-mvn334.fbx` | contextual action |
| `08-Loop_HappyWalk_MIXAMO_769_segment.fbx` | stylized walk |
| `11-WalkCycle_Cool_MIXAMO_WHS_segment.fbx` | stylized walk |
| `12-WalkCycle_Pacing_MIXAMO_769.fbx` | pacing/turning reference |
| `13-WalkingIntoWind01_MIXAMO_769.fbx` | weather locomotion |
| `14-WalkingIntoWind02_MIXAMO_769.fbx` | weather locomotion |
| `15-WalkingIntoWind03_MIXAMO_769.fbx` | weather locomotion |
| `16-WalkingIntoWind04_MIXAMO_769.fbx` | weather locomotion |
| `04-running-out-of-frame.fbx` | run domain |
| `05-running-treadmill.fbx` | run domain |
| `06-runninginjured-treadmill.fbx` | injured run domain |
| `07-runninginjured.fbx` | injured run domain |

## Required base MM coverage still missing

Priority order for new downloads:

1. `Idle_Neutral` — quiet standing loop, minimal upper-body acting.
2. `Walk_B` — authored backward walk.
3. `Walk_L`, `Walk_R` — true lateral/strafe cycles.
4. `Walk_FL`, `Walk_FR`, `Walk_BL`, `Walk_BR` — authored diagonals; do not fake by rotating Walk F.
5. `Start_F`, `Start_B`, `Start_L`, `Start_R`.
6. `Stop_F`, `Stop_B`, `Stop_L`, `Stop_R`.
7. `Pivot_90_L`, `Pivot_90_R`.
8. `Pivot_180_L`, `Pivot_180_R`.

Jog/sprint/crouch/injured/carry/weather variants are **out of the first database domain** until the base walk set is proven.

## Intake rule

New source rigs are allowed. All source FBX motions must be normalized through the Godot retarget layer to the canonical UAL/Henry skeleton before baking MotionDatabase samples. MotionDatabase never mixes source skeleton conventions directly.

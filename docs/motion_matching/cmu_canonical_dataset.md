# CMU Canonical Locomotion Source Set

Issue: #202 — Motion Matching Lab #2 — Pose Database Search

This manifest defines the public real-mocap pool used to replace the single-capture `CMU_41_02` database with a multi-clip locomotion database.

## Source policy

Primary source: Carnegie Mellon Graphics Lab Motion Capture Database. CMU states that its motion dataset is **free for all uses**.

BVH conversion mirror: `una-dinosauria/cmu-mocap`, already used by the existing #202 CI retarget spike.

Third-party BVH files are staged only for the lab/CI and remain ignored by Git. Hoarbound stores only project-owned ingestion/retarget/database code, source provenance, hashes, and segmentation metadata.

Hard rules:

- no rotating one forward walk to manufacture F/FR/R/BR/B/BL/L/FL;
- no mirroring a source clip to pretend an opposite authored direction exists;
- no reverse playback to manufacture backward locomotion;
- no paid or account-gated pack as an undocumented dependency;
- every database sample must be baked after retarget onto the canonical Henry UAL skeleton.

## Curated source pool

| Intended domain | Source | CMU description / use |
| --- | --- | --- |
| Neutral idle | `111_28` | Standing still. |
| Walk F | `69_01` | Walk forward. |
| Walk B / Start B pool | `69_34` | Walk backwards and turn; extract only kinematically verified backward windows. |
| Walk lateral A / Start lateral pool | `69_42` | Walk sideways and turn. Signed side is derived from root trajectory rather than filename assumptions. |
| Walk lateral B / Start lateral pool | `69_48` | Opposite sideways capture. Signed side is derived from root trajectory. |
| Diagonal pool | `40_02`, `40_03`, `40_04`, `40_05` | Navigate forward/backward/on a diagonal. Use trajectory classification to obtain authored diagonal windows. |
| Stop F | `16_33` | Slow walk, stop. |
| Pivot pool A | `69_16` | Turn in place. |
| Pivot pool B | `69_18` | Opposite turn in place. |
| 90° turn pool A | `69_20` | Walk forward, 90-degree turn. |
| 90° turn pool B | `69_24` | Walk forward, opposite 90-degree turn. |
| Multidirectional reference | `41_02` | Existing forward/backward/sideways/diagonal capture used by the current single-clip baseline. |

## Canonical roles still require segmentation, not invention

The source descriptions identify useful captures, but the database should not label a frame `Walk_L`, `Start_R`, `Pivot_180_L`, etc. merely from a filename.

The next ingestion pass must classify real windows from root kinematics:

- local horizontal velocity direction and speed;
- start: stable low speed -> locomotion speed;
- stop: locomotion speed -> stable low speed;
- turn/pivot: accumulated facing delta plus low translation;
- diagonal: local velocity angle relative to facing;
- left/right sign from canonical local-space trajectory.

A segment stores at minimum:

```text
canonical_role
source_clip
source_start_time
source_end_time
source_subject
source_sha256
```

If a clean `Start_B`, `Start_L`, or `Start_R` cannot be demonstrated from the neutral captures, the role remains `missing` and another permissive real-mocap source is researched. It is not synthesized.

## First multi-clip acceptance gate

Before visual tuning resumes:

- [ ] one dense `MotionDatabase` contains samples from multiple source clips;
- [ ] exact `clip + time` remains attached to every sample;
- [ ] playback can switch across source clips, not only re-seek inside `41_02`;
- [ ] neutral idle exists in the database;
- [ ] F/B/L/R each have real authored source coverage;
- [ ] four diagonal sectors each have real captured coverage;
- [ ] start/stop segments are source-backed and kinematically validated;
- [ ] 90° and 180° pivot/turn segments are source-backed and classified by facing delta;
- [ ] workflow video visibly tests abrupt F/R/B/L/diagonal/start/stop/turn requests;
- [ ] report includes per-role source provenance and selection cost.

Do not tune matcher weights around missing motion coverage. Dataset coverage is the blocker first.

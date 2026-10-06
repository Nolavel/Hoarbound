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

## Curation (current)

`MotionDatasetCurator` labels every 30 Hz sample of the *normalized* root track
(Henry scale, after `SourceRetargetProfile` units) as idle / turn / start /
stop / one of eight walk sectors / transition / too fast. Labels pick ranges
and are written as debug metadata only; the runtime matcher never reads them.

- windows of up to 8 s (hop 2 s) keep real transitions between directions;
- greedy selection against per-label budgets (seconds of real material), total
  cap 360 s, rarer labels weighted higher;
- source capture glitches (any joint > 20 rad/s between 30 Hz samples) are cut
  out with a 0.25 s margin instead of being smoothed over;
- selected windows of one source are merged into contiguous ranges, and each
  range is baked as its own clip `CMU_<trial>@<start>-<end>`.

The CMU pool alone covers idle, starts, stops, turns and all eight steady
directions once the correct unit (1/0.45 inch) is used; forward diagonals are
the thinnest (FR ~5 s). Before the unit fix the sideways captures (113_17,
113_18, 143_40) moved at 45% speed and never qualified as lateral walking.

`tools/runtime/audit_motion_dataset.gd` rebuilds the database headless and
fails when any baked range breaks the structural retarget audit or a label has
no material. Its JSON lists covered/available seconds per label and per range.

## Hard rules (unchanged)

No rotated, mirrored, reversed or generated locomotion; no paid or
account-gated packs; every sample is baked after retarget onto Henry's UAL
skeleton; third-party files stay out of Git.

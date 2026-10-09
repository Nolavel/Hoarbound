# Hoarbound — Build Plan

> **Purpose.** A single, ordered build sequence for assembling the game, replacing
> the scattered 20–30-issue backlog with ten checkpoints. Each step is a shippable
> state, not a micro-task. This is a production contract; it sits beside `PRD.md`
> and `docs/game_design/VERTICAL_SLICE.md` and overrides ad-hoc issue ordering.
>
> Author: Nolavel. Written 2026-10-08 as a direction reset after the motion-matching
> detour (#202). Branch rules in `AGENTS.md`.

## 0. The grammar (read this first)

Hoarbound is a third-person **systemic survival** game on a frozen Key West. Its
reference core system is *The Long Dark*: the **environment is the antagonist**,
and the game is interesting only when **cold, weather, weight, wetness, fatigue and
time force the player to keep re-deciding** what to do next. There are no enemies to
carry the tension; the world does.

Four grammar rules. Every feature is measured against them:

1. **Scarcity and exposure change decisions.** Boards, fuel, food, carried mass and
   safe daylight compete. If a system never changes the *order* of the player's
   actions, it is decoration, not a mechanic.
2. **Shelter is a verb.** A building is not safe until the player makes it usable.
3. **Sleep is save.** Reaching a safe sleep state closes the loop and sets the
   checkpoint.
4. **The world is the survival model.** Route, wind exposure, weather and shelter
   quality matter as much as inventory numbers, and must be *readable* from TPS
   without a map or a debug panel.

**The one test that gates everything:** *no system ships unless it visibly changes a
survival decision.* This is the rule we have been following poorly. Motion quality,
pose databases and embodied-interaction depth are presentation; they do not change a
decision, so they come **at the end of the path**, not the start.

## The spine

The whole game, right now, is one loop — **First Exit A (#42)**:

```
bunker -> land-route choice -> supplies -> worsening weather ->
Fort Street shelter -> repair -> stove -> recover/dry -> sleep/save -> reload
```

Per #42, this loop is **already assembled in production**. What is missing is not
more systems — it is **proof that the loop reads as a survival situation**. Steps 1–4
are that proof and involve little new code. That is the reset.

---

## The ten steps

Steps are ordered by dependency. Do not start a step before the one before it is
accepted. Each lists *Done when* (the acceptance that lets you move on) and the
issues it absorbs.

### 1 — Lock the grammar on one page
Make `PRD.md`, `VERTICAL_SLICE.md` and #42 state the *same* scope and the same four
grammar rules above. Delete contradictions. This is the north star every later step
is checked against.
- **Done when:** the three documents describe one scope; the "no system ships unless
  it changes a decision" rule is written into `PRD.md`.
- **Absorbs:** #157 (identity, Hoarbound name), the #42 "same scope" checkbox.

### 2 — First Exit A runs clean, no debug
One uninterrupted run, `bunker -> sleep/save -> reload`, with **zero** debug teleport,
console command or manual method call. This is the single most important proof that
the game exists as a playable thing.
- **Done when:** the run completes start to finish with no debug workaround, captured
  as a recording + boot log.
- **Absorbs:** the hard-gate half of #80.

### 3 — Weather changes a decision
Prove a WeatherBeat turn makes the player change route or action order — not just the
visuals. One documented run where the weather turn is the reason a plan changed.
- **Done when:** #78 acceptance met: a live run shows a weather turn altering a player
  decision, written up in `docs/playtest/FIRST_EXIT_A_RUN.md`.
- **Absorbs:** #78.

### 4 — Pressure breaks the checklist
Prove weight, wetness, cold and fatigue reorder `collect -> carry -> repair -> stove
-> food/water -> sleep`. The author accepts the run as a *situation*, not a checklist.
- **Done when:** #134's two open boxes close (a player can explain the pressure without
  debug UI; one 10–15 min run reorders actions) and the author signs off.
- **Absorbs:** #134, and closes the systemic-pressure half of #80.

### 5 — Interactivity reset: a thin, deterministic Use layer
Rebuild interaction as one small deterministic layer driven by **proximity + facing**,
feeding the existing Player Hub / Quick Access / universal Use path. **The crosshair
is a readability aid only — it is decoupled from the embodied-interaction condition**
(see ADR below). No body-alignment, affordance-graph or animation state may gate
whether an interaction is *possible*; those are presentation that layers on later.
- **Done when:** every First Exit interaction (pick up, carry, board, nail, door,
  stove, sleep) resolves through the thin Use layer; the crosshair reflects "what Use
  will act on" from a cheap pick and nothing else; removing all embodied-interaction
  code does not break any interaction.
- **Absorbs:** the interaction-foundation parts of #170 (camera input stays immediate);
  supersedes the embodied coupling in #198/#199.

### 6 — Readability pass on the real route
Walk the actual First Exit route in TPS and fix only what stops the player *reading
the situation*: two land-route options legible without a map, shelter obviously a
"verb," HUD that explains pressure, no streaming pop on the route.
- **Done when:** #138's remaining-acceptance boxes that touch the First Exit route pass
  in a real traversal (not a top-down capture).
- **Absorbs:** the First-Exit-route slice of #138; #159 (stats panel only as far as it
  aids readability).

### 7 — Winter identity to "acceptable," then stop
Snow and frost are the identity shot of a frozen Key West. Take them to author-
accepted quality and **lock them**. Presentation derives from the simulation and never
writes back. Deeper polish (deterministic foot-contact stamps) stays frozen.
- **Done when:** #16 and #156 reach author acceptance; #197 stays frozen; no sim/present
  feedback loop remains.
- **Absorbs:** #16, #156, #165. (#197 frozen.)

### 8 — Performance proof on the target machine
Confirm the slice runs on the HD 620 baseline at an acceptable frame. Classify
bottlenecks with evidence; apply only the cheap, safe wins (occlusion culling). No
speculative optimization.
- **Done when:** #172 evidence captured on HD 620; the First Exit run holds an agreed
  frame budget; only measured wins from #174 are applied.
- **Absorbs:** #172, #174, the relevant part of #173.

### 9 — Vertical-slice package
Produce the packaged, screenshot-able, 10–15 minute playable an outsider and the
author can run cold. This is the first real artifact of the summer-2027 vertical
slice and the publisher proof.
- **Done when:** #80 fully closes (continuous stranger run on a packaged build); a
  tagged build exists; `tools/ci/render.sh` produces a sane frame of the slice scene.
- **Absorbs:** #80 (final), the vertical-slice milestone's first deliverable.

### 10 — Then depth, from the end of the path
Only now unfreeze the deep tech, in this order, each resumed **only when it
demonstrably improves the proven loop**:
1. embodied interaction foundation (#198) → 2. diegetic inventory (#203) →
3. locomotion / motion matching (#201, #202) → 4. coastal thin-ice slice.
This is where the motion-matching work resumes — at the end of the path, as intended.
- **Done when:** each unfrozen item ships against a First-Exit-style decision test, not
  a tech demo.
- **Absorbs:** #198, #199, #201, #202, #203, and the new Coast / Thin Ice slice.

---

## One-year sequence (Oct 2026 → Oct 2027)

The target remains a **vertical slice by summer 2027** (PRD). The ten steps land on it
without the detours.

| Quarter | Steps | Milestone |
|---|---|---|
| **Q4 2026** · Oct–Dec | 1 → 5 | **First Exit A accepted.** Grammar locked, clean no-debug run, weather + pressure proven, interactivity reset with the crosshair decoupled. |
| **Q1 2027** · Jan–Mar | 6 → 7 | **Key West reads as a place; winter identity locked.** Route legible in TPS, snow/frost at accepted quality. |
| **Q2 2027** · Apr–Jun | 8 → 9 | **Vertical slice — packaged, playable, publisher-proof.** The summer-2027 target, on a proven loop. |
| **Q3 2027** · Jul–Sep | 10 | **Depth on a proven foundation.** Embodied interaction, diegetic inventory, motion matching, then the Coast / Thin Ice slice. |

If a quarter slips, the slip is absorbed by *cutting depth (step 10), never by
reordering the proof steps (2–4) later.*

## Frozen until step 9

On hold, preserved on `claudeflow` and in `docs/motion_matching/`, reopened only by the
step that schedules them:

- #198 Embodied Interaction Stack (epic — post-slice by its own text)
- #199 Embodied Interaction isolated lab
- #201 / #202 Motion Matching #1 / #2
- #203 Diegetic Inventory (physical backpack)
- #197 Deterministic foot-contact pipeline

Nothing here is cancelled. It is sequenced to the end of the path, where it belongs.

---

## ADR — the crosshair is decoupled from embodied interaction

**Context.** The Embodied Interaction Stack (#198) models interaction as `intent ->
affordance query -> body alignment -> animation -> world-state change`. Wiring the
crosshair / interaction reticle into that chain makes whether a player *can* interact
depend on animation and body-alignment state. That couples a cheap, must-always-work
readability cue to the most expensive, least finished subsystem.

**Decision.** The crosshair is a **readability aid only**. It is driven by a cheap
proximity + facing pick against the thin Use layer (step 5) and answers one question:
*"what will Use act on right now?"* It never waits on affordance queries, body
alignment, IK, warping or animation state, and it is never the gate for whether an
interaction is possible.

**Consequences.**
- Interaction stays deterministic and testable independent of presentation.
- Embodied animation (step 10) layers *on top* of a working interaction and can be
  deleted without breaking the loop.
- The crosshair has no dependency on #198/#199 and must not acquire one.

**Clarification (2026-10-09, owner decision).** Interaction now runs on two
channels:

- World mechanisms are picked by the player's view and shown through the
  central prompt.
- Pickups are picked by Henry's head attention and shown with a small `[F]`
  keycap.

A pickup's `[F]` is gated by a **cheap deterministic geometric affordance**: a
floor spot Henry fits in, a straight collision-safe walk to it, and the item
inside his anatomical reach envelope. This geometry is gameplay, like reach
distance, and is not the embodied stack. Hand choice, hand path, IK, authored
clips and pose quality remain presentation. They never gate an interaction or
refuse one. Removing all embodied code still breaks no interaction. #198 stays
frozen.

## How to use this document

- Before taking a task, find the lowest-numbered step not yet accepted. Work there.
- If a proposed task does not advance the current step, it waits — or it is a step-10
  item and stays frozen.
- When a step is accepted, note it in `CHANGELOG.md` and tick its issues.

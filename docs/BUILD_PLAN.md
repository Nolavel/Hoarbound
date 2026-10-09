# Hoarbound — Build Plan

> **Purpose.** A single, ordered build sequence for assembling the game, replacing
> the scattered 20–30-issue backlog with ten checkpoints. Each step is a shippable
> state, not a micro-task. This is a production contract; it sits beside `PRD.md`
> and `docs/game_design/VERTICAL_SLICE.md` and overrides ad-hoc issue ordering.
>
> Author: Nolavel. Written 2026-10-08 as a direction reset after the motion-matching
> detour (#202). Interaction targeting contract revised 2026-10-09 after the
> gaze/viewport design review. Branch rules in `AGENTS.md`.

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
survival decision.* Motion quality, pose databases and deep embodied-interaction
work are presentation/depth until they prove otherwise, so they come **at the end of
the path**, not before the survival loop works.

Interaction is an exception only in the narrow sense that the player must always be
able to express intent reliably. The Step-5 Use layer is therefore production
foundation; body alignment, IK, warping and advanced affordance solving are not.

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

### 5 — Interactivity reset: deterministic Use, domain-specific attention

Rebuild interaction as one small deterministic **Use** layer feeding the existing
Player Hub / Quick Access / interaction path. Selection is cheap and readable, but it
is **not one universal targeting rule**.

The production targeting grammar is:

```text
                         USE / F
                            |
                  deterministic arbitration
                    /                 \
                   /                   \
       WORLD INTERACTION              PICKUP
       player viewport intent      Henry attention/gaze
       door/stove/window/etc.      ordinary loose items
                   \                   /
                    \                 /
                      effective action
```

#### World interaction

Doors, stove/firebox controls, windows, repair surfaces, rest/use points and similar
physical mechanisms are selected primarily from **player viewport intent**. Use a
forgiving cheap view pick (screen-space/ray/cone + authored focus information + LOS
where appropriate), not pixel-perfect aiming and not Henry torso direction.

World interaction has priority over pickup when both are plausible. Its readable UI
is the central interaction prompt/bracket grammar.

#### Pickup

Ordinary pickups are selected from **Henry's attention**, not the camera crosshair and
not raw torso facing. The candidate field is intentionally broad (approximately 180°
total around the semantic head-attention direction); angular agreement with Henry's
attention dominates, distance is secondary, and hysteresis prevents flicker in dense
groups.

A dense group must expose **one obvious dominant pickup**: the item that `F` will take
right now. Its presentation is a compact world-space `[F]`/key marker attached to the
item, not the central world-interaction brackets.

Turning Henry's attention between neighbouring items may change the dominant pickup,
but **must not move, reframe, shoulder-swap or otherwise steer the gameplay camera**.
Target selection is never allowed to create a camera feedback loop.

#### Special awareness

`✓` is reserved for rare authored **special awareness**: "Henry noticed something
worth attention." It is opt-in, may work beyond the normal pickup attention field,
and is not the universal pickup marker. `✓` does not by itself mean that pressing
`F` will act on that object.

The three visual meanings stay distinct:

```text
✓                   notice this / authored special awareness
[F] on an item      this is the current dominant pickup
central prompt      this world mechanism is the current Use target
```

#### Deterministic acceptance contract

No body-alignment state, affordance graph, IK result, animation pose, warping result or
hand-reach solve may gate whether Step-5 Use is *possible*. Those belong to Step 10.

However, once the thin Use layer presents an actionable target and accepts `F`, the
action is a contract with the player. Presentation is not allowed to turn that into:

```text
F accepted -> Henry approaches -> collision/animation solve fails -> nothing happens
```

The logical action must either complete deterministically or fail for a real gameplay
reason already represented by the Use contract (for example inventory/full-hands or
an authored locked state). A missing body pose, IK solution or perfect approach point
is **not** a valid gameplay refusal.

A cheap collision-safe approach helper may improve presentation now, but it remains a
best-effort layer. Advanced automatic affordance solving (body position/yaw, hand
choice, contact path, authored pose matching) stays frozen with #198 until Step 10.

#### Step-5 acceptance

- **Done when:** every First Exit interaction (pick up, carry, board, nail, door,
  stove, sleep) resolves through the thin deterministic Use layer.
- World mechanisms are selected from forgiving viewport intent.
- Ordinary pickups are selected from Henry attention/gaze and have exactly one clear
  dominant `[F]` in a close group.
- World interaction wins arbitration over a nearby pickup.
- Central prompt/brackets are world-interaction UI, not ordinary pickup UI.
- `✓` is rare authored awareness, not universal loot notation.
- Switching pickup dominance causes zero camera framing movement.
- `F` never becomes a dead promise because an embodied/presentation solve failed.
- Removing all Step-10 embodied-interaction code still leaves every Step-5 gameplay
  interaction functional and deterministic.
- **Absorbs:** the interaction-foundation parts of #170 (camera input stays immediate);
  supersedes the old single-rule `proximity + facing` targeting language and the
  embodied coupling in #198/#199, but does **not** supersede #198's later presentation
  goals.

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

For interaction, Step 10 may improve **how** an accepted Step-5 action is physically
performed:

```text
accepted Use intent
-> affordance query
-> body position / yaw
-> collision-safe alignment
-> hand/contact target
-> authored animation + selective IK/warping
-> deterministic world-state change
```

The arrow from Step 5 into this chain is one-way: embodiment may improve presentation,
but failure of an embodied solve must not revoke a valid Use action. The underlying
selection/arbitration grammar (world=view intent, pickup=Henry attention) remains the
production contract unless the owner explicitly changes it.

- **Done when:** each unfrozen item ships against a First-Exit-style decision test, not
  a tech demo.
- **Absorbs:** #198, #199, #201, #202, #203, and the new Coast / Thin Ice slice.

---

## One-year sequence (Oct 2026 → Oct 2027)

The target remains a **vertical slice by summer 2027** (PRD). The ten steps land on it
without the detours.

| Quarter | Steps | Milestone |
|---|---|---|
| **Q4 2026** · Oct–Dec | 1 → 5 | **First Exit A accepted.** Grammar locked, clean no-debug run, weather + pressure proven, deterministic Use with viewport/world and Henry-attention/pickup selection. |
| **Q1 2027** · Jan–Mar | 6 → 7 | **Key West reads as a place; winter identity locked.** Route legible in TPS, snow/frost at accepted quality. |
| **Q2 2027** · Apr–Jun | 8 → 9 | **Vertical slice — packaged, playable, publisher-proof.** The summer-2027 target, on a proven loop. |
| **Q3 2027** · Jul–Sep | 10 | **Depth on a proven foundation.** Embodied interaction, diegetic inventory, motion matching, then the Coast / Thin Ice slice. |

If a quarter slips, the slip is absorbed by *cutting depth (step 10), never by
reordering the proof steps (2–4) later.*

## Frozen until step 9

On hold, preserved in their existing R&D branches/docs and reopened only by the step
that schedules them:

- #198 Embodied Interaction Stack (deep body/hand/affordance execution, not Step-5 targeting)
- #199 Embodied Interaction isolated lab
- #201 / #202 Motion Matching #1 / #2
- #203 Diegetic Inventory (physical backpack)
- #197 Deterministic foot-contact pipeline

Nothing here is cancelled. It is sequenced to the end of the path, where it belongs.
Step 5 may use cheap deterministic target selection and best-effort approach helpers;
it must not silently unfreeze the deep systems above.

---

## ADR — targeting is domain-specific; embodiment never gates Use

**Context.** The earlier Step-5 text described one `proximity + facing` pick and the
Embodied Interaction Stack (#198) models a deeper chain such as `intent -> affordance
query -> body alignment -> animation -> world-state change`. Production testing then
showed two separate facts:

1. one targeting rule is not sufficient for TPS readability — a door/handle is a
   player-view question, while choosing one can from a close table group is better
   represented by Henry's attention;
2. coupling target/action availability to unfinished affordance/body/animation work
   makes a cheap must-always-work Use action unreliable.

**Decision.** Step-5 target acquisition is **domain-specific but cheap**:

- world mechanisms: forgiving **player viewport intent**;
- ordinary pickups: **Henry semantic head attention/gaze**, with broad candidate field
  and hysteresis;
- special awareness: authored `✓`, informational unless separately actionable.

The UI reports the chosen Use semantics; it does not define them. Central
interaction brackets/prompts belong to world mechanisms. A compact world-space `[F]`
identifies the dominant pickup. Neither of these waits for affordance, body alignment,
IK, warping or animation state.

Target selection must not physically reframe the gameplay camera. In particular,
switching between nearby pickup candidates cannot change shoulder offset, yaw, pitch,
boom or camera position. Any historical interaction-framing experiment that creates
selection -> camera movement -> selection feedback is outside the Step-5 contract.

**Use acceptance rule.** If the deterministic Use layer exposes an actionable target
and accepts the input, presentation cannot later veto the action. Best-effort
approach/alignment may run, but a missing embodied solution falls back to deterministic
completion rather than producing a dead press. Genuine gameplay refusals (locked,
full inventory, occupied hands, invalid authored state) remain valid.

**Consequences.**
- Interaction stays deterministic and testable independent of presentation.
- World interaction and pickup targeting can each express the intent that fits them
  without reintroducing camera-driven pickup ambiguity.
- Dense pickup groups need no manual cycling action.
- The old `proximity + facing` wording is superseded by this ADR.
- Embodied animation/affordance work (Step 10) layers on top of a working interaction
  and can be deleted without breaking the loop.
- Step-5 UI/targeting has no hard dependency on #198/#199 and must not acquire one.
- #198 remains valid as the later physical execution/presentation layer, not as a gate
  for whether Use exists.

## How to use this document

- Before taking a task, find the lowest-numbered step not yet accepted. Work there.
- If a proposed task does not advance the current step, it waits — or it is a step-10
  item and stays frozen.
- When a step is accepted, note it in `CHANGELOG.md` and tick its issues.
- If an older issue/comment/code path contradicts this document, do not silently pick
  the older behaviour. Use the newest direct owner decision; if ambiguity remains,
  surface the conflict before implementation.

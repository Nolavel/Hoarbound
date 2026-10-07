# Hoarbound — Product Requirements Document

> **Living product contract.** Update this document when the current milestone, product direction or major scope boundary changes.
>
> Owner: Nolavel. Repository / branch rules live in `AGENTS.md`.

See also: [`README.md`](README.md), [`docs/game_design/VERTICAL_SLICE.md`](docs/game_design/VERTICAL_SLICE.md), [`docs/GDD.md`](docs/GDD.md), and [`CONTRIBUTING_DECOMPOSITION.md`](CONTRIBUTING_DECOMPOSITION.md).

## 1. Product vision

Hoarbound is a third-person systemic survival game set in a frozen Key West after a climate catastrophe.

Henry leaves a bunker with little margin for error. He must read the landscape, choose a route, carry useful supplies, prepare an unsafe house for the night, maintain heat and reach a safe sleep state.

The project is a solo-developed PC game built in Godot 4.8-dev6 .NET / Forward+.

## 2. Core player experience

The current survival grammar is:

`bunker -> land-route choice -> scarce resources -> worsening weather -> shelter -> repair -> fire -> dry/recover -> sleep/save`

The important design outcomes are:

- **Scarcity changes decisions.** Boards, fuel, food, carried mass and safe time compete with each other.
- **Shelter is a verb.** A discovered building is not automatically safe; the player must make it usable.
- **Sleep is save.** Reaching a safe sleep state closes the loop and creates the reliable checkpoint.
- **The world is part of the survival model.** Route, wind exposure, weather and shelter quality should matter as much as inventory values.
- **Physical handling supports readability.** Backpack, Quick Access, carried items and tools should feel connected to Henry rather than existing only as abstract UI.

Primary decision-pressure reference: *The Long Dark*. Tone reference: *The Road*.

## 3. Current milestone — First Exit A

**First Exit A: One Land Night** is the current production target.

The goal is one continuous **10–15 minute** playable run in the main Key West scene with no debug teleporting or manual repair of the flow.

Expected route:

`bunker / Whitehead Spit -> road / exposed shore / ruins -> supplies -> weather turn -> Fort Street shelter -> repair -> stove -> recovery -> sleep/save -> reload`

Coastal thin ice is intentionally deferred to a later Coast / Thin Ice slice.

## 4. First Exit A success criteria

First Exit A is ready to close when:

- [ ] A new player reaches the shelter and completes sleep/save in roughly 10–15 minutes without debug help.
- [ ] At least two land routes are readable without a map; the target grammar supports road / shore / ruins.
- [ ] Weather, carried load, wetness or time causes at least one understandable change of plan.
- [ ] Shelter preparation requires action and prioritisation rather than acting as an automatic safe room.
- [ ] Sleep/reload restores coherent shelter, fuel, weather, bedroll, inventory and consumed-world-loot state.
- [ ] README, this PRD and `VERTICAL_SLICE.md` describe the same current slice.
- [ ] Thin ice is not required or implied as a First Exit A route.

## 5. Current product state

### Now

**First Exit A** — the core actions and systemic foundation exist; continuous stranger-play acceptance remains the main closing gate.

**Diegetic inventory / embodied interaction** — Player Hub, physical Quick Access and item ownership already exist. Current work is proving controlled 3D placement and more tactile interaction without creating duplicate inventory or simulation systems.

### Next

**Coast / Thin Ice** — a later signature route problem: a shorter risky coastal / ice option versus safer longer travel.

### Later

Broader survival-pressure polish, route audio/readability, content expansion and publisher-facing capture should follow the proof of the First Exit loop rather than delay it.

## 6. Current supply note

The current First Exit candidate intentionally retains the author-approved increased supplies, including the existing bonus stacks. The working documents record **33 boards, 66 nails and 12 logs** for this candidate.

That run validates interaction flow, readability and systemic pressure. It does **not** revalidate the older reduced-stock scarcity target.

## 7. Out of scope for First Exit A

- coastal thin-ice gameplay;
- combat and enemies;
- active Kenny abilities;
- new survival meters added for completeness;
- island expansion unrelated to the First Exit route;
- large crafting trees;
- major HUD redesign;
- new standalone managers when an existing owner can handle the behaviour;
- technology or shader experiments that do not help close the playable loop.

Snow and rendering work may continue where it is already part of the production world, but visual technology must not replace human playability as the slice gate.

## 8. Production constraints

- `AGENTS.md` is authoritative for branch and agent workflow.
- `main` is production / integration; agent work follows the repository's persistent-branch rules.
- Issue #1 is the concise handoff thread for overlapping agent work.
- Existing CI / capture infrastructure should be extended rather than duplicated.
- Authored First Exit placement remains data-driven; do not create a second competing layout source.

## 9. Work decomposition

Use this hierarchy:

`PRD -> Epic / Milestone -> User Story -> Task / PR -> checklist subtasks`

An Epic defines a product outcome. A Story defines one player-facing value. A Task defines one bounded implementation unit. Checklist items are not separate issues unless they become independently owned work.

Detailed rules and templates live in `CONTRIBUTING_DECOMPOSITION.md` and `.github/ISSUE_TEMPLATE/`.
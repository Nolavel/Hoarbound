# AGENTS.md

This file applies to the entire repository.

## Branch ownership — strict rule

One agent uses one permanent branch. Agents never share a working branch.

- Codex owns `codex`.
- Claude owns `claudeflow`.
- Grok owns `grok`.
- Do not create task, fix, experiment, shader, research, or other temporary agent branches.
- A new agent-specific branch is allowed only when the author explicitly asks for one.
- Never commit directly to `main` unless the author explicitly requests direct integration.
- Never push commits to another agent's branch.
- Never force-move another agent's branch.
- Before every new task or substantial pass, an agent MUST synchronize the current `main` into its own branch; see **Mandatory pre-task sync** below.
- Integration into `main` happens only when the author asks for it.
- Before writing, verify the current branch belongs to the acting agent.

If an agent cannot create or write its assigned branch, it must stop instead of
falling back to `main` or inventing another branch.

## Mandatory pre-task sync

Before every new user task, substantial implementation pass, experiment,
review-with-fixes, CI repair, or resumed work after another agent may have
integrated changes, the acting agent **MUST** synchronize its permanent working
branch with the current `main` before the first write for that task.

Required order:

1. Fetch the current `main` and the agent's own permanent branch.
2. Verify whether current `main` is already an ancestor of the working branch.
3. If the working branch has no divergent commits and is only behind `main`,
   fast-forward it to `main`.
4. If both branches contain unique commits, merge `main` into the working
   branch. Never rebase or force-push a shared agent branch.
5. Resolve conflicts and inspect the integrated version before editing files.
6. Only after the working branch contains current `main` may the agent make
   task-specific edits, commits, expensive CI runs, or open/update a PR.

A sync from an earlier session or an earlier task does **not** count if `main`
has moved since then. The required flow is always:

`main -> permanent agent branch -> new work -> verification -> PR/integration`

If another agent's fix has reached `main`, do not recreate, revert, or work
around that fix from a stale branch state. Sync first and inspect the integrated
version. Before reporting a recurring CI failure as unresolved, verify that the
working branch contains the latest `main`.

Never create a temporary branch merely to avoid synchronizing the permanent
agent branch.

## Roles

| Agent | Branch | Owns |
|---|---|---|
| **Author (human)** | any | Design, narrative, art direction, final say on scope and integration. |
| **Claude** | `claudeflow` | Technical direction: architecture, engine baseline, build/CI, headless render pipeline, code review. See `CLAUDE.md`. |
| **Codex** | `codex` | Implementation and engineering: gameplay, physics, rendering, UI, world systems, tooling, refactors, runtime validation, and production integration work it opens. |
| **Grok** | `grok` | Commercial readiness, scope control, vertical-slice readiness audits, risk matrix, and related technical docs. Proposes only; does not auto-implement gameplay. |

Handover rules:

- An agent reviews the other's branch on request; it never pushes to it.
- Conflicting opinions are resolved in writing (a note in `CHANGELOG.md` or a doc under `docs/`), not by silently reverting the other's work.
- Shared conventions (style, engine version, hygiene) live in this file and in `CLAUDE.md`; neither agent changes them without saying so in `CHANGELOG.md`.

## Product documents

- [PRD.md](PRD.md) — Product Requirements Document (vision, current north-star, success criteria, out of scope).
- [CONTRIBUTING_DECOMPOSITION.md](CONTRIBUTING_DECOMPOSITION.md) — правила декомпозиции PRD → Epic → User Story → Task → Subtask.
- [docs/game_design/VERTICAL_SLICE.md](docs/game_design/VERTICAL_SLICE.md) — текущий scope First Exit A.
- [docs/art/ART_DIRECTION.md](docs/art/ART_DIRECTION.md) — production visual source of truth. Rendering, materials, assets, lighting and visual experiments must preserve this contract unless the author explicitly changes it.

## Engine baseline

- Godot: **4.8 dev6 .NET (mono)**
- Godot.NET.Sdk: **4.8.0-dev.6**
- .NET target: **net8.0**
- Main development scene: `res://tests/scenes/TestScene.tscn`
- Terrain is `IslandTerrain` built from the heightmap PNG; edit heights in Blender, not in code.

## Repository hygiene

- No ProjectSettings dump/load tools in runtime.
- No generated settings dictionaries committed into `project.godot`.
- Debug/profiling UI must be lightweight and optional.
- Legacy experiments do not live in a production `garbage/` folder.
- Prefer project systems under `scripts/`; tools under `tools/` must not own gameplay state.
- Temporary diagnostics, experimental nodes, capture helpers, and debug data must
  not become hidden production dependencies.

## Architecture guardrails

- Player movement, rotation, camera, interaction, and survival components keep separate ownership.
- Camera feedback may lag aesthetically, but input response must not be delayed by stacked smoothing systems.
- `IslandTerrain` owns terrain geometry/LOD. Project streaming owns gameplay content chunks.
- Streaming must preload before activation and use unload hysteresis; do not load on boundary entry and immediately free on boundary exit.
- Chunk definitions are data-driven. Avoid one `@onready` variable and one `match` arm per chunk.
- Simulation state is authoritative. Presentation derives from it and must not
  become a second source of truth.
- Do not add another manager, state mirror, compatibility layer, or wrapper until
  the existing owner of that responsibility has been identified and shown to be
  insufficient.

## Engineering quality target

The project targets the highest practical **AA/AAA production quality** that can
be achieved within the project's engine, hardware, schedule, and team limits.

The default priority is:

`correct model -> proven technique -> robust implementation -> runtime validation -> polish -> optimization`

Not:

`quick workaround -> compensating layer -> test that the workaround exists`

Do not silently reduce a requirement from "production quality", "physical",
"AAA-like", "correct", or "research how this is normally done" to the cheapest
approximation. If the proper method has a substantial cost or risk, explain that
cost to the author, but do not lower the requirement on your own.

## Research before implementation

For non-trivial gameplay, physics, rendering, animation, streaming, AI, UI, or
world-system work:

1. Read the existing implementation, scene ownership, signals, resources,
   lifecycle, and nearby systems before editing.
2. Reproduce or measure the current behaviour when fixing a defect.
3. Identify the actual owner of the state or behaviour.
4. Prefer documented engine behaviour and established production techniques.
5. When the mechanism is unfamiliar or contentious, check official
   documentation, engine behaviour/source where useful, and credible
   open-source or shipped-game techniques before inventing a custom solution.
6. Choose the implementation for technical correctness and maintainability, not
   for the smallest patch or fewest lines.

When a proven engine-native mechanism already matches the requirement, use it
before introducing a project-specific abstraction.

Examples include joints and physics bodies for physical constraints,
`AnimationTree`/animation state machinery for animation ownership,
`MultiMesh` for suitable repeated geometry, rendering APIs for rendering work,
and the existing project streaming system for gameplay-content streaming.

## Root-cause rule

For a bug or broken behaviour, establish:

`what happens -> why it happens -> which subsystem owns it -> which mechanism should control it`

Only then implement the fix.

- Fix the cause, not the symptom.
- If earlier project code is wrong, replace or remove it instead of preserving it
  behind another compensating layer.
- Do not use teleport corrections, velocity clamps, collision disabling,
  arbitrary timers, duplicate state, hidden offsets, or similar compensation
  merely because they make one reproduction case pass.
- A workaround is acceptable only when the proper fix is not currently possible,
  the workaround is explicitly identified as such, and its limits are documented.

## No surrogate implementations

Do not substitute a look-alike behaviour for the requested mechanic without the
author explicitly accepting that trade-off.

Examples:

- Physical interaction is not replaced by an invisible proximity trigger merely
  because it is easier.
- Correct collision response is not replaced by scripted displacement.
- Streaming is not considered implemented when objects are only hidden while
  remaining fully loaded and simulated.
- A gameplay system is not replaced by UI that only suggests the state exists.
- A render feature is not production-ready merely because its shader compiles.
- A mechanic is not complete merely because a unit test can detect one expected
  value.

The implemented system must satisfy the player's actual runtime interaction, not
only the structural shape of the requirement.

## Production implementation rules

- Prefer one authoritative implementation over compatibility shims and duplicate
  paths.
- Prefer composition and explicit ownership over global reach-through.
- Remove obsolete experimental code when the selected production method replaces
  it.
- Keep experimental work isolated from the production path and easy to delete.
- Do not preserve a weak implementation only because tests were written around
  it; tests follow the accepted mechanic, not the other way around.
- Syntax, parser, import, and compile errors are unfinished work, not QA debt.

## Validation and test policy

**A test must protect a decision, not substitute for making the decision.**

Mechanics and implementation methods are allowed to change rapidly while they
are being researched and tuned. During that phase:

- Do not create permanent regression tests for behaviour whose contract is still
  moving.
- Do not expand CI merely to prove every intermediate experiment.
- Use the cheapest useful evidence: direct runtime reproduction, an existing
  scene/harness, a focused trace, a capture, a readback, or an existing local
  tool.
- Reuse existing `tools/ci/`, `tools/runtime/`, tests, and capture scripts
  before creating new infrastructure.
- Keep cheap universal gates such as clean import/compile, input-map hygiene, and
  filename/UID checks cheap.

After the mechanic and method have settled:

- Add a focused regression test only when it protects an important stable
  contract or a realistic recurrence risk.
- Prefer a small number of high-value tests over many structural or
  implementation-detail tests.
- Do not encode temporary tuning values as architectural contracts unless the
  value itself is intentionally fixed.
- Expensive render/capture CI is used when it provides meaningful evidence for
  an accepted implementation, integration point, or visual regression — not for
  every small iteration.

Green CI does not prove gameplay feel or visual correctness.
A green unit test does not prove the player's interaction is correct.
Successful shader compilation does not prove a production-ready image.

## Runtime quality bar

For player-facing mechanics, validate the aspects that materially affect feel:

- responsiveness and input ownership;
- collision and physical plausibility;
- transitions and repeated use;
- animation continuity;
- camera behaviour;
- audiovisual feedback;
- unusual approach angles or player states;
- failure, interruption, deletion, unload/reload, or re-entry where relevant.

The exact validation method should fit the mechanic. Do not manufacture a new
test suite simply to satisfy this list.

For visual work, inspect the resulting frames or footage when the environment can
produce representative output. For physics/gameplay, exercise the actual
interaction rather than validating only node presence or exported values.

## CI and render discipline

Before creating or extending workflows, inspect:

- `.github/workflows/`
- `tools/ci/`
- `tools/runtime/`
- existing capture and test harnesses

Do not create a second pipeline when the existing one can be extended.

GitHub-hosted rendering may differ from the local Forward+/Vulkan target because
of CPU rendering, lavapipe/llvmpipe, missing surfaces, or compatibility limits.
Therefore a successful workflow is evidence of automation health, not by itself
evidence of final visual quality.

Bundle meaningful render captures into one run when possible. Avoid spending CI
on a sequence of tiny trial commits that can be prepared and checked together.

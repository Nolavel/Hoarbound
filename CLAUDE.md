# CLAUDE.md — Claude's operating charter

Scope: entire repository. Complements `AGENTS.md`; where both speak, `AGENTS.md`
branch rules win.

## Role

Claude acts as **Technical Director** of Hoarbound. That means:

- Owning engineering direction: architecture, engine baseline, build and CI health.
- Guarding the production path — a prototype that cannot be built, run and
  screenshotted by a machine is not a product.
- Saying no to scope that does not move the vertical slice forward, and saying
  so with a concrete alternative.
- Writing code only where it removes risk; otherwise writing the decision down.

Claude does not make design/narrative calls unilaterally — those belong to the
author. Claude flags cost and risk for them.

## Branch

- Claude owns `claudeflow` — **one branch, always**. Never create additional
  Claude branches; never touch `main`, `codex`, or another agent's branch.
- Merging `main` into `claudeflow` is routine (see below); integration into
  `main` happens only when the author asks. Same rule as `AGENTS.md`.

## Staying in sync

`main` moves ahead independently. **Before EVERY new user task or substantial
implementation pass, and before the first write for that task, Claude MUST sync
current `main` into `claudeflow` if needed.** This applies even when continuing
inside the same long-running Claude Code session. A sync from an earlier task or
session does not count after `main` has moved.

Required sequence:

1. `git fetch origin main claudeflow`.
2. Run `git merge-base --is-ancestor origin/main HEAD` to verify that the current
   `main` is already contained in `claudeflow`.
3. If it is not, merge `origin/main` into `claudeflow` (merge, never rebase or
   force-push — other agents read this branch).
4. Resolve conflicts and inspect integrated fixes before making new edits. Never
   recreate, revert, or work around another agent's already-merged fix from a
   stale branch state.
5. Before expensive CI or claiming a recurring failure is still unresolved,
   verify again that current `main` is an ancestor of HEAD.
6. Re-run `tools/ci/render.sh` on `TestScene` when the task affects runtime or
   rendering, and confirm the frame is sane.
7. Read GitHub issue #1 (*AI Talk*) for handoffs and reply with the synced
   `main` SHA, new `claudeflow` HEAD, and any conflict decisions.

The mandatory flow is:

`main -> claudeflow -> new work -> verification -> PR/integration`

Known recurring conflicts: `AGENTS.md` (keep Claude's roles table, take Codex's
rule changes) and `global.json` (take `main`'s).

## Engine baseline

- Godot **4.8-dev6 .NET (mono)**, `Godot.NET.Sdk` 4.8.x, `net8.0`.
- Renderer: Forward+ / Vulkan. CI runs headless suites only; render locally on
  CPU via lavapipe (`tools/ci/render.sh`).
- Main development scene: `res://tests/scenes/TestScene.tscn`.
- Main terrain is `IslandTerrain` from the preserved NOAA crop in
  `world/terrain/source/key_west/`; Graciosa sources live in `archive/graciosa/`.
  NOAA base heights remain unchanged. Authored height edits use Blender
  (`tools/blender/`), never hand-written code.

## Jenova (C++ scripts)

- How it works, pinned versions, patches and rebuild steps: `docs/technical/JENOVA.md`.
- We build Jenova ourselves for Windows and Linux from one pinned revision; keep
  `JENOVA_REF` / `$jenovaRef` equal in both `tools/ci/bootstrap_jenova_*` scripts.
- Windows runtime is built in CI (`[jenova-windows-build]`): this machine has 4 GB
  RAM and the local build was killed for lack of memory. Do not start it locally.
- Windows binaries go to Git LFS; Linux binaries stay plain git (Linux CI jobs
  check out without LFS and Godot loads the extension at every start).
- `Jenova/Compilers/` is local only (git-ignored); create it with
  `tools/jenova/install_msvc_compiler.ps1`.

## Language policy

- Code comments: **English only**, `##` doc-comment style, **max 2 lines**.
- `#` inline comments only for a short trailing note; never a comment block.
- Docs, changelog and commit messages: English.
- Player-facing strings go through localisation, never hardcoded Russian.

## GDScript style

Follows the official GDScript style guide, with these enforced points:

- Tabs for indentation. Two blank lines between top-level definitions.
- **Static typing everywhere**: `var speed: float = 0.0`, `func f(a: int) -> void:`.
- File names `snake_case.gd`; `class_name` in `PascalCase`; members `snake_case`;
  private members `_leading_underscore`; constants `CONSTANT_CASE`.
- Declaration order: `@tool`, `class_name`, `extends`, doc comment, signals, enums,
  constants, `@export`, public vars, private vars, `@onready`, `_init`, `_ready`,
  built-in virtuals, public methods, private methods.
- No `get_node()` chains in `_process`; cache in `@onready` or inject via `@export`.
- Prefer signals over polling; prefer composition over deep inheritance.
- `@export_group` labels are player-invisible tooling text — English.

## C#

- Only where it earns its place: heavy math, data processing, interop.
- Gameplay glue stays GDScript. Do not mirror the same system in both languages.
- A `.cs` script is never assigned to a variable typed as a GDScript class.

## Definition of done

A change is done when: the project imports clean, `tools/ci/render.sh` produces a
non-black frame of the affected scene, no new errors appear in the boot log, and
`CHANGELOG.md` has an entry.

## Working method (bugs and visuals)

1. **Measure before fixing.** Reproduce the defect and capture evidence first:
   a close-up frame, a numeric trace, a texture readback. No fix without a
   named root cause.
2. **Fix the cause, not the symptom.** If the cause is in earlier code
   (including Claude's own), replace it; do not layer patches on top.
3. **Use a proven technique.** Before inventing one, look up how shipped games
   or engines solve it and name the reference in the PR.
4. **Data and presentation stay separate.** Simulation state is authoritative;
   what is drawn is derived from it and never written back. No feedback loops
   across frames.
5. **Derive from real data, not constants.** Heights, lifts, thresholds come
   from the state they describe (snow top, sink depth), not fixed angles.
6. **Verify against the original evidence.** Re-run the same capture or trace
   and show the defect is gone before claiming it fixed. If it can't be
   verified here, say so plainly.

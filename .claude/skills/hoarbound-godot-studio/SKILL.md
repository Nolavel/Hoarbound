---
name: hoarbound-godot-studio
description: "Review, profile and audit Hoarbound's Godot 4.8 work through specialist lenses (engine architecture, GDScript, C#, shaders, GDExtension), plus performance, asset and test-evidence audits. Use before claiming a change done, for code review of a diff, a perf investigation, an asset/licence sweep, or checking that tests and captures really prove a fix."
---

# Hoarbound Godot studio — review lenses

Adapted, by selection, from Claude Code Game Studios (MIT, pinned `05ad7c8a`, see `NOTICE.md`; handoff: issue #1,
2026-11-06). Only the Godot specialists' knowledge and the review / profile / audit / evidence procedures are
taken. **Hoarbound's own rules win everywhere**: `CLAUDE.md`, `AGENTS.md`, `docs/technical/ARCHITECTURE.md`,
`docs/technical/GDEXTENSION.md`, the animation skill. Nothing here authorises a structural change by itself.

Not adopted, on purpose: the upstream hooks, `settings.json`, `project.yaml`, rules, `CLAUDE.md`, the
story/sprint/approval registry, trunk-based branching, `/start`, `/setup-engine`. Hoarbound keeps its branch
ownership (`claudeflow` for Claude), its Miro production source and its own Definition of done.

## Operating sequence

1. **Sync first.** `main -> claudeflow` per `CLAUDE.md`, then read issue #1 for handoffs touching the files.
2. **List the inputs, mark each FOUND or ABSENT.** A section whose input is absent is reported as
   `NOT ASSESSED — <why>`, never left silent: a skipped check must not read like a passed one.
3. **Pick the lenses** by what the diff touches (below). Run them inline; spawn agents only if the user asks.
4. **Measure, then judge.** A finding names a file:line and a concrete failure path (input -> wrong result).
   No path, no finding. Visual claims need a frame from `tools/ci/render.sh` or a capture tool.
5. **Report** with the verdict format at the end. Fixes follow `CLAUDE.md` "Working method"; this skill only
   finds and ranks.

## Lenses

### Engine architecture (any `.gd`, `.tscn`, `project.godot`)
- Composition over inheritance; a scene is self-contained, one root with one responsibility, shallow tree.
- Call down, signal up; a direct call when the caller needs a return value. Signals connected in `_ready`,
  never in `_process`; `CONNECT_ONE_SHOT` or `is_connected` against double connections.
- Cross-system seams go through `core/contracts/` capabilities. Flag any new scattered `has_method()` /
  string `call()` protocol outside the contracts/adapters boundary (Hoarbound rule).
- Autoloads only for truly global systems, never holding scene nodes.
- `Resource` subclasses and `.tres` for data; `duplicate()` for per-instance state (resources are shared).
- Idle nodes stop processing (`set_process(false)`); tweens over hand interpolation; pooling for frequent spawns.
- Data vs presentation: simulation state authoritative, the drawn view derived, never written back.
- Pitfalls: long `get_node()` paths or chains in `_process`, orphan nodes (no `queue_free`), `@tool` scripts
  without editor guards, untyped arrays, awaits that may never resolve (no timeout / validity check after).

### GDScript
- Static typing everywhere (vars, params, returns, typed arrays); `class_name` PascalCase, files snake_case,
  members snake_case, privates `_x`, constants CONSTANT_CASE; signals past tense with typed params.
- Declaration order and comment rules exactly as `CLAUDE.md` (English, `##`, at most 2 lines).
- After `await`, check `is_instance_valid(self)` / the target; avoid more than three chained awaits.
- Never a signal for request-response; a method instead. State machines: enum + match, or child-node states.
- `@export` with ranges / groups; validate exports in `_ready`. `@export_group` labels English.

### C# (`.cs`, `Hoarbound.csproj`)
- Only where it earns its place (heavy math, data, interop); gameplay glue stays GDScript; never the same
  system mirrored in both. A `.cs` script is never assigned to a variable typed as a GDScript class.
- `partial` classes; nullable enabled and honoured; `IsInstanceValid(this)` after `await`.
- Cache `GetNode<T>()` in `_Ready`; `StringName` for hot comparisons; no LINQ or allocations in hot paths;
  `List<T>` for C#-internal collections. Range hints only limit the inspector: clamp in setters.
- New NuGet packages need a clear reason and thread-model check; flag them for the Technical Director.

### Shaders (`.gdshader`)
- Renderer is Forward+ / Vulkan; CI renders on lavapipe. Note anything Forward+-only that would silently
  differ under the Compatibility fallback (the VK_KHR_surface lesson in issue #1).
- Uniforms with hints (`source_color`, `hint_range`, `hint_normal`), `group_uniforms` for the inspector.
- `varying` for vertex -> fragment data; no per-pixel work that could be per-vertex; watch overdraw of
  transparent and screen-texture passes (`hint_screen_texture` mip blurs cost a copy).
- One shader per purpose; shared code via `#include`. Material overrides stripped before freeing undrawn
  meshes (`SurvivalItemVisual.release`, the "material is null" lesson).

### GDExtension / native (`native/`)
- Hoarbound rule: native only after profiling shows a real bottleneck; the capability contract and its
  consumers stay unchanged; parity proven before the GDScript version goes. Portable math in
  `native/hoarbound_core/`, Godot adapters in `native/hoarbound_native/`; builds in GitHub Actions.
- godot-cpp: classes registered in `register_types`, `GDCLASS`, bindings in `_bind_methods`,
  `memnew`/`memdelete` (a node added to the tree belongs to the tree), godot `String`/`StringName`/typed arrays.
- Boundary: GDScript owns logic and coordination; native owns hot loops; simple typed data across it.
- Jenova stays rejected.

## Procedures

### Code review of a diff
Inputs: the diff, touched files, their docs (`docs/technical/*` named in the code), related tests.
Check, in order: correctness (a real caller or input reaching a wrong result), the lenses above, Hoarbound
architecture (contracts, ownership, data/presentation split), tests (does a test fail without the change?),
`CHANGELOG.md` entry, docs updated with the code (e.g. `BACKPACK_RIG.md` with backpack rig changes).
Rank BLOCKING (wrong behaviour, crash, rule violation) above WARNING (drift, fragile) above SUGGESTION.

### Performance profile
Inputs: a trace or profiler numbers on the named route (`PERFORMANCE_AUDIT_2026_10_03.md` for budgets and
earlier findings). Without numbers, report `NOT ASSESSED` and say what to measure, never guess.
Report hotspots with their measured cost, then options: A) fix now, B) reduce scope, C) accept and log,
D) escalate an architectural choice (e.g. a GDExtension move) to the owner. Physics stays GodotPhysics3D
unless profiling on that route says otherwise (`CLAUDE.md`).

### Asset audit
Scan `assets/` (and the paths named in the request): naming (snake_case), size (textures and audio out of
proportion to their use), format (import settings, compression), orphans (no `res://` or uid reference),
missing (referenced, not on disk), and a `LICENSE` / licence entry for every third-party asset.
Verdict: NON-COMPLIANT for a missing referenced asset, an oversized one or an unlicensed third-party one;
WARNINGS for naming / format / orphans.

### Test evidence
For a claimed fix: the original evidence (frame, trace, readback) and the same capture after. Automated
tests: real assertions on the behaviour (not only "no crash"), edge cases (empty, full, both sides, low fps),
and proof the test fails without the change. Visual work: a frame of the affected scene per criterion,
newer than the last code change it proves. Evidence older than its code counts as missing.

## Verdict format

```
## <Review | Profile | Audit | Evidence>: <scope>
Inputs: <each FOUND / ABSENT>
Findings: <BLOCKING / WARNING / SUGGESTION, each with file:line and failure path>
Not assessed: <sections and why, or none>
Verdict: NOT ASSESSED | CLEAN | CHANGES REQUIRED
```

# Open technical tasks

Parked work with enough context to resume. Not a build plan:
`docs/BUILD_PLAN.md` stays the source of truth for order.

## 1. Linux: Jenova C++ script build fails (open, 2026-10-09)

- **Symptom.** In the `[jenova-frost-preview]` CI job `BuildProject` returns
  false on Linux (run 37814389505). Windows builds and runs the frost script,
  both in CI and on the author's machine.
- **Diagnostics in place.** `tools/ci/build_jenova_project.gd` now routes
  Jenova's log to standard output (`jenova/editor_verbose_output = 0`). The job
  uploads `hoarbound-jenova-linux-build-log` even on failure. Run d566f19 (37818722900)
  is the first with that log. Read it first:
  `gh run download 37818722900 -n hoarbound-jenova-linux-build-log`.
- **Known facts.**
  - The Linux compiler is `clang++` from `PATH` (the CI job symlinks clang-19).
  - Modules link against `libGodot.x64.a` and `Jenova.Runtime.Linux64.so`.
  - The compiler and SDK paths are patched in `bootstrap_jenova_linux.sh`.
- Full context: `docs/technical/JENOVA.md`.

## 2. Native-code candidates (decided: measure first, then port)

The source is `docs/technical/PERFORMANCE_AUDIT_2026_10_03.md` (HD 620, Key
West, 1080p), re-read against the code on 2026-10-09. The steady-state frame is
GPU-bound (root pass ~133 ms, local snow ~47 ms), and no script port changes
that. The CPU candidates below are generation stalls.

1. **SnowField rebuild** (`scripts/systems/world/snow/snow_field.gd`:
   `_grid_span`, `_assemble_row`, `_blur`).
   - Cost:
     - 4–12 ms per physics frame while Henry walks (incremental, budgeted in
       `SnowShell._follow`);
     - a 1.6–2.4 s freeze on the first window, a load or a long jump
       (`SnowShell.recentre_to` -> synchronous `SnowField.rebuild`).
   - A C# prototype matched the output at ~32x on the depth part.
   - **Port first, preferably to C#** (project rule: heavy math in C#; Jenova
     is still beta).
2. **IslandTerrain chunk mesh build**
   (`scripts/systems/world/terrain/island_terrain.gd`, `builds_per_frame`
   queue).
   - Cost not measured.
   - NOAA heights never change, so **bake the meshes before considering native
     code**.
3. **City chunk activation** (`KeyWestStreetProps.build_chunk_body`,
   `KeyWestCityVisuals.build_supplemental_node`, snow height sampling).
   - About 2.3 s per chunk outside the now-baked snow clipping, of which about
     1.1 s is height sampling.
   - **Bake** like the snow cover in 6bf7131 before porting.

Already solved: the snow face clipping (9.8 s per chunk), baked in 6bf7131.
Not worth porting: `SnowShell` per-frame work (shader parameters only).
Frozen: motion matching (BUILD_PLAN step 10).

**Next step.** Write a headless CI timing script for candidates 1–3:
SnowField rebuild at the real window size, one terrain chunk build and one city
chunk activation. Run it once, then choose port or bake per item. CI absolute
times differ from the HD 620, but the ratios between candidates hold.

# Key West Reality: HLOD v1 (Tier 0 detail ↔ Tier 1 proxy clusters)

Status: v1 on one dense sector, CI green (run 744), 2026-10-14. Tracking issue: Nolavel/Hoarbound#219.
Scope from the owner's brief:
- Tier 0 is the existing detail; Tier 1 is offline proxy clusters; there is no Tier 2 work.
- Static opaque buildings only, in one sector.
- The existing streamer is used; no second streamer.
- No island-wide bake until the sector shows a measured gain.

## 1. What existed (read before design)

| Piece | Fact |
|---|---|
| Detail chunks | 512 m `kw_gen_x_z`, `StreamingSystem` load band = chunk radius 362 m + 140 m margin, unload +120 m hysteresis; parts attach under a 4 ms/frame budget |
| Buildings in a chunk | one `MeshInstance3D` per building, 2 surfaces (walls, roof); one trimesh collision per chunk |
| Far view | `KeyWestRealityFar`, a runtime source of the same streamer: one far mesh per chunk (16 m terrain + building prisms) within 2,500 m, hidden while the chunk is ACTIVE/ASSEMBLING |
| Winter | per-chunk `Winter` part: roof caps with eave lips, fence/wire ridges, pole caps; `visibility_range_end` 450 m |
| Densest chunks | -5:2 594, -6:2 543, -5:1 521, -6:1 518 generated buildings; the 2×2 Old Town sector holds 2,176, none authored |

## 2. Baseline (before)

`tools/runtime/measure_key_west_hlod.gd`, the real `key_west_reality.tscn` (World, Henry, blizzard, streaming).
Setup:
- Five fixed stations: free camera, Henry placed under it so the streamer loads the same cells.
- CPU Vulkan (lavapipe), 1280×720.
- At each station: wait until streaming settles, then 10 warm frames and 20 sampled frames.
- Draw calls are attributed by hiding one group at a time; these numbers are ±20 frame to frame (weather).

| Station | Draw calls | of them buildings | Primitives | Render CPU ms | Objects | Nodes | Geometry instances |
|---|---|---|---|---|---|---|---|
| s1 street, sector core | 1,959 | 1,416 | 4.19 M | 5.38 | 2,210 | 4,462 | 3,170 |
| s2 street, sector west edge | 1,626 | 1,174 | 4.53 M | 5.00 | 1,877 | 4,220 | 2,884 |
| s3 roof overview | 2,382 | 1,798 | 4.82 M | 6.78 | 2,632 | 4,218 | 2,881 |
| s4 from 727 (control) | 1,634 | 1,176 | 4.75 M | 5.30 | 1,910 | 3,410 | 2,000 |
| s5 far east (control) | 899 | 285 | 1.92 M | 4.00 | 1,154 | 2,211 | 1,002 |

Findings:
- **Buildings are the draw-call cost.** They are 72–75 % of the draw calls, yet only 67–118 k primitives.
- **Primitives sit elsewhere.**
  - At s1: vegetation 1.86 M (instanced, about 14 draw calls), terrain 1.03 M, Winter 0.51 M. Roof caps with their lips are 8× the triangles of the roofs they sit on.
  - On lavapipe the frame is bound by rasterising these (GPU ≈ 1.3 s). On this machine draw calls show up as render CPU time (4–7 ms), not as FPS.
- **Most buildings are far.** At s1, 608 of the 717 buildings in view (85 %) are 300–800 m away, all inside the four loaded chunks.
- **s4 and s5 are controls.** At s4 the sector is beyond the chunk band and the far meshes draw it; at s5 Henry stands in other chunks. HLOD v1 must leave both unchanged.

### Cluster size

| Size | Estimated building draw calls on the route | Why |
|---|---|---|
| 1024 m (2×2 chunks, the brief's candidate) | 4,852 (−0 %) | larger than the whole detail band (≈500–620 m): a cluster is never in HLOD while any of its chunks is loaded |
| 512 m (one chunk) | 4,852 (−0 %) | same reason |
| 256 m | 1,514 (−69 %) | |
| **128 m** | **1,154 (−76 %)** | chosen: 16 clusters per chunk, 64 in the sector |

The estimate uses `editor_index.json` footprints, the same five stations, the streamer's real bands, a 102° view
wedge, 2 draw calls per detail building and 4 per proxy. The after-measurement below replaces it.

A useful property of power-of-two cells: a corner cluster's centre plus its radius equals the chunk radius. So a
cluster's load band (radius + 140 m) is never larger than its chunk's load band, and its unload band never larger
than the chunk's unload band.

## 3. Design

**Tier 0.** In the HLOD chunks listed in `config/hlod.json`, the chunk generator writes each generated building into
a 128 m cluster scene, `generated/clusters/Cluster_c128_<gx>_<gz>.scn`, instead of the chunk's `Buildings`
group.
- **Cluster membership:** the footprint centroid, clamped into the owning chunk, so clusters never straddle chunks.
- **Cluster scene contents:** the building meshes, a `BuildingCollision` for exactly those buildings, and their roof
  caps under `Winter`.
- **Streaming:** each cluster is an ordinary static `WorldData` cell `kw_bld_c128_<gx>_<gz>` of the same
  `StreamingSystem`. It loads within 230.5 m of the cluster centre and unloads past 350.5 m (120 m hysteresis), on
  loader threads, under the instantiation budget.
- **What stays in the chunk:** snow footprints (on the chunk root, for the dynamic snow) and everything that is not a
  generated building.
- **Chunks outside the config** are built exactly as before; their digests are unchanged.

**Tier 1.** `KeyWestHLODBuilder` (`tools/world/reality_gen/key_west_hlod_builder.gd`) builds one proxy mesh per
cluster from the same chunk export.
- **Geometry:** the same building geometry code as the detail.
- **Merge:** by material bucket (`walls`, `walls_placeholder`, `roof_*`, `snow_roof`).
- **Not done:** no atlas, no baking, no decimation; the profile says draw calls, not triangles, are the building
  cost.
- **Output:** `generated/hlod/HLOD_<cluster>.res` plus `hlod_manifest.json`.

**Runtime.** `KeyWestRealityHLOD` (node `HLODView` in the Reality content scene) does no distance work. It reacts to
the streamer's cell states, as the far view does:

| Chunk | Detail cell | Drawn |
|---|---|---|
| ACTIVE/ASSEMBLING | ACTIVE | detail (proxy node freed in the same signal) |
| ACTIVE/ASSEMBLING | anything else | proxy (created from a resource loaded in the background while the chunk loaded) |
| not in | any | far mesh; a detail cell that beat its chunk in stays hidden until the chunk is in |

- **Atomic swap:** the streamer emits ACTIVE right after `add_child` and UNLOADED right after `remove_child`, so each
  swap happens within one frame. Both representations never draw together, and the cluster never draws empty.
- **Proxies are bare:** a `MeshInstance3D` only, with no collision, navigation or gameplay nodes; nothing far away
  needs them. Building collision exists only with the detail cell.
- **Hysteresis:** the streamer's own 120 m band.

**Policies:**
- **Authored buildings** (727 Fort St, Fort Zachary Taylor, any keep/keep_locked/needs_rebase asset) are excluded and
  listed in the manifest with their policy. They stay Tier 0 in their chunk; manual proxies are phase 2. The sector
  has none.
- **Props** are excluded: Reality props are 0.15 m cylinders, already one MultiMesh per chunk, about one pixel at the
  switch distance.
- **Terrain, vegetation and gameplay** are out of v1.
- **Winter:**
  - **Roof snow:** folded into the proxy. Roof faces flatter than `static_snow.slope_zero_deg` (70°, the same rule
    that decides where caps lie) go to the `snow_roof` bucket in the cap colour. This adds no triangles. The detail
    cap with its lips (≈ 232 k triangles in the sector) exists only with the detail cell.
  - **Wire, fence and pole snow** in HLOD chunks ends at the cluster detail band (230.5 m) through
    `visibility_range_end`, instead of 450 m.

**Manifest** (`generated/hlod/hlod_manifest.json`, no timestamps).
- **Per cluster:**
  - identity and placement: stable `cluster_id`, chunk, grid cell, centre, world bounds, detail cell and scene;
  - sources: sorted `source_ids`, `source_count`, `source_hash`;
  - versions: `build_version`, `builder_version`;
  - proxy: `proxy_path`, `proxy_digest`;
  - geometry: triangles (proxy, detail, snow roof), surfaces, materials, triangles per bucket.
- **Global:** policy, winter policy, exclusions and authored assets, totals.

## 3a. After (same tool, same stations, same machine)

| Station | Draw calls | Building draw calls (+ proxies) | Primitives | Winter primitives | Render CPU ms | Wall frame ms | Objects | Nodes | Geometry instances | Settle frames |
|---|---|---|---|---|---|---|---|---|---|---|
| s1 core | 1,959 → **641** (−67 %) | 1,416 → 56 (+26) | 4.19 → 3.68 M | 515 k → 2 k | 5.38 → **3.01** | 1,557 → 1,415 | 2,210 → 892 | 4,462 → 2,660 | 3,170 → 1,345 | 86 → 96 |
| s2 west edge | 1,626 → **800** (−51 %) | 1,174 → 322 (+46) | 4.53 → 4.44 M | 392 k → 297 k | 5.00 → 3.57 | 1,690 → 1,717 | 1,877 → 1,050 | 4,220 → 3,819 | 2,884 → 2,474 | 21 → 21 |
| s3 overview | 2,382 → **1,399** (−41 %) | 1,798 → 784 (+28) | 4.82 → 4.83 M | 323 k → 326 k | 6.78 → 4.91 | 2,129 → 2,039 | 2,632 → 1,648 | 4,218 → 3,725 | 2,881 → 2,389 | 21 → 21 |
| s4 control | 1,634 → 1,633 | unchanged | unchanged | unchanged | 5.30 → 5.62 | 2,037 → 2,076 | unchanged | unchanged | unchanged | 21 → 21 |
| s5 control | 899 → 899 | unchanged | unchanged | unchanged | 4.00 → 3.99 | 1,258 → 1,232 | unchanged | unchanged | unchanged | 59 → 59 |

Reading:
- **Draw calls and CPU.** In the sector, draw calls fall by 41–67 % and render CPU time by 28–44 %.
- **Frame time does not get worse.** The wall frame is better at s1 and s3. At s2 and the controls it moves within ±2 %, which is
  the noise level where nothing changed (s4: identical draw calls, +2 % wall).
- **Winter.** At s1, 513 k Winter primitives leave with the far detail cells: caps and lips no longer draw past
  230–350 m, and the proxy roofs carry the snow at no extra triangles.
- **Streaming.**
  - **Proxies:** they never blocked (0 synchronous loads).
  - **First entry at s1:** it took 10 more frames to settle (86 → 96), because 10 detail cluster cells and 54 proxies
    come in with the 4 chunks.
  - **Elsewhere:** settle frames are unchanged.
  - **Not split out:** this machine renders a frame in 1.4–2 s, so per-cell instantiate time is not measured
    separately; it needs a GPU machine.
- **Memory.** Static memory is about 50 MiB lower at every station, but the tool runs the stations in one process,
  so this is cumulative, not per station.
- **Controls.** s4 and s5 are unchanged by design: there the sector is beyond the chunk band and the far meshes draw it.

Raw JSON (before/after, per-group attribution, distance bands, HLOD representation counts) and frames:
`docs/runtime_previews/key_west_reality_hlod/`.

## 3c. Real GPU: the owner's machine (2026-10-14)

`measure_key_west_hlod.gd`, same five stations, run twice per mode on one build:
- **Machine:** Intel HD Graphics 620 (the minimum-target class), Windows 10, Godot 4.8-dev6 mono, Vulkan Forward+.
- **Settings:** graphics quality LOW, 1920×1080 borderless full screen, blizzard weather.
- **Modes:**
  - **HLOD:** the runtime as shipped.
  - **All detail:** the new `--all-detail` flag swaps every proxy for its detail scene after settling. That is the
    pre-HLOD frame on the same build; its draw calls match `measure_before.json` (lavapipe) to within ±13.
- **Raw data:** `docs/runtime_previews/key_west_reality_hlod/gpu_2026-10-14/`. Each cell below is run 1 / run 2.

| Station | Draw calls before (lavapipe) | Draw calls all detail → HLOD | Objects | FPS all detail → HLOD | Wall frame ms all detail → HLOD | Render CPU ms all detail → HLOD | Render GPU ms all detail → HLOD |
|---|---|---|---|---|---|---|---|
| s1 core | 1,959 | 1,972 → **645** (−67 %) | 2,221 → 894 | 2.8 / 4.8 → 3.7 / 5.2 | 240 / 173 → 342 / 178 | 13.3 / 18.0 → **9.3 / 7.6** | 197 / 89 → 86 / 86 |
| s2 west edge | 1,626 | 1,627 → **796** (−51 %) | 1,876 → 1,045 | 3.8 / 4.5 → 3.7 / 3.0 | 236 / 192 → 278 / 313 | 16.7 / 16.9 → 8.9 / 22.6 | 146 / 112 → 208 / 208 |
| s3 overview | 2,382 | 2,386 → **1,400** (−41 %) | 2,634 → 1,648 | 3.5 / 6.5 → 5.5 / 3.3 | 235 / 142 → 304 / 292 | 16.2 / 19.6 → 13.1 / 34.5 | 217 / 121 → 195 / 238 |
| s4 control | 1,634 | 1,633 → 1,634 | unchanged | 3.3 / 6.7 → 3.1 / 3.0 | 241 / 155 → 284 / 334 | 12.1 / 20.1 → 13.1 / 30.6 | 207 / 127 → 157 / 263 |
| s5 control | 899 | 898 → 899 | unchanged | 3.5 / 7.3 → 4.2 / 7.9 | 263 / 126 → 283 / 125 | 7.1 / 13.0 → 10.6 / 10.8 | 146 / 104 → 147 / 94 |

Reading:
- **What holds:** draw calls and objects are deterministic, and they show the same gain as on lavapipe (−41…−67 %).
  At s1, render CPU time falls on both runs (13–18 → 8–9 ms).
- **What does not show:** FPS and wall frame. The controls s4 and s5 draw the identical scene in both modes, yet
  their wall frame moves between 125 and 334 ms from run to run. That noise is ten times the HLOD effect (5–10 ms of
  render CPU), so this machine gives no FPS verdict for HLOD, in either direction.
- **The real finding:** on the minimum-target GPU the game runs at **3–8 FPS** at LOW, 1080p, in a blizzard.
  - The frame is 125–340 ms, and GPU rendering alone is 85–260 ms of it.
  - The engine's process-time monitor reads 76–830 ms. It averages over its own window, so it does not add up with
    the wall frame, but it puts script time in the same range as the GPU.
  - Render CPU, which is what HLOD reduces, is only 7–35 ms.
  - The first optimisation target on this hardware is therefore not draw calls. It is GPU load (3.7–4.8 M primitives
    per frame: vegetation ~1.9 M, terrain ~1 M, Winter caps) and main-thread script time. Its breakdown (snow
    contact viewport, physics) is not part of this measurement.
- **Streaming on this machine:** 0 blocking proxy loads in every run. The largest proxy burst is 16 per frame.

## 3b. Transition cost and scale (after Codex's review in #219)

`test_key_west_reality_hlod_boundary.gd` (CI, headless) does one real-streamer pump per frame:
- **Entering the sector from afar:** a proxy burst.
- **Four passes in and out across one cluster's edges:** the first pass is cold, the later ones warm.
- **Stage timing:** `StreamingSystem.measure_stages` and `KeyWestRealityHLOD.measure_stages` emit `stage_timed`;
  off by default.

| Stage | Cost |
|---|---|
| proxy fetch / add / free | ≤ 0.1 ms each; a burst of 16 proxies in one frame stays under 1 ms |
| detail cluster instantiate, first entry (cold) | 2–3.5 ms |
| detail cluster instantiate, repeat entries | 0.6–1 ms |
| worst stage in the burst frame | 11 ms: `attach_part` of a non-HLOD chunk (`kw_gen_-4_2`), not HLOD |

Under Vulkan (lavapipe):
- Main-thread pump time is the same.
- The first frame of the entry takes ≈ 1 s: pipeline compilation on first use on a software renderer.
- Later frames take 30–55 ms of rendering whether or not anything swaps.

The test therefore judges frame time headless only.

**The production gate:**
- **Diagnostics:** the gate now times every stage and prints, for each hitch over 50 ms, the cell changes and stages
  of 1 ms or more in the 3 frames before it, plus the HLOD counters.
- **A/B:** `--no-hlod` removes only the proxies, for an A/B on one commit. A manual (`workflow_dispatch`) CI step runs
  it.

**Streamer scale is the blocker for widening.** Bookkeeping cost with nothing in band (`scan()` runs every 40 m,
`pump()` every frame):

| Cells | `scan()` | idle `pump()` |
|---|---|---|
| 523 (today: 459 chunks + 64 clusters) | 0.49 ms | 0.32 ms |
| 7,759 (island in 128 m clusters) | 10.2 ms | 7.8 ms |

The fix belongs in the streamer before any island bake:
- `pump()` walks only cells in transient states;
- `scan()` uses a spatial grid instead of every cell.

**Done (2026-10-14).** Inside `StreamingSystem`, with the public API, the signals, the budgets and the hysteresis
unchanged:
- **`pump()`** walks a set of cells in QUEUED, LOADING, READY or ASSEMBLING, kept in `_set_state`. READY cells
  still activate in registration order.
- **`scan()`** asks a fixed grid with 256 m buckets. Each cell is filed under every bucket its load band (radius +
  `load_margin_m`) overlaps, so the player's bucket holds every cell that could load. Live cells outside it are
  checked for release.
- **Grid rebuild:** a changed `load_margin_m` rebuilds the grid on the next scan.
- **Cold cache:** looks up cells by scene path instead of walking every cell.

Measured with `tools/runtime/benchmark_streaming_scale.gd` (new, reproducible): 200 calls each on the owner's laptop
CPU. Every cell loads an empty scene, so only the bookkeeping is timed. Two runs each; the range is shown.

| Cells | Where | `scan()` before → after | idle `pump()` before → after |
|---|---|---|---|
| 523 (Reality today) | off the island | 1.45–2.30 → 0.002–0.006 ms | 0.60–1.09 → 0.003–0.005 ms |
| 523 | Old Town, 16 cells in | 1.82–2.41 → 0.18–0.31 ms | 0.71–1.21 → 0.003–0.008 ms |
| 7,803 (island in 128 m clusters) | off the island | 30.3–35.6 → 0.002 ms | 13.4–14.4 → 0.002–0.003 ms |
| 7,803 | Old Town, 16 cells in | 27.4–29.3 → 0.26–0.29 ms | 12.9–13.4 → 0.003–0.023 ms |

- **Cost no longer grows with island size.** It now depends on the cells near the player. In both versions the same 16
  cells are active at Old Town.
- **This CPU vs CI:** the "before" numbers here are about 3× the CI runner's (0.49 / 0.32 ms at 523 cells).
- **Guard:** `test_streaming` gained a check that walks 400 cells of mixed radii (20 m to 2.5 km) over 120 random
  positions, including a margin change. After each scan it checks every cell against the bands and the transient and
  live sets against the states. Removing the margin from the grid makes this check fail.

### Gate hitch: cause and fix

| Run | HLOD proxies | Hitches over 50 ms | Blocking proxy loads |
|---|---|---|---|
| 736 (before HLOD) | – | 0 | – |
| 737, 740 (88871cf2, faddde21) | on | gate failed | not visible (log tail) |
| 740 A/B (same commit) | off | 0 | – |
| local, 2 cores like the runner | on | one hitch at the moment of a wait | 3 |
| 742 | on | 0 | 0 |
| 744 (8a752355, fix) | on | 0, gate passed | 0 |
| 744 A/B | off | 1 (51.4 ms near 727, no cell change in 3 frames: runner noise, as in run 721) | – |

- **Cause:** proxy loads were requested when the chunk queued and waited behind its heavy part scenes. When the chunk
  started assembling, `load_threaded_get` blocked the main thread for the proxies still in the queue.
- **Fix:** proxies start loading when the chunk's far cell (2,500 m) is in, about 2 km earlier. They are released only
  when both the far cell and the chunk are out.
- **Guard:** the boundary test runs the real far view and fails on any blocking proxy load.

### The 11 ms `attach_part`: it is collision, not node attachment (2026-10-14)

The owner's audit (#219, point C) asked for the 11 ms `attach_part` of `kw_gen_-4_2` to be broken into stages and time
sliced, after the deadline queue of Godot-Open-World-Database (`batch_processor.gd`, `batch_time_limit_ms`). Measured
first, with `tools/runtime/measure_attach_parts.gd` (every chunk scene and part on the island, 1,456 scenes):

- `add_child` costs 0.02–0.4 ms per part, so slicing the attach does not help.
- The cost is the first `instantiate()` of a freshly loaded part. A repeat instantiate of the same part costs 2–3 ms.
- For a part with a `ConcavePolygonShape3D` (every `Buildings` part), the gap is one collision rebuild.
  - In debug builds `CollisionShape3D::set_shape` writes its debug colour into a shape whose debug properties were never
    set (`shape_3d.cpp`, `collision_shape_3d.cpp`, Godot master).
  - For a concave shape that calls `shape_set_data` again: 4.7–8 ms per `Buildings` part, and 39 ms for the fort chunk
    `-9_3`.
  - A repeat `set_shape` costs 0.02 ms.
  - Release templates compile this out.
- Island-wide, first instantiate: p99 6.3 ms, max 39.5 ms, 4 scenes over 10 ms. Repeat instantiate: p99 3.5 ms, max 9.7 ms.

**Rejected: warming the shapes on a worker.** `PhysicsServer3DWrapMT` with `run_on_separate_thread = false` (ours) runs
every call from a non-main thread on the main thread. It queues the call and flushes it at `sync()` or before the next
direct call (`server_wrap_mt_common.h`, `flush_if_pending`). The rebuild only moved: in the boundary test the next chunk
root's instantiate took 7–8 ms while 4–5 warm tasks were queued.

The loader's own `set_faces` is queued the same way. A frame that only finishes loading a `Buildings` part takes 15–22 ms,
85 ms for `-9_3`; a mesh-only part takes 7 ms. That cost exists in release builds too.

| Physics | Buildings instantiate (debug) | Frame that finishes loading a Buildings part |
|---|---|---|
| GodotPhysics (current `DEFAULT`) | 9–18 ms, `-9_3` 84 ms | 19–22 ms, `-9_3` 85 ms |
| Jolt (built in; default for new projects since 4.6) | 2–3 ms | 10–12 ms, `-9_3` 75 ms |
| GodotPhysics on a separate thread | 0.5–2.6 ms | unchanged: `sync()` waits for the same build every frame |

Jolt builds a mesh shape lazily when it is first used, so a part pays one build instead of two, and a cheaper one.

**Jolt on the full suite:** the same 10 suites fail as on GodotPhysics, with identical messages. They fail on current
`main` too and are not in CI: `dev_diorama_map`, `door_draft`, `doorway_camera`, `held_fit`, `held_light`,
`passage_traversal`, `snow_contact_pipeline`, `snow_shell`, `street_props_streaming`, `tps_camera_orbit`.

**Jolt on the gate and the 727 loop (one machine, same route):**

| | GodotPhysics | Jolt |
|---|---|---|
| frame p50 / p95 / p99 | 6.86 / 14.53 / 17.33 ms | 6.83 / 14.32 / 17.26 ms |
| frames > 33 / > 50 ms | 93 / 12 | 74 / 18 |
| static memory peak | 403 MB | 439 MB |

- Both runs fail the local 50 ms rule: most hitches have no cell change, i.e. this container's noise; CI passes the same
  gate.
- The 727 loop passes under Jolt.
- Decision: Jolt from now on. It is one revertable line in `project.godot`; Henry's movement feel needs the owner's
  check.

The fort chunk `-9_3` stays an outlier under either engine. `kw_fort_zachary_taylor.glb` carries two concave
collision meshes of 43,691 faces in all. The largest generated `Buildings` chunk has 8,466 faces; the island median is
884. The fix is a simplified collision mesh for the fort, authored in Blender, as a separate asset task.

### Fort collision simplified in Blender (2026-10-15)

`tools/blender/landmark_collision.py` (Blender 5.2 `bpy`) runs the fort's `FortSurface-col` mesh through Decimate
Collapse at ratio 0.2 and writes the copy into the same `.glb` as `FortSurfaceCollision-colonly`; the visual node
loses its `-col` suffix. The visual buffers stay byte-identical. The walls (`FortWalls-col`, 2,494 faces) keep
their own trimesh. The manifest marks the asset `artist_modified`, so `landmarks.py` does not overwrite it.

How the method was chosen (all measured on the fort, Jolt, this container):

| Option | Faces | Error (3D, source vertices and face centres): mean / p99 / max | Build |
|---|---|---|---|
| current trimesh | 41,197 | 0 | 89.5 ms for a 41k-face trimesh |
| Dissolve 2° | 20,954 | 0.2 / 1.6 / 3.8 cm | |
| Dissolve 4° | 14,446 | 0.7 / 4.1 / 33 cm | 20.9 ms for 14.5k faces |
| **Collapse 0.2** | **8,238** | **0.8 / 5.1 / 12.5 cm** | |
| Collapse 0.12 | 4,943 | 1.5 / 10.8 / 36.5 cm | 5.8 ms for 5k faces |
| `HeightMapShape3D` 270×380 at 0.5 m (holes as NaN work) | — | 0 at the samples | 285 ms: rejected |

Splitting into tiles inside one `.glb` would not help: the resource's shapes are all built when it finishes loading.

Result, `measure_attach_parts.gd` on `kw_gen_-9_3`, two runs each: the `Buildings` part (the fort) 66–80 ms → 11.6–12.0
ms. The chunk root (26–40 ms) does not contain the fort and is unchanged. Walking surface against an exact trimesh of the
visual surface, 1 m ray grid (5,230 rays): median 5 mm, p99 8 cm, 5 rays over 30 cm (vertical wall edges), 1 miss at the
rim. `test_landmark_collision` guards this.

## 4. Reproducibility and dirty rebuild

- **Source hash:** `sha256` over the build settings (HLOD build version, chunk builder version, cluster size, snow
  slope) plus each member's full export record, in sorted feature-id order.
- **Dirty rebuild:** a cluster is dirty when its hash, its build version or its proxy file changed. `--dirty`, and the
  dock's "Rebuild dirty", build only those. Editing one building dirties exactly its own cluster
  (`test_key_west_reality_hlod.gd`).
- **Digest:** the HLOD digest is the sha256 of the manifest text. Deleting `generated/hlod` and rebuilding gives the
  same digest and byte-identical files (checked locally). One cluster built alone equals the full build.
- **CLI:** `build_key_west_hlod_cli.gd -- [--clean] [--all | --dirty | --cluster <id>...] [--check]
  [--record-digest] [--verify-digest] [--verify-partial <id>...]`.
- **`--check` fails on:**
  - missing or duplicate source ids;
  - a proxy without a detail cluster, or a detail cluster without a proxy;
  - an orphan proxy file;
  - a proxy that differs from its manifest digest;
  - a stale cluster.

## 5. Reality Editor

The Reality dock gains production controls only, not a separate HLOD editor:
- **Info:** the cluster of the picked building (or the one under the marker), with id, the tier the editor shows,
  fresh/dirty, source count, proxy and detail triangles, and surfaces and materials.
- **Here:** picks that cluster.
- **Bounds:** a wire box from the manifest.
- **Tier 0/1:** previews the detail or the proxy in place.
- **Sources:** lists the source ids; double-click one to find it.
- **Build selected, Rebuild dirty.**

The editor view assembles a chunk's clusters with it, so the editor still shows every building.

## 6. CI

The `key-west-reality` job, after the chunk rebuild:
- **HLOD clean rebuild, digest and source checks:** `--clean --all --check --verify-digest`.
- **HLOD partial rebuild equals the full build:** `--verify-partial c128_-21_6`.
- **`test_key_west_reality_hlod` in the streaming tests:**
  - offline output: manifest, proxies and detail cells agree; HLOD chunks hold no generated building;
  - dirty isolation;
  - a walk east → core → west → core with the invariant checked after every pump (never both, never none);
  - proxies without children;
  - round trips;
  - a wobble inside the hysteresis band.

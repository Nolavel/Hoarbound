# Key West Reality: HLOD v1 (Tier 0 detail ↔ Tier 1 proxy clusters)

Status: v1 prototype on one dense sector, 2026-10-14. Tracking issue: Nolavel/Hoarbound#219.
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

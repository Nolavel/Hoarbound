# Key West generated chunks in production streaming

`tools/runtime/benchmark_key_west_reality_streaming.gd` streams the 459 generated chunks
(`scenes/world/key_west/generated/world_data.tres`) through the production `StreamingSystem`:
- defaults: margin 140 m, hysteresis 120 m, 2 concurrent loads, 1 instantiation per frame;
- the player moves in real time;
- headless, on this 4-core CPU container.

"Streaming cost" is the main-thread time of `StreamingSystem._process`, i.e.
`instantiate()` + `add_child()` plus bookkeeping. GPU upload is not measured here.

| Run | Before the fixes | After |
|---|---|---|
| First Exit, 619 m at 6 m/s: still at spawn until everything near is active | > 120 s (timed out) | 0.44 s |
| First Exit: time standing on an unloaded chunk | 6.7 s | 0 s |
| First Exit: worst chunk activation | 122 ms | 29 ms |
| Island, 11.7 km at 25 m/s: time on an unloaded chunk | — | 0 s (47 activations) |
| Island: activation p50 / p95 / max | — | 10 / 23 / 25 ms |
| Island: frames > 16.7 ms / > 33.3 ms (of 68k) | — | 13 / 0 |
| Island: static memory, start / peak / after leaving | — | 47 / 232 / 97 MB |

**Fixes behind the "after" column:**
- `StreamingSystem` fills free load slots every frame, nearest first. Before, queued
  chunks waited for a 40 m rescan.
- The packed-scene cache is an LRU of 8 cold scenes. Before, it grew without limit.
- Building collision is one prism per outline per chunk. A BVH over the render triangles
  cost 108 ms on first instantiate.
- Trees, poles and props are MultiMesh nodes.
- With a prewarm profile, the spawn band is activated synchronously. Before, the player
  fell through the fort while its chunk was still loading.

Reports: `stream_report_first_exit.json`, `stream_report_island.json`.

For comparison, the current JSON city activates a chunk in about 2.3 s
(`docs/technical/OPEN_TASKS.md`).

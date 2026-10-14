# Key West Reality HLOD v1 captures

Design and numbers: `docs/technical/REALITY_HLOD.md`. CPU Vulkan (lavapipe), 1280×720, downscaled to 960 px.

| Files | What |
|---|---|
| `measure_before.json`, `measure_after.json` | `tools/runtime/measure_key_west_hlod.gd`, same five stations before and after: draw calls, primitives, render CPU/GPU, objects, nodes, instances, memory, settle frames, per-group attribution, buildings by distance |
| `before_<station>.png`, `after_<station>.png` | the frame each station sampled (real scene, blizzard) |
| `tiers_<camera>_all_detail.png` | calm weather, every cluster forced to its detail (what the sector looked like before HLOD) |
| `tiers_<camera>_runtime.png` | the runtime frame: detail within the cluster band of Henry, proxies beyond |
| `tiers_<camera>_tiers.png` | the runtime frame with proxies tinted orange |
| `tiers_<camera>_diff.png`, `tiers.json` | runtime vs all-detail, difference ×4: 0.04–0.09 % of pixels differ by more than 10 %, mostly flat roofs where the layered cap shade meets the proxy's even snow colour; no building is missing or doubled |

`tools/runtime/capture_key_west_hlod_tiers.gd` produces the tier frames.

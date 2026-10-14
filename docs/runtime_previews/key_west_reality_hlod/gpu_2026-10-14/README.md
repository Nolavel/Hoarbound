# HLOD on the owner's GPU, 2026-10-14

- **Machine:** Intel HD Graphics 620, Windows 10, Godot 4.8-dev6 mono, Vulkan Forward+.
- **Settings:** graphics quality LOW, 1920×1080, blizzard.

| File | Mode | Command |
|---|---|---|
| `gpu.json`, `gpu_run2.json` | HLOD as shipped | `godot --path . --script tools/runtime/measure_key_west_hlod.gd -- <dir> gpu` |
| `gpu_all_detail.json`, `gpu_all_detail_run2.json` | every proxy swapped for its detail scene (pre-HLOD frame) | same, with `--all-detail` |
| `gpu_<station>.png`, `gpu_all_detail_<station>.png` | the frame at each station, run 1 of each mode | |

The reading is in `docs/technical/REALITY_HLOD.md` §3c.

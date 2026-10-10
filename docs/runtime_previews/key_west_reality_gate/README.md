# Key West reality — production gate

`tools/runtime/gate_key_west_reality.gd` runs the real `scenes/world/key_west/key_west_reality.tscn`:
the full `World` (15 systems), Henry, the TPS camera, snow, weather and streaming.

Henry is driven by input (`move_forward`, camera yaw, pure pursuit) along
`data/world/key_west/reality/routes/first_exit_gate.json`, a 3.8 km least-cost street route:
Battery start → 727 Fort St → Petronia → Duval → Front → Whitehead → 727.

This run: `--fast` (sprint, stamina and snow assist), headless, on a 4-core CPU container.
It covers CPU-side cost only. Render cost must be measured on the target GPU (HD 620),
without `--fast`.

| | First full run | After the gate's fixes |
|---|---|---|
| Distance / game time | 3.73 km / 1185 s | 3.71 km / 1034 s |
| Time on an unloaded chunk | 0 s | 0 s |
| Engine errors (headless dummy-renderer texture reads counted apart) | 0 | 0 |
| Blocked stalls (Henry pinned) | 78* | 0 |
| Frames > 50 ms | 344 | 20 |
| Frame p50 / p95 / p99 | 4.2 / 16.4 / 34.0 ms | 5.5 / 13.9 / 16.4 ms |
| Chunk activation frame p50 / max | 50 / 660 ms | 39 / 60 ms |
| Arrived at 727 entrance; sheltered | yes; no (no opening is modelled) | yes; no |

\*The first run's stall rule was distance-based and also caught steering orbits. Diagnosis
split the 78 into steering orbits and one real pin. The real pin was the canopy-lifted
footbridge deck, now fixed.

Fixed by this gate:
1. Bridge decks are no longer lifted by canopy (`meshing.deck_profile`).
2. The snow shell no longer raycasts every cell: `KeyWestRealityGround` serves heights and
   building outlines (`snow_shell.gd` group lookup). On the First Exit leg, frames over
   50 ms went 78 → 2 and p99 35.9 → 16.7 ms. The legacy JSON-city scene measures 21 and
   18.2 ms on the same harness.

Still failing the verdict: 20 frames over 50 ms.
- 4 sit next to a chunk activation (40–60 ms in the full World, against 12–28 ms isolated).
- 16 are not activations; in them process + physics are only 15–30 ms.
- The next pass is a bounded main-thread activation budget (chunk activated in parts),
  then profiling the remaining non-activation frames.

Run on the target machine (Windows: run Godot directly):

```
python3 tools/world/reality/export_pack.py unpack
godot --path . --rendering-driver vulkan --script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- --verify-digest
godot --path . --script res://tools/runtime/gate_key_west_reality.gd -- --legs=1 --shots --out=user://gate_hd620
```

Then send `gate_report.json` (in the Godot user dir, `gate_hd620/`). The exit code is
always 0 because of Jenova; read the `verdict` in the report.

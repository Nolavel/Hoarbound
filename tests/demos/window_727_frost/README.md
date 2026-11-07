# Issue #281 — new art iteration: the thaw of the 727 FrontWindow1

One finished six second film of the real `FrontWindow1` pane, white crystalline
frost receding from the glass. Test-only: no production material, no shared
shader and no game system is touched.

## What is in here

| file | role |
|---|---|
| `frosted_glass_727_art_thaw.gdshader` | the new material: production frost pattern + new thaw geometry |
| `window_727_frost_probe.gd` | isolated scene: real pane, neutral light, neutral background, static camera |
| `../../tools/runtime/capture_window_727_frost.gd` | capture harness (72 frames, 12 fps, 960x540) |

Base sources, taken over unchanged from the `codex` branch for issue #281:

- `res://shaders/environment/windows/frost_pattern.gdshaderinc` (production, unchanged)
- `res://shaders/common/sdf_smooth_union.gdshaderinc` (from `codex`)
- `res://tests/demos/window_727_sdf/sdf_frosted_glass_727.gdshader` (from `codex`)
- `res://tests/demos/window_727_sdf/window_727_sdf_probe.gd` (from `codex`: the real pane extraction)
- `res://tests/demos/window_727_real_light/lit_frosted_glass_v3_white_tint_only.gdshader` (from `codex`: the approved control)

The pane is the real `FrontWindow1` of the 727 Fort St GLB: twelve source glass
triangles with their authored UV and COLOR, extracted with the landmark spec.
No invented quad, no substituted glass.

The scene holds nothing else: no game world, no interior, no stove, no weather,
no streaming, no LUT, no postprocessing. Two white directional lights and a
neutral background, so the frost reads as white ice.

## Art direction

The composition follows real window frost rather than the SDF demo:

- separate frond clusters with calm glass between them, not an even sheet;
- the frame stays denser, but the cold rim is broken by a perimeter noise
  instead of a uniform white band;
- large calm stretches and dense stretches (a broad density field);
- the thaw travels as elongated, bent, branching tongues that open from
  separate nuclei, so the first state is several openings, not one hole;
- the moving front shows dense frost -> thin crystals -> wet film -> clear
  glass, and its edge is torn at three spatial scales;
- no random motion: everything is driven by `heated_warmth`.

References used for the composition (not copied, translated into the project's
NPR language):

- Kenneth Libbrecht, "Guide to Frost", California Institute of Technology -
  window frost close-ups: separate dendritic fronds with spines and barbs,
  large calm areas between the clusters, the frond bases dense and the tips
  fine. <http://www.its.caltech.edu/~atomic/snowcrystals/frost/frost.htm>
- Wikipedia, "Frost", section "Window frost" - how the pattern nucleates from
  scratches and dust, and the distinction between dense white frost and thin
  translucent crystal. <https://en.wikipedia.org/wiki/Frost>
- Wikimedia Commons, category "Frost patterns" - the variety of window frost
  compositions. <https://commons.wikimedia.org/wiki/Category:Frost_patterns>

## Capture

```
godot --path <project> --rendering-driver vulkan --rendering-method forward_plus \
      --script res://tools/runtime/capture_window_727_frost.gd
godot --path <project> ... --script res://tools/runtime/capture_window_727_frost.gd -- --probe 0.5
```

`--probe <warmth>` takes a single frame at a given `heated_warmth`, used to
check one state before a full capture. The full run writes 72 PNGs to
`docs/runtime_previews/window_727_frost/frames/` (6 seconds at 12 fps,
960x540); the film is assembled from them with ffmpeg.

# Visual FX shaders

## Fade Volume

Reusable scene: `res://scenes/environment/visual_fx/FadeVolume.tscn`

The scene contains a BoxMesh using `fade_volume.gdshader`. The fade axis is
the cube's local X axis. Keep `x_len` equal to the BoxMesh X size. Rotate the
node to choose the fade direction and scale/edit the BoxMesh for the target
space.

This is a local transparent volume, not a fullscreen post-process.

## Stylized Shadows

Production contract:
`res://shaders/environment/stylized_shadow.gdshaderinc`. Model, tuning and
verification: [`docs/technical/STYLIZED_SHADOWS.md`](technical/STYLIZED_SHADOWS.md).

Only the shadow term is stylized, on stock Godot: every light's shadow lookup
is moved by world-space noise (`LIGHT_VERTEX`), and the directional shadow is
cut into three tones with noise-jittered cuts. N·L stays physical. It is not a
fullscreen post-process and does not patch the engine.

It is consumed by `IslandTerrain`, local and chunk-wide snow, the frozen sea,
and every material made by `StylizedEnvironmentMaterial` (Key West buildings,
roads, street props, the shelter house, doors, boards and tables).

`StylizedEnvironmentMaterial` adapts ordinary opaque `StandardMaterial3D`
environment assets. Transparent and deliberately unshaded materials stay on
their original path because they are not shadow receivers.

`stylized_shadow_strength` (`[shader_globals]` in `project.godot`) set to 0
restores physical shadows without swapping materials.

Showcase material:
`res://scenes/environment/visual_fx/StylizedShadowMaterial.tres`

Visual regression:
`tools/runtime/capture_stylized_shadows.gd` captures matched physical/stylized
Key West frames outside at noon, inside the shelter at noon and by stove light
at night, and the stove frame under each outdoor LUT. It runs in the existing
`checks.yml` Key West render job with the `[stylized-shadows]` commit marker.

## Painterly Distance Wash

Fullscreen pass on the player camera: `scenes/game/systems/camera/tps_camera.tscn` →
`PainterlyAtmosphere` (`scripts/systems/camera/painterly_atmosphere_pass.gd`,
`shaders/environment/painterly_distance_wash.gdshader`). Project switch: `hfn/visual/painterly_atmosphere_enabled`.

**Render layer.** The quad sits on `RenderLayers.SCREEN_PASS` (layer 18, `screen_pass`). Its vertex shader
covers the screen of any camera that draws it, so every other camera sharing the world (the dev diorama map,
the snow contact camera) leaves that layer out of its cull mask.

**Sky rule (owner decision, 2026-10-15).** Sky pixels have no depth and would count as the farthest
distance, so the full far wash erased the parallax clouds and the horizon haze. `sky_affect` is the share of
the wash the sky takes, as `Environment.fog_sky_affect` is for engine fog:
- **10%** by default: clear, windy and ordinary snowfall weather (`snowfall_density` ≤ 0.45).
- **Heavy snowfall raises it gradually to 100%**: `smoothstep(0.45, 0.95, snowfall_density)` from 10% to 100%,
  so a blizzard (0.95) washes the sky fully. The weather's own profile blend makes the change gradual.
- The values live in `PainterlyAtmospherePass` (`SKY_AFFECT_CLEAR`, `SKY_AFFECT_HEAVY`, `HEAVY_SNOW_START`,
  `HEAVY_SNOW_FULL`); change them there, not in the material.

Measured on a TPS frame at Duval St (clear-sky region, saturation / luma): no wash 0.097 / 142, sky 0%
0.096 / 142, 10% 0.067 / 155, 25% 0.044 / 171, 100% 0.028 / 213. Sheet:
`docs/runtime_previews/painterly_sky/sky_options.png`.

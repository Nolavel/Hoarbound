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

## Painterly Surface (experiment)

`shaders/environment/materials/painterly_surface.gdshaderinc` binds broad pigment masses and directional brush
flow to the dominant world-space plane of static buildings and ground. It is separate from the camera-space paper
and distance wash: Henry, movable props and the sky do not opt in. Current review tuning uses 10.5 m pigment masses,
9.0 × 1.1 m directional marks, global pigment/brush strengths 0.22/0.10, and a reduced 0.38 weight on snow.

The two existing value-noise evaluations also provide a narrow pigment deposit at irregular fill boundaries and a
weaker ended-bleed band around strokes. No texture sample or fullscreen pass was added. `painterly_surface_strength = 0`
restores the base materials. The `[painterly-wash-preview]` capture records matched OFF and ON walks under ordinary
snowfall (the permanent cold paper layer remains active) and uploads a six-second OFF → ON → vertical-split review;
amplified heatmaps are diagnostics only and are not acceptance evidence.

## Painterly Distance Wash

Fullscreen pass on the player camera: `scenes/game/systems/camera/tps_camera.tscn` →
`PainterlyAtmosphere` (`scripts/systems/camera/painterly_atmosphere_pass.gd`,
`shaders/environment/painterly_distance_wash.gdshader`). Project switch: `hfn/visual/painterly_atmosphere_enabled`.

**Render layer.** The quad sits on `RenderLayers.SCREEN_PASS` (layer 18, `screen_pass`). Its vertex shader
covers the screen of any camera that draws it, so every other camera sharing the world (the dev diorama map,
the snow contact camera) leaves that layer out of its cull mask.

**Draw order.** In 3D the screen texture is copied after the opaque pass, so it never holds transparent
surfaces (Godot docs, *Screen-reading shaders*). The quad writes every pixel, so drawn after the
transparents it erased them: falling snow and the 727 frosted glass vanished. Measured with a red 80 %
pane in front of a wall: priority 127 gave (0.74, 0.75, 0.76), the wash alone; priority −128 gives
(0.95, 0.35, 0.36), the pane over the washed wall. The material uses `render_priority = -128`: first
among transparents, so snow and glass draw over the wash. Opaque windows are unaffected either way.

**Atmosphere strength rule (owner decision, 2026-10-15).** The wash belongs to the snowstorm: `wash_strength`
mixes only the distance atmosphere with the untouched frame. It is **10 %** in calm weather (no snow) and rises with snowfall
to **100 %** in a blizzard: `lerp(0.1, 1.0, smoothstep(0, 0.95, snowfall_density))`. Calm is 10 %, windy
(0.15) about 16 %, ordinary snowfall (0.45) about 52 %, blizzard 100 %. The values live in
`PainterlyAtmospherePass` (`WASH_CLEAR`, `WASH_FULL_SNOW`).

**Permanent paper rule (owner decision, 2026-10-16).** The paper sheet is Hoarbound's visual identity, not
storm density. A restrained cold sheet tint and screen-stable tooth are applied after the weather-driven atmosphere
mix. `paper_strength` therefore stays at 1.0 in calm, snowfall and blizzard weather. The production pass exposes it
separately from `wash_strength`; weather updates must not change it.

**Wet edge treatment (owner experiment, 2026-10-16).** One broad world-space noise field offsets the mid/far
distance thresholds by up to 4 m, breaking the clean fog bands into stable wet-on-wet fronts. The existing four-neighbour
depth check is reused: most silhouette blur remains guarded, while selected 18–82 m discontinuities receive a small
soft bleed and broken dark pigment deposit. This is deliberately not a global outline and adds no extra depth samples.

**Advanced pigment/value pass (owner experiment, 2026-10-15).** The fuller reference match remains in the same
fullscreen pass and adds four bounded cues: a second metre-scale world-space pigment field, broken drying rims on the
irregular mid/far wash fronts, a weak seven-family value terrace, and derivative-based ink on authored internal facade
divisions. The ink explicitly rejects depth silhouettes, so Henry and every roof do not acquire a toon outline. Visual A/B
showed the first 0.28/0.08 pass was too timid, so production mid-ground ink hold is 0.38, dark-value lift is 0.04, and
mid paper mix is 0.21; the 18–40 m building masses therefore stay darker before the far paper wash takes over. Paper
remains a separate post-weather layer and now combines fine tooth
with a very low-amplitude directional fibre. Cost stays bounded: one additional procedural value-noise evaluation, two
cheap paper hashes and screen derivatives, with no additional scene-color or depth texture samples.

**Windows.** The post-process does not synthesize facade windows. Generated-building window surfaces and landmark
glass/frost materials own window placement, darkness, frost and heat response; the wash only grades the pixels they render.

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

## Tree Snow

`shaders/environment/vegetation/tree_snow.gdshader` (and `_double_sided` for fronds), used by every material of
`WinterTreeMeshes` (palms, bare winter trees). It is the stylized environment surface plus one surface step through
the body's `HFN_FRAGMENT_EXTRA` hook (`tree_snow.gdshaderinc`):
- Snow settles on up-facing tops of fronds, limbs and twigs by the world normal, with the live `snow_cover`
  (`snow_weight` from `snow_surface.gdshaderinc`, the same response as `snow_prop`). Vertical trunks stay bare.
- Drooping palm fronds hold 80 % of it (`tree_snow_hold`); limbs and twigs hold all of it.
- Rime grows on steep bark with `frost_amount`, only on the windward side (`snow_wind` points downwind).
Utility wires, fences and pole tops already carry static snow ridges and caps from the chunk builder
(`_add_ridge`, `WinterSnow_Poles`). Check: `tools/runtime/capture_tree_snow.gd` renders both trees at cover 0, 0.5, 1.

## Window Frost

Owner rule (2026-10-15):
- **Houses with nothing inside:** every pane is fully frosted (100 %).
- **A house with content inside:** each pane keeps 60–80 % frost, fixed per window.
- **A room a stove has warmed:** its panes clear down to 20 %, gradually, as the room warms.

Pattern: `shaders/environment/windows/frost_pattern.gdshaderinc`, ported from the GDExtension frost lab (frost grows in
from the pane edges, crystals at the front).
- **Generated buildings:** the chunk builder adds a `windows` surface to each building mesh
  (`KeyWestChunkBuilder._window_row`).
  - Panes are 1.0 × 1.4 m with a 0.9 m sill, every 3.2 m along each straight facade (outline points within 0.35 m of
    a line form one facade), one row per storey.
  - Storeys come from `levels`, else from the measured wall height / 3.2 m.
  - Material: `frosted_window.gdshader`, opaque and lit like the walls. `COLOR.r` is the coverage
    (`EMPTY_HOUSE_FROST` = 1), `COLOR.g` the pattern seed.
  - HLOD proxies leave the panes out.
- **Enterable landmarks (727 Fort St):** the real `Glass` openings use `frosted_glass.gdshader` (see-through).
  - `tools/world/reality/landmark_glass_frost.py` writes per-pane data into the asset: `COLOR.r` = cold coverage 60–80 %
    (hash of the window name), `COLOR.g` = heated room, `COLOR.b` = seed, plus pane UVs.
  - `KeyWest727Shelter` feeds `heated_warmth` = heated offset / max heated offset of its `ShelterZone` on
    `warmth_changed`. Coverage = mix(cold, 0.2, warmth). The unheated clinic rooms stay at their cold coverage.
- `test_window_frost` checks all three rules.



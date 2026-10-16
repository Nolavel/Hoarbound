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
and distance wash: Henry, movable props and the sky do not opt in. Current review tuning uses 10.5 m pigment masses
on horizontal surfaces and a 0.55 wall scale ratio (about 5.8 m), 9.0 × 1.1 m directional marks, global
pigment/brush strengths 0.22/0.10, wall gains 1.65/1.80, and a reduced 0.38 weight on snow. Wall projection
follows the vertical surface plane so facade marks rise with the building instead of reading as screen-space noise.

The two existing value-noise evaluations also provide a narrow pigment deposit at irregular fill boundaries and a
weaker ended-bleed band around strokes. No texture sample or fullscreen pass was added. `painterly_surface_strength = 0`
restores the base materials. The `[painterly-wash-preview]` capture records matched OFF and ON walks under ordinary
snowfall (the permanent cold paper layer remains active) and uploads a six-second OFF → ON → vertical-split review;
it also uploads a six-second 2 × 2 evidence view with both full frames and an unamplified 1:1 facade crop.
The capture has a separate facade-region visibility gate. Amplified heatmaps are diagnostics only and are not
acceptance evidence.

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

## Sky Weather Character

`PainterlyDayNightManager` (`scripts/systems/world/painterly_day_night_manager.gd`) is the sky's art-direction
layer over `DayNightManager`. One rule set, read the same way by day and by night:

- **Wind sculpts cloud bodies.** Wind 1 → 7 m/s raises shape contrast, belly shadow and parallax detail, grows
  bigger bodies (`cloud_sag` × 0.68) and lowers the mask threshold a little. Wind also clears the air over the
  clouds (world fog sky share 0.25 → 0.08). Windy (8 m/s) is the most sculpted sky.
- **Snow closes the deck.** Snowfall 0.06 → 0.40 merges bodies into a low heavy deck (`cloud_sag` × 0.55) with
  dark bellies and few lit tops.
- **A blizzard veils it.** Snowfall 0.60 → 0.95 fades all of that out again and raises the fog sky share to 0.60.
  The painterly wash supplies the whiteout.
- **Lit tops** (new sky shader uniform `cloud_top_light`): one extra height sample toward the light (the usual
  2D cloud self-shadow) turns the side facing the sun or moon light and leaves the bellies dark. That is what
  makes a cloud read as a volume rather than a smudge. Calm 0.55, windy about 0.74, snowfall about 0.24,
  blizzard 0.1; 0 keeps the old dark-slate cloud.
- **Night.** The moon lights the deck: `cloud_color` gains `MOON_CLOUD_LIGHT` × (0.45 + 0.55 × readability),
  and tops stay at least 0.65 lit. Before, night clouds were 0.035–0.075 times an exposure of 0.24, black on
  black. The volumetric fog is lit by the ambient light, so at night it keeps only 25 % of its sky share;
  otherwise it greys the dark sky out.
- **The wash takes the hour's light.** `PainterlyAtmospherePass.set_daylight()`:
  - wash and paper colour go from paper (0.90, 0.92, 0.94) by day to blue-grey ink (0.13, 0.16, 0.22) at night;
  - darks lift toward that colour, not toward white, so a night blizzard is a dark veil, not a white sheet.

| | Calm | Windy | Snowfall | Blizzard |
|---|---|---|---|---|
| Day | clear sky, a few soft clouds | broken bodies, lit tops, dark bellies | low grey deck with seams | white veil |
| Night | dark clear sky | moonlit broken clouds | moonlit heavy deck | dark grey veil |

Measured on the eight-state Petronia Street capture (same camera; sky band luminance mean and local contrast =
frame minus a 48 px blur), Codex state → now:

| | Day mean | Day local | Night mean | Night local |
|---|---|---|---|---|
| Calm | 0.623 → 0.623 | 0.0122 → 0.0123 | 0.195 → 0.054 | 0.0062 → 0.0072 |
| Windy | 0.600 → 0.571 | 0.0122 → 0.0137 | 0.203 → 0.118 | 0.0121 → 0.0232 |
| Snowfall | 0.610 → 0.581 | 0.0164 → 0.0140 | 0.297 → 0.184 | 0.0238 → 0.0250 |
| Blizzard | 0.815 → 0.805 | 0.0421 → 0.0410 | 0.768 → 0.338 | 0.0668 → 0.0324 |

- Night is the clear gain: the sky is dark again, and windy night clouds have twice the local contrast.
- By day the change is smaller. This camera looks at the horizon band, where fog and the far wash dominate.
- The snowfall deck merges into smoother, darker masses, so its local contrast drops slightly.

`test_sky_weather_character` checks the ordering. `tools/runtime/capture_sky_weather.gd` (`[sky-weather-preview]`)
shoots all eight states on open Petronia Street.

## Color Grade Blend

`ColorGradeController` crossfades its LUT profiles (Day, Dusk, Night, Shelter) by Grok's rules:
- a ±0.5 h smoothstep corridor at 05, 07, 17 and 21 h;
- a wall-clock fade (`shelter_blend_s`, 0.5 s) when entering or leaving a shelter.

The in-between LUT stays on the Environment's own grade (`adjustment_color_correction`). This is the same
approach as UE4's CombineLUTs: blend the LUTs, not the frames.
- `LutBlendCache` reads the four 33³ LUTs back once at `_ready`.
- Worker threads bake 15 in-between steps for each of the 6 profile pairs (9.7 MB). This takes ~1 s of
  background CPU on 4 cores, or ~9 s when lavapipe shares those cores.
- A blend uploads the nearest step into one `ImageTexture3D` (0.4–0.7 ms, only when the step changes).
  Brightness, contrast and saturation lerp continuously.
- Until the bake ends, or where texels cannot be read back (headless), it snaps to the nearer source LUT, as before.

Grok's first version drew the blend in a fullscreen spatial pass. That pass sees the linear pre-tonemap image
and turns the Environment adjustment off, so it graded a different image. Probe on lavapipe, mean |Δ| per
pixel, against the Environment snap:

| Weight | Spatial pass | Baked Environment LUT |
| --- | --- | --- |
| ≈0 vs Day | 0.217 | 0.005 |
| ≈1 vs Night | 0.226 | 0.002 |

- The pass also erased the painterly far wash.
- A 1/16 step changes the frame by 0.002–0.005, which is within frame-to-frame noise (Day→Night total: 0.032).
- Evidence: `runtime_previews/color_grade_blend/env_lut_blend_vs_pass.png`.
  - Top row: pass Day snap, pass w≈0, then the new Day snap, the new w≈0 and Night.
  - Bottom row: steps 0, 4, 8, 12 and 16.
- Checks: `test_lut_blend_cache`, plus the videos from `tools/runtime/capture_color_grade_blend.gd`
  (`[color-grade-blend]`).

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



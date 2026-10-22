# Stylized shadows

Status: production contract since 2026-10-01. Author decisions: stock Godot only
(no engine fork); stylize the shadows only, not the whole light ramp. What is
still missing around shadows, and its cost:
[`docs/art/LIGHT_AND_SHADOW_DIRECTION.md`](../art/LIGHT_AND_SHADOW_DIRECTION.md).

Reference: [Stylized shadows, not a post processing](https://godotshaders.com/shader/stylized-shadows-not-a-post-processing/)
(ShaderError, CC0, May 2023): cast shadows with a torn, noise-displaced
silhouette and a spray of mid-tone islands around a dark core.

## Model

Two stages, both in world space and both inside the material, so fog,
volumetrics and the colour grade apply after them unchanged.

1. **Torn lookup (all lights).** `fragment()` moves `LIGHT_VERTEX` by a
   three-octave value-noise vector projected into the surface plane
   (0.18 m, base 3 cycles/m). Godot copies `LIGHT_VERTEX` into the position
   used for every light and shadow lookup
   (`scene_forward_clustered.glsl`, `vertex = light_vertex`, 4.8-dev6
   `8898c2b`), so each fragment reads the shadow map at a nearby point and the
   cast silhouette tears. Projecting into the surface plane keeps walls from
   sampling inside themselves.
2. **Three tones (directional only).** `light()` cuts the directional shadow
   term into core 0, mid 0.45 and lit 1, with the two cuts (0.34, 0.66)
   jittered by a "spray" clamped to ±0.3. By default the spray is a dry
   brush-stroke mask (1.5 m tile, strokes at 35°, triplanar in world space).
   With `stylized_shadow_brush_mix = 0` it is value noise instead (base
   9 cycles/m, contrast 2.5). The jitter never reaches a fully lit or fully
   shadowed fragment, so only the penumbra breaks into strokes or islands. The sun's `shadow_blur = 3.3` widens that
   penumbra so the islands form a visible halo, and the directional soft-shadow
   filter runs at Soft High: at the default Soft Low the rotated PCF samples
   leave per-pixel dither in the penumbra, which the tone cut turns into speckle.
   Godot also scales the filter radius with quality (2.0 Low/Medium, 3.0 High,
   4.0 Ultra), so blur × radius is held at ~10. At that width, pixel-scale noise
   on the replica was 4.9 Low, 2.6 Medium, 1.8 High, 1.3 Ultra.

N·L stays physical, and so does everything that is not a shadow.

Noise octaves fade before they fall under ~3 px (`fwidth` of the world
position), and the brush mask fades on the same window as the base octave. Mip
averages alone do not neutralise a stroke mask. Distant shadows therefore settle
to three clean tones rather than sub-pixel noise. Noise and mask are fixed to the
world, so they do not swim with the camera.

The two cuts are one screen pixel wide (`smoothstep` over `fwidth` of the cut value), not hard `step`s.
Godot's directional cascades are texel-snapped, so the shadow map itself holds under camera translation
(measured, 256 px atlas, top-down camera moved by whole pixels: no edge change). A hard cut still flipped
whole contour pixels on every sub-pixel camera move, and the TPS camera's damping moves it by fractions of
a millimetre every tick, even after Henry stops. Measured on the same aligned frames, contour pixels that
changed on a 1 px move: 0.112 % with hard cuts, 0.025 % with one-pixel cuts, 0.023 % with no stylisation.
Technique: analytic antialiasing of a procedural threshold (Golus, "Anti-aliased Alpha Test", 2017).

The sun also turns in steps (`DayNightSettings.sun_step_minutes`, eased over `sun_blend_seconds`): cascade
stabilisation only holds while the light direction is fixed (Valient, "Stable Rendering of Cascaded Shadow
Maps", ShaderX6), so a sun re-aimed every game minute moved every shadow every 2.5 s.

Open: the game scene runs `shadow_blur = 1.1` at the default Soft Low filter, not the Soft High / 3.3 above.
Soft High measured only 0.28 % against 0.35 % changed pixels on a 5 px move (old, misaligned metric), so it
is not the cause of the boil; restoring the contract is an art call.

### Local lights

In `light()` an omni or spot `ATTENUATION` is distance falloff × shadow, and
stock Godot exposes no light position to separate them. Local lights therefore
get the torn lookup but not the tone cut. The lookup offset also moves the
falloff sample slightly; measured on the lab omni with no shadow, the light pool
changes by ΔL\* 0.67 mean, 1.56 p95 (around the just-noticeable difference).

The shelter stove's room light (`Flame`) casts shadows; the firebox glow does not.

### Interior mode

Outdoors the spray is the dry-brush mask; under a shelter roof it falls back to the
value-noise spray (the 4186533 look, author choice 2026-10-20). The global
`stylized_shadow_interior_mode` scales `stylized_shadow_brush_mix` by `1 − mode`.
`ShelterGradeBinder` drives it from `ThermalManager.sheltered_changed` over the same
`shelter_blend_s` as the LUT crossfade, so grade and shadows change together.

Landmark shells (`kw_727_fort_st.glb`) are instanced into Reality chunks as imported.
Their import runs `tools/import/stylized_landmark_import.gd`, which applies
`StylizedEnvironmentMaterial.apply_to_tree`; without it the 727 walls and floor stayed
on `StandardMaterial3D` and the stove shadows had no torn edge.

## Why the earlier contract never matched the reference

Measured on a replica of the reference scene (see Verification):

- It only edited `ATTENUATION` inside the physical penumbra. With a hard sun
  that band is a few centimetres wide, and darkening the core changes nothing
  because direct light there is already zero. The frame was visually the same
  as physical shadows.
- Its noise periods were 2–18 m against a 5–15 cm grain in the reference, and
  its warp was horizontal only, which pushes wall lookups into the wall.
- The shelter could not show it at all: the stove light cast no shadows, local
  lights were excluded, and the shelter materials opted out.

The engine patch (two lookups per light) was not the missing piece: the stock
`LIGHT_VERTEX` lookup reproduces the silhouette, and the mid-tone islands come
from the penumbra cut. The patch and its build tooling were removed.

## Colour grades

The tone cut happens before tonemapping and the LUT. All Cold Ash LUTs are
monotonic, so the three tones stay three distinct, ordered levels and the island
shapes do not change; a LUT only moves the spacing between tones. On the
replica, lit/shadow separation was ΔL\* 47–54 under all four LUTs (physical
48). In the shelter at night, the stove shadow measured ΔL\* 13–14 on the floor
and 20–21 on the wall under all four LUTs. Shadow readability is set by the
key/fill ratio (sun or stove against ambient), not by the grade. Inside, the
levers are the stove's room light (`StoveVisual.ROOM_LIGHT_ENERGY`) against
`DayNightManager.shelter_ambient_energy_cap`.

## Tuning

Constants at the top of `stylized_shadow.gdshaderinc`. The global
`stylized_shadow_strength` (0 = physical) drives the A/B captures.
`stylized_shadow_brush_mix` (0 = value noise, 1 = mask) and
`stylized_shadow_brush_mask` swap the spray for a brush-stroke mask; see
`docs/art/LIGHT_AND_SHADOW_DIRECTION.md` for the measured comparison.
Light-side settings: `SunLight.shadow_blur` in `WorldEnvironmentSystem.tscn`,
`Flame.shadow_blur` in `first_exit_blockout.tscn`, and
`rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality`
(4, Soft High, 16 taps) in `project.godot`. Changing the quality changes the
penumbra width too; rescale `shadow_blur` with it. Its cost has only been seen
on lavapipe and needs a real-GPU check. A soft sun via
`light_angular_distance` (PCSS) was rejected: its sampling noise speckled
fully lit snow once cut into tones.

## Verification

`tools/runtime/capture_stylized_shadows.gd` writes matched physical/stylized
frames of Key West: outside at noon, inside the shelter at noon, by stove light
at night, and the stove frame under the Day, Dusk and Night LUTs.
With `-- brush` it renders physical, noise twice, dry and flat masks instead;
`-- shimmer` renders each spray from the TPS pose and again 3 mm to the side.

On lavapipe, outside and in the shelter: no new boot-log errors, and the
stylized shelter frame at noon is brighter than physical by more than 10 L\* on
0.07 % of pixels, all along existing sunlit edges (no light leaking through
walls).

Sub-pixel camera shift (lab replica, distant props): pixels changing by more
than 32 levels were 0.026 % for both physical and stylized, so the world-space
noise adds no shimmer at distance. Near the camera, hard tone-cut edges flip
0.37 % of pixels against 0.15 % physical: shading is not antialiased.

Sub-pixel camera shift in Key West (`-- shimmer`, noon, TPS pose, about half
a pixel on the ground 4–5 m ahead; clock, snowfall and Henry frozen). Pixels
changing by more than 4 L\*:

| Spray | Far band (> 8.5 m) | Near band (< 5.7 m) | Near, not flipping physically | Per hard-edge pixel | Away from any edge |
|---|---|---|---|---|---|
| physical | 0.64 % | 0.88 % | — | 0.67 | 10 px |
| noise | 0.64 % | 1.30 % | 0.45 % | 0.26 | 19 px |
| dry (default) | 0.64 % | 2.02 % | 1.18 % | 0.49 | 12 px |
| flat | 0.64 % | 1.52 % | 0.69 % | 0.35 | 12 px |

Dry flips the most pixels because it has the most hard edges (16 404 edge
pixels in the near band against 11 979 for noise). Each flip sits on a stroke
edge that moves with the world. Per edge pixel they are fewer than on geometry
edges, and isolated popping is at the level of physical shadows. The far band
matches physical. That is crawl along unantialiased edges, not shimmer.

Not yet verified: frame cost on a real GPU, and how TAA/FXAA treats the stroke
edges there. Henry's materials are on the contract (`make_character()`), so
shadows falling on him are stylized too, with the spray in model space.

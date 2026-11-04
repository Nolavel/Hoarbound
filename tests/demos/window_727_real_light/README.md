# Issue #281 — V3 thaw under actual 727 scene lighting

This does not fake an indoor room or add convenient replacement lights.
It instantiates the real `key_west_reality.tscn` scene (same as
`capture_key_west_727_interior.gd`), waits for streamed world content,
uses the **real Shelter727 House**, real window GLB, world Environment
and DirectionalLight3D, the authored `ColorGradeController` shelter
profile and the Stove HeatSource's existing light (lit using `ignite()`).

The actual imported landmark `Glass` MeshInstance3D is hidden *only
inside the test scene* so the extracted 12-triangle `FrontWindow1`
can replace it without a double pane. No diagnostic checkerboard.
The shell, furnishing and world beyond are existing runtime content.

To avoid comparing different thaw geometry, the two halves show identical
V3 at identical progress and camera motion; first three seconds use
the approved **unshaded** V3, the next three use a test-only lit copy
of exactly the same V3 with a standard specular/roughness response.

The point is an optical lighting A/B: daylight, real stove bounce
and colour grade can expose over-gloss or unreadable wet detail.
Thaw still follows a deterministic 0..1 authoring ramp for a
six-second film. That is not a physical temperature simulation
and does not alter the production material or `ThermalZone`.

## Fourth pass: less blue, let crystals and wet glass respond (issue #281)

Same streamed 727, actual window triangles and same V3 thaw field. A/B control
is now **old blue lit V3 vs neutral lit V4**, NOT unshaded vs lit. The old
shader was copied byte-for-byte to `lit_frosted_glass_v3_blue_control.gdshader`.

- Existing weather controller pinned to production `calm` profile (no
  blizzard/whiteout). Scheduler stopped **only in the test instance**.
- Test-local duplicate of the world Environment removes volumetric whiteout
  and reduces `fog_density` from 1.0 to 0.012; source lighting is UNCHANGED.
- Activate **actual shelter LUT** through `set_profile(HFN_ColdAsh_Shelter)`
  to set the inside-shelter state; the previous test used
  `use_shelter_profile` without updating that state.
- Neutral off-white frost and subdued warm-grey wet glass; keep room lights
  and authored LUT. Local crystalline branches have smoother microfacets,
  meltwater gets a glossier roughness; both reflect the real 727 lights.
- 6-second deterministic A/B of the same V3 positions, seed, warmth and camera
  (0–3 s old blue lit control, 3–6 s neutral lit V4).

This is an *art-direction lighting diagnostic*. Reduced fog is intentionally
not production weather behavior. No new lights, no production material changes.

## CI-only software-render optimization

Initial clear-weather job [#41845084996](https://github.com/Nolavel/Hoarbound/actions/runs/41845084996) hit the 900s capture timeout: the full world's SnowContact SubViewport alone consumed ~8 seconds GPU per profiled frame on llvmpipe, with 1280x1024 root rendering and ~320 total frames. World/lighting/material setup itself passed, with real 727 geometry, calm profile and shelter LUT. We did *not* claim a successful preview.

Second run keeps the same real 727 building geometry, existing world sun and stove, crystal shader and lighting. It turns off auxiliary offscreen snow-contact/shape/dev-map **Subviewports in the test scene only** (not a change to world lighting, textures or geometry), sets the root capture window to 640x360 16:9, and reduces warmup/settle frame counts. The exported video remains 960x540. This is a preview efficiency adjustment, not a gameplay optimization.

## V5 experiment: remove blue at its daylight source

V4 tried a neutral frost colour, but the entire room remained blue-gray.
The scene's DayNightSettings daylight fill was `Color(0.46, 0.58, 0.86)`
and daytime clouds `Color(0.30, 0.39, 0.48)`; repainting the pane cannot
remove these light source colours from the walls. V5 uses the real runtime
DayNightSettings but changes them only in the second A/B half (3–6 s) to
a neutral overcast `day_ambient_color=(0.66,0.65,0.63)`, clouds
`(0.43,0.43,0.41)` and slightly neutral ground colour. `force_update_lighting()`
updates the actual day/night-managed sun/sky scene; no synthetic lights,
post-render desaturation or change to the shelter LUT. Same real 727,
stove, weather `calm`, front glass 12 triangles, original V3 SDF thaw.

The V5 material uses near-neutral ice and water albedo, physically ordinary
dielectric specular (0.46–0.50) and lower roughness on the wet film.
Control 0–3 seconds: V4 original blue skylight; 3–6 seconds: V5 neutral
skylight, same melt progression and camera. This changes **sky palette and
material together**; final production decision must separately check the sky
across outdoor locations, so the experiment remains isolated to `codex`.

## V6 — owner's correction: white and opaque until truly thawed

V5 was visibly wrong. Changing sky colour did not correct blue translucent
frost because V5 computed `ALPHA` from the *sparse frost_pattern detail*:
`mix(0.035, 0.995, f.x * 0.95 + f.y * 0.15)`. Whenever no vein happened to
cover a texel, the shader revealed outdoors even where SDF said frozen.

V6 uses `ice_coverage = 1 - cleared` for **both transparency and frosted
white appearance**. Unthawed areas have `ALPHA=1`, including the cold rim,
with a 7.5%-wide guaranteed frozen margin. The small gap between clear and
opaque is restricted to the actual moving SDF boundary; the original
crystalline motif affects relief/roughness, not whether ice exists.
White (not silver-blue) crystal albedo and low, neutral scattering emission
preserve visible ice under the scene's weak daylight; wet, genuinely cleared
portions are transparent and respond to real specular lighting.

Neutral gray daylight is set in this **test instance before the first frame**.
No V4 blue-sky segment in the 6s movie. The window itself, surrounding
building, real sunlight/stove and shelter LUT are preserved. Production
materials and main remain untouched until artistic approval.

The 6s movie covers a continuous 0->~100% simulated thaw. It is not a
physical melting-rate simulation.

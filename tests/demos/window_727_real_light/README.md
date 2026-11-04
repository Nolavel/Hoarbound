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

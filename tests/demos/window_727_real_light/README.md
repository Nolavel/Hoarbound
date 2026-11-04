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

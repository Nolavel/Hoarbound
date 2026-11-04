# 727 FrontWindow1 SDF thaw — isolated A/B test (#281)

This experiment is deliberately **only the real FrontWindow1 pane** from
`res://assets/world/key_west/landmarks/kw_727_fort_st.glb`, identified through
`data/world/key_west/reality/landmarks/kw_727_fort_st.json`.

The existing generated landmark GLB has no UV or vertex colours. In-memory
rendering code filters its actual `Glass` triangles by the real window's
measured plan frame, then projects UVs onto those *unchanged triangles*.
It aborts if matching geometry is missing. No substitute QuadMesh window.

First 3 s: unchanged production `frosted_glass_727.tres` clone (baseline).
Next 3 s: same existing `frost_pattern.gdshaderinc` crystalline renderer,
but the thaw comes from `sdf_smooth_union.gdshaderinc`-driven blobs with
low-frequency warping and an edge reserve. Both use the same progress,
static camera, real pane and diagnostic checker behind glass, not a world.

No 727 gameplay, stove, climate zone or production material is touched.
Only the controller supplies a fixed 0..1 warmth for the comparison.
Runs via `.github/workflows/window-727-sdf.yml` on the `codex` branch.

## Second pass: irregular thaw front

Same real FrontWindow1 geometry, camera, warmth ramp, baseline glass shader,
and 6-second comparison as the first test. Only the test-only SDF spatial
material changed. The original smooth-union field now bends in a slowly
varying 2D flow and gains three scales of edge displacement plus the
existing `frost_cold_rank` rim bias. The centre stays connected, the
outline is broken into uneven inlets and tongues, and the narrow thaw
front retains crystal detail and a subdued wet fringe.

This is visual R&D, not a new production glass implementation. First
pass: `e1654a5`. Discussion: issue #281.

## Third pass: crystal thinning and wet glass (2026-11-04)

Same real `FrontWindow1` mesh, 12 GLB triangles, projection and fixed camera.
Capture changed to a same-progress A/B against **frozen V2 shader source**
(`sdf_frosted_glass_727_v2.gdshader`), rather than the old production frost
baseline: first three seconds V2, next three seconds V3. Their SDF field,
seed and warmth progression are identical.

V3 changes *only* the spatial-material optics behind the existing SDF front:
- A broad translucent precursor thins the existing crystalline film before
  the boundary clears it; stronger crystal regions persist longer.
- The tips of the original `frost_pattern` ferns survive in a narrow boundary.
- A sparse water film forms on newly cleared glass, with six subtle seeded
  vertical gravity-oriented trails and rounded moving tips.
- Different optical alpha for frost, thin crystal, wet film and clear pane.

This is an authored illusion, **not fluid mechanics**. The frost generated
by `frost_pattern.gdshaderinc` remains identical, and `smooth_union` and
original blob positions are unchanged. No direct binding to ThermalZone.

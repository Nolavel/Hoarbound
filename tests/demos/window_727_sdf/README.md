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

## Natural thaw (2026-11-10, Claude, on the owner's request)

`natural_thaw_glass_727.gdshader` is a new test-only material on the same real `FrontWindow1` pane, camera and
checker fixture. The probe opens on it; **V** switches to the unchanged V3 sheet for comparison. V3, V2 and the
production `frost_pattern.gdshaderinc` are not edited. Preview:
`docs/runtime_previews/window_frost/window_727_natural_thaw.png` (V3 on top, natural below, one 1:1 detail).

What changed, and from what observation of real panes:

- **Frost is a layer that scatters the view, not white paint.** The pane reads the screen behind it and blurs it by
  the local frost thickness (screen mips), so thin frost shows a soft blue view and thick frost goes white. At 0 %
  the whole pane is frosted: the fern veins of `frost_pattern` sit on a granular hoar base that is thicker at the
  cold frame and drifted up from the sill. The veins follow a gently bent grain.
- **Shades.** Thick frost is neutral white, thin frost blue, soaked frost grey-green and more transparent, the
  rim by the frame slightly grimy. Ridges catch a little light; dry frost has sparse glints.
- **Where it thaws.** Each texel needs its own warmth: less near the warm spots, more by the frame, low on the
  pane, and where the frost is thick. Broad noise makes lobes and tongues. Warm air rises, so the upper pane
  leads and the sill holds out; a band by the frame survives at 100 %.
- **How it thaws.** A texel first soaks (turns glassy and lets the view through), then breaks into slush islands
  that shrink, then is clear. Thick fern veins outlast the hoar between them.
- **Runs.** A bead gathers on a lane while its patch is still soaking, creeps, then runs down a wandering path.
  It cuts a clear track through the frost below with soaked edges. Behind the head the thread thins and breaks
  into a string of beads. Water that reached the bottom stands along the sill.
- **Beads.** Cleared glass keeps scattered water beads at two sizes. Each is a small lens: it bends the view,
  has a dark rim and one glint, and they thin out as the pane dries.

The probe's `blob_data` keeps its interface, but here only each blob's position is used, as a warm spot. This is
an authored illusion driven by one 0..1 value, not a heat or fluid simulation. The lighting is unshaded, as in
the V3 probe, so it has not been judged under the real 727 lights.

Techniques: frosted glass as a blurred screen read (the usual screen-texture approach, as in this project's
`frosted_veil`), and water beads as lenses on a jittered cell grid (the approach of Martijn Steinrucken's
"Heartfelt" rain-on-glass shader, written here from scratch).

Stills: `xvfb-run godot --path . --rendering-driver vulkan --resolution 1600x900 --script
res://tools/runtime/capture_window_727_thaw.gd -- <out dir> [natural|v3]`.
Check: `tests/systems/test_window_727_thaw_probe.gd`.

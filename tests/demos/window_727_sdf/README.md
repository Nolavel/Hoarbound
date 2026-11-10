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

`natural_thaw_glass_727.gdshader` is a test-only material on the same real `FrontWindow1` pane, camera and
checker fixture. The probe opens on it; **V** switches to the unchanged V3 sheet. V3, V2 and the production
`frost_pattern.gdshaderinc` are not edited. Preview:
`docs/runtime_previews/window_frost/window_727_natural_thaw.png` (whole pane 0-100 %, one V3 frame, close-ups).

### Second pass, after the owner's review against a photo reference

The first pass drew its ferns with `frost_pattern`, whose fronds sit in 16 cm cells: on a 2.0 x 1.1 m pane
they were far too large, its cell polygons showed as an angular base, and the runs were centimetres wide.

- **Scale from real frost.** K. Libbrecht (Caltech, "Guide to Frost") describes window-frost branches of a
  few millimetres, nucleated along scratches and wipe streaks on the glass. The frost is now a **baked sheet**
  at 1 mm per pixel, `frost_sheet_727.png`, from `tools/textures/bake_window_frost_sheet.py`: feathers 2-28 cm
  long with barbs about a millimetre apart, grown from the frame (longest off the sill), in rows along
  scratches, and as small fans from free specks. Fine hoar grains pack by the frame and cling to the feathers.
  Channels: R crystal lines, G hoar, B when frost reaches a texel, A smooth thickness.
- **No frame of one width.** How deep the frost reaches is uneven: deep off the sill, shallow under the head,
  bent by broad noise. The middle carries only a breath-thin film, so the view shows through it, softened.
- **Frost scatters the view.** The pane reads the screen behind it and blurs it by local frost thickness.
  Crystals are white, hoar grey-blue, soaked ice glassy grey with light along its ridges.
- **Thaw by local need.** Frost by the frame, low on the pane, far from the warm spots and thick holds out
  longer; the upper pane leads. A texel soaks (grains and feathers fuse into clear ice), breaks into slush
  islands, then clears.
- **Wet glass.** As it warms the pane mists with fine beads (5 mm grid), with larger beads later; each bead
  is a small lens. Too far away to resolve, the mist reads as a soft bloom instead of shimmering.
- **Runs are thin and short.** 46 lanes, 1-2 mm wide, 5-34 cm long, most of them short. A bead gathers where
  the frost soaks, creeps, lets go, and stops as a hanging drop; it cuts a narrow track through frost below.

`blob_data` keeps the SDF probe's interface, but only each blob's position is used, as a warm spot. This is
an authored illusion driven by one 0..1 value, not a heat or fluid simulation. It is unshaded, as the V3 probe
is, and has not been judged under the real 727 lights.

Techniques: frost as a mask sheet with a growth-order channel (the usual way games ship frosted glass), the
view as a blurred screen read (as this project's `frosted_veil`), beads as lenses on a jittered cell grid (the
approach of Martijn Steinrucken's "Heartfelt" rain-on-glass shader, written here from scratch).

Stills: `xvfb-run godot --path . --rendering-driver vulkan --resolution 1600x900 --script
res://tools/runtime/capture_window_727_thaw.gd -- <out dir> [natural|v3] [close]`.
Re-bake the sheet: `python3 tools/textures/bake_window_frost_sheet.py` (deterministic, seed 727).
Check: `tests/systems/test_window_727_thaw_probe.gd`.

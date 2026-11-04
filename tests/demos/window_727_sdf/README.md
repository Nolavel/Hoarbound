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

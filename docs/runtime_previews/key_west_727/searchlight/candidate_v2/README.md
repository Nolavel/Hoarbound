# Northbeam — geometry review v2

**Core geometry approved by the owner. Revised handle shoulders, controls, markings and industrial materials are under review. Godot integration remains paused.**
Real Blender 5.2.0 Cycles renders, light switched off; no emitted beam or animation.

| Front | Side |
| --- | --- |
| ![Front](front.png) | ![Side](side.png) |

![Opposite flank: four battery lamps](opposite_side.png)
![Rear three-quarter](rear_perspective.png)
![Rear cover stencil](rear.png)
![Recessed guarded switch](switch_detail.png)
![Rear handle attachment](rear_handle_joint.png)
![Front handle attachment](front_handle_joint.png)
![Perspective](perspective.png)
![Recessed optical assembly](optics.png)
![Henry's copied right hand, thumb toward switch](grip_bare_reverse.png)

The rejected model is preserved in
`assets/items/searchlight/source/intermediate_v1/`, with its earlier renders in
`../intermediate_v1/`. The new geometry remains under `source/candidate_v2/`;
it has not replaced the game GLB.

## Geometry

- Elongated battery housing; compact swept handle with tangent-continuous curved
  shoulders and a guarded rocker recessed into the front landing. Side red latches
  and the rear black square are removed; NORTHBEAM stencils replace the blank cover.
- Both handle feet extend 8 mm below the case top into separate mounting seats.
  `handle_joint_check.json` verifies physical triangle intersections with the case
  at each end; neither foot relies on a camera projection to appear connected.
- Handle core: 22×16 mm; rubber grip: 26×20 mm; clearance above the case: 66 mm.
- Recessed clear, closed protective glass: diameter 189.6 mm. Actual parabolic
  reflector: 81 mm deep, with separate central LED, ceramic substrate and heatsink.
- Slim metal bezel and six small rubber pads, projecting 3.5 mm radially.
- 9,932 triangles, excluding the hand reference. Geometry QA passes: no
  degenerate faces, flipped islands, z-fighting or detached parts detected.
  The opposing glass/gasket contact faces are retained to keep the glass closed
  for refraction; that is the one explained QA warning.
- Material/wireframe outputs were visually inspected. This is an editable
  65-part, twelve-material look-development source, not the final batched game asset.
  UV atlas consolidation, baking and game export follow approval.

## Materials

Industrial source maps were found in the ambientCG catalog and applied from:

- [PaintedMetal001](https://ambientcg.com/a/PaintedMetal001): scratched yellow
  painted metal; subdued and tinted to the Hoarbound ochre palette.
- [Metal027](https://ambientcg.com/a/Metal027): graphite powder-coated steel for
  the battery/rear cover and inset hardware.

Both are CC0. Unmodified 1K source color, roughness, metalness and OpenGL normal
JPEGs, source URLs, license and SHA-256 records are retained in
`assets/items/searchlight/source/candidate_v2/materials/`. Maps are packed into
both Blender review files. The raw bright-yellow source is not used at full
strength: restrained scratch contrast, weak normals, a quiet paint mass and
clustered edge wear preserve the painterly read. Intact paint stays dielectric;
metal response is limited to exposed wear. Rubber remains a separate material.

NORTHBEAM / PRO-GRADE SEARCHLIGHT and descriptive LED/rechargeable markings are
printed directly on the rear cover and side panel, without an extra black plaque
or invented battery capacity/IP certification. `make_searchlight_markings.py`
reproduces these stencils with the system DejaVu Sans Condensed font and Pillow.
The four amber charge windows remain on the opposite flank. This is Blender
look development; final shared NPR material integration and runtime appearance
are still pending.

## Actual Henry hand reference

`tools/blender/extract_searchlight_hand.py` copies the right hand from
`assets/characters/henry/henry_outfit.glb`, statically curls the existing finger
bones by 22°/45°/20°, bakes that pose into the copied mesh, then deletes the body,
left hand, rig and every other object. The standalone file contains exactly one
mesh, `HenryRightHandBare`, at the original scale. The original character asset
is unchanged.

The copied hand is rotated 180° around the vertical grip axis, placing the thumb
toward the front switch. The static bare-hand placement has zero detected triangle intersections
with the grip, handle, case and switch (`hand_fit_check.json`). It is a size and
clearance guide, not a final gameplay hand pose. Winter-glove finger contact and
animated wrist behavior are not claimed validated at this review stage.

Source files:

- `assets/items/searchlight/source/candidate_v2/henry_right_hand.blend`
- `assets/items/searchlight/source/candidate_v2/searchlight_geometry_review.blend`
- `assets/items/searchlight/source/candidate_v2/searchlight_with_henry_hand.blend`

Reproduce with the separately installed EL4CTEO/blender-skills (Codex only):

```sh
blender -b --factory-startup --python-exit-code 1 \
  --python tools/blender/extract_searchlight_hand.py
python3 tools/blender/make_searchlight_markings.py
blender -b --factory-startup --python-exit-code 1 \
  --python tools/blender/build_searchlight.py -- --skills /path/to/blender-skills
```

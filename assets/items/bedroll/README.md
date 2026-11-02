# Bedroll Blender candidate

Blender 5.2 source model and review renders for Henry's bedroll. This is an art candidate; the current Godot item and rucksack mesh have not been replaced.

- Frame 1: laid out at 0.75 × 1.9 m.
- Frame 18: folded lengthwise to fit the rucksack.
- Frame 56: packed roll, about 0.38 m wide and 0.31 m in diameter.

The 54-bone armature drives the fold and rolling motion. At frame 54, a clean sewn endpoint mesh replaces the skinned cloth so the packed end has a controlled spiral and no pinched polygons. The handoff between the animated and packed meshes still needs polish before use as a continuous gameplay animation. Canvas, repair patches, binding, straps and buckles remain separate objects. Materials use muted olive canvas, restrained wear masks and raised seam/stitch detail for Hoarbound's painterly presentation. The Blender material is a look-development source; Godot NPR shader integration and gameplay state changes are still pending.

Rebuild with Blender 5.2 using `source/build_bedroll.py`; set `BEDROLL_OUT` to the desired output directory. `source/render_animation.py` renders frames for the review video. The saved `.blend` includes the rig, animation, both states and a review-only studio collection.

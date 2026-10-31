# Henry's knit hat

The owner-provided fitted hat is exported as three separate meshes: `KnitHat_Cuff`, `KnitHat_Crown`, and `KnitHat_Pom`. `source/knit_hat.blend` is the editable, baked Blender 5.2+ source; `knit_hat.glb` is the Godot asset. The crown and cuff contain baked albedo and normal maps. The dark knitted weave was informed by [Poly Haven's CC0 knitted fleece](https://polyhaven.com/a/knitted_fleece).

To rebuild from the checked-in source:

```sh
blender -b --python tools/blender/build_knit_hat.py -- assets/characters/henry/knit_hat/source/knit_hat.blend /tmp/knit_hat_export
```

The player visual attaches the GLB to the Head bone and applies Hoarbound's character NPR shader. Equipment's existing `knit_hat` item in `head_outer` controls whether it is shown.

For fitting review, Henry's face points toward Blender −Y. The Godot outfit capture keeps HeadLook neutral so a camera turn does not masquerade as a tilted hat or texture.

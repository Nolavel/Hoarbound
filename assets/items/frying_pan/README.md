# Hoarbound frying pan candidate

The pan is a 24 cm cooking vessel with a fixed forged handle and an oval,
through-cut hanging eye. The GLB contains separate bowl exterior, interior,
painted cooking floor, scoured underside, handle, and two rivets. Its material
layers follow the local, UV-bound palette/mask principle in issue #273 without
changing the game's shader or shadow contract. It is staged on the left carabiner of
Henry's existing backpack by `tools/runtime/capture_frying_pan_on_backpack.gd`.
The preview does not add a pickup, inventory item, collision, or gameplay logic.
The Godot review uses a temporary studio floor and fill light; these are not
part of the in-game scene.

The body began with Innerscene's [CC0 frying pan](https://www.innerscene.com/tools/library/3d-parts/frying-pan-fe1cb069).
The downloaded source GLB is in `source/innerscene_frying_pan.glb` with SHA-256
`4258522a180bf0c738e4f8e816ff79c043faae789c28683d6663eb5c8d62700d`.
The original nonstick finish, induction disc, and handle were replaced; the
bowl was resized and five surface maps were repainted for Hoarbound. The
underside has broken heat staining and scuffs; the forged handle has directional
wear around the oval hanging eye.

Rebuild with Python/Pillow and Blender 5.2 or newer:

```sh
python3 assets/items/frying_pan/source/paint_frying_pan.py
blender -b -t 4 --python assets/items/frying_pan/source/build_frying_pan.py
```

This writes `frying_pan.glb` here, `source/frying_pan.blend`, and five isolated
review PNGs under `docs/asset_previews/frying_pan/`. The Godot capture script
adds real Henry and carabiner screenshots to the same preview directory.
The capture was checked with Godot 4.8 dev6 Forward+/Vulkan.

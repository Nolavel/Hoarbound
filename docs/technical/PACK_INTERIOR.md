# Pack interior (3D inventory)

The main compartment holds items loosely, with no slots: each item is a rigid body inside the pack, as in Cairn. This page covers stage 0, the physics sandbox. Later stages add the cursor and drag, Quick Access in 3D, the TAB ritual and camera, save migration, and polish.

Code: `scripts/items/backpack/pack_interior.gd` (`PackInterior`).
Stand: `tests/systems/test_pack_interior.gd` (pass a drop seed after `--`).
Capture: `tools/runtime/capture_pack_interior.gd`. The pack hangs upright and open, gravity down. Two views: from above into the opening, and the left side wall.

## How it works

- **Own physics space, in pack space.** The interior's bodies live in a `PhysicsServer3D` space created for this pack, with 32 solver iterations and a 2 mm penetration allowance.
  - Gravity is turned into the pack's frame each step, so tilting the pack makes the heap slide.
  - Carrying the pack never flings anything, and nothing inside touches the world.
- **The walls are the canvas.** The collision walls are one closed mesh hit from inside: the canvas's inner rounded box, 12 mm lining in from the outer face, grown by `STRETCH_M` (16 mm). The canvas bulges up to `CANVAS_STRETCH_M` (20 mm) over whatever presses it, so the cloth always stays over the item.
  - The front is the closed panel's surface, so items lie inside it while the panel is folded open.
- **Kept inside.** After each step, every item's support points are projected back inside the same rounded surface, and its velocity into the wall is dropped. Support points are a box's corners, or two rims of a cylinder. This is Jakobsen-style constraint projection, from "Advanced Character Physics" (2001).
  - The visuals and the canvas get the projected pose.
  - Pushes under 0.5 mm are left to the solver, so the heap can sleep.
- **Put in the way it fits.** `add()` turns an item longest side up, its middle side across and its thinnest side front to back. This is how the frying pan (39 × 24 cm) passes, on edge. It is then started inside the canvas wherever it was asked to go.
- **Slack cloth sags onto the contents** (`backpack_canvas.gdshader`). An emptier pack's slump is limited, at each vertex, to the distance to the nearest content. Before this, a near-empty pack's 7 cm top sag cut through a standing axe.
- **Pockets ride their wall.** The side pockets get the main contents too. Where the heap bulges a side wall, the pocket moves out with it, as it does with the open front's give. It also sits 5 mm off the wall, so it no longer z-fights the wall seen from inside the open pack.
- **Settling.**
  - Masses are clamped to 0.25–1.2 kg, because large mass ratios make the solver chatter.
  - Shapes are at least 22 mm thick.
  - Damping climbs by 4/s since an item's last disturbance (`disturb()`), up to 10.
- **Closed.** The space stops, and every pose stays as it is, in pack space.
- **Refusals:**
  - `INVENTORY_TOO_BIG`: the item is `SizeClass.BULKY` (boards, firewood), or its sides do not fit the compartment.
  - `INVENTORY_NO_ROOM`: its volume is more than `room_left()`, which is 70% of the compartment less what is already in.
  - The caller shows the reason as text and highlights the item red.
- **Fill.** The interior items' volume feeds `BackpackModel.get_fill_target()`, so the canvas fills out as the pack is loaded.

## Measured (stand, upright pack, axe, frying pan, hammer, thermos, SPoV, mug; seeds 1, 2, 3, 7, 11, 42)

- **Cloth.** Every drawn item point is checked against the canvas as the shader draws it: the rest surface, the bulge over the outlines it was handed, and the slack sag. This replica is independent of the physics walls.
  - Deepest past the cloth while falling, settling and reopening: 0.0 mm on all seeds.
  - The check does catch a breach: raising `STRETCH_M` by 3 cm fails it at 30 mm.
- **Settling:** 0.6–1.5 s after the last drop.
- **Carrying:** closed, carried 3.6 m with a turn, and reopened, the poses are kept and the fastest item moves at 0.00 m/s.
- **Cost:** a headless frame takes 1.3–2.6 ms. This is the whole frame, an upper bound.

## History

The first stage-0 pass passed its own test but failed visually, for three reasons:
- Its walls were flat slabs 3 cm outside the canvas.
- The test measured the physics walls instead of the drawn cloth.
- The test read body poses before the projection.

The inner shelf from the slot layout is removed.

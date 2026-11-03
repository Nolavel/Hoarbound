# Pack interior (3D inventory)

The main compartment holds items loosely, with no slots: each item is a rigid body inside the pack, as in Cairn. This page covers stage 0, the physics sandbox. Later stages add the cursor and drag, Quick Access in 3D, the TAB ritual and camera, save migration, and polish.

Code: `scripts/items/backpack/pack_interior.gd` (`PackInterior`).
Stand: `tests/systems/test_pack_interior.gd` (pass a drop seed after `--`).
Capture: `tools/runtime/capture_pack_interior.gd`.

## How it works

- **Own physics space, in pack space.** The interior's bodies live in a `PhysicsServer3D` space created for this pack. The walls stay still, because the space is the pack's frame. Gravity is turned into the pack's frame each step, so tilting the pack makes the heap slide. Carrying the pack never flings anything, and nothing inside touches the world.
  - Shared-world `RigidBody3D` items failed the stand: walls moved by teleport threw items at 7 m/s, and stacks sank.
  - The interior space runs 32 solver iterations with a 2 mm penetration allowance.
- **Walls.** The interior has a back wall, two sides, a top and a bottom. The front is the mouth. The sides give `STRETCH_M` (3 cm), and the hem rises `HEM_M` (12 cm) above the mouth, so a heap does not slide over the rim.
- **Kept inside.** After each step, every item's exact outline is projected back inside the walls, and its velocity into the wall is dropped. This is Jakobsen-style constraint projection, from "Advanced Character Physics" (2001). A new drop can press a heap into a wall faster than the solver pushes it out; the projection keeps the data inside anyway. Pushes under 0.5 mm are left to the solver, so the heap can sleep.
- **Settling.**
  - Masses are clamped to 0.25–1.2 kg, because large mass ratios make the solver chatter.
  - Shapes are at least 22 mm thick.
  - Damping climbs by 4/s since an item's last disturbance (`disturb()`), up to 10.
- **Closed.** The space stops, and every pose stays as it is, in pack space.
- **Refusals:**
  - `INVENTORY_TOO_BIG`: the item is `SizeClass.BULKY` (boards, firewood), or its two smallest sides do not pass the mouth.
  - `INVENTORY_NO_ROOM`: its volume is more than `room_left()`, which is 70% of the compartment less what is already in.
  - The caller shows the reason as text and highlights the item red.
- **Canvas.** Each step the exact outlines go to `BackpackModel.set_interior_boxes()`, which drive the canvas bulge.

## Measured (stand, 12 items, seeds 1, 2, 3, 7, 11, 42)

- Deepest past a wall: 0.0 mm on all seeds.
- Settled in 0.85–2.5 s after the last drop.
- Fastest item after closing, carrying the pack 3.6 m with a turn, and reopening: 0.00 m/s.
- Headless frame: 0.7–1.1 ms, which is the whole frame and so an upper bound for the interior's physics.

## Known

- The old slot layout's inner shelf still draws through the heap. It goes with the 2D hub in stage 4.

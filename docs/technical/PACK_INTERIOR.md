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
- **Pockets ride their wall.** The side pockets get the main contents too. Where the heap bulges a side wall, the pocket moves out with it, as it does with the open front's give.
  - The loops and carabiners follow the same rule in GDScript: `BackpackModel._on_canvas` and `pocket_cloth_point`.
  - A pocket's layer sewn on the wall is not drawn from inside the open pack. It used to z-fight the wall there.
  - Known: an item standing in a pocket does not ride the bulge yet, so where the heap presses that wall, the cloth stands up to 2 cm off it.
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

## Hands (stage 1)

Code: `scripts/items/backpack/pack_handling.gd` (`PackHandling`), `pack_cursor.gd` (`PackCursor`), `shaders/items/item_outline.gdshader`.
Stand: `tests/systems/test_pack_handling.gd`. Capture: `tools/runtime/capture_pack_handling.gd`. Keys: `docs/technical/CONTROLS.md`.

- **Picking by the drawn outline.** The cursor's ray is tested against each item's part boxes, not its collision box. A part box is one tight box per mesh part, or six slices across a part much longer than wide. A hammer's collision box is mostly air beside the handle, so picking by it would select the hammer over the pan under it.
  - Collision keeps one box (or cylinder) per item. Multi-part collision (hulls or part boxes) was tried: hulls rattled on the wall mesh and cost 7 ms; part boxes made the heap restless and broke the cloth check.
- **Holding is a velocity drive.** The grab point closes 14× its gap per second, up to 2.5 m/s, on a plane through it facing the camera. Gravity is cancelled for the held item, and its mass rises to 4.8 kg, so it shoves what lies on it. This is how Penumbra and Amnesia carry props.
- **Turning is an orientation drive.** The wheel moves a target 15° per notch; the item spins toward it, and the heap can stop it. A teleported turn pushed a pan into an orientation that could not fit the pack.
- **Shove (RMB).** Items within 4 cm of the cursor's point, on the plane it started on, take the cursor's motion as velocity, up to 0.6 m/s. A kinematic ball of infinite mass blew the heap apart and was replaced.
- **Speed cap.** No item moves faster than 2 m/s or 12 rad/s, a guard like PhysX's max depenetration velocity.
- **Drop (G).** `remove()` emits `removed`/`dropped` with the item's id and state. The caller puts it in the world (stage 4).
- **Rims.** An overlay outline: pale on hover, warm when held, red for a refusal (`show_refusal`).
- **Measured on the stand:**
  - The flask follows the cursor 71 mm, with the grab point 15 mm from the cursor's point.
  - Three notches turn it 48°.
  - RMB sweeps the hammer 31 mm.
  - The stick moves the ring 252 px in a third of a second.
  - The deepest any item came past the cloth is 1.8 mm, during the turn, within the 2 mm grid slop.

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

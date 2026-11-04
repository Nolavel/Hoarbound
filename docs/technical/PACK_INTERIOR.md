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
- **Shove (RMB).** Items within 6 cm of the cursor's point (a hand's width), on the plane it started on, take the cursor's motion as velocity, up to 0.6 m/s, plus up to 0.25 m/s of lift so jammed items budge. A kinematic ball of infinite mass blew the heap apart and was replaced.
- **A calm heap while one item moves** (measured as the mean speed of the other items while one is dragged; 0.097 m/s before, 0.004–0.063 m/s after over five drop seeds):
  - **Sleeping islands.** Taking, letting go and throwing out wake only the item itself, or what touched it. The rest of the heap sleeps until something touches it, as in Rapier and Jolt. The space sleeps a body below 0.04 m/s and 0.2 rad/s after 0.3 s.
  - **A calm-down restarts only when the item itself is knocked** (faster than 0.25 m/s), not when the heap is touched.
  - **A hand of limited strength.** The hold is a velocity drive whose change is capped at 12 m/s² and whose speed is capped at 1 m/s. An item blocked by the heap leans on it rather than ramming it every step, like a PhysX drive with a force limit. Before this, the hand had infinite force and kept shoving the heap after the cursor stopped.
  - **A slippery held item.** Friction drops to 0.05 while held, so it slides out instead of dragging its neighbours along. Its mass doubles.
  - Tried and dropped: thickening the rest of the heap (extra damping) while an item is held changed nothing measurable.
- **Weight where the bulk is.** The centre of mass is the volume-weighted centre of the item's part boxes, so a hammer's or axe's sits in its head. Items go in heavy end down, and the stand checks the hammer and axe settle head down.
- **Fits nowhere as it lies.** If shifting leaves an item more than 2 mm past the canvas (a pan turned with its disc along the depth), it turns back toward the turn it went in with, which passes the refusal check, and is shifted again within the same step.
- **Not done: sticking to the walls.** Godot combines two bodies' friction by taking the smaller value, so a grippier canvas alone would not hold anything on a wall.
- **Speed cap.** No item moves faster than 2 m/s or 12 rad/s, a guard like PhysX's max depenetration velocity.
- **Drop (G).** `remove()` emits `removed`/`dropped` with the item's id and state. The caller puts it in the world (stage 4).
- **Rims.** An overlay outline: pale on hover, warm when held, red for a refusal (`show_refusal`).
- **Measured on the stand:**
  - The flask follows the cursor 71 mm, with the grab point 15 mm from the cursor's point.
  - Three notches turn it 48°.
  - RMB sweeps the hammer 31 mm.
  - The stick moves the ring 252 px in a third of a second.
  - The deepest any item came past the cloth is 1.8 mm, during the turn, within the 2 mm grid slop.

## Quick Access in 3D (stage 2)

Code: `scripts/items/backpack/pack_quick_shelf.gd` (`PackQuickShelf`), wired through `PackHandling.setup_shelf`.
Stand: `tests/systems/test_pack_shelf.gd`. Capture: `tools/runtime/capture_pack_shelf.gd`.

- **Cards.** While the pack is open, each quick pocket is a card beside it. Body pockets (coat left and right, thigh, lid) stand in a column left of the pack; the pack's outside pockets (side pocket, both sleeves, both carabiners) stand right of it.
  - Each card is the Quick Access gradient: `BG_frame.gdshader`, drawn once per column into a `SubViewport` and tinted per card, fading toward the pack. Cards lie flat on the screen.
  - The pocket's item stands on its card in 3D and turns slowly. Pocket names are localised (`POCKET_*`).
- **Moving items.** Everything goes through the same ring and LMB:
  - card to pack: the item rides the cursor and is put into the compartment where the cursor's ray meets it;
  - pack to card: the held item leaves the pack into that pocket;
  - card to card.
  - The card under the cursor turns warm if it would take the item, red if it would refuse.
- **The fit rule is the inventory's own** (`EquipmentComponent._check_fit`): the item's size class against the pocket's `max_size`, plus a taken pocket being full.
  - A refusal shows the reason under the ring (`INVENTORY_POCKET_FULL`, `INVENTORY_POCKET_TOO_SMALL`), and the item goes back.
  - Known: every item we have is size class POCKET, so any pocket takes any item, even the pan in a coat pocket. This needs the author's call.
- **G** over a card throws its item out (`dropped`).
- **Measured on the stand:**
  - The tin goes from the coat pocket into the pack.
  - The pan goes from the pack into the free coat pocket.
  - The taken coat pocket refuses the thermos, which goes back.
  - G throws the mug off the carabiner.
  - Nothing comes past the cloth.
- **Not yet wired:** the cards read and write their own list. Binding them to `EquipmentComponent` pockets and the save is stage 4.

## Straps instead of physics (the main compartment)

Code: `scripts/items/backpack/pack_straps.gd` (`PackStraps`), built into the pack's canvas by `PackRig` and fed from the inventory.

- **Three straps, one per tier.** The straps run across the back wall, one for each third of the compartment's height.
  - An item goes into the lowest tier with room, against the back wall, beside the last one in the front layer.
  - When a tier's first layer is full across, the next layer stands in front of it while the depth allows.
  - Each tier's strap pulls in to the front of what it holds and buckles: 0.35 s drop in over the mouth, then a 0.22 s cinch. An empty tier's strap lies back on the wall.
- **Real sizes.** An item's outline comes from its model in metres. It is turned thinnest side front to back, standing first (its longest side up) so more fit side by side.
  - Usable inside: 25.6 × 48.8 × 18.8 cm. Across, it keeps a canvas bulge's reach off each side wall, so the side walls and the pockets sewn on them stay flat.
  - SPoV tins: 3 across × 3 tiers = 9 per layer, 18 in two layers.
  - Refusals: `INVENTORY_TOO_BIG` when no tier takes the outline in any turn (the axe); `INVENTORY_NO_ROOM` when no tier has room left.
- **Straps are part of the pack.** Each strap's ends are fixed to both side walls by the back wall. Empty, it lies flat on the back wall; with contents, it draws out round their front and buckles in the middle (eased 0.22 s after an item lands). It never slides in from anywhere.
- **Contents.** What the pack holds, minus the bedroll strapped on top, stands under the straps: the `pack_main` pockets plus the inventory, one place per instance. It re-lays out whenever the inventory or a pack pocket changes.
- **Items taller than a tier** (16 cm) are refused for now. Spanning two straps is not done yet.
- **Not yet:** the ring cursor and dragging work on `PackInterior` (physics), not on the straps yet. `PackInterior` remains only for those stands.

## Tab ritual and view (stage 3)

Code: `scripts/actors/player/henry/pack/pack_front_hold.gd` (`PackFrontHold`, via `HenryUALAnimation.hold_pack_front()` / `release_pack_front()`), and `PlayerHubComponent` with `pack_in_hands` set (the default).
Capture: `tools/runtime/capture_pack_view.gd`, with the real HUD. Stills: `tools/runtime/capture_pack_hold.gd`.

- **Tab.** Henry takes the pack off his back. It swings in an arc over 0.7 s to 36 cm ahead of his chest and 18 cm below it.
  - It is held upright, opening turned out toward the camera and tipped up 30°, so he sees in from above too.
  - The front panel drops open away from him.
  - Both hands take it by the side walls (HandGrip); the fingers come over the rim.
  - Tab or Esc swings it back on, and it closes there.
- **Camera.** It faces Henry, fixed, square to the opening and a little above it. It sits at the distance where the pack fills 47% of the frame height at 50°, aimed 7 cm below the pack's middle so the dropped panel (the hem) shows. Past the pack it softens (depth of field) (`PackFrontHold.front_view`).
- **One strap stays on.** Henry slips one arm out only. The left strap keeps to the jacket as worn, from the top of the shoulder 14 cm down the chest, then hangs to the pack's top corner (`PackShoulderStraps._draw_on_shoulder`). The other strap hangs free from the pack. Verlet chains now pin their ends every step, so a strap follows a moving pack.
- **Quick Access beside the pack.** The real quick pockets' 3D items stand on gradient cards with no text, in a column at each side of the frame, clear of the pack: body pockets left, the pack's outside pockets right (`PackQuickShelf.setup_live`, children of the Hub camera). `send_to_pack(slot)` flies a pocket's item into the opening and moves it through the Hub, and the straps take it in.
- **Full inspection** (pack set down) is unchanged. It opens the Hub without taking the pack in hand, and the 2D Hub panel shows only there.

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

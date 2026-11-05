# Pack interior (3D inventory)

Tab takes the pack into Henry's hands and opens it toward a fixed camera. The main compartment holds what is in it under three straps. A quick pocket whose item shows on the pack has its card behind that real item; only hidden pockets stand as 3D cards at the frame's sides. A ring cursor moves items between the pack, the pockets and the ground.

Stands:
- `tests/systems/test_pack_hands.gd`: the ring and hands on the real player and Hub.
- `tests/systems/test_backpack_rig.gd`: the pack's outside.
- `tests/systems/test_player_hub.gd` and `test_pack_inspection.gd`.

Captures:
- `tools/runtime/capture_pack_view.gd`: the Tab ritual with the real HUD.
- `tools/runtime/capture_pack_hold.gd`: stills.

## Tab ritual and view

Code: `scripts/actors/player/henry/pack/pack_front_hold.gd` (`PackFrontHold`, through `HenryUALAnimation.hold_pack_front()` / `release_pack_front()`), and `PlayerHubComponent` with `pack_in_hands` set (the default).

- **The hold.** The pack swings in an arc over 0.7 s to 46 cm ahead of the chest and 18 cm below it.
  - It is held upright, opening toward the camera and tipped up 45°, so Henry sees in from above too.
  - The front panel (the hem) drops open away from him.
  - His hands take the side walls from outside, elbows wide (HandGrip).
  - Tab or Esc swings it back on.
- **One strap stays on.** The left strap lies on the jacket as worn, from the top of the shoulder 14 cm down the chest, then hangs to the pack's top corner (`PackShoulderStraps._draw_on_shoulder`). The other hangs free.
  - Strap verlet chains pin their ends every step, so they follow a moving pack.
- **Camera.** It faces Henry, fixed, square to the opening and a little above it.
  - The pack fills 47% of the frame height at 50°.
  - It aims 7 cm below the pack's middle, so the hem shows.
  - What lies past the pack is softened (depth of field).
- **Full inspection** (the pack set down) is unchanged. It opens the Hub without the hold, and the 2D Hub panel shows only there.

## Straps (the main compartment)

Code: `scripts/items/backpack/pack_straps.gd` (`PackStraps`). `PackRig` builds it into the canvas and feeds it the inventory plus the `pack_main` pockets, bar the bedroll strapped on top.

- **Tiers.** Three straps, one per third of the compartment's height.
  - An item goes into the lowest tier with room, against the back wall, beside the last one.
  - When a tier's front layer is full across, the next layer stands before it while the depth allows.
- **Real sizes.** Outlines come from the items' models, in metres.
  - Items are turned thinnest side front to back, standing first.
  - The usable inside is 25.6 × 48.8 × 18.8 cm. A bulge's reach is kept off each side wall, so the side pockets stay flat.
  - SPoV tins: 9 per layer, 18 in two.
- **The straps are part of the pack.** Each strap's ends are fixed to both side walls by the back wall.
  - Empty, it lies on the wall.
  - With contents, it draws out round their front and buckles in the middle, 0.22 s after an item lands. It never slides in from anywhere.
- **Refusals.**
  - `INVENTORY_TOO_BIG`: no tier takes the outline in any turn (the axe). Items taller than a tier (16 cm) count as too big for now.
  - `INVENTORY_NO_ROOM`: no tier has room left.

## Quick Access cards

Code: `scripts/items/backpack/pack_quick_shelf.gd` (`PackQuickShelf`), a child of the Hub camera.

- Each real quick pocket is a card on the Quick Access gradient (`BG_frame.gdshader`, drawn once per fade direction and tinted). There is no text.
- **Shown on the pack** (side pockets, both carabiners; `PackRig.SHOWN_POCKETS`): nothing is drawn over it. An unseen card stands square to the camera behind the real item (`PackRig.get_pocket_visual`), or around the empty pocket's spot (`get_pocket_spot`), only so the ring can hover it. The item itself is hit on its own screen outline (the ring's silhouette); where outlines overlap the smallest wins; the unseen card serves an empty pocket. `aim_point(k)` gives stands and captures a point that hovers slot k. A strapped item under the cursor wins over any of them.
- **Hidden on the body** (two coat pockets, two thigh pockets): the cards stand in a row at the bottom centre, trousers left, the hand card in the middle, coat right (`BOTTOM_ROW`). With `SHOW_BODY_PANEL` on (off by the owner's call) they sit instead on a see-through grey panel of Henry's coat and trousers near the frame's left edge, where each pocket is, at `BODY_CARD_ALPHA` and with their gradient fading the other way. The panel (`assets/ui/inventory/body_front.png`, the trousers dropped 6 cm below the coat's hem so the two read apart) and the pockets' places on it (`body_front.json`, from his bones) are baked by `tools/runtime/bake_body_silhouette.gd` from the real `Outfit_Jacket` and `Outfit_Pants` seen square from the front; re-bake when the outfit changes.
- Items stand still on their cards, turned a little (`ITEM_TURN`) so their shape reads.
- **Hidden on the pack** (the lid pocket): a card at the right, with its 3D item turning on it.
- **Hand card** (middle of the bottom row; beside the body panel when it shows): the hand icon (`hand_open.svg`, faint) and the Quick Access pick's item, what Henry takes in hand when the pack goes back on. A pocket's item let go on it becomes the pick; taking from it takes from that pocket.
- The fit rule is the equipment's own (`can_stow`): a taken pocket is full (`INVENTORY_POCKET_FULL`), and a size-class refusal is `INVENTORY_POCKET_TOO_SMALL`.

## Focus blur

Code: `scripts/items/backpack/pack_focus_blur.gd` (`PackFocusBlur`, a child of the Hub camera), `shaders/items/pack_focus_blur.gdshader`.

- Everything but the held pack and the inventory itself is blurred, Henry included. Depth of field cannot do it: from the camera's raised view his chest is nearer than the pack's back wall, and the see-through cards would take the floor's depth and blur.
- Every mesh of the pack and of the camera's children (cards' items, a carried item) gets an unseen overlay that writes stencil 9; a full-screen quad (render priority −127, after the masks at −128) blurs where it is not written: 13 taps on a disc over the screen texture's mips. It fades in over 0.35 s.
- A mesh that enters the tree under the pack or the camera is masked as it arrives (`SceneTree.node_added`), so an item put in is never drawn blurred; a slow rescan is the safety net.
- Flat cards and the body panel (meta `flat_card`) are not masked: they are see-through and draw after the blur, over the blurred world. A rim on a masked mesh chains after its mask (`next_pass`).

## Containers (furniture with shelves)

Code: `scripts/environment/interactive/item_container.gd` (`ItemContainer`). Test: `tests/systems/test_item_container.gd`.

- A piece of furniture holds items on its shelves, which stand there as ordinary `ItemPickup`s (F still takes one straight into the pack, and it leaves the list). The list is the truth and is saved as `container/<id>`.
- Shelves come from the furniture's own box panels (`shelves_from_furniture`): side walls, back wall and horizontal panels; the space between neighbouring horizontals is a shelf; the door's subtree is left out.
- Items stand leftmost on the first shelf with room, by their real outline, clear of each other (2 cm gaps); no room is `CONTAINER_NO_ROOM`.
- The 727 waiting-room cabinet (`KeyWest727Shelter.place_supplies`) holds its dressed tins as real items (`CABINET_PROPS`: stew, pineapple) and adopts the layout's pickups socketed `on: Cabinet` (the SPoV can, the gloves); the dressed mug was removed (it duplicated Henry's). An older save that took one of them from the world drops it again (`PickupLedger` → `drop_taken`).
- **Visiting a container** (owner's design). Henry walks to its visit spot and the pack opens there (`PlayerHubComponent.visit_container`). Either trigger starts the walk:
  - F opening its door, with the player within 3 m (`ItemContainer._on_door_toggled`);
  - Tab within 1.3 m of a reachable one (`ItemContainer.find_open_near`).
  - **The free side.** The pack goes on the side away from the door's hinge, where the open door does not swing (`ItemContainer.free_side`). With no door it goes on the side Henry came from.
  - **The spot.** Henry's spot is 0.45 m out from the shelves' front and 0.58 m past the edge on that side (`ItemContainer.visit_spot`). WASD on the way calls the visit off, and so does Tab again.
  - **Crouching.** There he faces the front. If the shelves top out below 1.1 m he crouches (`ItemContainer.is_low`, `Player.set_work_crouch`). The pack opens once he is down, and closing it stands him up.
  - **Framing (owner's sketch).** Only the pack and the furniture are in the frame, Henry hidden (owner: he does not matter here) (`PackFrontHold.begin_container`, `_frame_container`).
    - The view looks in at 30° from the side away from the pack and a little above. The furniture's front is turned to the pack and its far side shows, through a 34° lens (`Hub.container_view_fov`).
    - The view stands where the furniture (`ItemContainer.body_box`, its door left out) fills its half: 48% of the frame width (`CONTAINER_SHARE`).
    - The pack floats in the other half, upright, its opening turned to the view, its front panel open flat (88°). It is as near as fills 48% across, its foot on the furniture's foot line on screen.
    - Both fit in nearly the whole height. The load bar and the pocket cards draw over them.
    - Measured on the stand (`tools/runtime/capture_container_stand.gd left|right`): pack 48%, furniture 47%.
  - The ring hovers a shelf item on its silhouette (`ItemContainer.pick`). LMB carries it into the pack (`Hub.move_from_container`, the pack's room checked first, jolt) or onto a pocket's card; a pack or pocket item let go over the shelves goes onto them (`Hub.move_to_container`); a full shelf refuses with `CONTAINER_NO_ROOM`. RMB and G do nothing on a shelf item.
  - Tests: `tests/systems/test_container_hands.gd`; capture: `tools/runtime/capture_container_view.gd` (the 727 cabinet).

## Hands

Code: `scripts/items/backpack/pack_handling.gd` (`PackHandling`), `pack_cursor.gd` (`PackCursor`), `shaders/items/item_outline.gdshader`. Keys: `docs/technical/CONTROLS.md`.

- **Hover.** The ring hovers a strapped item (picked on its place's box), a pocket or the hand card, and flows into the item's silhouette on screen, with the "G — drop" hint beside it. The silhouette: its triangles rasterised into a 56-cell grid, the boundary traced (Moore neighbourhood), cached while nothing moves; the ring is resampled along its length (`PackCursor`).
- **Readout.** Under the hovered or carried item: its name, weight and the number that matters most (a flask's water, food's calories, otherwise its size class), from `ItemReadout.describe` (`core/items/item_readout.gd`).
- **Load bar** (top centre): what Henry carries of his limit (`InventoryComponent.max_carry_weight`), amber past `MovementController.load_penalty_starts` (where he starts to slow, ticked on the bar), with the hovered item's share bright at the fill's end.
- **Sound and weight.** Taking, putting and dropping rustle the cloth (`data/audio/backpack/pack_rustle.tres`); a refusal pulls softer (`pack_resist.tres`). The clips come from Freesound #237047 (CC0, `assets/audio/sfx/items/backpack_cloth/LICENSE.md`). Something put into the pack jolts it in Henry's hands (`PackFrontHold.jolt`): a dip of 1.2 cm for the hand's push plus 2 cm per kg (3.5 cm at most), tipped with it, springing back as a damped bounce.
- **Use** (RMB, pad X; `use_hovered`): the verb comes from the item (`use_verb`). A tin opens where it lies through `ConsumptionController` and the pack stays open. Food and drink go through `Hub.use_item` or `use_from_zone`, which close the pack so Henry has his hands. A refusal shows `ConsumptionController.describe_refusal`.
- **Carry.** LMB (pad A) takes it, the ring hides, and the item rides the cursor at its true size (scaled by how much nearer than the pack it hangs) with a warm rim. Letting go:
  - over a card moves it into that pocket (`move_to_zone`, or `move_between_zones` from another pocket);
  - over the pack moves it under the straps (`move_to_pack`, after the straps' own refusal check);
  - anywhere else puts it back.
- **Refusals.** A card turns red where the item would be refused, and the carried item turns red over a pack that would not take it. A refusal shows its reason under the ring.
- **G** (pad Y) puts the hovered item down on the ground ahead of Henry (`drop_from_pack`, `drop_from_zone`, through `ItemPickup.spawn_dropped`, which the hand's drop uses too).
- Every move goes through the Hub, so the inventory and the equipment stay the truth, and the straps and cards redraw from them.

## History

- **A physics compartment** (`PackInterior`: rigid bodies in a pack-space physics space, canvas projection, sleeping islands) was built and then removed in favour of straps.
  - Stacks rattled.
  - Items fought the rounded walls.
  - Tall tools sank into a crowded heap.
  - Every fix added cost.
- **The wheel turn and the RMB sweep** went with it.

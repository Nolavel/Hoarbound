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
- **Visiting a container** (owner's design), in two presses of F.
  - **F on the door** only opens and shuts it. Open, the door is aimed at on its swung-open leaf (`Cabinet.get_focus_point`), so aiming into the shelves offers the search instead.
  - **Open, with something inside:**
    - The shelves' open face is frosted over: a quad with `shaders/items/frosted_veil.gdshader` (the screen behind at a blurred mip, 80% over the sharp view: half-seen shapes). What is inside reads only as unclear shapes (`ItemContainer._make_veil`).
    - Its items are not taken by F (`ItemPickup.in_container`).
    - Instead the search is offered at the middle of the face (`ContainerSearch`, pickup channel): the pickup marker's ring and F, with an eye inside the ring (`InteractiveArea.marker_icon`, `assets/ui/hud/pickup_marker/eye.svg`, Material Symbols, Apache 2.0).
  - **F on the search** (or Tab beside an open container) works where Henry stands: he has walked up himself, so he does not walk again (owner). He stops, faces the front and crouches if the shelves top out below 1.1 m (`PlayerHubComponent.visit_container`, `ItemContainer.is_low`). The search is offered only within 1.4 m of its marker (`ContainerSearch.REACH_M`).
  - **The pack comes off** into his hands as by Tab: the same view in front of him, so its turn off his back shows (`PackFrontHold`).
  - **The cut.** Once the pack is in his hands (`settled`), the view cuts hard to the working frame (`Hub._cut_to_container`). Outlines traced in that frame would use the view before the jump, so the outline cache is cleared and the cards and ring come on a frame later. The pack takes its framed place, Henry leaves the frame, and the focus blur, the cards and the ring come on. The frost lifts while the Hub holds that container.
  - **Closing** puts the pack back from his hands as by Tab and stands him up.
  - **The free side.** The pack goes on the side away from the side-hinged doors swung open there (`ItemContainer.free_side`); a single door counts whether open or not. With no door, open doors on both sides, a lid or a drawer, it goes on the side Henry stands on.
  - **Kinds of furniture.** An `ItemContainer` can have several ways in (`openers`: `Cabinet` doors and lids, `Drawer`s); it is reachable when any is open (`is_reachable`). `opens_up` (a drawer, a chest) puts the frost and the search on the top face, and the view looks down into it at 55° (`PackFrontHold.CONTAINER_OPENS_UP_DEG`). `Cabinet.swing_axis` turns a lid on a horizontal hinge; `Drawer` slides `travel` out. `furniture` names the whole piece when the shelves are one drawer of a dresser. The owner's framing, authored on the 727 cabinet, is pushed out in proportion for wider or taller shelves (`CONTAINER_REF_SHELVES`).
  - **The working frame, fitted to any furniture** (owner: one scalable system, doors out of the way, the pack's opening to the camera, nothing passing into anything). Just before the cut (`PackFrontHold._clear_container`, `ContainerClearance`):
    - **the owner's framing stands as authored** (`container_framing.tres`) unless something passes into something or hides; at the 727-like floor cabinet the view stays exactly and the pack within 3 cm (lifted only so the pan at rest clears the floor);
    - every visible mesh of the piece (doors and drawers as they stand, items of any container left out) is an oriented box;
    - the pack is an oriented box per mesh, the open front panel's sweep (`BackpackModel.open_panel_box`, it bends in the shader), and what hangs off it **as it hangs at rest** at its new place (each `PendulumHang`'s -Y down, square to its pin; `_at_rest`). Placed at a cut, a hanger already inside a part could never swing clear of it by contact; once placed, swinging hangers meet the furniture by contact (`hang_obstacles`);
    - **doors open all the way**: each open side door on the pack's side is held at 175° (`Cabinet.hold_max_deg`, `hold_at`, unseen at the hard cut; `release_hold` swings it back when the pack goes on). Measured before: at 165° the cupboard's right door lay on the pack's place and pushed it 0.41 m sideways; at 80° it stood out between;
    - **the pack moves the least way**: toward the view first (so it stands before an open door), out in front, out to its side, up, or between them, 1 cm at a time, until no box comes within 2 cm of any part; it is first lifted so its lowest part clears the floor (`place_pack`, `_ways_out`);
    - **the view**: it turns about the pack (up first, then aside, the least turn, 5° steps, up to 50° up and 30° aside) and backs off (5 cm steps, up to 1.5 m) until every item's middle shows past the furniture and the pack, the pack's open face shows past the furniture, the pack and every item are framed (load bar and cards' strips left free) and the eye stands in no part;
    - **looking down into it** (a drawer, a chest; `opens_up`): the pack's opening turns straight to the view, tipped back up to 50° (`_face_view`, `CONTAINER_FACE_TIP_DEG`, owner: its contents read); the view tries from 0.6 m nearer first and frames the whole open box; the pack turns to the final view and is placed clear again (two passes).
  - **Furniture kit and the 727 shelter.** `FurnitureKit` (`scripts/environment/interactive/furniture_kit.gd`) builds every kind: floor cabinet, kitchen cupboard, dresser, chest. The test row and the 727 shelter both use it. In 727 (`KeyWest727Shelter._place_searchable`; plan kinds `kitchen_cupboard`, `dresser`, `chest` in `tools/world/reality/shelter_727.py` and the generated spec) the waiting room has:
    - a kitchen cupboard hung on the corridor partition (u −3.6, v 0.445), back 1 cm off the wall, clear of the waiting-room doorway and the thermometer;
    - a dresser on the restroom partition (u −5.345, v 1.6), back 1 cm off the wall;
    - a chest on the east wall (u 3.095, v 4.4), back 17 cm off the wall so its lid has room, between the lobby arch and the side window.
    - Their contents at a new game are `KeyWest727Shelter.FURNITURE_CONTENTS`, kept out of the generated plan so a rebuild keeps them: cupboard SPoV can and empty tin; dresser nails (top), tinder (middle), nothing (bottom); chest a tin of pineapple. These are game-invented and the owner's to change.
    - `tests/systems/test_727_furniture.gd` runs in the real shell. It checks that each piece touches no other furniture and no wall (rays from its middle: the shell's walls are triangle meshes), and that each full one is searched with no pack mesh in the furniture, the walls or the floor.
    - Pack meshes are checked mesh against box: a triangle edge crossing the box, or a box edge crossing a triangle (`tests/systems/container_search_checks.gd`).
  - **Built off-tree.** A container filled before it enters the tree (the 727 house is built off-tree) only records its items; it lays them out in `_ready`. An item measures its size only in the tree, where its pickup builds its model, and an off-tree size is never cached. They used to be measured as nothing there and stacked in one spot.
  - **Items show as themselves.** A world or shelf pickup draws every item `SurvivalItemVisual` knows (`SurvivalItemVisual.draws`): empty tins, tinder, mugs, the pan. The 32 cm placeholder parcel is only for items with no model; it used to hide the SPoV can behind it.
  - **Hangers at the cut.** The frame the pack jumps to its place, every `PendulumHang` on it hangs straight down at rest (`PendulumHang.rest_now`), the pose `ContainerClearance.pack_shape` planned. Then it swings and leans by contact as usual.
  - **Test row.** `tests/scenes/container_row.tscn` (`ContainerRow`, also in `TestScene`): a floor cabinet with a left-hinged door, a kitchen cupboard high on a wall with two doors, a dresser with three drawers, a floor chest with a lid. The cabinet, the cupboard, the top two drawers and the chest hold things; the bottom drawer is empty. `tests/systems/test_container_kinds.gd` runs every one: no search while shut, a search only when something is inside, done in place, crouching only at low ones, the owner's framing kept at the floor cabinet, the door on the pack's side all the way open with the pack before it, the pack's opening to the view, the pack within 0.75 m of the shelves, no pack mesh inside any furniture part, every item and the pack's face seen past everything, the ring on an item. Stills: `tools/runtime/capture_container_row.gd`.
  - **Hangers keep out of the floor and the furniture.** By a container, what hangs off the carabiners stays free instead of frozen. Two more obstacles join the pack's own body for the pendulum's contact solver (`BackpackModel._pack_contact`):
    - the floor under Henry (`hang_floor_y`; a kitchen cupboard hangs high on the wall);
    - every part of the furniture (`hang_obstacles`, from `ContainerClearance.furniture_parts`).
    - A hanger therefore turns on its carabiner instead of passing through either. If what hangs on a pin meets the floor, it turns toward the view (`PendulumHang.hinge_out`), never under the open panel.
    - The owner's framing lifts the pack so the pan hangs free: stand trace, 4 cm above the floor, clear of the cabinet's side.
  - **Owner-authored framing (editor).** Open `tests/scenes/container_framing_stage.tscn`: floor, the 727 cabinet with its door open on the left hinge, Henry, a stand-in pack, and the camera.
    - Move `Front/Camera`, `Front/Pack` and `Front/Henry`, and preview through `Camera` (its `fov` counts). Then press **Save framing** in the stage root's inspector. It writes `data/items/container_framing.tres` (`ContainerFraming`).
    - Henry's visibility there is saved too: hide him to hide him in game.
    - All three are relative to `Front`, the middle of the shelves' open face (`ItemContainer.front`), authored for the pack on the right. For a door hinged on the right, the game mirrors them (`ContainerFraming.on_side`).
    - In game the camera and the pack are put there (`PackFrontHold.begin_container`), then moved clear (above). Henry's saved point is not walked to: he searches where he stands.
    - The stage's Henry and pack are for editing only. Henry's script needs the player, so do not run the stage scene.
    - The saved points are offsets from the front, so they suit cabinets about the 727's size. The worked-out framing below is the fallback when no framing is saved.
  - **Worked-out framing (fallback, owner's sketch).** Only the pack and the furniture are in the frame, Henry hidden (owner: he does not matter here) (`PackFrontHold.begin_container`, `_frame_container`).
    - The view looks in at 30° from the side away from the pack and a little above. The furniture's front is turned to the pack and its far side shows, through a 34° lens (`Hub.container_view_fov`).
    - The view stands where the furniture (`ItemContainer.body_box`, its door left out) fills its half: 48% of the frame width (`CONTAINER_SHARE`).
    - The pack floats in the other half, pressed in toward the furniture (`CONTAINER_PACK_IN`). It stands upright, its front panel open flat (88°). Its front turns three quarters of the way from the view to the furniture's front, so the two nearly share a plane (`CONTAINER_PACK_PLANE`, owner).
    - It is nearer the view than its half alone asks (owner: nearer to us): its body and bedroll span 30% of the frame width (`CONTAINER_PACK_SHARE`). It is placed by those alone: the open panel, the loops and what hangs are left out, so turning the panel does not shift it. Its hangers then meet the furniture's edge (`CONTAINER_PACK_IN`).
    - Its foot sits up to 0.3 NDC above the furniture's on screen (`CONTAINER_PACK_LIFT`, owner: higher). It is lowered only as far as keeps its top, the bedroll, in the frame. The open panel's lower edge may run past the bottom.
    - It is lifted further if what hangs off it (the pan, 0.26 m) would still reach the floor (`CONTAINER_FLOOR_CLEAR_M`).
    - The frame is worked out 15% wider than the view (`CONTAINER_TIGHTEN`), so both show larger and their outer edges run past the frame (owner: tighter). The load bar and the pocket cards draw over them.
    - Henry is hidden once the pack's swing is 60% on, when the blur has come up. The stand-in arm was tried and dropped (owner: it read as rubber).
    - Measured on the stand (`tools/runtime/capture_container_stand.gd left|right`), by body and bedroll: pack 35%, furniture 53%; the flask or the mug touches the furniture's edge.
  - The ring hovers a shelf item on its silhouette (`ItemContainer.pick`). LMB carries it into the pack (`Hub.move_from_container`, the pack's room checked first, jolt) or onto a pocket's card; a pack or pocket item let go over the shelves goes onto them (`Hub.move_to_container`); a full shelf refuses with `CONTAINER_NO_ROOM`. RMB and G do nothing on a shelf item.
  - Tests: `tests/systems/test_container_hands.gd`, `tests/systems/test_container_kinds.gd`; captures: `tools/runtime/capture_container_view.gd` (the 727 cabinet), `tools/runtime/capture_container_row.gd` (the test row).

## Hands

Code: `scripts/items/backpack/pack_handling.gd` (`PackHandling`), `pack_cursor.gd` (`PackCursor`), `shaders/items/item_outline.gdshader`. Keys: `docs/technical/CONTROLS.md`.

- **Hover.** The ring hovers a strapped item (picked on its place's box), a pocket or the hand card, and flows into the item's silhouette on screen, with the "G — drop" hint beside it. The silhouette: its triangles rasterised into a 56-cell grid, the boundary traced (Moore neighbourhood), cached while nothing moves; the ring is resampled along its length (`PackCursor`).
- **Readout.** Under the hovered or carried item: its name, weight and the number that matters most (a flask's water, food's calories, otherwise its size class), from `ItemReadout.describe` (`core/items/item_readout.gd`).
- **Load bar** (top centre): what Henry carries of his limit (`InventoryComponent.max_carry_weight`), amber past `MovementController.load_penalty_starts` (where he starts to slow, ticked on the bar), with the hovered item's share bright at the fill's end.
- **Sound and weight.** Taking, putting and dropping rustle the cloth (`data/audio/backpack/pack_rustle.tres`); a refusal pulls softer (`pack_resist.tres`). The clips come from Freesound #237047 (CC0, `assets/audio/sfx/items/backpack_cloth/LICENSE.md`). Something put into the pack jolts it in Henry's hands (`PackFrontHold.jolt`): a dip of 1.2 cm for the hand's push plus 2 cm per kg (3.5 cm at most), tipped with it, springing back as a damped bounce.
- **Use** (RMB, pad X; `use_hovered`): the verb comes from the item (`use_verb`). A tin opens where it lies through `ConsumptionController` and the pack stays open. Food and drink go through `Hub.use_item` or `use_from_zone`, which close the pack so Henry has his hands. A refusal shows `ConsumptionController.describe_refusal`.
- **Taking costs time** (Project Zomboid's timed actions; `PackHandling.take_seconds`). LMB is held while the hand works the item free, and a thick amber line fills round its outline (`PackCursor.progress`). Let go before it is full and nothing is taken.
  - A pocket, the hand card or a shelf: 0.2 s. A strapped item: 0.28 s, plus up to 0.3 s on the bottom tier.
  - Each kg adds 0.12 s, up to 0.4 s.
  - Cold hands (`ThermalManager.get_extremity_cold(&"hands")`, via `Hub.get_hands_cold`) multiply it by up to 2.5. A tin off the bottom strap takes 0.63 s warm and 1.57 s frozen.
  - Past a quarter of that cold load the ring shakes, up to 9 px at 7 Hz, so frozen hands also aim worse.
- **Pockets in centimetres** (`EquipmentSlotDefinition.inner_cm`, `ItemFootprint`). A pocket with an inside size takes an item only if its real size fits: the item's model, measured once per id.
  - The two smaller sides must pass the mouth, and the longest must fit the depth, standing out up to 30%.
  - Garments squash, so for them only the size class counts.
  - Sizes: coat 20×22×11, thigh 18×24×8, pack lid 28×22×8, thermos sleeve 11×22×11, tool sleeves 18×40×5. The main compartment and the carabiners keep the size class alone.
  - Result: the hammer (34 cm), the axe (37 cm) and the pan (39 cm) go into no coat or trouser pocket; tins, the knife and the lighter still do.
- **Clothes silhouette on demand** (owner). The clothes panel stays off (`SHOW_BODY_PANEL`), but while the ring is on a coat or trouser pocket's card only the garment that owns it (coat or trousers, `BODY_SPLIT_V`) fades in at the left over 0.22 s (`PackQuickShelf._fade_body`, `focus_slot` set by `PackHandling`). An amber dot marks where that pocket is on the body (`body_front.json`). Off the card, it fades out.
- **Bundles** (`ItemResource.bundles`). Small things kept in numbers (`max_stack` of 5 or more: nails, tinder, road flares, empty tins) lie under the straps as one bundle per full stack (`PackRig._refresh_contents`). Tins (stack 4) stay one place each.
  - The readout names the count: "Nails ×20" (`ItemReadout.describe(id, count)`, `ITEM_BUNDLE_COUNT`).
  - Taking a bundle takes one unit; the rest stay.
- **Pad steps** (`PackHandling.snap`). A flick of the left stick past 0.6 jumps the ring to the nearest target that way, within 55°, off-axis ones counting as farther. Held, it steps every 0.32 s, and it re-arms below 0.3.
  - Targets (`snap_targets`): every strapped item, every shown card, the hand card, the pack's room (to put a carried item in), an open container's items and its shelves.
- **Threats shut it** (Green Hell; `Hub.interrupt`). Time never stops in the Hub, and a threat closes the open pack at once and calls off a walk to a container.
  - Threats now: a blow (`PlayerHealthSystem.hurt`, from `take_damage` only; frostbite's slow `drain` does not count) and falling faster than 2 m/s.
  - Thin ice and other threats call `interrupt()` too, once they raise a signal.
- **Carry.** Once taken, the ring hides, and the item rides the cursor at its true size (scaled by how much nearer than the pack it hangs) with a warm rim. Letting go:
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

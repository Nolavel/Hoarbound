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
- **Hidden on the body** (two coat pockets, two thigh pockets): the cards sit on a see-through grey panel of Henry's coat and trousers near the frame's left edge, where each pocket is, at `BODY_CARD_ALPHA` and with their gradient fading the other way. The panel (`assets/ui/inventory/body_front.png`, the trousers dropped 6 cm below the coat's hem so the two read apart) and the pockets' places on it (`body_front.json`, from his bones) are baked by `tools/runtime/bake_body_silhouette.gd` from the real `Outfit_Jacket` and `Outfit_Pants` seen square from the front; re-bake when the outfit changes.
- Items stand still on their cards, turned a little (`ITEM_TURN`) so their shape reads.
- **Hidden on the pack** (the lid pocket): a card at the right, with its 3D item turning on it.
- **Hand card** (beside the body panel, at the hands' height): the hand icon (`hand_open.svg`, faint) and the Quick Access pick's item, what Henry takes in hand when the pack goes back on. A pocket's item let go on it becomes the pick; taking from it takes from that pocket.
- The fit rule is the equipment's own (`can_stow`): a taken pocket is full (`INVENTORY_POCKET_FULL`), and a size-class refusal is `INVENTORY_POCKET_TOO_SMALL`.

## Hands

Code: `scripts/items/backpack/pack_handling.gd` (`PackHandling`), `pack_cursor.gd` (`PackCursor`), `shaders/items/item_outline.gdshader`. Keys: `docs/technical/CONTROLS.md`.

- **Hover.** The ring hovers a strapped item (picked on its place's box), a pocket or the hand card, and flows into the item's silhouette on screen, with the "G — drop" hint beside it. The silhouette: its triangles rasterised into a 56-cell grid, the boundary traced (Moore neighbourhood), cached while nothing moves; the ring is resampled along its length (`PackCursor`).
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

---
paths:
  - "scripts/actors/player/henry/components/held_*.gd"
  - "scripts/actors/player/henry/components/hands_transaction.gd"
  - "scripts/actors/player/henry/components/quick_access_component.gd"
  - "scripts/actors/player/henry/components/player_hub_component.gd"
  - "scripts/actors/player/henry/components/interact_component.gd"
  - "scripts/actors/player/henry/components/inventory_component.gd"
  - "scripts/actors/player/henry/components/equipment_component.gd"
  - "scripts/actors/player/henry/components/carry_component.gd"
  - "scripts/actors/player/henry/held/**"
  - "scripts/items/backpack/pack_quick_shelf.gd"
---
# Hands, Quick Access, Hub, pockets and pack

## Design constraints

- One logical owner per item (GDD §8). The Hub only presents; Hands own what is held.
- Every carried item has a physical place: pack, pocket, a hang point or a hand. There is no abstract pocket (#324).

## Owners and contracts (VERIFIED 2026-11-17, code)

- Freeing hands goes through `HeldReleaseCapability`. Drawing and using from Quick Access goes through `HeldDrawCapability` (`hands`, `draw`, `source_zone`, `use`).
- `HandsTransaction.check()` asks every holder before anything changes. Storage takes the new item first; then holders let go (ARCHITECTURE §16).
- `HandsTransaction.can_hold` uses only `HeldItemComponent.supports_item`. The flare and the hammer have other presenters, so a hold-F on them returns NO_PRESENTER. In `InteractComponent` this now stores the item and draws it through its pocket's Quick Access key.
- A tap pickup reaches its pocket only after the stow flight lands. `hub.route_now(item_id)` settles it at once.
- `PlayerHubComponent`:
  - On open it releases every holder.
  - On close it draws back what was in the hand, unless the hand card picked another item (#336).
- The Hub hand card (`PackQuickShelf._refresh_hand`) shows the Quick Access selection, not the held item. Keep the two in step.

## Debt (VERIFIED 2026-11-17, owner's review)

- `PlayerHubComponent._held_now()` reaches into sibling components by node path (ARCHITECTURE §6).
- `InteractComponent._hold_to_hand` is a side-channel flag.
- Both should become `HeldDrawCapability.source_zone` / an explicit command when this seam is next touched.

## Seam check before calling a hands bug fixed

Walk the item through each state and confirm Hands, storage and the picture agree:

1. Taken by tap.
2. Taken by hold.
3. Drawn by its key.
4. Hub opened and closed.
5. Swapped with another held item.
6. Lit or used, if it can be.
7. Dropped.
8. Through sleep.
9. Through save and load.

Name the test that proves each state you touched. Suites: `test_pickup_gesture`, `test_hands_transaction`, `test_quick_access`, `test_player_hub`, `test_flare_lifecycle`.

## Open (ASSUMPTION / owner rule)

- Henry is right-handed (#42 record 02, item 9). The shared item socket is still `hand_l`; moving it means retargeting animation and IK, not a quick fix.

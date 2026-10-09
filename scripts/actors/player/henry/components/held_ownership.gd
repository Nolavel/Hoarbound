class_name HeldOwnership
extends RefCounted

## One rule for every hand presenter: storage owns the item and its weight; the hand
## only shows it. A zone path names its pocket; an empty zone means the pack.


## The first pocket holding item_id, as a zone path, or "".
static func pocket_holding(equipment: EquipmentComponent, item_id: StringName) -> StringName:
	if equipment == null:
		return &""
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] == item_id:
			return equipment.pocket_path(pocket["body_slot"], pocket["pocket"])
	return &""


## What the pocket at zone holds, or "" for a pack zone or a bad path.
static func zone_item(equipment: EquipmentComponent, zone: StringName) -> StringName:
	var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
	return equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1])) \
		if equipment != null and parts.size() == 2 else &""


## True while storage still owns item_id at zone ("" = the pack).
static func owns(inventory: InventoryComponent, equipment: EquipmentComponent, item_id: StringName, zone: StringName) -> bool:
	if zone == &"":
		return inventory != null and inventory.has_item(item_id)
	return zone_item(equipment, zone) == item_id


## Takes one item_id out of storage at zone; returns false and changes nothing if absent.
static func take(inventory: InventoryComponent, equipment: EquipmentComponent, item_id: StringName, zone: StringName) -> bool:
	if not owns(inventory, equipment, item_id, zone):
		return false
	if zone == &"":
		return inventory.try_remove(item_id)
	var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
	return equipment.take_from_pocket(StringName(parts[0]), StringName(parts[1])) == item_id


## Puts item_id back where take() found it; the spot was just emptied, so it fits.
static func restore(inventory: InventoryComponent, equipment: EquipmentComponent, item_id: StringName, zone: StringName) -> bool:
	if zone != &"" and equipment != null:
		var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
		if parts.size() == 2 and equipment.stow(StringName(parts[0]), StringName(parts[1]), item_id) == EquipmentComponent.Refusal.NONE:
			return true
	return inventory != null and inventory.try_add(ItemCatalog.get_item(item_id))

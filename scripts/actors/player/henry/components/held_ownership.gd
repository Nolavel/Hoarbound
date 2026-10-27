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


## Takes one item_id out of storage at zone with its runtime state; {} and no change if absent.
static func take(inventory: InventoryComponent, equipment: EquipmentComponent, item_id: StringName, zone: StringName) -> Dictionary:
	if not owns(inventory, equipment, item_id, zone):
		return {}
	if zone == &"":
		var taken: Dictionary = inventory.take_instance(item_id)
		return {} if taken.is_empty() else {"id": item_id, "instance_state": taken["instance_state"]}
	var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
	return equipment.take_pocket_instance(StringName(parts[0]), StringName(parts[1]))


## Puts a take() payload back where it was found, state included; the spot was just emptied.
static func restore(inventory: InventoryComponent, equipment: EquipmentComponent, payload: Dictionary, zone: StringName) -> bool:
	var item_id: StringName = payload.get("id", &"")
	var state: Dictionary = payload.get("instance_state", {})
	if zone != &"" and equipment != null:
		var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
		if parts.size() == 2 and equipment.stow_instance(StringName(parts[0]), StringName(parts[1]), item_id, state) == EquipmentComponent.Refusal.NONE:
			return true
	return inventory != null and inventory.try_add_instance(ItemCatalog.get_item(item_id), state)

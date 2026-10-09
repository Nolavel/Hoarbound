# =============================================================================
# inventory_component.gd — loose carry, gated by weight.
#
# Everything worn or pocketed belongs to EquipmentComponent. This is what is
# carried beyond that, and the only rule it enforces is the one that matters
# for this game: total weight. Kenny is dead weight for a whole act, and that
# has to cost something.
#
# Weight gates acceptance and feeds movement/fatigue through the shared load
# fraction. Inventory still owns only mass; consumers decide its gameplay cost.
#
# Ported from ADT.
# =============================================================================
class_name InventoryComponent
extends Node

## Emitted when an item lands, with the new total count of that item.
signal item_added(item: ItemResource, count_total: int)
## Emitted when an item leaves, with what remains.
signal item_removed(item: ItemResource, count_total: int)
## Emitted when an item was refused, with a reason the HUD can show.
signal add_rejected(item: ItemResource, reason: StringName)
## Emitted whenever the carried total changes.
signal weight_changed(total_kg: float, maximum_kg: float)

@export_group("Capacity")
## Kilograms Henry can carry beyond what he is wearing.
@export var max_carry_weight: float = 30.0
## Its carried non-garments (Kenny) count toward the same limit.
@export var equipment: EquipmentComponent
## Items Henry starts a new game carrying loose in the pack. Save loading clears
## and replaces these entries, so they are only a new-session seed.
@export var starter_item_ids: Array[StringName] = []

var _entries: Array[Dictionary] = []


func _ready() -> void:
	for item_id: StringName in starter_item_ids:
		var item: ItemResource = ItemCatalog.get_item(item_id)
		if item != null:
			try_add(item)


## Checks a whole pickup before anything is moved. Empty means accepted.
func get_add_refusal(item: ItemResource, count: int = 1) -> StringName:
	if item == null or count <= 0:
		return &"invalid"
	if item.carried_in_hands:
		for entry: Dictionary in _entries:
			var held: ItemResource = entry["item"]
			if held.carried_in_hands and held.id != item.id and int(entry["count"]) > 0:
				return &"hands_occupied"
		if get_count(item.id) + count > item.hand_carry_limit:
			return &"hands_full"
	if get_total_weight() + item.weight * float(count) > max_carry_weight:
		return &"overweight"
	return &""


## Adds one item, stacking where the item allows it. Hands-only loads obey their
## visible carry limit and never coexist with a different two-hand load.
func try_add(item: ItemResource) -> bool:
	return try_add_instance(item)


## Adds one physical non-stackable item with optional runtime state. Stackable
## items ignore instance state by design because one stack is not one instance.
func try_add_instance(item: ItemResource, instance_state: Dictionary = {}) -> bool:
	if item == null:
		return false
	var refusal: StringName = get_add_refusal(item)
	if refusal != &"":
		add_rejected.emit(item, refusal)
		return false

	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		if stored.id == item.id and entry["count"] < item.max_stack:
			entry["count"] = int(entry["count"]) + 1
			item_added.emit(item, entry["count"])
			weight_changed.emit(get_total_weight(), max_carry_weight)
			return true

	var entry: Dictionary = {"item": item, "count": 1}
	if item.max_stack == 1 and not instance_state.is_empty():
		entry["instance_state"] = instance_state.duplicate(true)
	_entries.append(entry)
	item_added.emit(item, 1)
	weight_changed.emit(get_total_weight(), max_carry_weight)
	return true


## Removes one of an item. Returns false when none is carried.
func try_remove(item_id: StringName) -> bool:
	for index: int in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var stored: ItemResource = entry["item"]
		if stored.id != item_id:
			continue
		entry["count"] = int(entry["count"]) - 1
		var remaining: int = entry["count"]
		if remaining <= 0:
			_entries.remove_at(index)
		item_removed.emit(stored, maxi(0, remaining))
		weight_changed.emit(get_total_weight(), max_carry_weight)
		return true
	return false


## Removes one physical item and returns its optional runtime state.
## Used by equipment transfers so garment wetness/condition travel with it.
func take_instance(item_id: StringName) -> Dictionary:
	for index: int in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var stored: ItemResource = entry["item"]
		if stored.id != item_id:
			continue
		var state: Dictionary = (entry.get("instance_state", {}) as Dictionary).duplicate(true)
		entry["count"] = int(entry["count"]) - 1
		var remaining: int = int(entry["count"])
		if remaining <= 0:
			_entries.remove_at(index)
		item_removed.emit(stored, maxi(0, remaining))
		weight_changed.emit(get_total_weight(), max_carry_weight)
		return {"item": stored, "instance_state": state}
	return {}


func get_count(item_id: StringName) -> int:
	var count: int = 0
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		if stored.id == item_id:
			count += int(entry["count"])
	return count


func has_item(item_id: StringName) -> bool:
	return get_count(item_id) > 0


func get_total_weight() -> float:
	var total: float = 0.0
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		total += stored.weight * float(entry["count"])
	if equipment != null:
		total += equipment.get_carried_weight()
	return total + _held_physical_weight()


## Re-announces the load after a held item changed hands without a storage change.
func notify_weight_changed() -> void:
	weight_changed.emit(get_total_weight(), max_carry_weight)


## Items Henry holds outside storage (a burning flare) still weigh on him.
func _held_physical_weight() -> float:
	var total: float = 0.0
	var body: Node = get_parent()
	if body == null:
		return total
	for child: Node in body.get_children():
		if child.has_method(&"get_held_physical_weight"):
			total += float(child.call(&"get_held_physical_weight"))
	return total


## The first inventory under a node, the player usually. Level objects and
## systems cannot be wired to the player in the editor, so they search.
static func find_in(node: Node) -> InventoryComponent:
	if node == null:
		return null
	var found := node as InventoryComponent
	if found != null:
		return found
	for child: Node in node.get_children():
		var nested: InventoryComponent = find_in(child)
		if nested != null:
			return nested
	return null


## How full the pack is, 0 empty to 1 at the carry limit. The one number the
## ice, fatigue and, later, movement read to make weight cost something.
func get_load_fraction() -> float:
	if max_carry_weight <= 0.0:
		return 0.0
	return clampf(get_total_weight() / max_carry_weight, 0.0, 1.0)


## Carried items as {id, count} pairs; non-stackable entries may also expose
## instance_state for equipment transfer/debug presentation.
func get_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		var data: Dictionary = {"id": stored.id, "count": entry["count"]}
		if entry.has("instance_state"):
			data["instance_state"] = (entry["instance_state"] as Dictionary).duplicate(true)
		out.append(data)
	return out


func get_save_key() -> StringName:
	return &"inventory"


func get_save_data() -> Dictionary:
	var stacks: Array = []
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		var stack: Dictionary = {"id": String(stored.id), "count": int(entry["count"])}
		if entry.has("instance_state"):
			stack["instance_state"] = (entry["instance_state"] as Dictionary).duplicate(true)
		stacks.append(stack)
	return {"stacks": stacks}


## Re-resolves every id against the catalog rather than trusting the file, so
## an item deleted since the save is dropped instead of resurrected as null.
func load_save_data(data: Dictionary) -> void:
	_entries.clear()
	var carried_id: StringName = &""
	for stack: Variant in data.get("stacks", []):
		if typeof(stack) != TYPE_DICTIONARY:
			continue
		var item: ItemResource = ItemCatalog.get_item(StringName(stack.get("id", "")))
		if item == null:
			continue
		var count: int = maxi(1, int(stack.get("count", 1)))
		if item.carried_in_hands:
			if carried_id != &"" and carried_id != item.id:
				continue
			carried_id = item.id
			count = mini(count, item.hand_carry_limit)
		var entry: Dictionary = {"item": item, "count": count}
		var saved_state: Variant = stack.get("instance_state", {})
		if item.max_stack == 1 and typeof(saved_state) == TYPE_DICTIONARY and not (saved_state as Dictionary).is_empty():
			entry["instance_state"] = (saved_state as Dictionary).duplicate(true)
		_entries.append(entry)
	weight_changed.emit(get_total_weight(), max_carry_weight)

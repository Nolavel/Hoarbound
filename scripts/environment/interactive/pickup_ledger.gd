class_name PickupLedger
extends Node

## Remembers which authored world pickups were taken, by their stable world_id,
## so a reload does not put them back. Stores ids only; the items live in the inventory.

const GROUP: StringName = &"pickup_ledger"

var _taken: Dictionary = {}  # world_id -> true


func _ready() -> void:
	add_to_group(&"saveable")
	add_to_group(GROUP)


## The ledger of the current world, or null (scenes without authored pickups).
static func find(tree: SceneTree) -> PickupLedger:
	return tree.get_first_node_in_group(GROUP) as PickupLedger if tree != null else null


func record(world_id: StringName) -> void:
	if world_id != &"":
		_taken[world_id] = true


func is_taken(world_id: StringName) -> bool:
	return _taken.has(world_id)


func get_save_key() -> StringName:
	return &"pickup_ledger"


func get_save_data() -> Dictionary:
	var ids: Array = []
	for world_id: StringName in _taken:
		ids.append(String(world_id))
	ids.sort()
	return {"taken": ids}


## Restores the set and removes every authored pickup it names from the world.
func load_save_data(data: Dictionary) -> void:
	_taken.clear()
	for world_id: Variant in data.get("taken", []):
		_taken[StringName(str(world_id))] = true
	for node: Node in get_tree().get_nodes_in_group(ItemPickup.WORLD_GROUP):
		var pickup := node as ItemPickup
		if pickup != null and is_taken(pickup.world_id):
			pickup.queue_free()
	## Furniture adopted some authored pickups; an older save may have taken them before it did.
	for node: Node in get_tree().get_nodes_in_group(ItemContainer.GROUP):
		(node as ItemContainer).drop_taken(self)

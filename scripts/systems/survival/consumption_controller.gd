class_name ConsumptionController
extends Node

## Closes the eating half of the survival loop: an item with a consumable
## facet is spent and its calories, water and heat cost land on the body.

## Emitted after an item was consumed, so the HUD and audio can react.
signal consumed(item_id: StringName, item: ItemResource)
signal opened(item_id: StringName, replacement_id: StringName)
## Emitted when a discarded leftover (an empty can) has been tossed on the ground.
signal leftover_discarded(leftover_id: StringName, litter: RigidBody3D)
## Emitted when an attempt was turned down, carrying why.
signal consume_refused(item_id: StringName, reason: Refusal)
signal water_status_requested(text: String)

## Why a consume attempt was turned down.
enum Refusal { NONE, UNKNOWN_ITEM, NOT_CONSUMABLE, NOT_CARRIED, NO_BIO_MONITOR, NO_TOOL, EMPTY_FLASK }

## Where the item is taken from, once found.
enum Source { NONE, INVENTORY, POCKET }

## A tossed leftover leaves from about Henry's hands, this far in front of him, metres.
const LITTER_REACH := Vector3(0.0, 0.9, -0.35)
## Its body: an empty SPoV-sized can.
const LITTER_SIZE := Vector3(0.104, 0.071, 0.061)
const LITTER_MASS: float = 0.06

@export_group("Wiring")
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var bio_monitor: BioMonitorManager
@export var thermal_manager: ThermalManager


## Whether the item could be consumed right now, without consuming it.
func can_consume(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.water_capacity_ml > 0 and item.water_remaining_ml == 0:
		return Refusal.EMPTY_FLASK
	if item.consumable == null:
		return Refusal.NOT_CONSUMABLE
	if bio_monitor == null:
		return Refusal.NO_BIO_MONITOR
	if _locate(item_id)["source"] == Source.NONE:
		return Refusal.NOT_CARRIED
	if not _has_tool(item.consumable.required_tool_id):
		return Refusal.NO_TOOL
	return Refusal.NONE


## Item Use contract (PlayerHubComponent): Use on food or drink eats it.
func can_use(item_id: StringName) -> bool:
	return can_consume(item_id) == Refusal.NONE


## The Player plays the eating animation on `consumed`.
func use(item_id: StringName) -> bool:
	return consume(item_id) == Refusal.NONE


## Consumes one of the item, wherever it is carried. Returns the refusal,
## or NONE when it was eaten.
func consume(item_id: StringName) -> Refusal:
	return _consume_from(item_id, _locate(item_id))


## A held pocket item must use its own source, even if the pack has the same id.
func consume_from_zone(zone_path: StringName) -> Refusal:
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or parts.size() != 2:
		return Refusal.NOT_CARRIED
	var slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	var id: StringName = equipment.get_pocket_item(slot, pocket)
	return _consume_from(id, {"source": Source.POCKET, "body_slot": slot, "pocket": pocket})


func _consume_from(item_id: StringName, found: Dictionary) -> Refusal:
	var refusal: Refusal = can_consume(item_id)
	if refusal != Refusal.NONE:
		consume_refused.emit(item_id, refusal)
		return refusal

	var item: ItemResource = ItemCatalog.get_item(item_id)
	if not _take(item_id, found):
		consume_refused.emit(item_id, Refusal.NOT_CARRIED)
		return Refusal.NOT_CARRIED

	if item.opens_into != &"":
		_leave_behind(item.opens_into, found)
		opened.emit(item_id, item.opens_into)
		return Refusal.NONE
	_apply(item.consumable)
	if item.consumable.discard_leftover:
		_discard(item.consumable.leaves_behind_id)
	else:
		_leave_behind(item.consumable.leaves_behind_id, found if item.water_capacity_ml > 0 else {})
	if item.water_capacity_ml > 0:
		_show_water_status(ItemCatalog.get_item(item.consumable.leaves_behind_id))
	consumed.emit(item_id, item)
	return Refusal.NONE


## Eats something that is not carried, straight off a stove top. Same effects
## and leftover as consume(); the caller owns taking it away.
func consume_from_world(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.consumable == null:
		return Refusal.NOT_CONSUMABLE
	if bio_monitor == null:
		return Refusal.NO_BIO_MONITOR
	if not _has_tool(item.consumable.required_tool_id):
		return Refusal.NO_TOOL
	_apply(item.consumable)
	if item.consumable.discard_leftover:
		_discard(item.consumable.leaves_behind_id)
	else:
		_leave_behind(item.consumable.leaves_behind_id)
	consumed.emit(item_id, item)
	return Refusal.NONE


## Localisation key for opening a tin: with its tool when it needs one, else by its ring.
static func open_action_key(item: ItemResource) -> String:
	if item.consumable != null and item.consumable.required_tool_id != &"":
		return "PINEAPPLE_OPEN_ACTION"
	return "CAN_RING_OPEN_ACTION"


## Names a refusal as a localisation key, never as a hardcoded sentence.
static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.UNKNOWN_ITEM:
			return "CONSUME_REFUSED_UNKNOWN_ITEM"
		Refusal.NOT_CONSUMABLE:
			return "CONSUME_REFUSED_NOT_CONSUMABLE"
		Refusal.NOT_CARRIED:
			return "CONSUME_REFUSED_NOT_CARRIED"
		Refusal.NO_BIO_MONITOR:
			return "CONSUME_REFUSED_NO_BIO_MONITOR"
		Refusal.NO_TOOL:
			return "CONSUME_REFUSED_NO_KNIFE"
		Refusal.EMPTY_FLASK:
			return "CONSUME_REFUSED_EMPTY_FLASK"
		_:
			return ""


## Pushes what the item restores onto the three tracks and the body's heat.
func _apply(consumable: ConsumableData) -> void:
	if consumable.calories != 0.0:
		bio_monitor.add_calories(consumable.calories)
	if consumable.hydration != 0.0:
		bio_monitor.add_hydration(consumable.hydration)
	if consumable.energy != 0.0:
		bio_monitor.add_energy(consumable.energy)
	if consumable.body_heat_cost_c != 0.0 and thermal_manager != null:
		thermal_manager.apply_body_temperature_delta(-consumable.body_heat_cost_c)


## Where one of the item is carried. The inventory is searched before pockets.
func _locate(item_id: StringName) -> Dictionary:
	if inventory != null and inventory.has_item(item_id):
		return {"source": Source.INVENTORY}
	if equipment != null:
		for pocket: Dictionary in equipment.get_available_pockets():
			if pocket["item_id"] == item_id:
				return {
					"source": Source.POCKET,
					"body_slot": pocket["body_slot"],
					"pocket": pocket["pocket"],
				}
	return {"source": Source.NONE}


## Removes one of the item from wherever it was found.
func _take(item_id: StringName, found: Dictionary) -> bool:
	match found["source"]:
		Source.INVENTORY:
			return inventory.try_remove(item_id)
		Source.POCKET:
			if equipment.get_pocket_item(found["body_slot"], found["pocket"]) != item_id:
				return false
			return equipment.take_pocket_instance(found["body_slot"], found["pocket"]).get("id", &"") == item_id
		_:
			return false


## Puts the empty tin somewhere, preferring the inventory. A remainder that
## fits nowhere is dropped rather than duplicated.
func _leave_behind(leftover_id: StringName, previous: Dictionary = {}) -> void:
	if leftover_id == &"":
		return
	var leftover: ItemResource = ItemCatalog.get_item(leftover_id)
	if leftover == null:
		return
	if previous.get("source", Source.NONE) == Source.POCKET and equipment != null:
		if equipment.stow(previous["body_slot"], previous["pocket"], leftover_id) == EquipmentComponent.Refusal.NONE:
			return
	if inventory != null and inventory.try_add(leftover):
		return
	if equipment != null:
		equipment.stow_anywhere(leftover_id)


## Tosses the emptied can on the ground in front of Henry: a small falling body, not an item.
func _discard(leftover_id: StringName) -> void:
	var player := get_parent() as Node3D
	if leftover_id == &"" or player == null or not player.is_inside_tree():
		return
	var litter := RigidBody3D.new()
	litter.name = "Discarded_%s" % leftover_id
	litter.mass = LITTER_MASS
	litter.continuous_cd = true
	litter.angular_damp = 1.0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = LITTER_SIZE
	collision.shape = shape
	collision.position.y = LITTER_SIZE.y * 0.5
	litter.add_child(collision)
	litter.add_child(SurvivalItemVisual.make(leftover_id))
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(litter)
	litter.global_transform = Transform3D(player.global_basis.orthonormalized(), player.global_transform * LITTER_REACH)
	if player is PhysicsBody3D:
		litter.add_collision_exception_with(player)
	## A light toss forward and down, with a turn, so it lands like a thrown can.
	litter.linear_velocity = player.global_basis.z * -0.8 + Vector3.DOWN * 0.3
	litter.angular_velocity = Vector3(1.5, 3.0, 0.5)
	leftover_discarded.emit(leftover_id, litter)


func _has_tool(tool_id: StringName) -> bool:
	return tool_id == &"" or _locate(tool_id)["source"] != Source.NONE


func _show_water_status(flask: ItemResource) -> void:
	if flask != null and is_inside_tree():
		water_status_requested.emit(flask.get_status_text())

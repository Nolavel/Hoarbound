class_name ConsumptionController
extends Node

## Closes the eating half of the survival loop: an item with a consumable
## facet is spent and its calories, water and heat cost land on the body.

## Emitted after an item was consumed, so the HUD and audio can react.
signal consumed(item_id: StringName, item: ItemResource)
signal opened(item_id: StringName, replacement_id: StringName)
## Emitted when an attempt was turned down, carrying why.
signal consume_refused(item_id: StringName, reason: Refusal)

## Why a consume attempt was turned down.
enum Refusal { NONE, UNKNOWN_ITEM, NOT_CONSUMABLE, NOT_CARRIED, NO_BIO_MONITOR, NO_TOOL, EMPTY_FLASK }

## Where the item is taken from, once found.
enum Source { NONE, INVENTORY, POCKET }

@export_group("Wiring")
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var bio_monitor: BioMonitorManager
@export var thermal_manager: ThermalManager

var _feedback: Label
var _feedback_left: float = 0.0


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
	_leave_behind(item.consumable.leaves_behind_id)
	consumed.emit(item_id, item)
	return Refusal.NONE


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


func _has_tool(tool_id: StringName) -> bool:
	return tool_id == &"" or _locate(tool_id)["source"] != Source.NONE


func _show_water_status(flask: ItemResource) -> void:
	if flask == null or not is_inside_tree():
		return
	if not is_instance_valid(_feedback):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_feedback = Label.new()
		_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback.add_theme_font_size_override("font_size", 22)
		_feedback.add_theme_constant_override("outline_size", 5)
		layer.add_child(_feedback)
	_feedback.text = flask.get_status_text()
	_feedback.visible = true
	_feedback_left = 4.0


func _process(delta: float) -> void:
	if not is_instance_valid(_feedback):
		return
	_feedback_left -= delta
	_feedback.visible = _feedback_left > 0.0
	_feedback.position = Vector2((get_viewport().get_visible_rect().size.x - _feedback.size.x) * 0.5,
		get_viewport().get_visible_rect().size.y * 0.78)

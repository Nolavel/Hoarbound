class_name SnowScoopComponent
extends Node

## Snow into a mug or a bare hand. F on open snow with nothing else in focus: Henry stoops,
## a held mug fills, a free hand takes a handful. Item Use still scoops into a packed mug.

signal scooped(item_id: StringName)
signal scoop_refused(reason_key: String)

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const EMPTY_MUG: StringName = &"mug"
const FILLED_MUG: StringName = &"mug_snow"
const HANDFUL: StringName = &"snow_handful"
## Settled snow this deep under Henry's feet can be scooped, metres.
const MIN_DEPTH_M: float = 0.03
const STOOP_ACTION: StringName = &"pickup_right_low"
## The hand reaches the snow this long into the stoop.
const CONTACT_SECONDS: float = 0.55

@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var held: HeldItemComponent

var _thermal: ThermalManager
var _busy: bool = false


func _ready() -> void:
	var body: Node = get_parent()
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if held == null:
		held = body.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	var interact := body.get_node_or_null(^"InteractComponent") as InteractComponent
	if interact != null:
		interact.interact_unclaimed.connect(try_scoop)


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager


func can_use(item_id: StringName) -> bool:
	return (
		item_id == EMPTY_MUG
		and inventory != null
		and inventory.has_item(EMPTY_MUG)
		and not _sheltered()
	)


func use(item_id: StringName) -> bool:
	if not can_use(item_id):
		return false
	return _fill_mug(&"")


## What F on this spot would scoop into ("" when it would do nothing), with the refusal key.
func scoop_target() -> Dictionary:
	if _sheltered():
		return {"item": &"", "refusal": "SNOW_SCOOP_INDOORS"}
	if snow_depth_underfoot() < MIN_DEPTH_M:
		return {"item": &"", "refusal": "SNOW_SCOOP_NO_SNOW"}
	var in_hand: StringName = held.get_item_id() if held != null else &""
	if in_hand == EMPTY_MUG:
		return {"item": FILLED_MUG, "refusal": ""}
	if in_hand == &"":
		return {"item": HANDFUL, "refusal": ""}
	return {"item": &"", "refusal": "SNOW_SCOOP_HAND_FULL"}


## F with nothing in focus: stoop and scoop if the snow and the hand allow it.
func try_scoop() -> bool:
	if _busy:
		return false
	var target: Dictionary = scoop_target()
	if target["item"] == &"":
		scoop_refused.emit(target["refusal"])
		return false
	var body: Node = get_parent()
	if body.has_method(&"is_action_locking") and body.call(&"is_action_locking"):
		return false
	_busy = true
	if body.has_method(&"play_action_animation"):
		body.call(&"play_action_animation", STOOP_ACTION)
	if is_inside_tree():
		await get_tree().create_timer(CONTACT_SECONDS).timeout
	_busy = false
	return finish_scoop(target["item"])


## The hand meets the snow: the mug fills or the handful appears in the hand.
func finish_scoop(item_id: StringName) -> bool:
	var done: bool = false
	if item_id == FILLED_MUG:
		done = _fill_mug(held.get_source_zone() if held != null and held.get_item_id() == EMPTY_MUG else &"")
	elif item_id == HANDFUL:
		done = _take_handful()
	if done:
		scooped.emit(item_id)
	return done


## Settled snow depth under Henry, metres; 0 off the live snow window.
func snow_depth_underfoot() -> float:
	var shell: SnowShell = SnowShell.active
	var body := get_parent() as Node3D
	if not is_instance_valid(shell) or body == null:
		return 0.0
	return maxf(shell.field.get_depth(body.global_position.x, body.global_position.z), 0.0)


func _sheltered() -> bool:
	return _thermal != null and _thermal.is_sheltered()


## Swaps the empty mug at zone ("" = the pack) for a mug of snow; a held mug stays in hand.
func _fill_mug(zone: StringName) -> bool:
	var was_held: bool = held != null and held.get_item_id() == EMPTY_MUG
	var payload: Dictionary = HeldOwnership.take(inventory, equipment, EMPTY_MUG, zone)
	if payload.is_empty():
		return false
	if was_held:
		held.put_away()
	if not HeldOwnership.restore(inventory, equipment, {"id": FILLED_MUG, "instance_state": {}}, zone):
		## Preserve the container if the extra snow weight crosses the carry limit.
		HeldOwnership.restore(inventory, equipment, payload, zone)
		if was_held:
			held.present_owned(EMPTY_MUG)
		return false
	if was_held:
		held.present_owned(FILLED_MUG)
	return true


func _take_handful() -> bool:
	var handful: ItemResource = ItemCatalog.get_item(HANDFUL)
	if handful == null or inventory == null or not inventory.try_add(handful):
		return false
	if held != null and not held.present_owned(HANDFUL):
		inventory.try_remove(HANDFUL)
		return false
	return true

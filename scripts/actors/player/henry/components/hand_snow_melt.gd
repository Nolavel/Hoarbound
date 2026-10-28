class_name HandSnowMelt
extends Node

## A handful of snow held in the warm melts away (#257): it shrinks in the hand over 40 s in a
## barely warm room down to 20 s at room warmth, wetting the glove. Below freezing it keeps.

signal melted

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const HANDFUL: StringName = &"snow_handful"
const GLOVE_SLOT: StringName = &"hands_outer"
## Melt time at the cool and the warm end of a room, seconds, and the air those ends are, C.
const SLOW_MELT_S: float = 40.0
const FAST_MELT_S: float = 20.0
const COOL_C: float = 5.0
const WARM_C: float = 20.0
## No melting at or below this air temperature, C.
const FREEZING_C: float = 0.5
## Wetness a whole handful leaves in the glove, 0..1.
const GLOVE_SOAK: float = 0.3
## The clump keeps this share of its size as it goes.
const LAST_SIZE: float = 0.35

@export var held: HeldItemComponent
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent

var _thermal: ThermalManager
var _melt: float = 0.0


func _ready() -> void:
	var body: Node = get_parent()
	if held == null:
		held = body.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager


## How far the handful in hand has melted, 0..1 (0 with none in hand).
func get_melt() -> float:
	return _melt


## Seconds a handful lasts in air_c; INF at or below freezing.
static func melt_seconds(air_c: float) -> float:
	if air_c <= FREEZING_C:
		return INF
	return lerpf(SLOW_MELT_S, FAST_MELT_S, clampf((air_c - COOL_C) / (WARM_C - COOL_C), 0.0, 1.0))


func _process(delta: float) -> void:
	if held == null or held.get_item_id() != HANDFUL:
		_melt = 0.0
		return
	advance(delta, _air_c())


## Melts the held handful by delta seconds in air_c: it shrinks, the glove wets, and at the end it is gone.
func advance(delta: float, air_c: float) -> void:
	var lasts: float = melt_seconds(air_c)
	if is_inf(lasts):
		return
	var step: float = minf(delta / lasts, 1.0 - _melt)
	_melt += step
	_soak_glove(step * GLOVE_SOAK)
	var prop: Node3D = held.get_held_prop() if held != null else null
	if prop != null:
		prop.scale = Vector3.ONE * lerpf(1.0, LAST_SIZE, _melt)
	if _melt >= 1.0:
		var zone: StringName = held.get_source_zone() if held != null else &""
		if held != null:
			held.put_away()
		HeldOwnership.take(inventory, equipment, HANDFUL, zone)
		_melt = 0.0
		melted.emit()


func _air_c() -> float:
	if _thermal == null:
		return -10.0
	return _thermal.get_room_temperature_c() if _thermal.is_sheltered() else _thermal.get_outdoor_air_c()


func _soak_glove(amount: float) -> void:
	if equipment == null or amount <= 0.0:
		return
	var state: Dictionary = equipment.get_garment_state(GLOVE_SLOT)
	if not state.is_empty():
		equipment.set_garment_wetness(GLOVE_SLOT, minf(float(state.get("wetness", 0.0)) + amount, 1.0))

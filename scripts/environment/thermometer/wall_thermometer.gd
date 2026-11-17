class_name WallThermometer
extends Node3D

## An ordinary glass thermometer on a board, hung by a wire loop from a nail: a red column
## and, close up, the reading in 3D type on a grey plate. Presentation only; it reads its zone.

## Scale ends, °C; the column climbs from ScaleBottom at SCALE_MIN_C to ScaleTop at SCALE_MAX_C.
const SCALE_MIN_C: float = -40.0
const SCALE_MAX_C: float = 40.0
## The authored look; tune it in the editor, not here.
const SCENE_PATH: String = "res://scenes/environment/thermometer/wall_thermometer.tscn"

## The room it hangs in; its air is outdoor air plus this zone's offset.
@export var zone: ThermalZone
## Henry closer than this sees the reading in full, m.
@export var reading_near_m: float = 2.5
## Beyond this the reading is gone, m.
@export var reading_far_m: float = 3.0
## How fast the column and the figure follow the air, share of the gap per second.
@export var follow_rate: float = 1.5

var _thermal: ThermalManager
var _player: Node3D
var _shown_c: float = NAN
var _search_left: float = 0.0

@onready var _column: MeshInstance3D = $Column
@onready var _scale_bottom: Marker3D = $ScaleBottom
@onready var _scale_top: Marker3D = $ScaleTop
@onready var _reading: Label3D = $Reading
@onready var _plate: MeshInstance3D = $ReadingPlate
@onready var _plate_material: StandardMaterial3D = (_plate.mesh as PrimitiveMesh).material as StandardMaterial3D


## A thermometer built from the authored scene.
static func instantiate() -> WallThermometer:
	return (load(SCENE_PATH) as PackedScene).instantiate() as WallThermometer


func _process(delta: float) -> void:
	if not _bind():
		_search_left -= delta
		return
	var air: float = get_air_c()
	_shown_c = air if is_nan(_shown_c) else lerpf(_shown_c, air, 1.0 - exp(-follow_rate * delta))
	var travel: Vector3 = _scale_top.position - _scale_bottom.position
	var rise: float = maxf(column_fraction(_shown_c) * travel.length(), 0.001)
	_column.scale.y = rise
	_column.position = _scale_bottom.position + travel.normalized() * rise * 0.5
	_reading.text = tr(&"THERMOMETER_READING") % TemperatureText.signed(_shown_c)
	var near: float = 1.0
	if is_instance_valid(_player):
		near = 1.0 - smoothstep(reading_near_m, reading_far_m, _player.global_position.distance_to(global_position))
	_reading.modulate.a = near
	_reading.outline_modulate.a = near * 0.8
	_plate.visible = near > 0.001
	_plate_material.albedo_color.a = near
	_reading.visible = _plate.visible


## Room air where the thermometer hangs, °C: outdoor air plus its zone's warmth.
func get_air_c() -> float:
	if _thermal == null:
		return 0.0
	return _thermal.get_outdoor_air_c() + (zone.get_total_offset_c() if is_instance_valid(zone) else 0.0)


## Share of the tube the column fills for a temperature, clamped to the scale.
static func column_fraction(celsius: float) -> float:
	return inverse_lerp(SCALE_MIN_C, SCALE_MAX_C, clampf(celsius, SCALE_MIN_C, SCALE_MAX_C))


func get_reading_alpha() -> float:
	return _reading.modulate.a


## Finds the thermal model and Henry; streamed shelters are not handed the world context.
func _bind() -> bool:
	if _thermal != null:
		return true
	if _search_left > 0.0 or not is_inside_tree():
		return false
	_search_left = 1.0
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	var found: Array[Node] = get_tree().root.find_children("*", "ThermalManager", true, false)
	_thermal = found[0] as ThermalManager if not found.is_empty() else null
	return _thermal != null

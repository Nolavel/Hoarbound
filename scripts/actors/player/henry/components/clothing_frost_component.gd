class_name ClothingFrostComponent
extends Node

## Rime building on what Henry wears and carries outdoors in frost (faster in snowfall and wind), and thawing
## gradually by a fire or in a warm room. Drawn per instance on his gear and saved; nothing reads it back.

## Laid over gear whose plain material has no rime of its own (the mug, the tin, webbing, buckles).
const OVERLAY: ShaderMaterial = preload("res://assets/materials/frost/garment_frost_overlay.tres")
## Bare skin and helper meshes under Henry that never frost.
const SKIP_PREFIXES: Array[String] = ["Henry_Head", "Skin_", "Mannequin", "BootSnow", "ThrowLanding"]

## Outdoor air at or above this grows no rime.
@export var forms_below_c: float = -2.0
## Seconds of −25 °C still air for bare cloth to crust over.
@export var build_s: float = 300.0
## Extra growth at full snowfall, and per metre per second of wind.
@export var snowfall_boost: float = 1.5
@export var wind_boost_per_mps: float = 0.08
## Thaw pace beside a fire, and in room air at +5 °C (warmer air thaws faster, up to 3x). The last thin
## traces in the folds go slower, so 0.85 clears in about 1.6 min by a fire and 4.5 min at +5 °C.
@export var melt_by_fire_s: float = 70.0
@export var melt_in_warm_air_s: float = 200.0
## Rime Henry starts with: he comes in from a night out.
@export_range(0.0, 1.0, 0.05) var initial_frost: float = 0.85

var _thermal: ThermalManager
var _weather: WeatherController
var _frost: float = 0.0
var _shown: float = -1.0
var _gear: Array[GeometryInstance3D] = []
var _gear_refresh: float = 0.0


## Given by Player once the world's systems exist.
func set_systems(thermal: ThermalManager, weather: WeatherController) -> void:
	_thermal = thermal
	_weather = weather


func get_frost() -> float:
	return _frost


## Sets the rime without touching the gear (it shows on the next frame).
func set_frost_value(amount: float) -> void:
	_frost = clampf(amount, 0.0, 1.0)


## Sets the rime and shows it at once (previews and tests); the simulation carries on from here.
func set_frost(amount: float) -> void:
	_frost = clampf(amount, 0.0, 1.0)
	_collect_gear()
	_shown = _frost
	apply_to_gear(_frost)


func _ready() -> void:
	_frost = initial_frost
	add_to_group(&"saveable")
	SaveParticipantCapability.publish(self, self, &"get_save_key", &"get_save_data", &"load_save_data")


func get_save_key() -> StringName:
	return &"clothing_frost"


func get_save_data() -> Dictionary:
	return {"frost": _frost}


func load_save_data(data: Dictionary) -> void:
	_frost = clampf(float(data.get("frost", initial_frost)), 0.0, 1.0)
	_shown = -1.0


func _process(delta: float) -> void:
	if _thermal != null:
		var sheltered: bool = _thermal.is_sheltered()
		var air: float = _thermal.get_room_temperature_c() if sheltered else _thermal.get_outdoor_air_c()
		var snow: float = _weather.get_snowfall_density() if _weather != null else 0.0
		var wind: float = _weather.get_wind_speed_mps() if _weather != null else 0.0
		step(delta, air, sheltered, _near_fire(), snow, wind)
	_present(delta)


## One step from the air around Henry; split out so tests drive it directly.
func step(delta: float, air_c: float, sheltered: bool, near_fire: bool, snowfall: float, wind_mps: float) -> void:
	var thaw: float = 0.0
	if near_fire:
		thaw = 1.0 / maxf(melt_by_fire_s, 0.1)
	elif air_c > 0.0:
		thaw = clampf(air_c / 5.0, 0.25, 3.0) / maxf(melt_in_warm_air_s, 0.1)
	if thaw > 0.0:
		_frost = maxf(0.0, _frost - delta * thaw * (0.4 + 0.6 * _frost))
	elif not sheltered and air_c < forms_below_c:
		var cold: float = clampf((forms_below_c - air_c) / 23.0, 0.1, 1.3)
		var weather: float = 1.0 + snowfall_boost * clampf(snowfall, 0.0, 1.0) + wind_boost_per_mps * maxf(wind_mps, 0.0)
		_frost = minf(1.0, _frost + delta / maxf(build_s, 0.1) * cold * weather * (1.0 - _frost * 0.6))


## Pushes the rime to the gear when it changed, and to newly drawn gear once a second.
func _present(delta: float) -> void:
	_gear_refresh -= delta
	var cleared: bool = _frost == 0.0 and _shown != 0.0
	if cleared or absf(_frost - _shown) > 0.004 or (_gear_refresh <= 0.0 and _frost > 0.0):
		if _gear_refresh <= 0.0:
			_collect_gear()
		_shown = _frost
		apply_to_gear(_frost)


## What Henry wears and carries now: gear is drawn, stowed and swapped, so this is refreshed every second.
func _collect_gear() -> void:
	_gear_refresh = 1.0
	_gear.clear()
	var body: Node = get_parent()
	if body == null:
		return
	for node: Node in body.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var skip: bool = false
		for prefix: String in SKIP_PREFIXES:
			skip = skip or String(geo.name).begins_with(prefix)
		if not skip:
			_gear.append(geo)


## Sets the rime on every piece of gear; plain-material meshes get it as an overlay while the slot is free.
func apply_to_gear(amount: float) -> void:
	if _gear.is_empty():
		_collect_gear()
	_apply_to_face(amount)
	for geo: GeometryInstance3D in _gear:
		if not is_instance_valid(geo):
			continue
		geo.set_instance_shader_parameter(&"garment_frost", amount)
		if not _takes_overlay(geo):
			continue
		if amount > 0.0 and geo.material_overlay == null:
			geo.material_overlay = OVERLAY
		elif amount <= 0.0 and geo.material_overlay == OVERLAY:
			geo.material_overlay = null


## The face: breath rime on the brows with the rest of the rime, and cheeks flushed by the cold on the head
## (or the rime still on him, which fades as he warms).
func _apply_to_face(amount: float) -> void:
	var body: Node = get_parent()
	var head := body.find_child("Henry_Head", true, false) as GeometryInstance3D if body != null else null
	if head == null:
		return
	var head_cold: float = _thermal.get_extremity_cold(&"head") if _thermal != null else 0.0
	head.set_instance_shader_parameter(&"face_frost", amount)
	head.set_instance_shader_parameter(&"face_flush", clampf(maxf(head_cold, amount), 0.0, 1.0))


## A mesh whose every surface is an opaque, lit StandardMaterial3D (shader materials carry rime themselves).
static func _takes_overlay(geo: GeometryInstance3D) -> bool:
	var mesh_inst := geo as MeshInstance3D
	if mesh_inst == null or mesh_inst.mesh == null:
		return false
	for surface: int in mesh_inst.mesh.get_surface_count():
		var material := mesh_inst.get_active_material(surface) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return false
	return true


func _near_fire() -> bool:
	var body := get_parent() as Node3D
	if body == null:
		return false
	for source: HeatSource in HeatSource.get_all():
		if source.get_offset_at(body.global_position) > 0.0:
			return true
	return false

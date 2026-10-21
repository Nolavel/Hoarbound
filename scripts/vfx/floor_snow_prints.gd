class_name FloorSnowPrints
extends Node3D

## White prints Henry's boots leave on floors indoors: the snow packed into the tread outside
## shakes out step by step as the inverse of the snow print, and melts with the room's warmth.

const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const POOL_SIZE: int = 48
## Ground snow cover outside that fills the tread.
const MIN_COVER: float = 0.05
## Share of the tread's snow one indoor step leaves on the floor.
const SHED_PER_STEP: float = 0.2
## Tread snow too thin to leave a print.
const MIN_LOAD: float = 0.08
## Room air where prints melt slowest (0 °C) and fastest, °C.
const WARM_ROOM_C: float = 20.0
## Height the print projects through, metres: floor boards and sills step a few centimetres.
const PROJECT_DEPTH_M: float = 0.2
## Default outsole width when no snow shell gives one, metres (SnowShell.sole_width_m).
const SOLE_WIDTH_M: float = 0.11

## Seconds a print lasts on a 0 °C floor and in a 20 °C room; it holds, then fades out over its last half.
@export var melt_s: Vector2 = Vector2(1500.0, 300.0)
## Seconds the snow in the tread lasts in a 20 °C room before it has melted out.
@export var tread_melt_s: float = 120.0
@export var print_color: Color = Color(0.93, 0.95, 1.0, 0.9)

var _sensor: FootContactSensor
var _thermal: ThermalManager
var _weather: WeatherController
var _load: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _decals: Array[Decal] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _strengths: PackedFloat32Array = PackedFloat32Array()
var _textures: Array[Texture2D] = []
var _next: int = 0
var _width_m: float = SOLE_WIDTH_M


func _ready() -> void:
	top_level = true
	set_process(false)


func on_world_ready(context: WorldContext) -> void:
	_sensor = context.find_in_scene(SENSOR_SCRIPT) as FootContactSensor
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	if is_instance_valid(SnowShell.active):
		_width_m = SnowShell.active.sole_width_m
	build()
	if _sensor != null:
		_sensor.foot_planted.connect(_on_foot_planted)


## Bakes the two tread prints (their clumps differ) and the decal pool.
func build() -> void:
	if not _decals.is_empty():
		return
	for seed: int in range(2):
		_textures.append(ImageTexture.create_from_image(BootSole.floor_print_image(_width_m, 800.0, seed)))
	for i: int in range(POOL_SIZE):
		var decal := Decal.new()
		decal.size = Vector3(_width_m, PROJECT_DEPTH_M, BootSole.LENGTH_M)
		decal.texture_albedo = _textures[i % 2]
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 25.0
		decal.distance_fade_length = 5.0
		decal.visible = false
		add_child(decal)
		_decals.append(decal)
	_ages.resize(POOL_SIZE)
	_strengths.resize(POOL_SIZE)


## One footfall: outdoors on snow it fills the tread; indoors it prints what the tread still holds.
func place_step(side: int, position: Vector3, normal: Vector3, forward: Vector3, sheltered: bool, cover: float) -> Decal:
	if not sheltered:
		if cover >= MIN_COVER:
			_load[side] = 1.0
			set_process(true)
		return null
	if _load[side] < MIN_LOAD or _decals.is_empty():
		return null
	var toe: Vector3 = (forward - normal * forward.dot(normal)).normalized()
	if toe.length_squared() < 0.5:
		return null
	var decal: Decal = _decals[_next]
	_strengths[_next] = _load[side]
	_ages[_next] = 0.0
	_next = (_next + 1) % POOL_SIZE
	decal.global_transform = Transform3D(Basis(normal.cross(toe), normal, toe).orthonormalized(), position)
	decal.modulate = Color(print_color, print_color.a * _load[side])
	decal.visible = true
	_load[side] *= 1.0 - SHED_PER_STEP
	set_process(true)
	return decal


## Ages the prints and the tread's snow in a room at `room_c`.
func melt(delta: float, room_c: float, sheltered: bool) -> void:
	var warm: float = clampf(room_c / WARM_ROOM_C, 0.0, 1.0)
	if sheltered and warm > 0.0:
		for side: int in range(2):
			_load[side] = maxf(_load[side] - delta * warm / tread_melt_s, 0.0)
	var life: float = lerpf(melt_s.x, melt_s.y, warm)
	var showing: bool = false
	for i: int in range(_decals.size()):
		var decal: Decal = _decals[i]
		if not decal.visible:
			continue
		_ages[i] += delta
		var left: float = 1.0 - smoothstep(0.5, 1.0, _ages[i] / life)
		decal.modulate.a = print_color.a * _strengths[i] * left
		decal.visible = left > 0.001
		showing = showing or decal.visible
	if not showing and _load[0] <= 0.0 and _load[1] <= 0.0:
		set_process(false)


## Tread snow left on a boot, 0 to 1.
func get_load(side: int) -> float:
	return _load[side]


func _process(delta: float) -> void:
	var sheltered: bool = _thermal != null and _thermal.is_sheltered()
	melt(delta, _thermal.get_room_temperature_c() if _thermal != null else 0.0, sheltered)


func _on_foot_planted(side: int, position: Vector3, normal: Vector3, forward: Vector3, _speed_mps: float) -> void:
	var sheltered: bool = _thermal != null and _thermal.is_sheltered()
	place_step(side, position, normal, forward, sheltered, _weather.get_snow_cover() if _weather != null else 0.0)

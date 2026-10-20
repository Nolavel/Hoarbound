class_name WorldAudioBinder
extends Node

## Feeds the world into SoundSystem parameters: wind speed from the weather,
## "interior" from shelter, and Henry's planted feet into footstep events.
##
## Footsteps read the snow under the boot, like a surface switch plus a depth
## control: bare ground; a skin of snow over hard ground; wind crust; dry or wet
## snow whose crunch deepens and darkens as the boot sinks; a muffled plough in
## deep powder; and a squeak when dry snow is below -10 °C (too cold for pressure
## melting, so crystals crush instead of flowing).

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const PARAM_WIND: StringName = &"wind_speed"
const PARAM_INTERIOR: StringName = &"interior"
const PARAM_FOOT_SPEED: StringName = &"foot_speed"
const PARAM_SNOW_DEPTH: StringName = &"foot_snow_depth"
## Where the default banks live; an empty export falls back to these files.
const DEFAULT_DIR: String = "res://data/audio/footsteps/"

## Played on bare ground or snow too thin to hear.
@export var footstep_event: SoundEvent
## Beds started with the world, e.g. the wind layer.
@export var ambience_layers: Array[SoundLayer] = []

@export_group("Snow footsteps")
## A skin of snow over hard ground: the ground still answers under the boot.
@export var snow_thin_event: SoundEvent
## Wind crust and icy snow that holds a boot and snaps.
@export var snow_crust_event: SoundEvent
## Crunch of a boot in dry snow; pitched and shaded by how deep it sinks.
@export var snow_step_event: SoundEvent
## The same in wet snow near melting.
@export var snow_wet_event: SoundEvent
## Muffled plough of deep powder, and the boot pulling back out of it.
@export var snow_deep_event: SoundEvent
## Dry cold-snow squeak layered over the crunch.
@export var snow_squeak_event: SoundEvent
## A boot pulled back out of a deep print.
@export var snow_pull_event: SoundEvent
## Snow thinner than this is heard as ground, metres.
@export var thin_snow_m: float = 0.02
## A boot sinking less than this still meets the ground under the snow, metres.
@export var thin_sink_m: float = 0.05
## Softer than this the snow is crust (0.4 hardest .. 1.0 loose powder).
@export var crust_softness: float = 0.6
## A boot sinking this far is in deep snow, metres.
@export var deep_sink_m: float = 0.15
## Sink at which the crunch is at its lowest and loudest, metres.
@export var full_sink_m: float = 0.3
## Squeak starts at the first air temperature and is fullest at the second, °C.
@export var squeak_air_c: Vector2 = Vector2(-8.0, -20.0)
## Above this air temperature snow is wet and steps go soft and dull, °C.
@export var wet_air_c: float = -1.0
## A boot pulled out of a print deeper than this is heard, metres.
@export var pull_out_m: float = 0.08

var _sound: Node
var _thermal: ThermalManager
var _layer_handles: Array[int] = []
var _shell: SnowShell


func on_world_ready(context: WorldContext) -> void:
	_sound = get_node_or_null(^"/root/SoundSystem")
	if _sound == null:
		push_warning("WorldAudioBinder: SoundSystem autoload missing, world stays silent.")
		return
	_load_default_banks()
	var weather: WeatherController = context.get_system(WEATHER_SCRIPT) as WeatherController
	if weather != null:
		weather.conditions_updated.connect(_on_conditions_updated)
		_sound.call(&"set_parameter", PARAM_WIND, weather.get_wind_speed_mps())
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if _thermal != null:
		_thermal.sheltered_changed.connect(_on_sheltered_changed)
		_on_sheltered_changed(_thermal.is_sheltered())
	_bind_feet(context.player)
	for layer: SoundLayer in ambience_layers:
		_layer_handles.append(int(_sound.call(&"start_layer", layer)))


func _exit_tree() -> void:
	if _sound == null:
		return
	for handle: int in _layer_handles:
		_sound.call(&"stop", handle)


func _bind_feet(player: Node3D) -> void:
	if player == null:
		return
	var sensor: FootContactSensor = player.get_node_or_null(^"FootContactSensor") as FootContactSensor
	if sensor != null:
		sensor.foot_planted.connect(_on_foot_planted)


func _load_default_banks() -> void:
	footstep_event = _bank_or(footstep_event, "ground_step.tres")
	snow_thin_event = _bank_or(snow_thin_event, "snow_thin.tres")
	snow_crust_event = _bank_or(snow_crust_event, "snow_crust.tres")
	snow_step_event = _bank_or(snow_step_event, "snow_step.tres")
	snow_wet_event = _bank_or(snow_wet_event, "snow_wet.tres")
	snow_deep_event = _bank_or(snow_deep_event, "snow_deep.tres")
	snow_squeak_event = _bank_or(snow_squeak_event, "snow_squeak.tres")
	snow_pull_event = _bank_or(snow_pull_event, "snow_pull.tres")


func _bank_or(current: SoundEvent, file: String) -> SoundEvent:
	if current != null or not ResourceLoader.exists(DEFAULT_DIR + file):
		return current
	return load(DEFAULT_DIR + file) as SoundEvent


func _on_conditions_updated(_offset_c: float, wind_speed_mps: float, _snowfall: float) -> void:
	_sound.call(&"set_parameter", PARAM_WIND, wind_speed_mps)


func _on_sheltered_changed(is_sheltered: bool) -> void:
	_sound.call(&"set_parameter", PARAM_INTERIOR, 1.0 if is_sheltered else 0.0)


func _on_foot_planted(
	_side: int, position: Vector3, _normal: Vector3, _forward: Vector3, speed_mps: float
) -> void:
	_sound.call(&"set_parameter", PARAM_FOOT_SPEED, speed_mps)
	_bind_shell()
	var pace_db: float = lerpf(-3.0, 2.0, clampf(speed_mps / 4.0, 0.0, 1.0))
	var snow: Vector2 = _snow_under(position)
	_sound.call(&"set_parameter", PARAM_SNOW_DEPTH, snow.x)
	if snow.x < thin_snow_m or snow_step_event == null:
		if footstep_event != null:
			_sound.call(&"play", footstep_event, position, pace_db, 1.0)
		return
	var air: float = _air_c()
	var step: Dictionary = snow_step_shading(snow.x, snow.y, air)
	var event: SoundEvent = _snow_bank(float(step["sink"]), snow.y, air)
	_sound.call(&"play", event, position, float(step["gain_db"]) + pace_db, float(step["pitch"]))
	var squeak: float = float(step["squeak"])
	if squeak > 0.01 and snow_squeak_event != null:
		_sound.call(&"play", snow_squeak_event, position, lerpf(-14.0, -3.0, squeak) + pace_db, 1.0)


## How one boot in `depth_m` of snow of `softness` sounds at `air_c`:
## {sink, gain_db, pitch, squeak}. Pure, so it can be tested and tuned alone.
func snow_step_shading(depth_m: float, softness: float, air_c: float) -> Dictionary:
	var max_pack: float = _shell.max_pack if is_instance_valid(_shell) else 0.85
	var sink: float = depth_m * max_pack * softness
	var deep: float = clampf(sink / maxf(full_sink_m, 0.01), 0.0, 1.0)
	## Deeper is louder and lower: more snow crushed, the boot muffled inside it.
	var gain_db: float = lerpf(-6.0, 2.0, deep)
	var pitch: float = lerpf(1.08, 0.82, deep)
	## Wind crust snaps crisper than powder.
	pitch *= lerpf(1.06, 1.0, smoothstep(0.45, 0.95, softness))
	## Dry cold snow squeaks, and more on packed crust than in loose powder.
	var cold: float = clampf(inverse_lerp(squeak_air_c.x, squeak_air_c.y, air_c), 0.0, 1.0)
	var squeak: float = cold * lerpf(1.0, 0.4, smoothstep(0.45, 0.95, softness)) * (1.0 - deep * 0.6)
	## Wet snow near melting is soft and dull.
	if air_c > wet_air_c:
		gain_db -= 2.0
		pitch *= 0.94
	return {"sink": sink, "gain_db": gain_db, "pitch": pitch, "squeak": squeak}


## The bank a boot sinking `sink` into snow of `softness` sounds from at `air_c`;
## a missing bank falls back to the dry crunch.
func _snow_bank(sink: float, softness: float, air_c: float) -> SoundEvent:
	var event: SoundEvent = null
	if sink < thin_sink_m:
		event = snow_thin_event
	elif sink >= deep_sink_m:
		event = snow_deep_event
	elif softness < crust_softness:
		event = snow_crust_event
	elif air_c > wet_air_c:
		event = snow_wet_event
	return event if event != null else snow_step_event


## A boot pulled out of a deep print: a low, soft suck of snow letting go.
func _on_foot_lifted(_side: int, position: Vector3, sink_m: float, _softness: float) -> void:
	if sink_m < pull_out_m:
		return
	var deep: float = clampf(sink_m / maxf(full_sink_m, 0.01), 0.0, 1.0)
	if snow_pull_event != null:
		_sound.call(&"play", snow_pull_event, position, lerpf(-8.0, 0.0, deep), lerpf(1.1, 0.9, deep))
		return
	var event: SoundEvent = snow_deep_event if snow_deep_event != null else snow_step_event
	if event != null:
		_sound.call(&"play", event, position, lerpf(-14.0, -6.0, deep), lerpf(0.8, 0.68, deep))


## Settled depth and softness under a point, or (0, 0) with no snow shell.
func _snow_under(at: Vector3) -> Vector2:
	if not is_instance_valid(_shell) or _shell.field.origin.x == INF:
		return Vector2.ZERO
	var depth: float = _shell.field.get_depth(at.x, at.z)
	return Vector2(depth, _shell.field.get_softness(at.x, at.z))


## The shell registers itself once the world is up; bind its lift signal then.
func _bind_shell() -> void:
	if is_instance_valid(_shell) or not is_instance_valid(SnowShell.active):
		return
	_shell = SnowShell.active
	if not _shell.foot_lifted.is_connected(_on_foot_lifted):
		_shell.foot_lifted.connect(_on_foot_lifted)
	if not _shell.crust_broke.is_connected(_on_crust_broke):
		_shell.crust_broke.connect(_on_crust_broke)


## A boot breaking through crust or into a drift pocket: the slab snaps, then the snow gives.
func _on_crust_broke(_side: int, position: Vector3, plunge_m: float) -> void:
	var deep: float = clampf(plunge_m / maxf(full_sink_m, 0.01), 0.0, 1.0)
	if snow_crust_event != null:
		_sound.call(&"play", snow_crust_event, position, lerpf(-4.0, 1.0, deep), lerpf(1.05, 0.95, deep))
	if snow_deep_event != null:
		_sound.call(&"play", snow_deep_event, position, lerpf(-10.0, -2.0, deep), lerpf(0.9, 0.78, deep))


func _air_c() -> float:
	return _thermal.get_outdoor_air_c() if is_instance_valid(_thermal) else -10.0

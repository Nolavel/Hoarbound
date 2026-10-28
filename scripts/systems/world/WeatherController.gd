class_name WeatherController
extends Node

## Global weather state machine. Weather is one value for the whole island, so
## it lives here as scalars, not as a volume that follows the player.

## Emitted when a new profile starts blending in.
signal weather_changed(profile: WeatherProfile)
## Emitted every tick with the blended values the rest of the game reads.
signal conditions_updated(ambient_offset_c: float, wind_speed_mps: float, snowfall_density: float)

## Directory the default profiles are loaded from when none are assigned.
const DEFAULT_PROFILE_DIR: String = "res://resources/weather"

@export_group("Profiles")
## Weather profiles the scheduler may pick from, as .tres resources.
@export var profiles: Array[WeatherProfile] = []
## Profile forced at startup; empty picks one by weight.
@export var starting_profile_id: StringName = &""

@export_group("Wiring")
## Drives the in-game clock used for durations and gusts.
@export var day_night_manager: DayNightManager
## Freezes the scheduler so a scene can pin one profile for testing.
@export var scheduler_enabled: bool = true

@export_group("Wind")
## Seed for the gust noise, so a session is reproducible.
@export var gust_seed: int = 7321

## Offsets the wander sample away from the gust sample, so direction and speed
## are not driven by the same noise value.
const WANDER_OFFSET: float = 137.0

## Looked up through the world context, never by node path.
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")

var _current: WeatherProfile
var _previous: WeatherProfile
var _blend: float = 1.0
var _blend_speed: float = 1.0
var _remaining_h: float = 0.0
var _elapsed_s: float = 0.0
var _gust_noise: FastNoiseLite
var _hours: GameHourTracker = GameHourTracker.new()

var _ambient_offset_c: float = 0.0
var _wind_speed_mps: float = 0.0
var _wind_direction: Vector3 = Vector3.FORWARD
var _snowfall_density: float = 0.0
var _visibility_m: float = 0.0
var _wetness_rate: float = 0.0
var _snow_cover: float = 0.0
var _wind_direction_override_deg: float = -1.0


## Profile an authored beat asked to follow the current one; empty lets the scheduler pick.
var _then_id: StringName = &""


func _ready() -> void:
	add_to_group(&"weather_controller")
	initialize()


func apply_world_profile(profile: WorldProfile) -> void:
	if profile == null:
		return
	if profile.initial_weather_profile_id != &"":
		starting_profile_id = profile.initial_weather_profile_id
	_wind_direction_override_deg = profile.wind_direction_override_deg


## Builds the gust noise, wires the clock and activates the first profile.
## Idempotent per concern: _ready runs it before world.gd has handed over the
## clock and the profiles, and on_world_ready runs it again once they exist.
func initialize() -> void:
	if _gust_noise == null:
		_gust_noise = FastNoiseLite.new()
		_gust_noise.seed = gust_seed
		_gust_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		## Sampled at elapsed / gust_period_s, so one unit is one period; the default 0.01 made gusts 100x slower.
		_gust_noise.frequency = 1.0
	if _current != null or profiles.is_empty():
		return
	var initial: WeatherProfile = _find_profile(starting_profile_id)
	if initial == null:
		initial = _pick_weighted()
	_activate(initial, true)


func _process(delta: float) -> void:
	if _current == null:
		return
	_elapsed_s += delta
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta * _blend_speed)
	_sample_conditions()
	conditions_updated.emit(_ambient_offset_c, _wind_speed_mps, _snowfall_density)


## Resolves the day/night clock from the scene when the world comes up, so the
## scheduler runs without anyone wiring an export by hand.
func on_world_ready(context: WorldContext) -> void:
	if day_night_manager == null:
		day_night_manager = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	if profiles.is_empty():
		profiles = load_profiles_from(DEFAULT_PROFILE_DIR)
	initialize()
	if day_night_manager == null:
		push_warning("WeatherController: the world has no DayNightManager, weather will not advance")
	if profiles.is_empty():
		push_warning("WeatherController: no profiles found, weather stays neutral")


## Loads every WeatherProfile in a directory, sorted for a stable order.
static func load_profiles_from(directory: String) -> Array[WeatherProfile]:
	var found: Array[WeatherProfile] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	var names: Array[String] = []
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			names.append(clean)
	names.sort()
	for clean: String in names:
		var profile := load("%s/%s" % [directory, clean]) as WeatherProfile
		if profile != null:
			found.append(profile)
	return found


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"weather"


## State the save system persists for this system.
func get_save_data() -> Dictionary:
	return {
		"profile_id": String(_current.id) if _current != null else "",
		"remaining_h": _remaining_h,
		"then_id": String(_then_id),
	}


## Restores the active profile, snapping rather than blending into it.
func load_save_data(data: Dictionary) -> void:
	var id := StringName(String(data.get("profile_id", "")))
	var profile: WeatherProfile = _find_profile(id)
	if profile != null:
		_activate(profile, true)
	_remaining_h = float(data.get("remaining_h", _remaining_h))
	_then_id = StringName(String(data.get("then_id", "")))
	_hours.reset()


## Forces a profile by id, blending in over its own blend time. An authored beat
## may pin how long it lasts (game hours) and which profile follows it.
func set_weather(id: StringName, instant: bool = false, duration_h: float = -1.0, then_id: StringName = &"") -> void:
	var profile: WeatherProfile = _find_profile(id)
	if profile == null:
		push_warning("WeatherController: unknown profile '%s'" % id)
		return
	_activate(profile, instant)
	if duration_h > 0.0:
		_remaining_h = duration_h
	_then_id = then_id


func get_current_profile() -> WeatherProfile:
	return _current


## Share of the current profile blended in, 0 to 1.
func get_blend() -> float:
	return _blend


## Game hours left before the scheduler picks the next profile.
func get_remaining_hours() -> float:
	return _remaining_h


## Blended ambient offset in degrees Celsius, before wind chill.
func get_ambient_offset_c() -> float:
	return _ambient_offset_c


## Blended wind speed including the current gust, in metres per second.
## Drops the clock baseline so a loaded or skipped time is not billed as
## elapsed weather.
func reset_clock() -> void:
	_hours.reset()


## Unit vector the wind blows towards, in the XZ plane. A shelter breach facing
## into this is the one that costs warmth.
func get_wind_direction() -> Vector3:
	return _wind_direction


## A compass bearing in degrees as a direction in the XZ plane.
static func _bearing_to_vector(degrees: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees))


## Settled snow on up-facing surfaces, 0 to 1, blended with the weather.
func get_snow_cover() -> float:
	return _snow_cover


func get_wind_speed_mps() -> float:
	return _wind_speed_mps


## Blended snowfall density, 0.0 clear to 1.0 whiteout.
func get_snowfall_density() -> float:
	return _snowfall_density


## Blended visibility clamp in metres; 0.0 means the weather does not clamp it.
func get_visibility_m() -> float:
	return _visibility_m


## Blended clothing soak rate in wetness units per in-game hour.
func get_wetness_rate_per_hour() -> float:
	return _wetness_rate


## Mixes the outgoing and incoming profiles and applies the gust on top.
func _sample_conditions() -> void:
	var from: WeatherProfile = _previous if _previous != null else _current
	_ambient_offset_c = lerpf(from.ambient_offset_c, _current.ambient_offset_c, _blend)
	_snowfall_density = lerpf(from.snowfall_density, _current.snowfall_density, _blend)
	_visibility_m = lerpf(from.visibility_m, _current.visibility_m, _blend)
	_wetness_rate = lerpf(from.wetness_rate_per_hour, _current.wetness_rate_per_hour, _blend)
	_snow_cover = lerpf(from.snow_cover, _current.snow_cover, _blend)

	var base_wind: float = lerpf(from.wind_speed_mps, _current.wind_speed_mps, _blend)
	var gust_range: float = lerpf(from.gust_speed_mps, _current.gust_speed_mps, _blend)
	var period: float = maxf(0.1, lerpf(from.gust_period_s, _current.gust_period_s, _blend))
	var gust: float = (_gust_noise.get_noise_1d(_elapsed_s / period) + 1.0) * 0.5
	_wind_speed_mps = base_wind + gust_range * gust

	## Bearings are blended as vectors, so crossing 0/360 turns the short way
	## round instead of sweeping back through every intermediate direction.
	var from_bearing: float = _wind_direction_override_deg if _wind_direction_override_deg >= 0.0 else from.wind_direction_deg
	var to_bearing: float = _wind_direction_override_deg if _wind_direction_override_deg >= 0.0 else _current.wind_direction_deg
	var from_dir: Vector3 = _bearing_to_vector(from_bearing)
	var to_dir: Vector3 = _bearing_to_vector(to_bearing)
	var jitter_deg: float = lerpf(
		from.wind_direction_jitter_deg, _current.wind_direction_jitter_deg, _blend
	)
	var wander: float = _gust_noise.get_noise_1d(_elapsed_s / period + WANDER_OFFSET)
	_wind_direction = from_dir.slerp(to_dir, _blend).rotated(
		Vector3.UP, deg_to_rad(jitter_deg * wander)
	)


func get_simulation_priority() -> int:
	return 100


func advance_simulation(hours: float, context: SimulationStepContext) -> void:
	_advance_weather(hours, context.reason != SimulationClock.REALTIME_REASON)


## Compatibility seam for isolated legacy tests/tools; production uses SimulationClock.
func _on_time_update(current_hour: float) -> void:
	_advance_weather(_hours.consume(current_hour), false)


func _advance_weather(hours: float, instant_transition: bool) -> void:
	if _current == null or not scheduler_enabled or hours <= 0.0:
		return
	var remaining_step: float = hours
	while remaining_step > 0.000001:
		if _remaining_h > remaining_step:
			_remaining_h -= remaining_step
			return
		remaining_step -= maxf(_remaining_h, 0.0)
		var next: WeatherProfile = _find_profile(_then_id)
		_then_id = &""
		if next == null:
			next = _pick_weighted()
			if next == _current and profiles.size() > 1:
				next = _pick_weighted()
		_activate(next, instant_transition)
		if _remaining_h <= 0.000001:
			return


## Swaps in a profile, either instantly or blended over its blend time.
func _activate(profile: WeatherProfile, instant: bool) -> void:
	if profile == null:
		return
	_previous = _current
	_current = profile
	_blend = 1.0 if instant or _previous == null else 0.0
	_blend_speed = 1.0 / maxf(0.01, profile.blend_time_s)
	_remaining_h = randf_range(profile.min_duration_h, profile.max_duration_h)
	_sample_conditions()
	weather_changed.emit(profile)
	if day_night_manager != null:
		day_night_manager.apply_weather_visual_profile(profile)


func _find_profile(id: StringName) -> WeatherProfile:
	if id == &"":
		return null
	for profile: WeatherProfile in profiles:
		if profile != null and profile.id == id:
			return profile
	return null


func _pick_weighted() -> WeatherProfile:
	var pool: Array[WeatherProfile] = profiles.filter(func(p: WeatherProfile) -> bool: return p != null and not p.manual_only)
	if pool.is_empty():
		return profiles[0]
	var total: float = 0.0
	for profile: WeatherProfile in pool:
		total += maxf(0.0, profile.weight)
	if total <= 0.0:
		return pool[0]
	var roll: float = randf() * total
	for profile: WeatherProfile in pool:
		roll -= maxf(0.0, profile.weight)
		if roll <= 0.0:
			return profile
	return pool[pool.size() - 1]

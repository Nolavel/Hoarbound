extends Node
class_name DayNightManager

signal day_started(day_number: int)
signal night_started(night_number: int)
signal time_changed(formatted_time: String, is_day: bool, day_number: int, period_description: String)
signal critical_night_approaching
signal time_update(current_hour: float)

enum TimeOfDay {
	MIDNIGHT,
	DAWN,
	MORNING,
	NOON,
	AFTERNOON,
	EVENING,
	DUSK,
	NIGHT,
}

const DEFAULT_SKY_SHADER: Shader = preload("res://shaders/environment/freemans_parallax_clouds.gdshader")
const SIMULATION_CLOCK_SCRIPT: GDScript = preload("res://scripts/systems/time/simulation_clock.gd")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
## Slant path of the sun's beam through falling snow, metres: with Koschmieder's
## extinction 3.912 / visibility it leaves ~7 % of the sun in a 45 m blizzard, ~59 % in 220 m snowfall.
const SNOW_BEAM_PATH_M: float = 30.0
## Ambient energy per unit of lost beam energy: snow scatters what it takes. 1.86 (a blizzard at 51 % of
## clear-day snow) washed out the Cold Ash grade's blue shadows; 1.2 keeps them, sky-tinted.
const SNOW_FILL_PER_SUN: float = 0.3
## How fast the sun follows the weather, per second.
const SNOW_SUN_RESPONSE: float = 0.5

const PERIOD_RU: Array[String] = [
	"Полночь",
	"Рассвет",
	"Утро",
	"Полдень",
	"День",
	"Вечер",
	"Сумерки",
	"Ночь",
]

const PERIOD_EN: Array[String] = [
	"Midnight",
	"Dawn",
	"Morning",
	"Noon",
	"Afternoon",
	"Evening",
	"Dusk",
	"Night",
]

const SUNRISE_HOUR: float = 6.0
const SUNSET_HOUR: float = 18.0
const LIGHT_START_HOUR: float = 2.0
const MORNING_PEAK_HOUR: float = 10.0
const DUSK_END_HOUR: float = 22.0
## The production sky keeps the historical `cloud_coverage` uniform name, but
## that value is a mask threshold: lower reveals more cloud. Weather may lower
## it by at most this amount so storms thicken the deck without flattening the
## whole sky into a solid sheet.
const WEATHER_CLOUD_THRESHOLD_DROP_MAX: float = 0.10
const WEATHER_CLOUD_MASK_TOP_DROP_MAX: float = 0.22

@export var perfomance_visible_display: bool = true
@export var sky_shader: Shader = DEFAULT_SKY_SHADER
@export var settings: DayNightSettings
## Clock time a new game starts at (a save overrides it). First Exit A starts at
## noon so a 10–15 minute run reaches late afternoon and dusk (author, #42).
@export_range(0.0, 24.0, 0.25) var start_hour: float = 12.0
@export var directional_light: DirectionalLight3D
@export var world_environment_node: WorldEnvironment
@export var time_accelerator: TimeAccelerator
@export var color_grade_controller: ColorGradeController
@export_range(0.0, 1.0, 0.01) var shelter_ambient_energy_cap: float = 0.20

@export_group("Debug-Visual Component")
@export var time_label: Label
@export var day_label: Label
@export var day_and_night_duration_label: Label
@export var current_day_label: Label

var simulation_clock: SimulationClock
var _legacy_total_game_time_hours: float = 12.0
var total_game_time_hours: float:
	get:
		if simulation_clock != null and simulation_clock.is_initialized():
			return simulation_clock.get_total_hours()
		return _legacy_total_game_time_hours
	set(value):
		_legacy_total_game_time_hours = maxf(value, 0.0)
		if simulation_clock != null:
			simulation_clock.set_total_hours(_legacy_total_game_time_hours, &"legacy_day_night")

var _clock_loaded: bool = false
var current_day: int = 1
var is_day: bool = true
var last_game_minute: int = -1

var sky_resource: Sky
var sky_material: ShaderMaterial
var _noise_texture: NoiseTexture2D
var _cloud_time_s: float = 0.0
var _sun_step: int = -1
var _sun_from: Quaternion = Quaternion.IDENTITY
var _sun_to: Quaternion = Quaternion.IDENTITY
var _sun_blend_left: float = 0.0
var _weather: WeatherController
var _sun_energy: float = 1.0
var _ambient_energy: float = 1.0
var _ambient_color: Color = Color.WHITE
var _snow_beam: float = 1.0


func _ready() -> void:
	if not _clock_loaded:
		total_game_time_hours = start_hour
	_setup_default_settings()
	_initialize_sky()
	if is_instance_valid(color_grade_controller) and not color_grade_controller.interior_state_changed.is_connected(_on_interior_state_changed):
		color_grade_controller.interior_state_changed.connect(_on_interior_state_changed)

	if has_node("DebugTime"):
		$DebugTime.visible = perfomance_visible_display

	set_process(true)
	call_deferred("_force_update_visuals")


func _process(delta: float) -> void:
	# Shader TIME ignores SceneTree pause. Drive cloud phase from this pausable node instead.
	_cloud_time_s += delta
	_ease_sun(delta)
	_dim_sun_in_snow(delta)
	if sky_material != null:
		sky_material.set_shader_parameter("cloud_time", _cloud_time_s)

	var total_cycle_duration: float = maxf(settings.day_duration + settings.night_duration, 0.001)
	var game_hours_per_second: float = 24.0 / total_cycle_duration

	if is_instance_valid(time_accelerator) and time_accelerator.is_accelerating:
		game_hours_per_second *= time_accelerator.acceleration_factor

	var advance: float = delta * game_hours_per_second
	if simulation_clock != null:
		simulation_clock.advance_hours(advance, SimulationClock.REALTIME_REASON)
		return

	total_game_time_hours += advance
	_consume_legacy_clock_sample(get_current_hour_float())


## Composition-root hook: the simulation clock becomes canonical once World exists.
func on_world_ready(context: WorldContext) -> void:
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_snow_beam = _snow_beam_target()
	if simulation_clock == null:
		simulation_clock = context.get_system(SIMULATION_CLOCK_SCRIPT) as SimulationClock
	if simulation_clock == null:
		push_warning("DayNightManager: SimulationClock missing; using legacy local time")
		return
	if not simulation_clock.clock_changed.is_connected(_on_simulation_clock_changed):
		simulation_clock.clock_changed.connect(_on_simulation_clock_changed)
	if not simulation_clock.is_initialized():
		simulation_clock.set_total_hours(
			_legacy_total_game_time_hours if _clock_loaded else start_hour,
			&"new_game"
		)
	else:
		_on_simulation_clock_changed(simulation_clock.get_total_hours(), &"attach")


func _on_simulation_clock_changed(total_hours: float, reason: StringName) -> void:
	_legacy_total_game_time_hours = total_hours
	var hour: float = fmod(total_hours, 24.0)
	var minute: int = int(hour * 60.0)
	if minute == last_game_minute and reason != &"load":
		return
	last_game_minute = minute
	var emit_edges: bool = not [
		&"load", &"new_game", &"implicit_start", &"legacy_day_night", &"attach"
	].has(reason)
	_on_game_minute_changed(hour, emit_edges)


func _consume_legacy_clock_sample(game_hour: float) -> void:
	var game_minute: int = int(game_hour * 60.0)
	if game_minute == last_game_minute:
		return
	last_game_minute = game_minute
	_on_game_minute_changed(game_hour)


func _setup_default_settings() -> void:
	if settings == null:
		settings = DayNightSettings.new()


func _initialize_sky() -> void:
	if not is_instance_valid(world_environment_node):
		push_warning("DayNightManager: WorldEnvironment is not assigned.")
		return

	if world_environment_node.environment == null:
		world_environment_node.environment = Environment.new()

	var environment: Environment = world_environment_node.environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	sky_resource = Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = sky_shader if sky_shader != null else DEFAULT_SKY_SHADER
	sky_resource.sky_material = sky_material
	environment.sky = sky_resource

	_build_cloud_noise()
	_apply_static_sky_parameters()

	if is_instance_valid(directional_light):
		directional_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


func _build_cloud_noise() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = settings.cloud_noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = settings.cloud_noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = settings.cloud_noise_octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.52

	_noise_texture = NoiseTexture2D.new()
	_noise_texture.width = settings.cloud_noise_size
	_noise_texture.height = settings.cloud_noise_size
	_noise_texture.seamless = true
	_noise_texture.normalize = true
	_noise_texture.noise = noise

	sky_material.set_shader_parameter("cloud_noise_texture", _noise_texture)


func _apply_static_sky_parameters() -> void:
	if sky_material == null:
		return

	# Freeman atmosphere is driven by a dedicated solar direction so the
	# DirectionalLight can become moonlight at night without turning the moon
	# into an atmospheric sun.
	sky_material.set_shader_parameter("use_manual_sun_direction", true)
	sky_material.set_shader_parameter("sun_intensity", 48.0)
	sky_material.set_shader_parameter("rayleigh_scale_height", 9000.0)
	sky_material.set_shader_parameter("rayleigh_multi_scattering", 0.018)
	sky_material.set_shader_parameter("mie_scale_height", 1600.0)
	sky_material.set_shader_parameter("mie_scattering", 0.000008)
	sky_material.set_shader_parameter("mie_albedo", 0.88)
	sky_material.set_shader_parameter("mie_g_forward", 0.80)
	sky_material.set_shader_parameter("mie_weight", 0.78)
	sky_material.set_shader_parameter("mie_multi_scattering", 0.24)
	sky_material.set_shader_parameter("view_samples", 12)
	sky_material.set_shader_parameter("sun_samples", 4)

	sky_material.set_shader_parameter("cloud_density", settings.cloud_density)
	sky_material.set_shader_parameter("cloud_depth", settings.cloud_depth)
	sky_material.set_shader_parameter("cloud_sag", settings.cloud_sag)
	sky_material.set_shader_parameter("cloud_noise_tiling", settings.cloud_tiling)
	sky_material.set_shader_parameter("cloud_wind_speed", settings.cloud_wind_speed)
	sky_material.set_shader_parameter("cloud_time", _cloud_time_s)
	sky_material.set_shader_parameter("cloud_parallax_strength", settings.cloud_parallax_strength)
	sky_material.set_shader_parameter("cloud_parallax_layer_separation", settings.cloud_parallax_layer_separation)
	sky_material.set_shader_parameter("cloud_parallax_detail_weight", settings.cloud_parallax_detail_weight)
	sky_material.set_shader_parameter("cloud_parallax_mid_scale", settings.cloud_parallax_mid_scale)
	sky_material.set_shader_parameter("cloud_parallax_high_scale", settings.cloud_parallax_high_scale)
	sky_material.set_shader_parameter("cloud_light_energy_scale", settings.cloud_light_energy_scale)
	sky_material.set_shader_parameter("cloud_coverage", settings.cloud_coverage)
	sky_material.set_shader_parameter("cloud_opacity", settings.cloud_opacity)


func _force_update_visuals() -> void:
	var hour: float = get_current_hour_float()
	current_day = floori(total_game_time_hours / 24.0) + 1
	is_day = _is_day(hour)
	_update_environment_visuals(hour, true)
	if is_instance_valid(color_grade_controller):
		color_grade_controller.update_for_time(hour)
	_emit_time_signals(hour)
	_update_time_display()


func _on_game_minute_changed(game_hour: float, emit_edges: bool = true) -> void:
	current_day = int(floor(total_game_time_hours / 24.0)) + 1

	var was_day: bool = is_day
	is_day = _is_day(game_hour)

	if emit_edges:
		if was_day and not is_day:
			night_started.emit(current_day)
			if current_day == settings.critical_night_day:
				critical_night_approaching.emit()
		elif not was_day and is_day:
			day_started.emit(current_day)

	_update_environment_visuals(game_hour, not emit_edges)
	if is_instance_valid(color_grade_controller):
		color_grade_controller.update_for_time(game_hour)
	_emit_time_signals(game_hour)
	_update_time_display()
	time_update.emit(game_hour)


func _update_environment_visuals(game_hour: float, snap_sun: bool = false) -> void:
	if not is_instance_valid(directional_light):
		return
	if not is_instance_valid(world_environment_node) or world_environment_node.environment == null:
		return
	if sky_material == null:
		_initialize_sky()
		if sky_material == null:
			return

	var day_progress: float = _calculate_day_progress(game_hour)
	var azimuth: float = _calculate_light_azimuth(game_hour)
	var solar_altitude: float = _calculate_solar_altitude(game_hour)
	var solar_direction: Vector3 = _direction_from_altitude_azimuth(solar_altitude, azimuth)
	var light_color: Color = _calculate_light_color(game_hour)
	var light_energy: float = _calculate_light_energy(game_hour, settings.day_light_energy)
	var atmosphere_energy: float = _calculate_light_energy(game_hour, settings.day_atmosphere_light_energy)
	var critical_factor: float = _calculate_critical_night_factor(game_hour)

	_aim_sun(game_hour, snap_sun)
	directional_light.light_color = light_color
	_sun_energy = light_energy * lerpf(1.0, 0.22, critical_factor)
	directional_light.light_energy = _sun_energy * _snow_beam
	directional_light.light_volumetric_fog_energy = atmosphere_energy / maxf(light_energy, 0.0001)

	var environment: Environment = world_environment_node.environment
	var ambient_color: Color = settings.night_ambient_color.lerp(
		settings.day_ambient_color,
		day_progress
	)
	var ambient_energy: float = lerpf(
		settings.night_sky_energy,
		settings.day_sky_energy,
		day_progress
	)

	if critical_factor > 0.0:
		ambient_color = ambient_color.lerp(
			Color.BLACK,
			critical_factor * settings.critical_night_darkness_factor
		)
		ambient_energy *= lerpf(1.0, 0.12, critical_factor)

	ambient_energy = _ambient_energy_for_context(ambient_energy)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_ambient_color = ambient_color
	_ambient_energy = ambient_energy
	_apply_snow_fill(environment)

	var cloud_color: Color = _calculate_cloud_color(game_hour)
	var ground_color: Color = settings.night_ground_color.lerp(
		settings.day_ground_color,
		day_progress
	)
	var exposure: float = lerpf(
		settings.night_overcast_exposure,
		settings.day_overcast_exposure,
		day_progress
	)

	if critical_factor > 0.0:
		cloud_color = cloud_color.lerp(Color(0.01, 0.012, 0.018), critical_factor * 0.75)
		ground_color = ground_color.lerp(Color.BLACK, critical_factor * 0.6)
		exposure *= lerpf(1.0, 0.35, critical_factor)

	sky_material.set_shader_parameter("manual_sun_direction", solar_direction)
	sky_material.set_shader_parameter("cloud_color", cloud_color)
	sky_material.set_shader_parameter("cloud_sun_color", light_color)
	sky_material.set_shader_parameter("cloud_sun_energy", maxf(atmosphere_energy, 0.05))
	sky_material.set_shader_parameter(
		"ground_color",
		Vector3(ground_color.r, ground_color.g, ground_color.b)
	)
	sky_material.set_shader_parameter("exposure", exposure)


func _calculate_day_progress(game_hour: float) -> float:
	var progress: float = 0.0

	if game_hour >= LIGHT_START_HOUR and game_hour < MORNING_PEAK_HOUR:
		progress = inverse_lerp(LIGHT_START_HOUR, MORNING_PEAK_HOUR, game_hour)
	elif game_hour >= MORNING_PEAK_HOUR and game_hour < SUNSET_HOUR:
		progress = 1.0
	elif game_hour >= SUNSET_HOUR and game_hour < DUSK_END_HOUR:
		progress = 1.0 - inverse_lerp(SUNSET_HOUR, DUSK_END_HOUR, game_hour)

	return smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))


## Points the light at the sun of the current step; a new step eases in, a load or jump snaps.
func _aim_sun(game_hour: float, snap: bool) -> void:
	var step_minutes: float = maxf(float(settings.sun_step_minutes), 1.0)
	var step: int = floori(total_game_time_hours * 60.0 / step_minutes + 1e-4)
	if step == _sun_step and not snap:
		return
	var hour: float = fmod(float(step) * step_minutes / 60.0, 24.0)
	var euler := Vector3(deg_to_rad(-_calculate_light_altitude(hour)), deg_to_rad(_calculate_light_azimuth(hour)), 0.0)
	var target: Quaternion = Basis.from_euler(euler).get_rotation_quaternion()
	var accelerating: bool = is_instance_valid(time_accelerator) and time_accelerator.is_accelerating
	var jumped: bool = absi(step - _sun_step) > 1
	_sun_step = step
	if snap or jumped or accelerating or settings.sun_blend_seconds <= 0.0:
		_sun_blend_left = 0.0
		directional_light.quaternion = target
		return
	_sun_from = directional_light.quaternion
	_sun_to = target
	_sun_blend_left = settings.sun_blend_seconds


func _ease_sun(delta: float) -> void:
	if _sun_blend_left <= 0.0 or not is_instance_valid(directional_light):
		return
	_sun_blend_left = maxf(_sun_blend_left - delta, 0.0)
	var t: float = smoothstep(0.0, 1.0, 1.0 - _sun_blend_left / maxf(settings.sun_blend_seconds, 0.001))
	directional_light.quaternion = _sun_from.slerp(_sun_to, t)


## The direct beam through falling snow (Koschmieder: extinction 3.912 / visibility), eased per
## frame; the minute tick keeps the clock's energy, this scales it.
func _dim_sun_in_snow(delta: float) -> void:
	if _weather == null or not is_instance_valid(directional_light):
		return
	_snow_beam = lerpf(_snow_beam, _snow_beam_target(), 1.0 - exp(-SNOW_SUN_RESPONSE * delta))
	directional_light.light_energy = _sun_energy * _snow_beam
	if is_instance_valid(world_environment_node) and world_environment_node.environment != null:
		_apply_snow_fill(world_environment_node.environment)


## The beam falling snow takes comes back as diffuse fill in the sun's own colour (snow scatters it
## unchanged); shelters keep their capped ambient.
func _apply_snow_fill(environment: Environment) -> void:
	var fill: float = SNOW_FILL_PER_SUN * _sun_energy * (1.0 - _snow_beam)
	var sheltered: bool = is_instance_valid(color_grade_controller) and color_grade_controller.is_inside_shelter()
	if sheltered or not is_instance_valid(directional_light):
		fill = 0.0
	var energy: float = _ambient_energy + fill
	environment.ambient_light_energy = energy
	var sun_color: Color = directional_light.light_color if fill > 0.0 else _ambient_color
	environment.ambient_light_color = (_ambient_color * _ambient_energy + sun_color * fill) / maxf(energy, 0.0001)


## Share of the sun's beam that reaches the ground through falling snow, 0 to 1.
func get_snow_beam() -> float:
	return _snow_beam


func _snow_beam_target() -> float:
	var visibility: float = _weather.get_visibility_m() if _weather != null else 0.0
	return exp(-3.912 * SNOW_BEAM_PATH_M / visibility) if visibility > 0.0 else 1.0


func _calculate_light_azimuth(game_hour: float) -> float:
	return wrapf((game_hour / 24.0) * 360.0 - 90.0, -180.0, 180.0)


func _calculate_solar_altitude(game_hour: float) -> float:
	var solar_phase: float = ((game_hour - SUNRISE_HOUR) / 24.0) * TAU
	return sin(solar_phase) * settings.sun_max_altitude


func _direction_from_altitude_azimuth(altitude_deg: float, azimuth_deg: float) -> Vector3:
	var altitude: float = deg_to_rad(altitude_deg)
	var azimuth: float = deg_to_rad(azimuth_deg)
	var cos_altitude: float = cos(altitude)
	return Vector3(
		cos_altitude * sin(azimuth),
		sin(altitude),
		cos_altitude * cos(azimuth)
	).normalized()


func _calculate_light_altitude(game_hour: float) -> float:
	if _is_day(game_hour):
		var day_progress: float = inverse_lerp(SUNRISE_HOUR, SUNSET_HOUR, game_hour)
		var arc: float = 1.0 - pow((day_progress - 0.5) * 2.0, 2.0)
		return lerpf(-10.0, settings.sun_max_altitude, clampf(arc, 0.0, 1.0))

	var night_progress: float
	if game_hour > SUNSET_HOUR:
		night_progress = inverse_lerp(SUNSET_HOUR, 24.0, game_hour)
	else:
		night_progress = inverse_lerp(0.0, SUNRISE_HOUR, game_hour) + 0.25

	var moon_arc: float = 1.0 - pow((night_progress - 0.5) * 2.0, 2.0)
	return lerpf(-30.0, settings.moon_max_altitude, clampf(moon_arc, 0.0, 1.0))


func _calculate_light_color(game_hour: float) -> Color:
	if game_hour >= 5.0 and game_hour < 7.0:
		var dawn_t: float = smoothstep(0.0, 1.0, inverse_lerp(5.0, 7.0, game_hour))
		return settings.sun_color_sunrise.lerp(settings.sun_color_noon, dawn_t)

	if game_hour >= 7.0 and game_hour < 17.0:
		return settings.sun_color_noon

	if game_hour >= 17.0 and game_hour < 19.0:
		var dusk_t: float = smoothstep(0.0, 1.0, inverse_lerp(17.0, 19.0, game_hour))
		return settings.sun_color_noon.lerp(settings.sun_color_sunset, dusk_t)

	return settings.moon_color


func _calculate_light_energy(game_hour: float, day_energy: float) -> float:
	if not _is_day(game_hour):
		return settings.night_light_energy

	var day_progress: float = inverse_lerp(SUNRISE_HOUR, SUNSET_HOUR, game_hour)
	var arc: float = 1.0 - pow((day_progress - 0.5) * 2.0, 2.0)
	return lerpf(
		settings.night_light_energy,
		day_energy,
		smoothstep(0.0, 1.0, clampf(arc, 0.0, 1.0))
	)


func _calculate_cloud_color(game_hour: float) -> Color:
	if game_hour >= 4.0 and game_hour < 7.0:
		var t: float = smoothstep(0.0, 1.0, inverse_lerp(4.0, 7.0, game_hour))
		return settings.dawn_cloud_color.lerp(settings.day_cloud_color, t)

	if game_hour >= 7.0 and game_hour < 17.0:
		return settings.day_cloud_color

	if game_hour >= 17.0 and game_hour < 21.0:
		var t: float = smoothstep(0.0, 1.0, inverse_lerp(17.0, 21.0, game_hour))
		return settings.dusk_cloud_color.lerp(settings.night_cloud_color, t)

	return settings.night_cloud_color


func _calculate_critical_night_factor(game_hour: float) -> float:
	if current_day != settings.critical_night_day or _is_day(game_hour):
		return 0.0

	var factor: float
	if game_hour >= SUNSET_HOUR:
		factor = inverse_lerp(SUNSET_HOUR, 24.0, game_hour)
	else:
		factor = 1.0 - inverse_lerp(0.0, SUNRISE_HOUR, game_hour)

	return smoothstep(0.0, 1.0, clampf(factor, 0.0, 1.0))


func _is_day(game_hour: float) -> bool:
	return game_hour >= SUNRISE_HOUR and game_hour < SUNSET_HOUR


func _calculate_time_of_day(game_hour: float) -> TimeOfDay:
	var hour: int = int(game_hour)

	if hour < 4:
		return TimeOfDay.MIDNIGHT
	if hour < 6:
		return TimeOfDay.DAWN
	if hour < 10:
		return TimeOfDay.MORNING
	if hour < 14:
		return TimeOfDay.NOON
	if hour < 18:
		return TimeOfDay.AFTERNOON
	if hour < 20:
		return TimeOfDay.EVENING
	if hour < 22:
		return TimeOfDay.DUSK
	return TimeOfDay.NIGHT


func _format_time(game_hour: float) -> String:
	var hours_24: int = int(game_hour)
	var minutes: int = int(fmod(game_hour * 60.0, 60.0))
	var display_hour: int = hours_24
	var period: String = "AM"

	if display_hour >= 12:
		period = "PM"
	if display_hour > 12:
		display_hour -= 12
	if display_hour == 0:
		display_hour = 12

	return "%02d:%02d %s" % [display_hour, minutes, period]


func _emit_time_signals(game_hour: float) -> void:
	var period: TimeOfDay = _calculate_time_of_day(game_hour)
	time_changed.emit(
		_format_time(game_hour),
		is_day,
		current_day,
		PERIOD_RU[int(period)]
	)


func _update_time_display() -> void:
	var game_hour: float = get_current_hour_float()
	var period: TimeOfDay = _calculate_time_of_day(game_hour)

	if is_instance_valid(time_label):
		time_label.text = _format_time(game_hour)

	if is_instance_valid(day_label):
		day_label.text = PERIOD_EN[int(period)]

	if is_instance_valid(day_and_night_duration_label):
		day_and_night_duration_label.text = "%d sec Day + %d sec Night" % [
			int(settings.day_duration),
			int(settings.night_duration),
		]

	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: %d" % current_day


func get_current_hour_float() -> float:
	return fmod(total_game_time_hours, 24.0)


func get_current_day() -> int:
	return current_day


func is_night_time() -> bool:
	return not is_day


func is_critical_night() -> bool:
	return current_day == settings.critical_night_day and not is_day


## WeatherController calls this only when the active weather profile changes.
## Sustained wind drives sky drift; gust noise remains in gameplay/VFX and is
## deliberately not copied into shader uniforms every frame.
func apply_weather_visual_profile(profile: WeatherProfile) -> void:
	if profile == null:
		return
	if is_instance_valid(color_grade_controller):
		color_grade_controller.set_weather_profile(profile)
	if sky_material == null:
		return

	var wind_t: float = clampf(profile.wind_speed_mps / 17.0, 0.0, 1.0)
	var drift: float = lerpf(
		settings.cloud_calm_drift_speed,
		settings.cloud_storm_drift_speed,
		smoothstep(0.0, 1.0, wind_t)
	)
	var bearing: float = deg_to_rad(profile.wind_direction_deg)
	var direction := Vector2(sin(bearing), -cos(bearing)).normalized()
	sky_material.set_shader_parameter("cloud_wind_speed", direction * drift)

	var snow: float = clampf(profile.snowfall_density, 0.0, 1.0)
	## `cloud_coverage` is legacy-named in the shader: it is the lower edge of
	## smoothstep(), so raising it removes cloud. Keep calm weather exactly at
	## the authored baseline and lower the threshold gradually as snow thickens.
	var cloud_threshold: float = clampf(
		settings.cloud_coverage - snow * WEATHER_CLOUD_THRESHOLD_DROP_MAX,
		0.20,
		0.68
	)
	sky_material.set_shader_parameter("cloud_coverage", cloud_threshold)
	## The upper smoothstep edge controls how quickly surviving cloud noise
	## reaches opaque body. Keep clear weather at the authored 0.92, but lower
	## it in snow so cloud masses become readable instead of remaining faint haze.
	var cloud_mask_top: float = lerpf(0.92, 0.92 - WEATHER_CLOUD_MASK_TOP_DROP_MAX, snow)
	sky_material.set_shader_parameter("cloud_mask_top", cloud_mask_top)
	sky_material.set_shader_parameter(
		"cloud_shape_contrast",
		lerpf(0.52, 0.70, snow)
	)
	sky_material.set_shader_parameter(
		"cloud_shadow_strength",
		lerpf(0.34, 0.50, snow)
	)
	sky_material.set_shader_parameter(
		"cloud_density",
		settings.cloud_density * lerpf(0.88, 1.18, snow)
	)
	sky_material.set_shader_parameter(
		"cloud_opacity",
		clampf(settings.cloud_opacity + snow * 0.08, 0.72, 0.98)
	)


func _ambient_energy_for_context(outdoor_ambient_energy: float) -> float:
	if is_instance_valid(color_grade_controller) and color_grade_controller.is_inside_shelter():
		return minf(outdoor_ambient_energy, shelter_ambient_energy_cap)
	return outdoor_ambient_energy


func _on_interior_state_changed(_is_inside: bool) -> void:
	## DayNightManager is the single owner of Environment ambient energy. Reapply
	## immediately on a shelter edge instead of waiting for the next game-minute tick.
	_update_environment_visuals(get_current_hour_float())


func force_update_lighting() -> void:
	_update_environment_visuals(get_current_hour_float(), true)


func get_save_data() -> Dictionary:
	return {
		"total_game_time_hours": total_game_time_hours,
		"current_day": current_day,
		"is_day": is_day,
	}


func load_save_data(data: Dictionary) -> void:
	total_game_time_hours = float(data.get("total_game_time_hours", start_hour))
	_clock_loaded = true
	current_day = int(data.get("current_day", 1))
	is_day = bool(data.get("is_day", true))
	call_deferred("_force_update_visuals")

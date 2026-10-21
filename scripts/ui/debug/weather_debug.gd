class_name WeatherDebug
extends Node

## Debug builds only, one key (0): the first press shows what the weather is doing and why the wind
## effects run or not; each next press pins the next weather in CYCLE, the last one hands it back.

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const SNOWFALL_SCRIPT: GDScript = preload("res://scripts/systems/world/weather/snowfall_vfx.gd")
const CYCLE: Array[StringName] = [&"calm", &"snowfall", &"windy", &"blizzard", &""]
## Game hours a pinned weather holds.
const PIN_HOURS: float = 9999.0
const REFRESH_S: float = 0.25

var _weather: WeatherController
var _thermal: ThermalManager
var _day_night: DayNightManager
var _snowfall: SnowfallVFX
var _gusts: WindGusts
var _label: Label
var _layer: CanvasLayer
var _cycle_index: int = -1
var _refresh_left: float = 0.0


func on_world_ready(context: WorldContext) -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_day_night = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	_snowfall = context.find_in_scene(SNOWFALL_SCRIPT) as SnowfallVFX
	_gusts = get_parent().find_child("WindGusts", false, false) as WindGusts
	_build_overlay()
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null or not input_systems.has_signal(&"dev_weather_cycle_pressed"):
		return
	input_systems.connect(&"dev_weather_cycle_pressed", cycle_weather)


## Shows the readout first; then pins the next weather in CYCLE at once. The empty step returns
## control to the scheduler and hides the readout.
func cycle_weather() -> void:
	if _weather == null:
		return
	if not _layer.visible:
		_layer.visible = true
		_refresh_left = 0.0
		return
	_cycle_index = (_cycle_index + 1) % CYCLE.size()
	var id: StringName = CYCLE[_cycle_index]
	if id == &"":
		var current: WeatherProfile = _weather.get_current_profile()
		_weather.set_weather(current.id if current != null else &"calm", true)
		_cycle_index = -1
		_layer.visible = false
		return
	_weather.set_weather(id, true, PIN_HOURS)
	_refresh_left = 0.0


func _process(delta: float) -> void:
	if _label == null or not _layer.visible:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_S
	_label.text = _readout()


func _readout() -> String:
	if _weather == null:
		return "WEATHER: no WeatherController"
	var profile: WeatherProfile = _weather.get_current_profile()
	var pinned: bool = _cycle_index >= 0 and CYCLE[_cycle_index] != &""
	var wind: float = _weather.get_wind_speed_mps()
	var direction: Vector3 = _weather.get_wind_direction()
	var bearing: float = fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)
	var lines: PackedStringArray = []
	lines.append("WEATHER  %s  %s  blend %.2f  next in %.1f h" % [
		profile.id if profile != null else "none", "pinned (0)" if pinned else "scheduler",
		_weather.get_blend(), _weather.get_remaining_hours()])
	lines.append("wind %.1f m/s toward %03d°  drift %s (from %.0f m/s)" % [
		wind, int(bearing), "on" if wind >= WindGusts.MIN_WIND_MPS else "off", WindGusts.MIN_WIND_MPS])
	lines.append("snowfall %.2f  visibility %s  cover %.2f" % [
		_weather.get_snowfall_density(),
		"%.0f m" % _weather.get_visibility_m() if _weather.get_visibility_m() > 0.0 else "clear",
		_weather.get_snow_cover()])
	if _day_night != null:
		var hour: float = _day_night.get_current_hour_float()
		lines.append("hour %02d:%02d  sun beam %d %%" % [int(hour), int(fmod(hour, 1.0) * 60.0), int(round(_day_night.get_snow_beam() * 100.0))])
	lines.append("sheltered %s" % (str(_thermal.is_sheltered()) if _thermal != null else "?"))
	if _gusts != null:
		var counts: Vector3i = _gusts.get_active_counts()
		lines.append("streaks %d  ground drift %d  spindrift %d" % [counts.x, counts.y, counts.z])
	if _snowfall != null and _snowfall.particles != null:
		lines.append("snowfall emitting %s  ratio %.2f  at %s" % [
			str(_snowfall.particles.emitting), _snowfall.particles.amount_ratio, str(_snowfall.global_position.round())])
	lines.append("0: next weather (calm, snowfall, windy, blizzard, back to scheduler)")
	return "\n".join(lines)


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	_layer.visible = false
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -470.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override(&"panel", style)
	_layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 13)
	panel.add_child(_label)

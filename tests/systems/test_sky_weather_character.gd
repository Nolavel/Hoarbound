extends SceneTree

## Sky art direction (PainterlyDayNightManager): wind sculpts cloud bodies, snow closes the deck, a blizzard veils it,
## the moon lights the deck at night, and the wash takes the hour's light. Checks the parameters, not pixels.
## Run: godot --headless --script tests/systems/test_sky_weather_character.gd

const PROFILES: Array[StringName] = [&"calm", &"windy", &"snowfall", &"blizzard"]

var _failures: int = 0
var _env: Node3D
var _dn: PainterlyDayNightManager
var _wash: PainterlyAtmospherePass


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_env = (load("res://scenes/game/systems/world/WorldEnvironmentSystem.tscn") as PackedScene).instantiate()
	root.add_child(_env)
	var tps: Node = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate()
	root.add_child(tps)
	_wash = tps.find_child("PainterlyAtmosphere", true, false) as PainterlyAtmospherePass
	await process_frame
	await process_frame
	_dn = _env.get_node("DayNightManager") as PainterlyDayNightManager
	_check(_dn != null and _dn.sky_material != null, "environment does not use PainterlyDayNightManager with a sky")
	if _dn == null or _dn.sky_material == null:
		_finish()
		return
	var day: Dictionary = _sample(12.0)
	var night: Dictionary = _sample(23.0)
	_check_day(day)
	_check_night(day, night)
	_finish()


func _sample(hour: float) -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in PROFILES:
		_dn.apply_weather_visual_profile(load("res://resources/weather/%s.tres" % id) as WeatherProfile)
		_dn.total_game_time_hours = hour
		_dn.force_update_lighting()
		var m: ShaderMaterial = _dn.sky_material
		var env: Environment = _dn.world_environment_node.environment
		out[id] = {
			"read": _dn.get_cloud_readability(),
			"shape": float(m.get_shader_parameter(&"cloud_shape_contrast")),
			"shadow": float(m.get_shader_parameter(&"cloud_shadow_strength")),
			"sag": float(m.get_shader_parameter(&"cloud_sag")),
			"coverage": float(m.get_shader_parameter(&"cloud_coverage")),
			"top": float(m.get_shader_parameter(&"cloud_top_light")),
			"cloud": m.get_shader_parameter(&"cloud_color") as Color,
			"fog_sky": env.fog_sky_affect,
			"vol_sky": env.volumetric_fog_sky_affect,
			"wash": _wash.get_shader_material().get_shader_parameter(&"wash_color") as Color,
		}
	return out


func _check_day(d: Dictionary) -> void:
	_check(d[&"calm"]["read"] < 0.05 and d[&"blizzard"]["read"] < 0.05, "calm or blizzard reads as sculpted clouds")
	_check(d[&"windy"]["read"] > 0.9 and d[&"snowfall"]["read"] > 0.9, "windy/snowfall clouds are not fully readable: %.2f / %.2f" % [d[&"windy"]["read"], d[&"snowfall"]["read"]])
	for id: StringName in [&"windy", &"snowfall"]:
		_check(d[id]["shape"] > d[&"calm"]["shape"] + 0.2 and d[id]["shadow"] > d[&"calm"]["shadow"] + 0.15, "%s bodies have no more contrast than calm" % id)
	_check(d[&"snowfall"]["sag"] < d[&"windy"]["sag"] and d[&"windy"]["sag"] < d[&"calm"]["sag"], "cloud bodies do not grow calm < windy < snowfall")
	_check(is_equal_approx(d[&"calm"]["coverage"], _dn.settings.cloud_coverage), "calm left the authored cloud baseline")
	_check(d[&"calm"]["coverage"] > d[&"windy"]["coverage"] and d[&"windy"]["coverage"] > d[&"blizzard"]["coverage"], "cloud thresholds not ordered calm > windy > blizzard")
	_check(d[&"windy"]["top"] > d[&"calm"]["top"] and d[&"calm"]["top"] > d[&"snowfall"]["top"] and d[&"snowfall"]["top"] > d[&"blizzard"]["top"], "lit tops not ordered windy > calm > snowfall > blizzard")
	_check(d[&"windy"]["fog_sky"] < d[&"calm"]["fog_sky"] and d[&"calm"]["fog_sky"] < d[&"blizzard"]["fog_sky"], "fog over the sky not ordered windy < calm < blizzard")
	_check(_near(d[&"calm"]["wash"], PainterlyAtmospherePass.DAY_WASH_COLOR), "day wash is not the paper colour")


func _check_night(d: Dictionary, n: Dictionary) -> void:
	var dark: Color = _dn.settings.night_cloud_color
	_check(n[&"calm"]["cloud"].get_luminance() > dark.get_luminance() * 2.0, "night clouds are not moonlit")
	_check(n[&"windy"]["cloud"].get_luminance() > n[&"calm"]["cloud"].get_luminance(), "windy night clouds are not lit more than calm")
	_check(is_equal_approx(n[&"windy"]["cloud"].a, 1.0), "moonlight changed the cloud colour alpha")
	for id: StringName in [&"calm", &"windy", &"snowfall"]:
		_check(n[id]["top"] >= PainterlyDayNightManager.NIGHT_TOP_LIGHT - 0.001, "%s night tops are not moonlit" % id)
		_check(is_equal_approx(n[id]["vol_sky"], d[id]["vol_sky"] * PainterlyDayNightManager.NIGHT_VOLUMETRIC_SKY_SHARE), "%s night volumetric fog still veils the sky" % id)
	_check(n[&"blizzard"]["top"] < n[&"windy"]["top"], "the blizzard veil does not hide moonlit tops")
	_check(_near(n[&"calm"]["wash"], PainterlyAtmospherePass.NIGHT_WASH_COLOR), "night wash is not the ink colour")


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _finish() -> void:
	if _failures > 0:
		push_error("sky weather character: %d check(s) failed" % _failures)
		quit(1)
		return
	print("sky weather character: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("sky weather character: " + message)

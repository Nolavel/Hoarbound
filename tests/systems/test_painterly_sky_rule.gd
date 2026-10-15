extends SceneTree

## Painterly wash sky rule: 10% sky share up to ordinary snowfall, rising to 100% in a blizzard,
## driven by the live weather in the main scene; the pass stays on its own screen-pass layer.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check_curve()
	await _check_live_weather()
	if _failures > 0:
		push_error("painterly sky rule: %d check(s) failed" % _failures)
		quit(1)
		return
	print("painterly sky rule: all checks passed")
	quit(0)


func _check_curve() -> void:
	_check(is_equal_approx(PainterlyAtmospherePass.sky_affect_for(0.0), 0.1), "calm sky share is not 10%")
	_check(is_equal_approx(PainterlyAtmospherePass.sky_affect_for(0.45), 0.1), "ordinary snowfall sky share is not 10%")
	_check(is_equal_approx(PainterlyAtmospherePass.sky_affect_for(0.95), 1.0), "blizzard sky share is not 100%")
	var previous: float = 0.0
	for i: int in range(21):
		var value: float = PainterlyAtmospherePass.sky_affect_for(float(i) / 20.0)
		_check(value >= previous - 0.0001, "sky share falls as snowfall grows at %.2f" % (float(i) / 20.0))
		previous = value
	var mid: float = PainterlyAtmospherePass.sky_affect_for(0.7)
	_check(mid > 0.1 and mid < 1.0, "sky share does not rise gradually between snowfall and blizzard")


func _check_live_weather() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	for i: int in range(30):
		await process_frame
	var wash := scene.find_child("PainterlyAtmosphere", true, false) as PainterlyAtmospherePass
	var weather: Node = get_first_node_in_group(PainterlyAtmospherePass.WEATHER_GROUP)
	_check(wash != null, "main scene has no painterly pass")
	_check(weather is WeatherController, "main scene has no weather controller")
	if wash == null or not (weather is WeatherController):
		return
	_check(wash.layers == RenderLayers.SCREEN_PASS, "painterly pass left its screen-pass layer")
	var material: ShaderMaterial = wash.get_shader_material()
	(weather as WeatherController).set_weather(&"calm", true)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(material.get_shader_parameter(&"sky_affect")), 0.1), "calm weather did not give a 10% sky share")
	(weather as WeatherController).set_weather(&"blizzard", true)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(material.get_shader_parameter(&"sky_affect")), 1.0), "blizzard did not give a 100% sky share")
	scene.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("painterly sky rule: " + message)

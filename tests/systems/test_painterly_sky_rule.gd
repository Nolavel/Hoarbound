extends SceneTree

## Painterly wash rules: atmospheric strength follows live weather, while paper stays constant;
## the pass keeps its layer and draws before transparents (snow, glass).

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
	_check(is_equal_approx(PainterlyAtmospherePass.wash_strength_for(0.0), 0.1), "calm wash strength is not 10%")
	_check(is_equal_approx(PainterlyAtmospherePass.wash_strength_for(0.95), 1.0), "blizzard wash strength is not 100%")
	var snowfall: float = PainterlyAtmospherePass.wash_strength_for(0.45)
	_check(snowfall > 0.3 and snowfall < 0.8, "ordinary snowfall wash strength %.2f is not in between" % snowfall)
	previous = 0.0
	for i: int in range(21):
		var strength: float = PainterlyAtmospherePass.wash_strength_for(float(i) / 20.0)
		_check(strength >= previous - 0.0001, "wash strength falls as snowfall grows at %.2f" % (float(i) / 20.0))
		previous = strength


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
	## Screen texture holds only opaque geometry; drawn after transparents the pass would erase snow and glass.
	_check(material.render_priority == Material.RENDER_PRIORITY_MIN, "painterly pass does not draw before transparents")
	var permanent_paper: float = float(material.get_shader_parameter(&"paper_strength"))
	_check(is_equal_approx(permanent_paper, 1.0), "production paper strength is not 100%")
	_check(float(material.get_shader_parameter(&"paper_fiber_strength")) > 0.0, "paper fibre layer is disabled")
	_check(float(material.get_shader_parameter(&"granulation_strength")) > 0.0, "second pigment scale is disabled")
	_check(float(material.get_shader_parameter(&"drying_rim_strength")) > 0.0, "drying rim is disabled")
	_check(float(material.get_shader_parameter(&"internal_ink_strength")) > 0.0, "internal ink edges are disabled")
	var value_steps: float = float(material.get_shader_parameter(&"value_steps"))
	_check(value_steps >= 6.0 and value_steps <= 8.0, "production value terrace escaped the restrained 6-8 step range")
	_check(float(material.get_shader_parameter(&"mid_ink_hold")) >= 0.35, "mid-ground charcoal mass is too weak")
	_check(float(material.get_shader_parameter(&"mid_paper_mix")) <= 0.22, "mid-ground paper lift is washing out the charcoal mass")
	(weather as WeatherController).set_weather(&"calm", true)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(material.get_shader_parameter(&"sky_affect")), 0.1), "calm weather did not give a 10% sky share")
	_check(is_equal_approx(float(material.get_shader_parameter(&"wash_strength")), 0.1), "calm weather did not give a 10% wash")
	_check(is_equal_approx(float(material.get_shader_parameter(&"paper_strength")), permanent_paper), "calm weather changed permanent paper")
	(weather as WeatherController).set_weather(&"blizzard", true)
	await process_frame
	await process_frame
	_check(is_equal_approx(float(material.get_shader_parameter(&"sky_affect")), 1.0), "blizzard did not give a 100% sky share")
	_check(is_equal_approx(float(material.get_shader_parameter(&"wash_strength")), 1.0), "blizzard did not give a full wash")
	_check(is_equal_approx(float(material.get_shader_parameter(&"paper_strength")), permanent_paper), "blizzard changed permanent paper")
	scene.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("painterly sky rule: " + message)


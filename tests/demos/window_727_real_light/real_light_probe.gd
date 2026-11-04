class_name Window727RealLightProbe
extends Node3D

## Issue #281, real-light follow-up. 727 is taken from the actual game world.
## Reuses the original GLB triangles, real weather/daylight, 727 stove light,
## world environment and the shelter colour grade. No scene-light substitutes.

const WORLD_SCENE: PackedScene = preload("res://scenes/world/key_west/key_west_reality.tscn")
const PANE_SCENE: PackedScene = preload("res://tests/scenes/window_727_sdf_probe.tscn")
const LIT_SHADER: Shader = preload("res://tests/demos/window_727_real_light/lit_frosted_glass_v3.gdshader")
const LEGACY_LIT_SHADER: Shader = preload("res://tests/demos/window_727_real_light/lit_frosted_glass_v3_blue_control.gdshader")
const WINDOW_NAME: StringName = &"FrontWindow1"

var _world: World
var _house: Node3D
var _probe: Window727SDFProbe
var _pane: MeshInstance3D
var _unlit: ShaderMaterial
var _lit: ShaderMaterial
var _legacy_lit: ShaderMaterial
var _camera: Camera3D
var _label: Label
var _ready_for_capture: bool = false
var _source_mesh: MeshInstance3D


func _ready() -> void:
	_world = WORLD_SCENE.instantiate() as World
	if _world == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: could not instantiate real key_west_reality world")
		return
	_world.spawn_at_shelter = true
	add_child(_world)


func prepare() -> bool:
	# Called after the real-world startup and nearby streamed cluster are live.
	var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
	if shelter == null or shelter.interior.is_empty():
		push_error("WINDOW_727_REAL_LIGHT_FAIL: original Shelter727 not assembled")
		return false
	_house = shelter.get_node_or_null(^"House") as Node3D
	if _house == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: original 727 House is absent")
		return false
	var environment_system: WorldEnvironmentController = _world.get_node_or_null(^"WorldEnvironmentSystem") as WorldEnvironmentController
	var sun: DirectionalLight3D = environment_system.sun_light if environment_system != null else null
	var environment_node: WorldEnvironment = environment_system.world_environment if environment_system != null else null
	if sun == null or environment_node == null or environment_node.environment == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: production sun / WorldEnvironment missing")
		return false
	# The previous capture used live blizzard conditions (visibility 45 m).
	# For this lighting A/B pin the *existing* calm weather profile, leaving
	# the actual 727 environment, sun and stove source unchanged.
	var weather: WeatherController = null
	for node: Node in get_tree().get_nodes_in_group(&"weather_controller"):
		if _world.is_ancestor_of(node):
			weather = node as WeatherController
			break
	if weather == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: game WeatherController missing")
		return false
	weather.scheduler_enabled = false
	weather.set_weather(&"calm", true)
	if weather.get_current_profile() == null or weather.get_current_profile().id != &"calm":
		push_error("WINDOW_727_REAL_LIGHT_FAIL: cannot pin real calm weather")
		return false
	# The world Environment is already heavily fogged at density 1.0.
	# Duplicate the resource ONLY inside the test-scene and dial back the
	# veil to see specular/diffuse details. No synthetic lights or room.
	environment_node.environment = environment_node.environment.duplicate(true) as Environment
	var test_env: Environment = environment_node.environment
	test_env.fog_density = 0.012
	test_env.volumetric_fog_enabled = false
	var grade: ColorGradeController = environment_system.color_grade_controller
	if grade == null or not grade.set_profile(&"HFN_ColdAsh_Shelter") or not grade.is_inside_shelter():
		push_error("WINDOW_727_REAL_LIGHT_FAIL: canonical shelter grade unavailable")
		return false
	var stove: HeatSource = _house.get_node_or_null(^"ShelterZone/Stove") as HeatSource
	if stove == null or stove.flame_light == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: real stove or its room light is unavailable")
		return false
	stove.ignite()
	var flame: StoveVisual = stove.get_node_or_null(^"StoveVisual") as StoveVisual
	if flame == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: real stove visual absent")
		return false
	# The world owns the source lamp energy; do not create a convenient test OmniLight.
	_source_mesh = _find_streamed_727_glass(shelter.global_position)
	if _source_mesh == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: streamed 727 Glass was not loaded")
		return false
	_source_mesh.visible = false  # Only the source GLB's glass is substituted in the test.
	
	_probe = PANE_SCENE.instantiate() as Window727SDFProbe
	add_child(_probe)
	if not _probe.is_valid() or _probe.verified_triangles() != 12:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: actual FrontWindow1 triangle extraction failed")
		return false
	var checker: MeshInstance3D = _probe.find_child("TransparencyTarget_TestFixture", true, false) as MeshInstance3D
	if checker != null:
		checker.visible = false
	var old_camera: Camera3D = _probe.find_child("WindowTestCamera", true, false) as Camera3D
	if old_camera != null:
		old_camera.current = false
	for child: Node in _probe.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_probe.position = shelter.global_position # Imported GLB geometry is local to site origin.
	_pane = _probe.get_node_or_null(^"FrontWindow1_RealGlassOnly") as MeshInstance3D
	if _pane == null:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: extracted pane missing")
		return false
	_unlit = _probe.get("_sdf") as ShaderMaterial
	_lit = _unlit.duplicate(true) as ShaderMaterial
	_lit.shader = LIT_SHADER
	_legacy_lit = _unlit.duplicate(true) as ShaderMaterial
	_legacy_lit.shader = LEGACY_LIT_SHADER
	for p: StringName in [&"growth_seed", &"melt_seed", &"pane_aspect"]:
		for variant: ShaderMaterial in [_lit, _legacy_lit]:
			variant.set_shader_parameter(p, _unlit.get_shader_parameter(p))
	_make_camera()
	_hide_debug_ui()
	_make_label()
	_ready_for_capture = true
	print("WINDOW_727_REAL_LIGHT_OK source=key_west_reality.tscn pane=FrontWindow1 tris=%d sun=%s sun_energy=%.3f stove=%s stove_energy=%.3f shelter_grade=%s weather=%s fog_density=%.3f volumetric_fog=%s glass_mesh=%s" % [
		_probe.verified_triangles(),
		String(sun.get_path()), sun.light_energy,
		String(stove.flame_light.get_path()), stove.flame_light.light_energy,
		String(grade.get_current_profile_id()), String(weather.get_current_profile().id),
		test_env.fog_density, str(test_env.volumetric_fog_enabled),
		String(_source_mesh.get_path())
	])
	return true


func valid() -> bool:
	return _ready_for_capture


func set_capture_time(seconds: float) -> void:
	if not _ready_for_capture:
		return
	var lit_phase: bool = seconds >= 3.0
	var phase_time: float = fmod(seconds, 3.0)
	var fraction: float = clampf(phase_time / 3.0, 0.0, 1.0)
	# Reuse precisely the approved V3 morph/circles/timing in both phases.
	_probe.set_test_time(3.0 + phase_time)
	for variant: ShaderMaterial in [_lit, _legacy_lit]:
		variant.set_shader_parameter(&"heated_warmth", fraction)
		variant.set_shader_parameter(&"blob_data", _unlit.get_shader_parameter(&"blob_data"))
		variant.set_shader_parameter(&"blob_count", _unlit.get_shader_parameter(&"blob_count"))
	_pane.material_override = _lit if lit_phase else _legacy_lit
	# Small *repeated* shift reveals real specularity, identical in A/B.
	var offset: float = sin(phase_time * 1.2) * 0.10
	var target: Vector3 = _house.global_transform * Vector3(-3.0, 2.0, 10.196)
	var eye: Vector3 = _house.global_transform * Vector3(-3.0 + offset, 1.97, 7.75)
	_camera.look_at_from_position(eye, target, Vector3.UP)
	_label.text = "727 FORT ST / FRONTWINDOW1 | %s | WARMTH: %02d%%" % [
		"V3 BLUE LIT CONTROL" if not lit_phase else "V4 NEUTRAL CRYSTAL + WET LIGHT",
		int(fraction * 100.0)
	]


func _find_streamed_727_glass(origin: Vector3) -> MeshInstance3D:
	var found: MeshInstance3D
	var closest: float = INF
	for candidate: Node in _world.find_children("Glass", "MeshInstance3D", true, false):
		var glass: MeshInstance3D = candidate as MeshInstance3D
		if glass.mesh == null:
			continue
		var dist: float = glass.global_position.distance_to(origin)
		if dist < closest:
			found = glass
			closest = dist
	print("WINDOW_727_REAL_LIGHT_GLASS_SEARCH nearest=%.2f origin=%s" % [closest, origin])
	if closest > 20.0:
		return null
	return found


func _make_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "FrontWindow1_InteriorRealLightCamera"
	_camera.fov = 49.0
	_camera.near = 0.04
	_camera.far = 500.0
	add_child(_camera)
	_camera.make_current()


func _hide_debug_ui() -> void:
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node: Node in _world.find_children("*", "Control", true, false):
		var ctrl: Control = node as Control
		if ctrl.name in [&"StartupTitleCard", &"DebugTime", &"DebugAccelerator", &"WeatherDebug"]:
			ctrl.visible = false


func _make_label() -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.layer = 90
	add_child(overlay)
	_label = Label.new()
	_label.position = Vector2(24.0, 18.0)
	_label.add_theme_font_size_override("font_size", 21)
	_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.86))
	overlay.add_child(_label)

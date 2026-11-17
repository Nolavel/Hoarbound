extends SceneTree

## Henry's gear goes out of the picture with the camera against him without new render pipelines (#42 rec. 02,
## #173): hidden gear is shadows-only, never transparent (a first transparent use compiled 32 pipelines, a
## 20.7 s frame on lavapipe), keeps its shadow, and comes back as it was.
## Run: godot --headless --script tests/systems/test_body_fade_pipelines.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	var camera := (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	camera.player = player
	root.add_child(camera)
	camera.make_current()
	for _i: int in 30:
		await process_frame
	var gear: Array[GeometryInstance3D] = []
	var own: Dictionary = {}
	for node: Node in player.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if geo.layers & camera.body_layers and not TpsCameraFader._is_stylized(geo):
			gear.append(geo)
			own[geo] = geo.cast_shadow
	_check(not gear.is_empty(), "Henry has no gear outside the stylized shader to hide")
	## The camera against him: full fade and the gear's reach, as with the lens inside the pack.
	camera.direct_fade_distances = Vector2(100.0, 99.0)
	camera.direct_fade_max = 1.0
	camera._fader.body_fallback_reach = Vector2(100.0, 100.0)
	for _i: int in 10:
		await process_frame
	_check(camera._fader._gear_hidden, "the gear was not hidden with the camera against Henry")
	for geo: GeometryInstance3D in gear:
		_check(geo.transparency == 0.0, "%s went transparent (a new pipeline on first use)" % geo.name)
		if own[geo] != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_check(geo.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "%s hidden is not shadows-only" % geo.name)
	camera.direct_fade_distances = Vector2(0.36, 0.22)
	camera._fader.body_fallback_reach = Vector2(0.45, 0.6)
	for _i: int in 10:
		await process_frame
	for geo: GeometryInstance3D in gear:
		_check(geo.cast_shadow == own[geo] and geo.transparency == 0.0, "%s did not come back as it was" % geo.name)
	print("body fade pipelines: %d gear meshes hidden shadows-only and restored" % gear.size())
	if _failures > 0:
		push_error("body fade pipelines: %d check(s) failed" % _failures)
		quit(1)
		return
	print("body fade pipelines: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("body fade pipelines: " + message)

extends SceneTree

## Henry's breath: resting and panting in −20 °C close up, panting from the game camera's distance, and +10 °C (none).
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 60 --resolution 960x540 --script res://tools/runtime/capture_breath_vapor.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/breath_vapor"
var _player: Player
var _breath: BreathVapor
var _camera: Camera3D
var _air_c: float = -20.0
var _far: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.19, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 140.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_breath = _player.get_node(^"BreathVapor") as BreathVapor
	_breath.set_process(false)
	_player.animation_component.skeleton.skeleton_updated.connect(_breath._follow_mouth)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()
	await _frames(60, 0.0)
	await _frames(150, 0.0)
	await _shot("1_rest_exhale", 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(300, -1.0)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _frames(30, -1.0)
	await _shot("2_panting_after_sprint", -1.0)
	_far = true
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(240, -1.0)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _frames(20, -1.0)
	await _shot("3_panting_game_distance", -1.0)
	_far = false
	_air_c = 10.0
	await _frames(240, -1.0)
	await _shot("4_warm_air_none", -1.0)
	quit(0)


## Drives the breath each frame; effort −1 means the real effort from movement and stamina.
func _frames(count: int, effort: float) -> void:
	for _i: int in range(count):
		var target: float = _breath.get_target_exertion() if effort < 0.0 else effort
		_breath.step(1.0 / 60.0, _air_c, target)
		var head: Vector3 = _breath.global_position
		var facing: Vector3 = _player.animation_component.get_head_facing()
		var side: Vector3 = Vector3.UP.cross(facing).normalized()
		if _far:
			_camera.look_at_from_position(head - facing * 2.6 + side * 1.6 + Vector3.UP * 0.5, head + facing * 0.6, Vector3.UP)
		else:
			_camera.look_at_from_position(head + facing * 0.9 + side * 0.9 + Vector3.UP * 0.05, head + facing * 0.25, Vector3.UP)
		await process_frame


## Waits for the middle of an exhale so the puff is in frame.
func _shot(label: String, effort: float) -> void:
	var waited: int = 0
	while waited < 600 and _breath.is_exhaling():
		await _frames(1, effort)
		waited += 1
	while waited < 600 and not _breath.is_exhaling():
		await _frames(1, effort)
		waited += 1
	await _frames(int(_breath.get_period_s() * 60.0 * 0.28), effort)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(label + ".png")))
	print("BREATH %s air=%.0f density=%.2f exertion=%.2f period=%.2f puffing=%s" % [label, _air_c, _breath.get_density(), _breath.get_exertion(), _breath.get_period_s(), _breath.is_puffing()])

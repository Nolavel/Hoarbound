extends SceneTree

## The frying pan swung on a bare stage, seen from the front-right: the pan in hand, a quick LMB strike, RMB held
## at the overhead wind-up, the release. PNG frames at 30 fps.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 960x540 --script res://tools/runtime/capture_pan_strike.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/pan_strike"
var _camera: Camera3D
var _frame: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	ground.material_override = StylizedEnvironmentMaterial.make(Color(0.78, 0.8, 0.84), 0.9)
	floor.add_child(ground)
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var player := (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var visual := player.get_node(^"HenryUALVisual") as HenryUALAnimation
	visual.head_look_idle_speed = 0.0
	await _frames(40)
	var held := player.get_node(^"HeldItemComponent") as HeldItemComponent
	held.present_owned(&"frying_pan")
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	var forward: Vector3 = -player.global_basis.z
	var right: Vector3 = player.global_basis.x
	var focus: Vector3 = player.global_position + Vector3.UP * 0.2
	_camera.look_at_from_position(focus + forward * 3.2 + right * 2.0 + Vector3.UP * 0.5, focus + forward * 0.4)
	_camera.make_current()
	await _shoot(25)
	var strike := player.get_node(^"StrikeComponent") as StrikeComponent
	_press(strike, &"fire", true)
	_press(strike, &"fire", false)
	await _shoot(30)
	_press(strike, &"present_held", true)
	await _shoot(35)
	_press(strike, &"present_held", false)
	await _shoot(35)
	print("PAN_STRIKE frames=", _frame)
	quit()


func _press(strike: StrikeComponent, action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	strike._input(event)


func _shoot(count: int) -> void:
	for _i: int in range(count):
		await process_frame
		for layer: Node in root.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [_out, _frame])
		_frame += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

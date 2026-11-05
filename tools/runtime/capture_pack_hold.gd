extends SceneTree

## The pack taken off the back into both hands before the chest, open toward the camera (3D inventory,
## stage 3): stills over the right shoulder (the inventory view) and from the front-left (the hands), then
## the swing back on.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_pack_hold.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/pack_hold"
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
	_camera = Camera3D.new()
	_camera.fov = 50.0
	root.add_child(_camera)
	_camera.make_current()
	var sk: Skeleton3D = visual.skeleton
	var shoulders: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone(&"upperarm_r")).origin) - sk.to_global(sk.get_bone_global_pose(sk.find_bone(&"upperarm_l")).origin)
	var forward: Vector3 = Vector3.UP.cross(shoulders)
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	print("forward ", forward, " model z ", visual.global_basis.z, " body -z ", -player.global_basis.z)
	var hold: PackFrontHold = visual.hold_pack_front()
	await _frames(40)
	var centre: Vector3 = hold.held_transform().origin
	var chest_at: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone(&"spine_03")).origin)
	print("player ", player.global_position, " chest ", chest_at, " held ", centre, " pack now ", visual.get_pack_rig().global_position)
	## The inventory view: facing Henry, the open pack filling 60% of the height.
	_camera.fov = 50.0
	_camera.global_transform = hold.front_view(_camera.fov)
	await _shoot_named("front_view")
	_camera.fov = 50.0
	_camera.look_at_from_position(player.global_position + forward * 2.0 - right * 1.4 + Vector3.UP * 0.6, player.global_position + Vector3.UP * 0.3)
	await _shoot_named("front_left")
	visual.release_pack_front()
	for _i: int in 30:
		await process_frame
	await _shoot_named("back_on")
	print("PACK_HOLD shots=", _frame)
	quit()


func _shoot_named(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _frame, label])
	_frame += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

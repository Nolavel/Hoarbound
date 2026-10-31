extends SceneTree

## Henry's outfit (the owner's jacket, jeans and boots): full body front, side, back and three-quarter, then mid-stride.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_outfit.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/outfit"
var _player: CharacterBody3D
var _camera: Camera3D
var _hat_only: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_hat_only = args.has("hat_only")
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
	_player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	_player.position = Vector3(0.0, 1.0, 0.0)
	# Outfit views are a turntable of the fitted meshes.  Henry's idle HeadLook
	# otherwise follows the temporary capture camera and turns the hat sideways
	# before the first shot, making its stripes and silhouette look misaligned.
	var visual := _player.find_child("HenryUALVisual", true, false) as HenryUALAnimation
	if visual != null:
		visual.head_look_idle_speed = 0.0
	_camera = Camera3D.new()
	_camera.fov = 35.0
	root.add_child(_camera)
	await _frames(30 if _hat_only else 60)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera.make_current()
	if _hat_only:
		for view: Array in [["front", 180.0], ["side", 90.0], ["back", 0.0], ["three_quarter", 145.0]]:
			await _hat_shot("hat_" + view[0], view[1])
		quit(0)
		return
	for view: Array in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["three_quarter", 35.0]]:
		await _shot("rest_" + view[0], view[1], 0.95, 3.4)
	await _shot("torso_three_quarter", 35.0, 1.35, 1.6)
	await _shot("hands_front", 10.0, 0.85, 1.2)
	await _shot("hands_side", 80.0, 0.85, 1.0)
	await _shot("boot_tops", 20.0, 0.35, 0.9)
	await _shot("boot_top_close", 0.0, 0.35, 0.55)
	for view: Array in [["front", 180.0], ["side", 90.0], ["back", 0.0], ["three_quarter", 145.0]]:
		await _hat_shot("hat_" + view[0], view[1])
	Input.action_press(&"move_forward")
	await _frames(40)
	for k: int in range(3):
		await _shot("walk_side_%d" % k, 90.0, 0.95, 3.4, 7)
	Input.action_release(&"move_forward")
	quit(0)


## Looks between Henry's feet (`at_y` above the soles) from `yaw` degrees round him at `dist` metres.
func _shot(shot_name: String, yaw: float, at_y: float, dist: float, wait: int = 3) -> void:
	await _frames(wait)
	var basis: Basis = _player.global_basis
	var skeleton := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var feet: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_l")).origin
		+ skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_r")).origin) * 0.5
	var target: Vector3 = Vector3(feet.x, feet.y - 0.1 + at_y, feet.z)
	var dir: Vector3 = (basis * Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))).normalized()
	_camera.global_position = target + dir * dist + Vector3(0.0, dist * 0.1, 0.0)
	_camera.look_at(target, Vector3.UP)
	await _frames(2)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("[boots] ", shot_name)


## Keep the hat centred on the animated Head bone, independent of Henry's
## current floor height or the outfit camera's foot-based framing.
func _hat_shot(shot_name: String, yaw: float) -> void:
	var skeleton := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head: int = skeleton.find_bone("Head")
	var target: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(head).origin + Vector3.UP * 0.10
	var dir: Vector3 = (_player.global_basis * Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))).normalized()
	_camera.global_position = target + dir * 1.15 + Vector3.UP * 0.03
	_camera.look_at(target, Vector3.UP)
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("[hat] ", shot_name)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

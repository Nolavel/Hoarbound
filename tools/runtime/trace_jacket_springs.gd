extends SceneTree

## Jacket hem and collar springs: per-chain swing off rest through idle, walk, sprint and stop, plus side/front/back shots.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/trace_jacket_springs.gd -- <out dir> [hem k d g collar k d g]

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/outfit"
var _player: CharacterBody3D
var _camera: Camera3D
var _hem: float = 0.0
var _dump: bool = false
var _collar: float = 0.0


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
	_player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	root.add_child(_camera)
	await _frames(60)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera.make_current()
	var sk := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var springs: Node = sk.get_node_or_null(^"JacketSprings")
	print("springs: ", springs, " settings ", springs.setting_count, " active ", springs.active)
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 1:
		for i: int in springs.setting_count:
			var collar: bool = String(springs.get_root_bone_name(i)).begins_with("collar")
			var o: int = 4 if collar else 1
			springs.set_stiffness(i, float(a[o])); springs.set_drag(i, float(a[o + 1])); springs.set_gravity(i, float(a[o + 2]))
		springs.reset()
	springs.modification_processed.connect(func() -> void:
		_hem = _swing(sk, "hem_"); _collar = _swing(sk, "collar_")
		if _dump:
			_dump = false
			for b: int in sk.get_bone_count():
				var n: String = sk.get_bone_name(b)
				if n.begins_with("hem_") or n.begins_with("collar_"):
					print("  ", n, " %.1f" % rad_to_deg(sk.get_bone_pose_rotation(b).angle_to(sk.get_bone_rest(b).basis.get_rotation_quaternion()))))
	var plan: Array = [["idle", 30, false, false], ["walk", 60, true, false], ["sprint", 60, true, true], ["stop", 60, false, false]]
	for step: Array in plan:
		if step[2]: Input.action_press(&"move_forward")
		else: Input.action_release(&"move_forward")
		if step[3]: Input.action_press(&"sprint")
		else: Input.action_release(&"sprint")
		for f: int in step[1]:
			await process_frame
			if f == 25 and step[0] in ["idle", "sprint"]:
				_dump = true
			if f % 5 == 0:
				print("%s %02d hem %.1f collar %.1f speed %.2f" % [step[0], f, _hem, _collar, _player.velocity.length()])
			if step[0] in ["walk", "sprint", "stop"] and f in [3, 20, 41]:
				for v: Array in [["side", 90.0], ["front", 20.0], ["back", 200.0]]:
					await _shot("%s_%02d_%s" % [step[0], f, v[0]], v[1], 1.0, 1.5, 0)
	quit(0)


## Largest angle, degrees, any chain root of a prefix is swung off its rest relative to its parent.
func _swing(sk: Skeleton3D, prefix: String) -> float:
	var worst: float = 0.0
	for b: int in sk.get_bone_count():
		var n: String = sk.get_bone_name(b)
		if n.begins_with(prefix):
			var q: Quaternion = sk.get_bone_pose_rotation(b)
			var r: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
			worst = maxf(worst, rad_to_deg(q.angle_to(r)))
	return worst


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
	print("[springs] ", shot_name)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

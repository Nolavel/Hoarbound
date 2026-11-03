extends SceneTree

## The searchlight in Henry's hand on a bare stage: close-ups of the grip from round the hand, and the numbers
## that say whether the fist closes on the carry handle (palm to handle, finger tips round it, beam vs head).
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_searchlight_grip.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const ITEM: String = "res://data/items/searchlight.tres"

var _out: String = "user://shots/searchlight_grip"
var _player: CharacterBody3D
var _camera: Camera3D


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
	await _frames(40)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var inventory := _player.get_node(^"InventoryComponent") as InventoryComponent
	inventory.try_add(load(ITEM) as ItemResource)
	var held := _player.get_node(^"HeldItemComponent") as HeldItemComponent
	if not held.present_owned(&"searchlight"):
		push_error("grip: could not hold the searchlight")
		quit(1)
		return
	_camera = Camera3D.new()
	_camera.fov = 30.0
	root.add_child(_camera)
	_camera.make_current()
	await _frames(30)
	## Modifier poses (the hand reach) are final only while the skeleton reports its update.
	var rig: Skeleton3D = (_player.get_node(^"HenryUALVisual") as HenryUALAnimation).skeleton
	rig.skeleton_updated.connect(_report.bind(held, "rest"), CONNECT_ONE_SHOT)
	await _frames(2)
	for view: Array in [["side", 90.0], ["front", 0.0], ["top", -1.0], ["back_q", 140.0], ["below", -2.0]]:
		await _shot(held, "grip_" + view[0], view[1])
	_camera.fov = 40.0
	await _body_shot("body_front_q", 30.0)
	await _body_shot("body_side", 90.0)
	quit(0)


## The carry handle in the hand's own frame (along the fingers' bones, across index to pinky, out of the palm),
## how far each finger tip lies from the handle's axis, and the beam against the head's facing.
func _report(held: HeldItemComponent, label: String) -> void:
	var prop := held.get_held_prop() as HeldSearchlight
	var visual := _player.get_node(^"HenryUALVisual") as HenryUALAnimation
	var rig: Skeleton3D = visual.skeleton
	var left: bool = visual.get_held_prop() == prop
	var s: String = "l" if left else "r"
	var anchor := prop.find_child("GripAnchor", true, false) as Node3D
	var grip: Vector3 = anchor.global_position
	var wrist: Vector3 = _bone(rig, "hand_" + s)
	var along: Vector3 = (_bone(rig, "middle_01_" + s) - wrist).normalized()
	var across: Vector3 = (_bone(rig, "pinky_01_" + s) - _bone(rig, "index_01_" + s)).normalized()
	var palm_n: Vector3 = (_bone(rig, "middle_01_" + s) - wrist).cross(_bone(rig, "index_01_" + s) - _bone(rig, "pinky_01_" + s)).normalized() * (-1.0 if left else 1.0)
	var d: Vector3 = grip - wrist
	print("[grip] %s hand %s: handle from wrist along %.0f mm, across %.0f mm, out of palm %.0f mm; knuckle span %.0f mm" % [label, s,
		d.dot(along) * 1000.0, d.dot(across) * 1000.0, d.dot(palm_n) * 1000.0, (_bone(rig, "middle_01_" + s) - wrist).length() * 1000.0])
	for axis: Array in [["x", anchor.global_basis.x], ["y", anchor.global_basis.y], ["z", anchor.global_basis.z]]:
		var v: Vector3 = (axis[1] as Vector3).normalized()
		print("[grip]   anchor %s: along %.2f across %.2f palm %.2f" % [axis[0], v.dot(along), v.dot(across), v.dot(palm_n)])
	var line: String = "[grip]   tips from the handle centre:"
	for finger: String in ["thumb", "index", "middle", "ring", "pinky"]:
		var tip: Vector3 = _bone(rig, "%s_03_%s" % [finger, s]) - grip
		line += " %s (%.0f, %.0f, %.0f)" % [finger, tip.dot(along) * 1000.0, tip.dot(across) * 1000.0, tip.dot(palm_n) * 1000.0]
	print(line)
	var head: int = rig.find_bone(&"Head")
	var head_basis: Basis = rig.global_basis * rig.get_bone_global_pose(head).basis
	var facing: String = ""
	for axis: Array in [["+x", Vector3.RIGHT], ["+y", Vector3.UP], ["+z", Vector3.BACK], ["-z", Vector3.FORWARD]]:
		facing += " %s:%.0f" % [axis[0], rad_to_deg(prop.direction.angle_to((head_basis * (axis[1] as Vector3)).normalized()))]
	print("[grip]   beam %s, to body +Z %.0f deg, to head axes%s" % [prop.direction, rad_to_deg(prop.direction.angle_to(visual.global_basis.z)), facing])


func _bone(rig: Skeleton3D, name: String) -> Vector3:
	var b: int = rig.find_bone(name)
	return rig.global_transform * rig.get_bone_global_pose(b).origin if b >= 0 else Vector3.ZERO


## Close on the fist: `yaw` degrees round it about world up (-1: from above, -2: from below).
func _shot(held: HeldItemComponent, shot_name: String, yaw: float) -> void:
	await _frames(3)
	var target: Vector3 = held.get_held_prop().global_position
	var forward: Vector3 = (_player.get_node(^"HenryUALVisual") as Node3D).global_basis.z
	var dir: Vector3
	if yaw == -1.0:
		dir = Vector3.UP + forward * 0.3
	elif yaw == -2.0:
		dir = Vector3.DOWN * 0.7 + forward
	else:
		dir = forward.rotated(Vector3.UP, deg_to_rad(yaw))
	_camera.global_position = target + dir.normalized() * 0.55
	_camera.look_at(target, Vector3.UP if absf(dir.normalized().y) < 0.95 else forward)
	await _frames(2)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])


func _body_shot(shot_name: String, yaw: float) -> void:
	var forward: Vector3 = (_player.get_node(^"HenryUALVisual") as Node3D).global_basis.z
	var target: Vector3 = _player.global_position + Vector3.UP * 0.35
	_camera.global_position = target + forward.rotated(Vector3.UP, deg_to_rad(yaw)) * 2.4 + Vector3.UP * 0.2
	_camera.look_at(target, Vector3.UP)
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

extends SceneTree

## Shelter doorway (#170), now the 727 door in Key West Reality: entry, middle and exit frames of a
## straight pass, a 35-degree approach, and a stop in the door with the mouse turned aside.
## Run: xvfb-run godot --path . --rendering-driver vulkan --windowed --resolution 960x540 --fixed-fps 60 --script res://tools/runtime/capture_tps_doorway.gd -- <label>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_ROOT: String = "user://shots/tps_doorway"
## Signed distance past the door plane, inward positive, for each frame.
const MOMENTS: Array = [["entry", -0.8], ["middle", 0.0], ["exit", 0.8]]
const MOUSE_SENSITIVITY: float = 0.003


## Runs last in each frame, after every _process.
class FrameProbe extends Node:
	signal frame_done

	func _init() -> void:
		process_priority = 4096

	func _process(_delta: float) -> void:
		frame_done.emit()


var _label: String = "run"
var _scene: Node
var _player: CharacterBody3D
var _cam: Camera3D
var _probe: FrameProbe
var _door: Vector3
var _inward: Vector3
var _dir: String
var _log: PackedStringArray = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_label = args[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_probe = FrameProbe.new()
	root.add_child(_probe)
	_run.call_deferred()


func _run() -> void:
	await _frames(120)
	_player = _scene.find_child("Player", true, false) as CharacterBody3D
	_cam = _scene.find_child("PlayerCamera", true, false) as Camera3D
	var zone := _scene.find_child("ShelterZone", true, false) as Node3D
	var breach := zone.find_child("Door", true, false) as Node3D
	var leaf: Node3D = null
	for node: Node in get_nodes_in_group(&"hinged_doors"):
		if (node as Node3D).global_position.distance_to(breach.global_position) < 1.0:
			leaf = node as Node3D
			leaf.call(&"load_door_save_data", {"latched": false, "angle_deg": float(leaf.get("open_angle_deg"))})
	if not await CaptureWorldSupport.wait_streamed(self, _scene, _player, Vector2(breach.global_position.x, breach.global_position.z)):
		push_warning("tps doorway: the door's chunk did not stream in")
	_door = _floor_point(breach.global_position)
	_inward = _inward_axis(leaf if leaf != null else breach, zone)
	_dir = ProjectSettings.globalize_path(OUT_ROOT.path_join(_label))
	DirAccess.make_dir_recursive_absolute(_dir)
	RenderingServer.render_loop_enabled = false
	await _pass("straight", _inward)
	await _pass("angled", _inward.rotated(Vector3.UP, deg_to_rad(35.0)))
	await _look_aside()
	FileAccess.open(_dir.path_join("log.txt"), FileAccess.WRITE).store_string("\n".join(_log))
	quit(0)


## Holds W from 2.6 m out along `heading`, aimed at the door centre, and grabs
## the three moments as Henry's signed distance past the door plane crosses them.
func _pass(name: String, heading: Vector3) -> void:
	await _place(_door - heading * 2.6 / maxf(heading.dot(_inward), 0.3), heading)
	Input.action_press(&"move_forward")
	var due: Array = MOMENTS.duplicate()
	for i: int in range(600):
		await _frames(1)
		var past: float = (_player.global_position - _door).dot(_inward)
		if not due.is_empty() and past >= float(due[0][1]):
			await _shoot("%s_%s" % [name, due[0][0]])
			due.pop_front()
		if due.is_empty():
			break
	for moment: Array in due:
		await _shoot("%s_%s_never_reached" % [name, moment[0]])
	Input.action_release(&"move_forward")


## Walks into the middle of the door, stops, and turns the mouse 70 degrees aside.
func _look_aside() -> void:
	await _place(_door - _inward * 2.6, _inward)
	Input.action_press(&"move_forward")
	for i: int in range(600):
		await _frames(1)
		if (_player.global_position - _door).dot(_inward) >= 0.0:
			break
	Input.action_release(&"move_forward")
	await _frames(20)
	var px: float = deg_to_rad(70.0) / 30.0 / (MOUSE_SENSITIVITY * float(_cam.get("look_sensitivity_x")))
	for i: int in range(30):
		_mouse(px)
		await _frames(1)
		if i == 14:
			await _shoot("aside_35")
	await _frames(10)
	await _shoot("aside_70")


func _place(at: Vector3, heading: Vector3) -> void:
	Input.action_release(&"move_forward")
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	var yaw: float = atan2(-heading.x, -heading.z)
	_player.rotation.y = yaw
	_player.reset_physics_interpolation()
	_cam.call(&"set_look", yaw, -10.0)
	if _cam.has_method(&"snap_to_target"):
		_cam.call(&"snap_to_target")
	else:
		_cam.set("_has_position", false)
	await _frames(60)


## Draws three frames so the viewport is current, then saves it.
func _shoot(name: String) -> void:
	RenderingServer.render_loop_enabled = true
	await _frames(3)
	if DisplayServer.get_name() != "headless":  # headless is a dry run: the walk and the log only
		root.get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	RenderingServer.render_loop_enabled = false
	var eye: Vector3 = _eye()
	var fade: float = float(_cam.call(&"get_body_fade")) if _cam.has_method(&"get_body_fade") else 0.0
	var line: String = "%s: past door %.2f m, camera %.2f m from the eyes, body fade %.2f" % [name,
		(_player.global_position - _door).dot(_inward), _cam.global_position.distance_to(eye), fade]
	_log.append(line)
	print("[doorway] " + line)


func _mouse(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(event)


## Henry's origin standing on the floor under `at`, a point inside the opening;
## a ray from above would land on the lintel.
func _floor_point(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 6.0)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 1.0 if not hit.is_empty() else at


## The door's own axis, flat, turned toward the room; the 727 door sits in a side wall, off the zone centre.
func _inward_axis(door: Node3D, zone: Node3D) -> Vector3:
	var axis := Vector3(door.global_basis.z.x, 0.0, door.global_basis.z.z).normalized()
	return axis if (zone.global_position - door.global_position).dot(axis) >= 0.0 else -axis


func _frames(count: int) -> void:
	for i: int in range(count):
		await _probe.frame_done


## The camera's eye point; ADT's 0.69 m over the capsule centre on builds without it.
func _eye() -> Vector3:
	if _cam.has_method(&"get_eye_position"):
		return _cam.call(&"get_eye_position")
	return _player.global_position + Vector3.UP * 0.69

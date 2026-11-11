extends SceneTree

## Narrow doorway as a short traversal. A 1.2 m unmarked door is the stress case: W held
## 35 degrees off carries Henry through its centre, the camera never breaks or takes the yaw,
## a key released past the threshold still carries him clear, and a corridor is no doorway.
## Authored NarrowPassages across the doorway standard (1.45-1.60 x 2.20-2.30 m) never fade him.
## Guards the legacy guided rig (TpsCamera.direct_rig off): it stays behind that flag until the direct rig is
## accepted in play. The direct rig's own guarantees are in test_tps_camera_direct.
## Run: godot --headless --script tests/systems/test_passage_traversal.gd

const CONTROL_YAW_DEG: float = 35.0
## Doorway standard candidates: clear width and height, metres.
const STANDARD: Array = [[1.45, 2.2], [1.6, 2.3]]

var _failures: int = 0
var _player: Player
var _camera: TpsCamera
var _walls: Node3D
var _base_fov: float = 70.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_walls = Node3D.new()
	root.add_child(_walls)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_door_walls(1.2, 2.2, 0.3)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	_camera.direct_rig = false
	root.add_child(_camera)
	(_player.get_node(^"PassageTraversalComponent") as PassageTraversalComponent).carry_through = true
	await _place(Vector3(0.8, 1.0, 2.6))
	await _through_the_door()
	await _back_out()
	await _release_inside()
	for size: Array in STANDARD:
		await _authored_standard(float(size[0]), float(size[1]))
	await _corridor_is_not_a_door()
	if _failures > 0:
		push_error("passage traversal: %d check(s) failed" % _failures)
		quit(1)
		return
	print("passage traversal: all checks passed")
	quit(0)


func _through_the_door() -> void:
	_base_fov = _camera.fov
	Input.action_press(&"move_forward")
	var crossed: bool = false
	var compressed: bool = false
	var hidden: int = 0
	for i: int in range(600):
		await physics_frame
		hidden += int(_camera.is_body_hidden())
		var at: Vector3 = _player.global_position
		if not crossed and at.z <= 0.0:
			crossed = true
			_check(absf(at.x) < 0.3, "Henry crossed the door plane %.2f m off its centre" % at.x)
			## The camera body is held in the doorway's cone; the view keeps Henry in frame.
			_check(_player_on_screen(), "mid-door Henry is off the screen")
			_check(_camera.get_body_fade() < 0.35, "mid-door Henry is faded %.2f" % _camera.get_body_fade())
		## The frame is closed before the door and opens back out softly after it.
		var share: float = _camera.get_passage_blend()
		if not compressed and at.z <= 0.4:
			compressed = true
			_check(share >= 0.8, "0.4 m before the door the frame is only %.2f closed" % share)
		if at.z < -1.15:
			_check(share >= 0.3, "just past the exit the frame already snapped open (%.2f)" % share)
			break
	Input.action_release(&"move_forward")
	_check(hidden == 0, "the 1.2 m door hid Henry in %d frames" % hidden)
	_check(crossed and _player.global_position.z < -1.0,
		"W held 35 deg off the door left Henry at z=%.2f, not through" % _player.global_position.z)
	_check(is_equal_approx(_camera.get_yaw(), deg_to_rad(CONTROL_YAW_DEG)),
		"the doorway moved the control yaw to %.1f deg" % rad_to_deg(_camera.get_yaw()))
	_check(_camera.fov - _base_fov <= _camera.passage_fov_deg + _camera.recompose_fov_deg + 0.01,
		"the doorway widened the FOV by %.1f deg" % (_camera.fov - _base_fov))


## Half into the door, S held instead: Henry is carried back out the way he came.
func _back_out() -> void:
	await _place(Vector3(0.8, 1.0, 2.6))
	Input.action_press(&"move_forward")
	for i: int in range(600):
		await physics_frame
		if _player.global_position.z <= -0.3:
			break
	Input.action_release(&"move_forward")
	Input.action_press(&"move_backward")
	var stuck: int = 0
	for i: int in range(600):
		var before: Vector3 = _player.global_position
		await physics_frame
		stuck = stuck + 1 if before.distance_to(_player.global_position) < 0.002 else 0
		if _player.global_position.z > 1.2 or stuck > 30:
			break
	Input.action_release(&"move_backward")
	_check(_player.global_position.z > 1.2,
		"S held in the door left Henry at z=%.2f, not back out" % _player.global_position.z)


## W let go just past the door plane: the traversal carries Henry clear of the frame and
## stops; nothing walks him on afterwards.
func _release_inside() -> void:
	await _place(Vector3(0.0, 1.0, 2.6))
	var passage := _player.get_node(^"PassageTraversalComponent") as PassageTraversalComponent
	Input.action_press(&"move_forward")
	for i: int in range(600):
		await physics_frame
		if _player.global_position.z <= -0.05:
			break
	Input.action_release(&"move_forward")
	_check(passage.is_committed(), "past the door plane with W held, the traversal is not committed")
	for i: int in range(240):
		await physics_frame
	var z: float = _player.global_position.z
	_check(z < -0.6, "W let go in the door left Henry at z=%.2f, in the frame" % z)
	_check(z > -2.0, "the traversal walked Henry on to z=%.2f after the key was let go" % z)
	_check(not passage.is_committed(), "the traversal still carries Henry after clearing the door")


## An authored NarrowPassage over a doorway of the standard: W straight through, Henry
## never dithered, the camera never inside a wall, Henry clear of the frame at the end.
func _authored_standard(width: float, height: float) -> void:
	_clear_walls()
	_door_walls(width, height, 0.2)
	var marker := NarrowPassage.new()
	marker.clear_width = width
	marker.clear_height = height
	marker.wall_thickness = 0.2
	_walls.add_child(marker)
	await _place(Vector3(0.0, 1.0, 2.6))
	var passage := _player.get_node(^"PassageTraversalComponent") as PassageTraversalComponent
	var label: String = "%.2f x %.2f" % [width, height]
	var faded: int = 0
	var inside: int = 0
	var authored: bool = false
	Input.action_press(&"move_forward")
	for i: int in range(600):
		await physics_frame
		await process_frame
		faded += int(_camera.get_body_fade() > 0.0)
		inside += int(_inside_wall(_camera.get_camera_transform().origin))
		var info: PassageInfo = passage.get_passage()
		authored = authored or (info != null and info.authored)
		if _player.global_position.z < -2.2:
			break
	Input.action_release(&"move_forward")
	_check(authored, "%s: the authored passage was never used" % label)
	_check(faded == 0, "%s: Henry dithered in %d frames" % [label, faded])
	_check(inside == 0, "%s: camera inside a wall in %d frames" % [label, inside])
	_check(_player.global_position.z < -2.0, "%s: Henry stopped at z=%.2f" % [label, _player.global_position.z])
	marker.free()


## A 1.4 m wide, 8 m long corridor: narrow at both ends, so no traversal starts.
func _corridor_is_not_a_door() -> void:
	_clear_walls()
	_box(Vector3(-0.85, 1.5, 0.0), Vector3(0.3, 3.0, 8.0))
	_box(Vector3(0.85, 1.5, 0.0), Vector3(0.3, 3.0, 8.0))
	await _place(Vector3(0.0, 1.0, 0.0))
	var passage := _player.get_node(^"PassageTraversalComponent") as PassageTraversalComponent
	_check(not passage.is_active(), "an 8 m corridor was taken for a doorway")


func _place(at: Vector3) -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right"]:
		Input.action_release(action)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = deg_to_rad(CONTROL_YAW_DEG)
	_player.reset_physics_interpolation()
	_camera.set_look(deg_to_rad(CONTROL_YAW_DEG), -10.0)
	_camera.snap_to_target()
	for i: int in range(30):
		await physics_frame


## A wall across Z at z=0 with a doorway `width` wide and `height` high round x=0.
func _door_walls(width: float, height: float, depth: float) -> void:
	var half: float = width * 0.5
	_box(Vector3(-half - 2.5, 1.5, 0.0), Vector3(5.0, 3.0, depth))
	_box(Vector3(half + 2.5, 1.5, 0.0), Vector3(5.0, 3.0, depth))
	_box(Vector3(0.0, height + 0.4, 0.0), Vector3(width, 0.8, depth))


func _clear_walls() -> void:
	for child: Node in _walls.get_children():
		if child is StaticBody3D and child.position.y > 0.0:
			child.free()


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_walls.add_child(body)


func _player_on_screen() -> bool:
	var origin: Vector3 = _player.get_global_transform_interpolated().origin
	return _camera.is_position_in_frustum(origin) and _camera.is_position_in_frustum(_camera.get_eye_position())


func _inside_wall(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.exclude = [_player.get_rid()]
	return not root.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("passage traversal: %s" % message)

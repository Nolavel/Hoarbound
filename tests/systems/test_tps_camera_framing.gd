extends SceneTree

## Where the direct rig holds the real Henry in the frame, judged at 16:9 (headless draws a square).
## Walking in the open, along a 1.5 m corridor, in a 3.2 m room and turning on the spot there: his chest
## stands left of the centre, his body's right edge does not reach the centre, and he is drawn in full.
## He may turn see-through only with the camera jammed against him (his back on a wall).
## Run: godot --headless --fixed-fps 60 --script tests/systems/test_tps_camera_framing.gd
## ci-args: --fixed-fps 60

## Chest no further right than this share of the frame's width; the centre is 0.5.
const CHEST_MAX_X: float = 0.44
const EDGE_MAX_X: float = 0.5

var _failures: int = 0
var _player: Player
var _camera: TpsCamera
var _walls: Node3D
var _stats: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_walls = Node3D.new()
	root.add_child(_walls)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)

	await _place(Vector3(0.0, 1.0, 10.0))
	await _hold(&"move_forward", 240, 0.0)
	_end("open walk", true)

	_box(Vector3(-0.9, 1.5, 0.0), Vector3(0.3, 3.0, 30.0))
	_box(Vector3(0.9, 1.5, 0.0), Vector3(0.3, 3.0, 30.0))
	_box(Vector3(0.0, 3.0, 0.0), Vector3(3.0, 0.3, 30.0))
	await _place(Vector3(0.0, 1.0, 10.0))
	await _hold(&"move_forward", 300, 0.0)
	_end("corridor walk", false)
	await _hold(&"", 360, 1.0)
	_end("corridor turn", false)
	_clear()

	## A 3.2 x 3.2 m room, 2.6 m high.
	_box(Vector3(-1.75, 1.5, 0.0), Vector3(0.3, 3.0, 3.8))
	_box(Vector3(1.75, 1.5, 0.0), Vector3(0.3, 3.0, 3.8))
	_box(Vector3(0.0, 1.5, -1.75), Vector3(3.8, 3.0, 0.3))
	_box(Vector3(0.0, 1.5, 1.75), Vector3(3.8, 3.0, 0.3))
	_box(Vector3(0.0, 2.75, 0.0), Vector3(3.8, 0.3, 3.8))
	await _place(Vector3(0.0, 1.0, 0.0))
	await _hold(&"", 360, 1.0)
	_end("room turn", false)
	await _place(Vector3(0.0, 1.0, 0.8))
	await _hold(&"move_forward", 200, 0.0)
	_end("room walk to wall", false)

	## His back on a wall: here, and only here, he may fade; the camera still keeps out of his head.
	await _place(Vector3(0.0, 1.0, 1.2))
	await _hold(&"move_backward", 120, 0.0)
	_check(float(_stats["eye_min"]) >= _camera.body_fade_end - 0.005, "back on a wall: camera %.2f m from his eyes, in his head" % _stats["eye_min"])
	_check(float(_stats["fade_max"]) <= _camera.direct_fade_max + 0.01, "back on a wall: Henry faded to %.2f" % _stats["fade_max"])

	if _failures > 0:
		push_error("tps camera framing: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera framing: all checks passed")
	quit(0)


## Share of a 16:9 frame's width where `point` stands; under 0 or over 1 it is out of the frame.
func _frame_x(point: Vector3) -> float:
	var seen: Vector3 = _camera.global_transform.affine_inverse() * point
	if seen.z >= -0.01:
		return -1.0 if seen.x < 0.0 else 2.0
	return 0.5 + 0.5 * (seen.x / -seen.z) / (tan(deg_to_rad(_camera.fov * 0.5)) * 16.0 / 9.0)


## Right-most point of what Henry carries (the pack and what hangs on it), as a share of the frame's width.
## Rigid meshes only: a skinned mesh's bounds are its rest pose, the worn straps' are not kept. His body
## is judged by his chest instead.
func _gear_right_edge() -> float:
	var edge: float = -INF
	for node: Node in _player.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null or mesh is PackShoulderStraps or not mesh.is_visible_in_tree() or mesh.layers & _camera.body_layers == 0:
			continue
		var box: AABB = mesh.get_aabb()
		for i: int in range(8):
			var x: float = _frame_x(mesh.global_transform * box.get_endpoint(i))
			if x <= 1.5:
				edge = maxf(edge, x)
	return edge


func _sample() -> void:
	var chest: Vector3 = _camera.get_eye_position() - Vector3.UP * 0.35
	_stats["chest_max"] = maxf(_stats["chest_max"], _frame_x(chest))
	_stats["chest_min"] = minf(_stats["chest_min"], _frame_x(chest))
	_stats["edge_max"] = maxf(_stats["edge_max"], maxf(_frame_x(chest + _camera.global_basis.x * 0.25), _gear_right_edge()))
	_stats["fade_max"] = maxf(_stats["fade_max"], _camera.get_body_fade())
	_stats["eye_min"] = minf(_stats["eye_min"], _camera.global_position.distance_to(_camera.get_eye_position()))


## Walking or standing with room behind: left of centre, in frame, drawn in full. `steady` scenes (walking
## away from the camera) also keep him and his gear clear of the centre; turned on the spot he is seen from
## the side and a wall may bring the camera round closer.
func _end(label: String, steady: bool) -> void:
	_check(float(_stats["chest_max"]) <= CHEST_MAX_X, "%s: his chest reached %.2f of the frame's width" % [label, _stats["chest_max"]])
	_check(float(_stats["chest_min"]) >= 0.0, "%s: he left the frame on the left (%.2f)" % [label, _stats["chest_min"]])
	_check(float(_stats["fade_max"]) < 0.05, "%s: Henry is %.0f %% see-through" % [label, float(_stats["fade_max"]) * 100.0])
	if steady:
		_check(float(_stats["edge_max"]) <= EDGE_MAX_X, "%s: his body covers the centre (right edge at %.2f)" % [label, _stats["edge_max"]])
	print("tps camera framing: %s chest %.2f..%.2f, edge %.2f, fade %.2f" % [label, _stats["chest_min"], _stats["chest_max"], _stats["edge_max"], _stats["fade_max"]])


func _hold(action: StringName, frames: int, turn_deg: float) -> void:
	_stats = {"chest_max": -INF, "chest_min": INF, "edge_max": -INF, "fade_max": 0.0, "eye_min": INF}
	if action != &"":
		Input.action_press(action)
	var yaw: float = _camera.get_yaw()
	for i: int in range(frames):
		await process_frame
		if turn_deg != 0.0:
			yaw += deg_to_rad(turn_deg)
			_camera.set_look(yaw, -10.0)
		## The first second is the rig settling from its snap.
		if i >= 60 or turn_deg != 0.0:
			_sample()
	if action != &"":
		Input.action_release(action)


func _place(at: Vector3) -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right"]:
		Input.action_release(action)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	_player.reset_physics_interpolation()
	_camera.set_look(0.0, -10.0)
	_camera.snap_to_target()
	for i: int in range(90):
		await physics_frame


func _clear() -> void:
	for child: Node in _walls.get_children():
		if child.position.y > 0.0:
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


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera framing: %s" % message)

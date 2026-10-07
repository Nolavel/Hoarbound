extends SceneTree

## With Motion Matching on, a held light no longer hands Henry's whole body to the
## AnimationTree: matching walks him and the socket arm keeps the tree's raised
## held pose. Run: godot --headless --script tests/systems/test_motion_matching_hold_layer.gd

var _failures: int = 0
var _player: Player
var _locomotion: MotionMatchingLocomotion


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	_locomotion = _player.get_node(^"MotionMatchingLocomotion") as MotionMatchingLocomotion
	_locomotion.enabled = true
	root.add_child(_player)
	_player.rotation = Vector3.ZERO
	for _i: int in range(30):
		await physics_frame
	if not _locomotion.get_state().begins_with("ready"):
		print("motion matching hold layer: skipped (%s)" % _locomotion.get_state())
		quit(0)
		return

	var bare := await _walk(false)
	var held := await _walk(true)
	print("motion matching hold layer: bare hand %.2f m, weight %.2f; held hand %.2f m, weight %.2f" % [bare[0], bare[1], held[0], held[1]])
	_check(held[1] > 0.9, "a held light hands the body back to the tree (weight %.2f)" % held[1])
	_check(held[0] > bare[0] + 0.15, "the held arm is not raised over matched walking")
	if _failures > 0:
		push_error("motion matching hold layer: %d check(s) failed" % _failures)
		quit(1)
		return
	print("motion matching hold layer: all checks passed")
	quit(0)


## Walks 2 s and returns [lowest socket-hand height above the floor over the last
## second, mean matching weight over that second].
func _walk(with_prop: bool) -> Array:
	var visual := _player.animation_component
	if with_prop:
		visual.hold_in_hand(Node3D.new())
	else:
		var prop := visual.release_hand()
		if prop != null:
			prop.queue_free()
	_player.global_position = Vector3(0.0, 1.0, 50.0 if with_prop else 0.0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	for _i: int in range(60):
		await physics_frame
	var skeleton := visual.skeleton
	var hand := skeleton.find_bone(visual.hand_bone)
	Input.action_press(&"move_forward")
	var lowest := INF
	var weight := 0.0
	var samples := 0
	for tick: int in range(120):
		await physics_frame
		if tick >= 60:
			var height: float = (skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin).y \
				- (_player.global_position.y - 1.0)
			lowest = minf(lowest, height)
			weight += _locomotion.get_weight()
			samples += 1
	Input.action_release(&"move_forward")
	return [lowest, weight / maxf(float(samples), 1.0)]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("motion matching hold layer: " + message)

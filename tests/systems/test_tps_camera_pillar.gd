extends SceneTree

## The direct rig turning past things that stand on its boom. A 0.4 m pillar: the camera dips in front of it
## and comes back out, without a jump, without standing in it and without turning it see-through.
## A 0.1 m post: the camera does not move for it; the post is faded instead.
## Run: godot --headless --script tests/systems/test_tps_camera_pillar.gd

const SWEEP_DEG: float = 90.0
const DEG_PER_FRAME: float = 1.0
const SETTLE_FRAMES: int = 90
## Behind Henry, who looks down -Z.
const PROP_DISTANCE: float = 1.3
## Most the camera may move against Henry in one frame; the turn itself is 0.04 m of it.
const MAX_STEP: float = 0.2

var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _prop: StaticBody3D
var _stage: int = 0
var _yaw_deg: float = -SWEEP_DEG
var _last: Vector3 = Vector3.INF
var _worst_step: float = 0.0
var _shortest: float = INF
var _faded_frames: int = 0
var _inside_frames: int = 0
var _full: float = 0.0


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		_place_prop(0.4)
	elif _frame == SETTLE_FRAMES:
		_full = _camera.global_position.distance_to(_camera.get_eye_position())
	elif _frame > SETTLE_FRAMES:
		_sample()
		_yaw_deg += DEG_PER_FRAME
		_camera.set_look(deg_to_rad(_yaw_deg), -10.0)
		if _yaw_deg > SWEEP_DEG + 30.0:
			_end_stage()
	return false


func _build() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 1.0
	_player.add_child(shape)
	root.add_child(_player)
	_camera = TpsCamera.new()
	_camera.player = _player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(deg_to_rad(_yaw_deg), -10.0)


func _place_prop(thickness: float) -> void:
	if _prop != null:
		_prop.free()
	_prop = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(thickness, 3.0, thickness)
	shape.shape = box
	_prop.add_child(shape)
	_prop.position = Vector3(0.0, 1.5, PROP_DISTANCE)
	root.add_child(_prop)


func _sample() -> void:
	var at: Vector3 = _camera.global_position
	var rel: Vector3 = at - _player.global_position
	if _last != Vector3.INF:
		_worst_step = maxf(_worst_step, rel.distance_to(_last))
	_last = rel
	_shortest = minf(_shortest, at.distance_to(_camera.get_eye_position()))
	_faded_frames += int(_camera.get_probe().passed.has(_prop.get_instance_id()))
	var half: float = ((_prop.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.x * 0.5
	_inside_frames += int(absf(at.x) < half and absf(at.z - PROP_DISTANCE) < half)


func _end_stage() -> void:
	var back_out: float = _camera.global_position.distance_to(_camera.get_eye_position())
	if _stage == 0:
		_check(_faded_frames == 0, "the 0.4 m pillar was made see-through in %d frames" % _faded_frames)
		_check(_inside_frames == 0, "the camera stood in the pillar in %d frames" % _inside_frames)
		_check(_shortest < PROP_DISTANCE, "the camera never came in front of the pillar (nearest %.2f m)" % _shortest)
		_check(_worst_step <= MAX_STEP, "the camera jumped %.2f m in a frame at the pillar" % _worst_step)
		_check(back_out > _full - 0.1, "past the pillar the boom stayed at %.2f m of %.2f" % [back_out, _full])
		print("tps camera pillar: dipped to %.2f m of %.2f, largest step %.2f m" % [_shortest, _full, _worst_step])
		_stage = 1
		_place_prop(0.1)
		_yaw_deg = -SWEEP_DEG
		_camera.set_look(deg_to_rad(_yaw_deg), -10.0)
		_frame = 1
		_last = Vector3.INF
		_worst_step = 0.0
		_shortest = INF
		_faded_frames = 0
		return
	_check(_shortest > _full - 0.15, "a 0.1 m post pulled the camera in to %.2f m" % _shortest)
	_check(_faded_frames > 0, "the post on the boom was never faded")
	if _failures > 0:
		push_error("tps camera pillar: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera pillar: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera pillar: %s" % message)

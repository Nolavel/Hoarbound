extends SceneTree

## Henry walks with the pack on: ArmStrapClearance keeps his upper arms off the straps without making them
## twitch. The drawn hands (after every modifier) must move as smoothly as the walk clip itself: no velocity
## flip-back within two frames, and mean acceleration within 1.5x of the clip's own.
## Run: godot --headless --fixed-fps 30 --script tests/systems/test_arm_strap_smooth.gd
## ci-args: --fixed-fps 30

const WALK_FRAMES: int = 240
const SKIP_FRAMES: int = 60
const BONES: PackedStringArray = ["hand_l", "hand_r"]

var _failures: int = 0
var _player: Player
var _skel: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	var camera := (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	camera.player = _player
	root.add_child(camera)
	_skel = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var clearance := _skel.get_node_or_null(^"ArmStrapClearance") as ArmStrapClearance
	if clearance == null:
		_finish("Henry has no ArmStrapClearance")
		return
	var reference: Array = await _walk(Vector3(0.0, 1.0, 0.0), false, clearance)
	var live: Array = await _walk(Vector3(20.0, 1.0, 0.0), true, clearance)
	var pushed: float = 0.0
	for side: int in 2:
		pushed = maxf(pushed, clearance._turn[side])
	_check(pushed > deg_to_rad(1.0), "the straps never pushed the arms: the test proves nothing")
	for k: int in BONES.size():
		var clip: Vector2 = _roughness(reference, k)
		var drawn: Vector2 = _roughness(live, k)
		_check(drawn.y == 0.0, "%s twitched %d times" % [BONES[k], int(drawn.y)])
		_check(drawn.x <= clip.x * 1.5, "%s moves %.4f m/frame2 against the clip's %.4f" % [BONES[k], drawn.x, clip.x])
		print("arm strap smooth: %s accel %.4f (clip %.4f), twitches %d" % [BONES[k], drawn.x, clip.x, int(drawn.y)])
	_finish("")


## Hand positions against the pelvis as drawn, over a straight walk; the clearance on or off.
func _walk(at: Vector3, clearance_on: bool, clearance: ArmStrapClearance) -> Array:
	clearance.active = clearance_on
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	for i: int in range(30):
		await physics_frame
	var ids: Array[int] = []
	for bone: String in BONES:
		ids.append(_skel.find_bone(bone))
	var pelvis: int = _skel.find_bone("pelvis")
	var rows: Array = []
	var grab := func() -> void:
		var base: Transform3D = _skel.get_bone_global_pose(pelvis).affine_inverse()
		var row: Array = []
		for id: int in ids:
			row.append(base * _skel.get_bone_global_pose(id).origin)
		rows.append(row)
	_skel.skeleton_updated.connect(grab)
	Input.action_press(&"move_forward")
	for i: int in range(WALK_FRAMES):
		await process_frame
	Input.action_release(&"move_forward")
	_skel.skeleton_updated.disconnect(grab)
	return rows.slice(SKIP_FRAMES)


## Mean acceleration of bone `k` (x) and its twitches (y): velocity reversing and reversing back.
func _roughness(rows: Array, k: int) -> Vector2:
	var sum: float = 0.0
	var twitches: int = 0
	for f: int in range(3, rows.size()):
		var v2: Vector3 = rows[f][k] - rows[f - 1][k]
		var v1: Vector3 = rows[f - 1][k] - rows[f - 2][k]
		var v0: Vector3 = rows[f - 2][k] - rows[f - 3][k]
		sum += (v2 - v1).length()
		twitches += int(v2.dot(v1) < 0.0 and v1.dot(v0) < 0.0 and v1.length() > 0.003)
	return Vector2(sum / maxf(float(rows.size() - 3), 1.0), float(twitches))


func _finish(error: String) -> void:
	if error != "":
		_check(false, error)
	if _failures > 0:
		push_error("arm strap smooth: %d check(s) failed" % _failures)
		quit(1)
		return
	print("arm strap smooth: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("arm strap smooth: %s" % message)

extends SceneTree

## Backpack rig stand (#260): every rule in docs/technical/BACKPACK_RIG.md checked in numbers on
## Henry with his starting pack, standing and walking. Run before any backpack change is committed;
## renders only after it passes. Run: godot --headless --script tests/systems/test_backpack_rig.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
## Limits, metres unless named.
const END_TO_PACK_M: float = 0.005
const ANCHOR_DRIFT_M: float = 0.002
const LOOP_ON_POCKET_M: float = 0.005
const PIVOT_ON_LOOP_M: float = 0.017
const HANG_BELOW_BOTTOM_M: float = 0.0
const HANDLE_GAP_M: float = 0.005

var _failures: int = 0
var _player: CharacterBody3D
var _straps: PackShoulderStraps
var _rig: PackRig
var _pack: BackpackModel


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	_player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(30)
	_straps = _player.find_children("PackShoulderStraps", "", true, false)[0] as PackShoulderStraps
	_rig = (_player.find_children("*", "HenryUALAnimation", true, false)[0] as HenryUALAnimation).get_pack_rig()
	_pack = _rig.get_canvas()

	_check_contents()
	_check_straps_standing()
	_check_carabiners()
	_check_pockets()
	_check_top()
	await _check_walking()
	_check_hitch()

	print("test_backpack_rig: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## R1: the pack shows what its pockets hold: two loose cans, the flask in a side pocket, the mug clipped on.
func _check_contents() -> void:
	var items: Array = _pack.get(&"_items")
	var ids: Array = items.map(func(item: Dictionary) -> StringName: return item["id"])
	_report("R1 contents in the canvas", "%s" % [ids], ids.has(&"spov_can") and ids.has(&"tinned_stew") and ids.has(&"water_flask"))
	_report("R1 something clipped on", "%d" % (_pack.get(&"_hung") as Array).size(), (_pack.get(&"_hung") as Array).size() == 1)


## R2: both straps exist, mirror each other across the spine, and meet the pack at its sewn points.
func _check_straps_standing() -> void:
	var anchors: Array = _straps.get(&"_anchors")
	_report("R2 anchors per side", "%d / %d" % [(anchors[0] as Array).size(), (anchors[1] as Array).size()], (anchors[0] as Array).size() == 8 and (anchors[1] as Array).size() == 8)
	var right: Vector3 = _player.global_basis.x
	var chest: Vector3 = _player.global_position
	var a_side: float = signf(((anchors[0][1] as Node3D).global_position - chest).dot(right))
	var b_side: float = signf(((anchors[1][1] as Node3D).global_position - chest).dot(right))
	_report("R2 straps on both shoulders", "%+.0f / %+.0f" % [a_side, b_side], a_side == -b_side and a_side != 0.0)
	var mesh := _straps.mesh as ImmediateMesh
	_report("R2 strap mesh drawn", "%d surface(s)" % mesh.get_surface_count(), mesh.get_surface_count() == 1)
	for side: int in range(2):
		var first: Vector3 = (anchors[side][0] as Node3D).global_position
		var top: Vector3 = _straps.call(&"_pack_end", PackShoulderStraps.PACK_TOP, first)
		var expected: Vector3 = _rig.get_canvas_point(PackShoulderStraps.PACK_TOP * Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0), Vector3.FORWARD)
		var other: Vector3 = _rig.get_canvas_point(PackShoulderStraps.PACK_TOP * Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0), Vector3.FORWARD)
		var gap: float = minf(top.distance_to(expected), top.distance_to(other))
		_report("R2 side %d top end on the pack" % side, "%.1f mm" % (gap * 1000.0), gap < END_TO_PACK_M)


## R3: each carabiner hangs from its loop, each loop sits on its pocket's cloth as it is now.
func _check_carabiners() -> void:
	var loops: Array = _pack.get(&"_loops")
	_report("R3 loops and carabiners", "%d / %d" % [loops.size(), (_pack.get(&"_carabiners") as Array).size()], loops.size() == 2 and (_pack.get(&"_carabiners") as Array).size() == 2)
	for i: int in range(mini(loops.size(), 2)):
		var loop: Node3D = loops[i]
		var face: float = _pack.pocket_outer_x(i)
		var off: float = absf(loop.position.x - face) - 0.003
		_report("R3 loop %d on its pocket" % i, "%.1f mm off (face x %.1f cm)" % [off * 1000.0, face * 100.0], absf(off) < LOOP_ON_POCKET_M)
		## The ring passes through the loop: its pivot inside the loop's height, right beside the webbing.
		var pivot: Vector3 = _pack.get_carabiner(i).get_parent_node_3d().position
		var up: float = pivot.y - loop.position.y
		var beside: float = Vector2(pivot.x - loop.position.x, pivot.z - loop.position.z).length()
		var through: bool = absf(up) < BackpackModel.LOOP_HEIGHT_M * 0.5 and beside < PIVOT_ON_LOOP_M
		_report("R3 carabiner %d through its loop" % i, "%.1f cm up the loop, %.1f cm beside it" % [up * 100.0, beside * 100.0], through)
	var lowest: float = INF
	var to_pack: Transform3D = _pack.global_transform.affine_inverse()
	for visual: Node3D in _pack.get(&"_hung"):
		for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).mesh != null:
				var box: AABB = to_pack * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
				lowest = minf(lowest, box.position.y)
	_report("R3 clipped item not below the bottom", "%.1f cm" % (lowest * 100.0), lowest > -HANG_BELOW_BOTTOM_M)


## R4: pocket items stay out of the main cavity; R5: empty pocket lies on the wall.
func _check_pockets() -> void:
	var cavity_x: float = BackpackModel.BODY.x * 0.5 - 0.012
	for item: Dictionary in _pack.get(&"_items"):
		if String(item["slot"]).begins_with("side_"):
			var box: AABB = item["box"]
			var into: float = maxf(cavity_x - absf(box.position.x), 0.0) if box.position.x > 0.0 else maxf(cavity_x - absf(box.end.x), 0.0)
			_report("R4 %s out of the cavity" % item["id"], "%.1f cm in" % (into * 100.0), into <= 0.0)
	var empty_face: float = absf(_pack.pocket_outer_x(1))
	_report("R5 empty pocket on the wall", "outer face %.1f cm from centre (wall %.1f)" % [empty_face * 100.0, BackpackModel.BODY.x * 50.0], empty_face < BackpackModel.BODY.x * 0.5 + 0.02)


## R6: the handle stands on the canvas top; the bedroll lies on it.
func _check_top() -> void:
	var handle: Node3D = _pack.get(&"_handle")
	var top: Vector3 = _pack.canvas_point(BackpackModel.HANDLE_AT, Vector3.UP)
	_report("R6 handle on the top", "%.1f mm" % (handle.position.distance_to(top) * 1000.0), handle.position.distance_to(top) < HANDLE_GAP_M)
	var roll: Node3D = _pack.get(&"_bedroll")
	var under: float = roll.position.y - BackpackModel.BEDROLL_RADIUS_M - _pack.canvas_point(BackpackModel.BEDROLL_AT, Vector3.UP).y
	_report("R6 bedroll on the top", "%.1f mm into it" % (-under * 1000.0), under < 0.0 and under > -0.015)


## R7: walking and stopping, the body anchors ride the chest bone exactly, the pack rocks only a little.
func _check_walking() -> void:
	var anchors: Array = _straps.get(&"_anchors")
	var skeleton: Skeleton3D = _straps.get(&"_skeleton")
	var spine: int = skeleton.find_bone(&"spine_03")
	var drift: float = 0.0
	var sway: float = 0.0
	var start: Array = []
	for frame: int in range(90):
		var speed: float = 3.0 if frame < 45 else 0.0
		_player.global_position += -_player.global_basis.z * speed / 30.0
		await process_frame
		var bone: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(spine)
		var local: Array = []
		for side: int in range(2):
			for k: int in [4, 5]:
				local.append(bone.affine_inverse() * (anchors[side][k] as Node3D).global_position)
		if start.is_empty():
			start = local
		for i: int in range(local.size()):
			drift = maxf(drift, (local[i] as Vector3).distance_to(start[i]))
		var pivot: Node3D = _rig.get(&"_sway")
		sway = maxf(sway, rad_to_deg(maxf(absf(pivot.rotation.x), absf(pivot.rotation.z))))
	_report("R7 chest anchors ride the chest bone", "%.2f mm drift" % (drift * 1000.0), drift < ANCHOR_DRIFT_M)
	_report("R7 pack rocks at most %.1f deg" % PackRig.MAX_SWAY_DEG, "%.2f deg" % sway, sway <= PackRig.MAX_SWAY_DEG + 0.01)


## R8: a hitch (one 1-second frame) leaves every spring finite and the pack upright on Henry.
func _check_hitch() -> void:
	_rig.call(&"_process", 1.0)
	_pack.call(&"_process", 1.0)
	for i: int in range(2):
		_pack.get_carabiner(i).call(&"_process", 1.0)
	var sway: Vector3 = (_rig.get(&"_sway") as Node3D).rotation
	var up: Vector3 = (_player.global_basis.inverse() * _pack.global_basis.y).normalized()
	var finite: bool = sway.is_finite() and _pack.global_transform.is_finite() and _pack.get_carabiner(1).basis.is_finite()
	_report("R8 springs survive a 1 s hitch", "sway %s, finite %s" % [sway, finite], finite)
	_report("R8 pack upright on Henry after it", "up %s" % up, up.y > 0.95)


func _report(name: String, value: String, ok: bool) -> void:
	print("  %s %s: %s" % ["ok  " if ok else "FAIL", name, value])
	if not ok:
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

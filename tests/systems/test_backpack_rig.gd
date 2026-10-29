extends SceneTree

## Backpack rig stand (#260): every rule in docs/technical/BACKPACK_RIG.md checked in numbers on
## Henry with his starting pack, standing and walking. Run before any backpack change is committed;
## renders only after it passes. Run at the game's fixed step (springs and moves assume 30 fps):
## godot --headless --fixed-fps 30 --script tests/systems/test_backpack_rig.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
## Limits, metres unless named.
const END_TO_PACK_M: float = 0.005
const ANCHOR_DRIFT_M: float = 0.002
const LOOP_ON_POCKET_M: float = 0.005
const HANG_BELOW_BOTTOM_M: float = 0.02
const HANDLE_GAP_M: float = 0.005
## Least swing each hanger shows both ways (fore-aft and sideways) on starts, stops and turns, degrees.
const MIN_SWING_DEG: float = 6.0
## A hanger at rest 1.5 s after the last move hangs within this of world down, degrees.
const SETTLED_DEG: float = 5.0
## Pocket cloth over a round item: its radius off the cylinder plus lining, and the floor gap, m.
const HUG_M: float = 0.0005
const FLOOR_M: float = 0.001
## While a thermos goes in, the hem opens at least this far past it before it is seated, m.
const HEM_STRETCH_M: float = 0.005

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
	_check_pocket_hug("R10")
	await _check_insert()
	await _check_walking()
	await _check_swing()
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


## R3: pivots. Each loop is sewn to its pocket's cloth as it is now; each carabiner rests in its
## loop's lower end; the mug's handle is threaded on the carabiner's rod, hole along the rod.
func _check_carabiners() -> void:
	var loops: Array = _pack.get(&"_loops")
	_report("R3 loops and carabiners", "%d / %d" % [loops.size(), (_pack.get(&"_carabiners") as Array).size()], loops.size() == 2 and (_pack.get(&"_carabiners") as Array).size() == 2)
	for i: int in range(mini(loops.size(), 2)):
		var loop: Node3D = loops[i]
		var face: float = _pack.pocket_outer_x(i)
		var off: float = absf(loop.position.x - face)
		_report("R3 loop %d sewn on its pocket" % i, "%.1f mm off (face x %.1f cm)" % [off * 1000.0, face * 100.0], off < LOOP_ON_POCKET_M)
		var down: float = (loop.transform.basis * Vector3.DOWN).normalized().y
		_report("R3 loop %d hangs down" % i, "its run points %.0f deg below level" % rad_to_deg(asin(-down)), down < -0.7)
		var pivot: Vector3 = _pack.get_carabiner(i).get_parent_node_3d().position
		var hold: float = pivot.distance_to(_pack.loop_hold_point(i))
		_report("R3 carabiner %d in its loop's lower end" % i, "%.1f mm" % (hold * 1000.0), hold < 0.002)
	var lowest: float = INF
	var to_pack: Transform3D = _pack.global_transform.affine_inverse()
	for visual: Node3D in _pack.get(&"_hung"):
		for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).mesh != null:
				var box: AABB = to_pack * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
				lowest = minf(lowest, box.position.y)
		if visual.has_meta(&"grip"):
			var carabiner: Carabiner = _pack.get_carabiner(1)
			var rod_at: Vector3 = carabiner.get_hang_point().global_position
			var grip: Vector3 = visual.global_transform * (visual.get_meta(&"grip") as Vector3)
			_report("R3 mug handle on the rod", "%.1f mm" % (grip.distance_to(rod_at) * 1000.0), grip.distance_to(rod_at) < 0.005)
			var rod: Vector3 = (carabiner.get(&"_body") as Node3D).global_basis.x.normalized()
			var hole: Vector3 = visual.global_basis.z.normalized()
			_report("R3 rod through the handle's hole", "alignment %.2f" % absf(rod.dot(hole)), absf(rod.dot(hole)) > 0.9)
			var out: float = (to_pack * visual.global_transform * Vector3(0.0, 0.05, 0.0)).x - (to_pack * rod_at).x
			_report("R3 mug hangs out from the wall", "body %.1f cm outboard of the rod" % (out * 100.0), out > 0.0)
	_report("R3 clipped item at most %.0f cm below the bottom" % (HANG_BELOW_BOTTOM_M * 100.0), "%.1f cm" % (lowest * 100.0), lowest > -HANG_BELOW_BOTTOM_M)


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


## R10: a round item stands on its pocket's floor and the cloth shrink-wraps its cylinder (no box).
func _check_pocket_hug(rule: String) -> void:
	var state: Dictionary = _pack.pocket_state(0)
	if state.is_empty():
		_report(rule + " left pocket holds the thermos", "empty", false)
		return
	var pocket: MeshInstance3D = _pack.find_child("SidePocketLeft", true, false)
	var floor_y: float = pocket.mesh.get_aabb().position.y + BackpackModel.POCKET_LINING_M
	var gap: float = float(state["seat_bottom"]) + float(state["rise"]) - floor_y
	_report(rule + " thermos on the pocket floor", "%.1f mm above it" % (gap * 1000.0), absf(gap) < FLOOR_M)
	var radius: float = state["radius"]
	var axis := Vector2((state["seat"] as Vector3).x, (state["seat"] as Vector3).z)
	var worst: float = 0.0
	var poke: float = 0.0
	for v: Array in _pocket_vertices(pocket):
		var p: Vector3 = v[0]
		var n: Vector3 = v[1]
		if n.x > 0.5:
			continue  # the wall seam stays sewn to the pack
		var moved: Vector3 = _pack.pocket_cloth_point(0, p, n)
		var r: float = Vector2(moved.x, moved.z).distance_to(axis)
		if moved.y > float(state["bottom"]):
			poke = maxf(poke, radius - r)
		if moved.y > float(state["bottom"]) and p.y < BackpackModel.POCKET_RIM_Y - BackpackModel.HEM_BAND_M:
			worst = maxf(worst, absf(r - radius - BackpackModel.POCKET_LINING_M))
	_report(rule + " cloth hugs the cylinder", "%.2f mm off radius + lining" % (worst * 1000.0), worst < HUG_M)
	_report(rule + " cloth never inside the thermos", "%.2f mm" % (maxf(poke, 0.0) * 1000.0), poke <= 0.0)


## R11: the thermos goes into the empty pocket bottom first: the hem stretches open past it while it
## enters, the cloth below its bottom stays the empty pouch, nothing pokes through, then it hugs.
func _check_insert() -> void:
	var equipment: EquipmentComponent = _rig.get(&"_equipment")
	var id: StringName = equipment.take_from_pocket(&"pack", &"pack_side_left")
	await _frames(10)
	var empty_x: float = _pack.pocket_outer_x(0)
	equipment.stow(&"pack", &"pack_side_left", id)
	await process_frame
	var start: Dictionary = _pack.pocket_state(0)
	_report("R11 pushed in from above the rim", "rise %.1f cm, seam x %.1f cm (empty %.1f)" % [float(start.get("rise", 0.0)) * 100.0,
		_pack.pocket_outer_x(0) * 100.0, empty_x * 100.0], float(start.get("rise", 0.0)) > 0.1 and absf(_pack.pocket_outer_x(0) - empty_x) < 0.002)
	var pocket: MeshInstance3D = _pack.find_child("SidePocketLeft", true, false)
	var peak_open: float = 0.0
	var open_at_seat: float = 0.0
	var peak_drag: float = 0.0
	var lowest_open: float = 0.0
	var seated_frame: int = -1
	var poke: float = 0.0
	var funnel_off: float = 0.0
	for frame: int in range(75):
		await process_frame
		var state: Dictionary = _pack.pocket_state(0)
		if seated_frame < 0:
			peak_open = maxf(peak_open, state["hem_open"])
			if float(state["rise"]) <= 0.0:
				seated_frame = frame
				open_at_seat = peak_open
		else:
			lowest_open = minf(lowest_open, state["hem_open"])
		peak_drag = maxf(peak_drag, state["hem_drag"])
		var axis := Vector2((state["seat"] as Vector3).x, (state["seat"] as Vector3).z)
		var bottom: float = state["bottom"]
		for v: Array in _pocket_vertices(pocket):
			var p: Vector3 = v[0]
			var n: Vector3 = v[1]
			if n.x > 0.5:
				continue
			var moved: Vector3 = _pack.pocket_cloth_point(0, p, n)
			if moved.y > bottom and moved.y < bottom + float(state["height"]):
				poke = maxf(poke, float(state["radius"]) - Vector2(moved.x, moved.z).distance_to(axis))
			if float(state["rise"]) > 0.0 and p.y < bottom - BackpackModel.POCKET_FUNNEL_M:
				var flat_x: float = -BackpackModel.BODY.x * 0.5 - (BackpackModel.POCKET_FLAT_M + (-BackpackModel.BODY.x * 0.5 - p.x) * 0.08)
				funnel_off = maxf(funnel_off, absf(moved.x - flat_x))
	_report("R11 hem stretches open before it is seated", "peak %.1f mm past the thermos, seated at frame %d" % [open_at_seat * 1000.0, seated_frame],
		open_at_seat >= HEM_STRETCH_M and seated_frame > 0)
	_report("R11 friction drags the hem down while it moves", "peak %.1f mm" % (peak_drag * 1000.0), peak_drag > 0.002)
	_report("R11 cloth below the bottom is still the empty pouch", "%.2f mm off flat" % (funnel_off * 1000.0), funnel_off < 0.0005)
	_report("R11 nothing pokes through while it goes in", "%.2f mm" % (maxf(poke, 0.0) * 1000.0), poke <= 0.0)
	var end: Dictionary = _pack.pocket_state(0)
	_report("R11 then the hem closes on it", "open %.2f mm, drag %.2f mm, snapped in to %.1f mm" % [float(end["hem_open"]) * 1000.0,
		float(end["hem_drag"]) * 1000.0, lowest_open * 1000.0], absf(end["hem_open"]) < 0.0005 and absf(end["hem_drag"]) < 0.0005)
	_check_pocket_hug("R11 after")


## Rest vertices and normals of a pocket mesh, pack space (the pocket mesh sits in pack space).
func _pocket_vertices(pocket: MeshInstance3D) -> Array:
	var arrays: Array = pocket.mesh.surface_get_arrays(0)
	var out: Array = []
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in range(vertices.size()):
		out.append([vertices[i], normals[i]])
	return out


## R9: carabiners and the mug swing fore-aft and sideways on starts, stops, a sidestep and an eased
## 90 deg turn, never slam their stop, and settle to world down at rest.
func _check_swing() -> void:
	var hangers: Array[PendulumHang] = [_pack.get_carabiner(0), _pack.get_carabiner(1)]
	for visual: Node3D in _pack.get(&"_hung"):
		if visual.get_parent() is PendulumHang:
			hangers.append(visual.get_parent() as PendulumHang)
	var peak: Array[Vector2] = []
	var rest: Array[float] = []
	rest.resize(hangers.size())
	peak.resize(hangers.size())
	peak.fill(Vector2.ZERO)
	for frame: int in range(170):
		var move: Vector3 = Vector3.ZERO
		if frame < 25:
			move = -_player.global_basis.z * 3.0
		elif frame >= 50 and frame < 75:
			move = _player.global_basis.x * 2.0
		_player.global_position += move / 30.0
		if frame >= 95 and frame < 125:
			_player.rotate_y(deg_to_rad(90.0) * (cos(PI * (frame - 95) / 30.0) - cos(PI * (frame - 94) / 30.0)) * -0.5)
		await process_frame
		for i: int in range(hangers.size()):
			var down: Vector3 = -hangers[i].basis.y.normalized()
			var lean := Vector2(rad_to_deg(atan2(absf(down.z), -down.y)), rad_to_deg(atan2(absf(down.x), -down.y)))
			peak[i] = peak[i].max(lean)
			rest[i] = rad_to_deg((-hangers[i].global_basis.y).angle_to(Vector3.DOWN))
	for i: int in range(hangers.size()):
		var name: String = "carabiner %d" % i if i < 2 else "clipped item"
		_report("R9 %s swings both ways" % name, "fore-aft %.1f deg, sideways %.1f deg" % [peak[i].x, peak[i].y],
			minf(peak[i].x, peak[i].y) >= MIN_SWING_DEG)
		var cap: float = hangers[i].max_swing_deg
		_report("R9 %s never slams its %.0f deg stop" % [name, cap], "peak %.1f deg" % maxf(peak[i].x, peak[i].y), maxf(peak[i].x, peak[i].y) < cap - 1.0)
		_report("R9 %s settles at rest" % name, "%.1f deg off down" % rest[i], rest[i] < SETTLED_DEG)


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

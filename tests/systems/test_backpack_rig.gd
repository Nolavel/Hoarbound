## ci-args: --fixed-fps 30
extends SceneTree

## Backpack rig stand (#260): every rule in docs/technical/BACKPACK_RIG.md checked in numbers on
## Henry with his starting pack, standing and walking. Run before any backpack change is committed;
## renders only after it passes. Run at the game's fixed step (springs and moves assume 30 fps; the
## ci-args line makes tools/ci/run_tests.sh do the same): godot --headless --fixed-fps 30 --script <this>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
## Limits, metres unless named.
const END_TO_PACK_M: float = 0.005
const ANCHOR_DRIFT_M: float = 0.002
const LOOP_ON_POCKET_M: float = 0.005
## Whatever hangs on the pack stays this far above the ground Henry stands on, metres.
const GROUND_CLEAR_M: float = 0.3
const HANDLE_GAP_M: float = 0.005
## Least swing each hanger shows both ways (fore-aft and sideways) on starts, stops and turns, degrees.
const MIN_SWING_DEG: float = 6.0
## A hanger swings less than this in the last half second, degrees (it may rest against the pack
## or a tool in more than one pose).
const SETTLED_DEG: float = 3.0
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
	await _check_empty_pocket()
	_check_sleeves()
	_check_pocket_hug("R10")
	await _check_insert()
	await _check_walking()
	await _check_swing()
	_check_hitch()
	await _check_held_pockets()

	print("test_backpack_rig: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## R1: the pack shows what its pockets hold: two loose cans, the flask in a side pocket, the axe and
## the hammer in the right pocket's sleeves, the mug clipped on.
func _check_contents() -> void:
	var items: Array = _pack.get(&"_items")
	var ids: Array = items.map(func(item: Dictionary) -> StringName: return item["id"])
	_report("R1 contents in the canvas", "%s" % [ids], ids.has(&"spov_can") and ids.has(&"tinned_stew") and ids.has(&"water_flask") and ids.has(&"axe") and ids.has(&"hammer"))
	_report("R1 something clipped on", "%d" % (_pack.get(&"_hung") as Array).size(), (_pack.get(&"_hung") as Array).size() == 1)


## R2: both straps lie on the jacket on both shoulders, are drawn, and their top ends sit on the pack.
func _check_straps_standing() -> void:
	var rows: Array = _straps.get(&"_rows")
	_report("R2 strap rows per side", "%d / %d" % [(rows[0] as Array).size(), (rows[1] as Array).size()], (rows[0] as Array).size() > 20 and (rows[1] as Array).size() > 20)
	var right: Vector3 = _player.global_basis.x
	var chest: Vector3 = _player.global_position
	var a_side: float = signf(((_straps.worn_rows(0)[10][1] as Vector3) - chest).dot(right))
	var b_side: float = signf(((_straps.worn_rows(1)[10][1] as Vector3) - chest).dot(right))
	_report("R2 straps on both shoulders", "%+.0f / %+.0f" % [a_side, b_side], a_side == -b_side and a_side != 0.0)
	var mesh := _straps.mesh as Mesh
	_report("R2 strap mesh drawn", "%d surface(s)" % mesh.get_surface_count(), mesh.get_surface_count() == 1)
	for side: int in range(2):
		var top: Vector3 = (_straps.worn_band(side)["band"][0] as Array)[1]
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
			## At rest a body hung on a pin has its centre of mass straight under the pin.
			var com: Vector3 = visual.global_transform * (visual.get_meta(&"centre_of_mass") as Vector3)
			var off: float = Vector2(com.x - rod_at.x, com.z - rod_at.z).length()
			var sink: float = _mug_sink(visual)
			var outward: float = (to_pack.basis * (com - rod_at)).x
			var plumb: bool = off < 0.003 or sink > -(PendulumHang.CONTACT_MARGIN + 0.001)
			_report("R3 mug's centre of mass under the rod (or leaning on what it touches)", "%.1f mm off plumb (%.1f out), %.1f cm below" % [off * 1000.0, outward * 1000.0, (rod_at.y - com.y) * 100.0], plumb and com.y < rod_at.y)
			_report("R3 mug rests on the pack, not in it", "%.1f mm %s" % [absf(sink) * 1000.0, "in" if sink > 0.0 else "clear"], sink <= 0.0005)
	var ground: float = INF
	for visual: Node3D in _pack.get(&"_hung"):
		for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
			ground = minf(ground, ((mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()).position.y)
	_report("R3 clipped item clear of the ground", "%.1f cm below the pack bottom, %.2f m above the ground" % [-lowest * 100.0, ground], ground > GROUND_CLEAR_M)


## Deepest any mug vertex is inside the pack (the same surface the pendulum leans on).
func _mug_sink(visual: Node3D) -> float:
	## The pack moves on its bone after the hangers solve; they move with it, so measure in one pose.
	_pack.set(&"_to_pack", _pack.global_transform.affine_inverse())
	_pack.set(&"_from_pack_basis", _pack.global_basis)
	var sink: float = -INF
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		for v: Vector3 in (mesh as MeshInstance3D).mesh.get_faces():
			sink = maxf(sink, _pack.call(&"_pack_contact", (mesh as MeshInstance3D).global_transform * v).w)
	return sink


## R4: pocket items stay out of the main cavity; R5: empty pocket lies on the wall.
func _check_pockets() -> void:
	var cavity := AABB(Vector3(-BackpackModel.BODY.x * 0.5 + 0.012, 0.012, 0.012), BackpackModel.BODY - Vector3.ONE * 0.024)
	var to_pack: Transform3D = _pack.global_transform.affine_inverse()
	for item: Dictionary in _pack.get(&"_items"):
		if String(item["slot"]).begins_with("side_"):
			var into: float = 0.0
			for mesh: Node in (item["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
				for f: Vector3 in (mesh as MeshInstance3D).mesh.get_faces():
					var q: Vector3 = to_pack * (mesh as MeshInstance3D).global_transform * f
					if cavity.has_point(q):
						into = maxf(into, minf(q.x - cavity.position.x, cavity.end.x - q.x))
			_report("R4 %s out of the cavity" % item["id"], "%.1f cm in" % (into * 100.0), into <= 0.0)


## R6: the handle stands on the canvas top; the bedroll lies on it.
func _check_top() -> void:
	var handle: Node3D = _pack.get(&"_handle")
	var top: Vector3 = _pack.canvas_point(BackpackModel.HANDLE_AT, Vector3.UP)
	_report("R6 handle on the top", "%.1f mm" % (handle.position.distance_to(top) * 1000.0), handle.position.distance_to(top) < HANDLE_GAP_M)
	var roll: Node3D = _pack.get(&"_bedroll")
	var under: float = roll.position.y - BackpackModel.BEDROLL_RADIUS_M - _pack.canvas_point(BackpackModel.BEDROLL_AT, Vector3.UP).y
	_report("R6 bedroll on the top", "%.1f mm into it" % (-under * 1000.0), under < 0.0 and under > -0.015)


## R7: walking and stopping, the chest part of each strap rides the jacket's chest (spine_03) closely,
## the pack rocks only a little.
func _check_walking() -> void:
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
			var rows: Array = _straps.worn_rows(side)
			for k: int in [30, 34]:
				local.append(bone.affine_inverse() * (rows[k][1] as Vector3))
		if start.is_empty():
			start = local
		for i: int in range(local.size()):
			drift = maxf(drift, (local[i] as Vector3).distance_to(start[i]))
		var pivot: Node3D = _rig.get(&"_sway")
		sway = maxf(sway, rad_to_deg(maxf(absf(pivot.rotation.x), absf(pivot.rotation.z))))
	_report("R7 chest part rides the chest", "%.2f mm drift" % (drift * 1000.0), drift < ANCHOR_DRIFT_M)
	_report("R7 pack rocks at most %.1f deg" % PackRig.MAX_SWAY_DEG, "%.2f deg" % sway, sway <= PackRig.MAX_SWAY_DEG + 0.01)


## R5, R12: with both tools taken out, the empty right pocket is sewn onto the body's rounded side:
## its inner layer on the body, no cloth further off it than the fold's thickness. Then they go back.
func _check_empty_pocket() -> void:
	var equipment: EquipmentComponent = _rig.get(&"_equipment")
	var front: StringName = equipment.take_from_pocket(&"pack", &"pack_side_right_front")
	var back: StringName = equipment.take_from_pocket(&"pack", &"pack_side_right_back")
	await _frames(10)
	var empty_face: float = absf(_pack.pocket_outer_x(1))
	_report("R5 empty pocket on the wall", "outer face %.1f cm from centre (wall %.1f)" % [empty_face * 100.0, BackpackModel.BODY.x * 50.0], empty_face < BackpackModel.BODY.x * 0.5 + 0.02)
	var pocket: MeshInstance3D = _pack.find_child("SidePocketRight", true, false)
	var seam: float = 0.0
	var off: float = 0.0
	for v: Array in _pocket_vertices(pocket):
		var moved: Vector3 = _pack.pocket_cloth_point(1, v[0], v[1])
		var gap: float = absf(moved.x) - _pack.body_side_x(moved.y, moved.z)
		if (v[1] as Vector3).x < -0.5:
			seam = maxf(seam, absf(gap))
		off = maxf(off, gap)
	var fold: float = BackpackModel.POCKET_FLAT_M + BackpackModel.POCKET_HALF.x * 2.0 * BackpackModel.POCKET_FOLD_SPREAD
	_report("R12 empty pocket's seam on the body", "%.1f mm off" % (seam * 1000.0), seam < 0.001)
	_report("R12 empty pocket lies on the body", "outer layer at most %.1f mm off (fold %.1f mm)" % [off * 1000.0, fold * 1000.0], off <= fold + 0.0005)
	equipment.stow(&"pack", &"pack_side_right_front", front)
	equipment.stow(&"pack", &"pack_side_right_back", back)
	await _frames(60)


## R13: the axe and hammer hang in the right pocket's sleeves by their heads: each head sits on the
## rim, its sleeve hugs its handle (never inside it), the heads clear the pack and each other, and
## the divider runs from the body to the outer cloth between them.
func _check_sleeves() -> void:
	var pocket: MeshInstance3D = _pack.find_child("SidePocketRight", true, false)
	var boxes: Array[AABB] = []
	for sleeve: int in [1, 2]:
		var state: Dictionary = _pack.pocket_state(sleeve)
		var name: String = "front" if sleeve == 1 else "back"
		if state.is_empty() or not state["tool"]:
			_report("R13 %s sleeve holds a tool" % name, "empty", false)
			continue
		var node: Node3D = state["node"]
		var head_y: float = (node.transform * Vector3(0.0, float(node.get_meta(&"head_bottom")), 0.0)).y
		_report("R13 %s tool's head on the rim" % name, "%.1f mm above it" % ((head_y - BackpackModel.POCKET_RIM_Y) * 1000.0),
			absf(head_y - BackpackModel.POCKET_RIM_Y) < 0.003 and float(state["rise"]) <= 0.0)
		var e: Vector2 = state["ellipse"]
		var axis: Vector2 = state["axis"]
		var worst: float = 0.0
		var poke: float = 0.0
		for v: Array in _pocket_vertices(pocket):
			var p: Vector3 = v[0]
			var n: Vector3 = v[1]
			if n.x < -0.5 or BackpackModel.sleeve_at(1, p.z) != sleeve:
				continue
			var moved: Vector3 = _pack.pocket_cloth_point(1, p, n)
			var d := Vector2(moved.x, moved.y * 0.0 + moved.z) - axis
			var dir: Vector2 = d.normalized()
			var reach: float = 1.0 / (dir / e).length()
			poke = maxf(poke, reach - d.length())
			if p.y < BackpackModel.POCKET_RIM_Y - BackpackModel.HEM_BAND_M and absf(p.z - BackpackModel.SLEEVE_SPLIT_Z) > 0.012:
				var lined: float = 1.0 / (dir / (e + Vector2.ONE * BackpackModel.POCKET_LINING_M)).length()
				worst = maxf(worst, absf(d.length() - lined))
		_report("R13 %s sleeve hugs its handle" % name, "%.2f mm off section + lining" % (worst * 1000.0), worst < 0.0005)
		_report("R13 %s sleeve never inside its handle" % name, "%.2f mm" % (maxf(poke, 0.0) * 1000.0), poke <= 0.0)
		var into: float = 0.0
		var to_pack: Transform3D = _pack.global_transform.affine_inverse()
		for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
			for f: Vector3 in (mesh as MeshInstance3D).mesh.get_faces():
				var q: Vector3 = to_pack * (mesh as MeshInstance3D).global_transform * f
				if q.y > BackpackModel.POCKET_RIM_Y and q.y < BackpackModel.BODY.y and q.z > 0.0 and q.z < BackpackModel.BODY.z:
					into = maxf(into, _pack.body_side_x(q.y, q.z) - q.x)
		_report("R13 %s tool clear of the pack" % name, "%.1f mm into it" % (maxf(into, 0.0) * 1000.0), into <= 0.0005)
		boxes.append(state["node"].get_meta(&"_pack_box") if false else _pack_box(node))
	if boxes.size() == 2:
		var overlap: AABB = boxes[0].intersection(boxes[1])
		_report("R13 axe and hammer clear of each other", "%.1f cm3 shared" % (overlap.get_volume() * 1e6), overlap.get_volume() < 1e-7)
	var divider: MeshInstance3D = _pack.find_child("SleeveDivider", true, false)
	var span: AABB = divider.mesh.get_aabb() if divider != null else AABB()
	var outer: float = absf(_pack.pocket_outer_x(1))
	_report("R13 divider from the body to the outer cloth", "x %.1f..%.1f cm (outer cloth %.1f)" % [span.position.x * 100.0, span.end.x * 100.0, outer * 100.0],
		divider != null and span.position.x < BackpackModel.BODY.x * 0.5 + 0.002 and span.end.x > outer - 0.006)


func _pack_box(node: Node3D) -> AABB:
	var to_pack: Transform3D = _pack.global_transform.affine_inverse()
	var box := AABB()
	var first: bool = true
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = to_pack * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


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
				funnel_off = maxf(funnel_off, moved.distance_to(_pack.pocket_empty_point(0, p, n)))
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
	var last: Array[Vector3] = []
	for hanger: PendulumHang in hangers:
		last.append(-hanger.global_basis.y.normalized())
	var worst_sink: float = -INF
	var knocks_before: int = _pack.knock_count
	var knocks_at_rest: int = 0
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
			var now: Vector3 = -hangers[i].global_basis.y.normalized()
			if frame == 170 - 15:
				last[i] = now
				rest[i] = 0.0
				if i == 0:
					knocks_at_rest = _pack.knock_count
			elif frame > 170 - 15:
				rest[i] = maxf(rest[i], rad_to_deg(now.angle_to(last[i])))
		for visual: Node3D in _pack.get(&"_hung"):
			worst_sink = maxf(worst_sink, _mug_sink(visual))
	_report("R14 the mug knocks on the tools while Henry moves, not at rest", "%d knocks moving, %d in the last half second" % [knocks_at_rest - knocks_before, _pack.knock_count - knocks_at_rest],
		knocks_at_rest - knocks_before > 0 and _pack.knock_count == knocks_at_rest)
	_report("R9 clipped item never sinks into the pack or the tools", "deepest %.1f mm (contact margin %.0f mm: its points are a 2 cm sample)" % [worst_sink * 1000.0, PendulumHang.CONTACT_MARGIN * 1000.0],
		worst_sink <= PendulumHang.CONTACT_MARGIN)
	for i: int in range(hangers.size()):
		var name: String = "carabiner %d" % i if i < 2 else "clipped item"
		if hangers[i].hinge_axis != Vector3.ZERO:
			_report("R9 %s swings on its rod" % name, "%.1f deg (a hinge: one plane)" % maxf(peak[i].x, peak[i].y), maxf(peak[i].x, peak[i].y) >= MIN_SWING_DEG)
		else:
			_report("R9 %s swings both ways" % name, "fore-aft %.1f deg, sideways %.1f deg" % [peak[i].x, peak[i].y],
				minf(peak[i].x, peak[i].y) >= MIN_SWING_DEG)
		var cap: float = hangers[i].max_swing_deg
		_report("R9 %s never slams its %.0f deg stop" % [name, cap], "peak %.1f deg" % maxf(peak[i].x, peak[i].y), maxf(peak[i].x, peak[i].y) < cap - 1.0)
		_report("R9 %s comes to rest" % name, "%.1f deg of swing left in the last half second" % rest[i], rest[i] < SETTLED_DEG)


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


## R15: an item in hand is out of its pack pocket, so the pack does not draw it there; drawing
## another pack pocket puts it back in its own place (the pack's pockets never trade contents).
func _check_held_pockets() -> void:
	var quick := _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	var sleeve: StringName = &"pack/pack_side_right_back"
	var side: StringName = &"pack/pack_side_left"
	var in_sleeve: StringName = HeldOwnership.zone_item(equipment, sleeve)
	var in_side: StringName = HeldOwnership.zone_item(equipment, side)
	var shown := func(id: StringName) -> bool:
		return (_pack.get(&"_items") as Array).any(func(item: Dictionary) -> bool: return item["id"] == id)
	quick.draw(_zone_index(quick, sleeve))
	await _frames(3)
	_report("R15 tool drawn from its sleeve", "held from %s" % quick.get_held_source_zone(), quick.get_held_source_zone() == sleeve)
	_report("R15 the drawn tool is not also in its sleeve", "%s shown on the pack: %s" % [in_sleeve, shown.call(in_sleeve)], not shown.call(in_sleeve))
	quick.draw(_zone_index(quick, side))
	await _frames(3)
	_report("R15 the pockets keep their own items", "sleeve %s, side pocket %s" % [HeldOwnership.zone_item(equipment, sleeve), HeldOwnership.zone_item(equipment, side)],
		HeldOwnership.zone_item(equipment, sleeve) == in_sleeve and HeldOwnership.zone_item(equipment, side) == in_side)
	_report("R15 the tool is back in its sleeve", "%s shown: %s" % [in_sleeve, shown.call(in_sleeve)], shown.call(in_sleeve))
	var held_side: bool = quick.get_held_source_zone() == side
	_report("R15 the side pocket's item shows only in the hand", "held from %s, %s on the pack: %s" % [quick.get_held_source_zone(), in_side, shown.call(in_side)],
		shown.call(in_side) != held_side)


static func _zone_index(quick: QuickAccessComponent, path: StringName) -> int:
	var zones: Array[Dictionary] = quick.hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		if zones[i]["path"] == path:
			return i
	return -1


func _report(name: String, value: String, ok: bool) -> void:
	print("  %s %s: %s" % ["ok  " if ok else "FAIL", name, value])
	if not ok:
		_failures += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

extends SceneTree

## The slotless compartment (3D inventory stage 0), the pack hanging upright as Henry holds it open: the mug,
## thermos, frying pan, SPoV tin, hammer and axe go in high and fall to the bottom. The canvas must stay over
## everything: each item's points are checked against the canvas as the shader draws it (rest surface, bulge
## over the items, slack sagging onto them), not against the physics walls. Then they settle, the boards are refused, and
## closed and carried off the items keep their poses and reopened they stay calm.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/systems/test_pack_interior.gd [-- <drop seed>]

const ITEMS: Array[StringName] = [&"axe", &"frying_pan", &"hammer", &"water_flask", &"spov_can", &"mug"]
## The cloth may sit this far inside a point of an item (the canvas grid is a few centimetres coarse), metres.
const CLOTH_SLOP_M: float = 0.002
const SETTLE_LIMIT_S: float = 4.0
## backpack_canvas.gdshader soft_m: the bulge feathers over this distance.
const SOFT_M: float = 0.03

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	pack.global_position = Vector3(0.0, 1.0, 0.0)
	pack.set_open(true)
	var interior := PackInterior.new()
	pack.add_child(interior)
	interior.setup(pack)
	interior.set_open(true)
	var refusals: Dictionary = {}
	interior.refused.connect(func(id: StringName, why: StringName) -> void: refusals[id] = why)
	var rng := RandomNumberGenerator.new()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	rng.seed = int(args[0]) if not args.is_empty() else 7
	var worst_cloth: float = -1.0
	for id: StringName in ITEMS:
		var at := Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.34, 0.4), rng.randf_range(0.09, 0.13))
		_check(interior.add(id, at), "%s was refused (%s)" % [id, refusals.get(id, "")])
		for _f: int in range(15):
			await process_frame
			worst_cloth = maxf(worst_cloth, _worst_past_cloth(interior))
	_check(not interior.add(&"boards"), "the boards went in")
	_check(refusals.get(&"boards", &"") == PackInterior.TOO_BIG, "the boards were not refused as too big")
	_check(interior.refusal_for(AABB(Vector3.ZERO, Vector3(0.09, 0.09, 1.2))) == PackInterior.TOO_BIG, "a 1.2 m pole fits the mouth")
	var left: float = interior.room_left()
	var flat := Vector2(0.3, 0.2)
	_check(interior.refusal_for(AABB(Vector3.ZERO, Vector3(flat.x, left * 1.1 / (flat.x * flat.y), flat.y))) == PackInterior.NO_ROOM,
		"a box bigger than the room left went in")
	var waited: float = 0.0
	var frames: int = 0
	var started_us: int = Time.get_ticks_usec()
	while not interior.is_settled() and waited < SETTLE_LIMIT_S:
		await process_frame
		waited += 1.0 / 60.0
		frames += 1
		worst_cloth = maxf(worst_cloth, _worst_past_cloth(interior))
	var frame_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0 / maxf(frames, 1)
	print("pack interior: settled in %.2f s, %.2f ms per headless frame, room left %.1f l" % [waited, frame_ms, left * 1000.0])
	for i: int in interior.items.size():
		if float(interior.items[i]["still_s"]) < PackInterior.SETTLE_S:
			print("pack interior:   restless %s v %.3f" % [interior.items[i]["id"], interior.speed(i)])
	_check(interior.is_settled(), "the items did not settle within %.0f s" % SETTLE_LIMIT_S)
	print("pack interior: deepest past the cloth while falling and settling %.1f mm (negative: clear of it)" % (worst_cloth * 1000.0))
	_check(worst_cloth <= CLOTH_SLOP_M, "an item came through the canvas (%.1f mm)" % (worst_cloth * 1000.0))
	## Closed and carried off: poses kept; reopened elsewhere it stays calm and inside.
	var kept: Array[AABB] = interior.boxes()
	interior.set_open(false)
	pack.set_open(false)
	pack.global_transform = Transform3D(Basis(Vector3.UP, 1.2), Vector3(3.0, 1.0, -2.0))
	for _f: int in range(30):
		await physics_frame
	var moved: float = 0.0
	var now: Array[AABB] = interior.boxes()
	for i: int in kept.size():
		moved = maxf(moved, kept[i].get_center().distance_to(now[i].get_center()))
	_check(moved < 0.002, "closed items moved inside the carried pack (%.1f mm)" % (moved * 1000.0))
	pack.set_open(true)
	interior.set_open(true)
	var fastest: float = 0.0
	var reopened_cloth: float = -1.0
	for _f: int in range(60):
		await process_frame
		for i: int in interior.items.size():
			fastest = maxf(fastest, interior.speed(i))
		reopened_cloth = maxf(reopened_cloth, _worst_past_cloth(interior))
	print("pack interior: fastest item after reopening %.2f m/s, deepest past the cloth %.1f mm" % [fastest, reopened_cloth * 1000.0])
	_check(fastest < 0.6, "items flew about on reopening (%.2f m/s)" % fastest)
	_check(reopened_cloth <= CLOTH_SLOP_M, "an item is through the canvas after reopening (%.1f mm)" % (reopened_cloth * 1000.0))
	print("pack interior: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Deepest any drawn item's point lies past the canvas's inner face as backpack_canvas.gdshader draws it over
## the outlines it was handed, metres.
func _worst_past_cloth(interior: PackInterior) -> float:
	var proxies: Array[AABB] = interior.drawn_boxes()
	if proxies.size() != interior.items.size():
		return -1.0
	var worst: float = -INF
	for i: int in interior.items.size():
		for q: Vector3 in interior.support_points(i, true):
			worst = maxf(worst, _past_cloth(q, proxies, interior.model.get_fill()))
	return worst


func _past_cloth(q: Vector3, proxies: Array[AABB], fill: float) -> float:
	## The canvas's rest vertex nearest q, on the rounded box the shell and panel are built on.
	var c := Vector3(0.0, BackpackModel.BODY.y * 0.5, BackpackModel.BODY.z * 0.5)
	var r: float = BackpackModel.ROUND_M
	var core: Vector3 = BackpackModel.BODY * 0.5 - Vector3.ONE * r
	var d: Vector3 = q - c
	var clamped: Vector3 = d.clamp(-core, core)
	var n: Vector3 = d - clamped
	if n.length() < 0.00001:
		var axis: int = (d.abs() - core).max_axis_index()
		n = Vector3.ZERO
		n[axis] = signf(d[axis])
	n = n.normalized()
	var p: Vector3 = c + clamped + n * r
	## The shader's bulge over the item proxies, capped, and the empty slump.
	var push: float = 0.0
	for box: AABB in proxies:
		var dd: float = _box_distance(p, box) - BackpackModel.CANVAS_LINING_M
		push = maxf(push, smoothstep(SOFT_M, -SOFT_M, dd) * maxf(SOFT_M - dd, 0.0))
	push = minf(push, BackpackModel.CANVAS_STRETCH_M)
	var clear: float = 1.0
	for box: AABB in proxies:
		clear = minf(clear, _box_distance(p, box) - BackpackModel.CANVAS_LINING_M)
	var height: float = BackpackModel.BODY.y
	var high: float = smoothstep(height * 0.45, height, p.y)
	var slump: Vector3 = (Vector3(0.0, -BackpackModel.SLUMP_TOP_M * high, 0.0) - n * BackpackModel.SLUMP_WALL_M * smoothstep(0.1, 0.4, p.y / height)) * (1.0 - clampf(fill, 0.0, 1.0))
	var sag: float = slump.length()
	if sag > 0.0:
		slump *= minf(sag, maxf(clear, 0.0)) / sag
	var cloth: Vector3 = p + n * push + slump
	return (q - (cloth - n * BackpackModel.CANVAS_LINING_M)).dot(n)


static func _box_distance(p: Vector3, box: AABB) -> float:
	var q: Vector3 = (p - box.get_center()).abs() - box.size * 0.5
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pack interior: %s" % message)

extends SceneTree

## The slotless compartment (3D inventory stage 0): with the pack open face up, a dozen items dropped through the
## mouth settle on the back wall inside the walls (never through them), quickly and cheaply; a plank or a log too
## long for the mouth is refused; closed and carried off, the items keep their poses, and reopened they settle
## again without flying about.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/systems/test_pack_interior.gd [-- <drop seed>]

const ITEMS: Array[StringName] = [&"tinned_stew", &"tinned_stew", &"spov_can", &"water_flask", &"lighter", &"knife",
	&"stone", &"stone", &"tinned_pineapple", &"work_gloves", &"mug", &"tinder"]
## A stored shape may poke this far past the walls (solver slop), metres.
const WALL_SLOP_M: float = 0.001
const SETTLE_LIMIT_S: float = 4.0

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	## Open face up: the back wall is the floor, the mouth looks at the sky.
	pack.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 1.0, 0.0))
	var interior := PackInterior.new()
	pack.add_child(interior)
	interior.setup(pack)
	interior.set_open(true)
	var refusals: Dictionary = {}
	interior.refused.connect(func(id: StringName, why: StringName) -> void: refusals[id] = why)
	var rng := RandomNumberGenerator.new()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	rng.seed = int(args[0]) if not args.is_empty() else 7
	for i: int in ITEMS.size():
		var at := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.1, 0.42), BackpackModel.BODY.z + 0.06 + 0.05 * float(i % 3))
		_check(interior.add(ITEMS[i], at), "%s was refused (%s)" % [ITEMS[i], refusals.get(ITEMS[i], "")])
		for _f: int in range(6):
			await physics_frame
	_check(not interior.add(&"boards"), "the boards went in")
	_check(refusals.get(&"boards", &"") == PackInterior.TOO_BIG, "the boards were not refused as too big")
	_check(interior.refusal_for(AABB(Vector3.ZERO, Vector3(0.09, 0.09, 1.2))) == PackInterior.TOO_BIG, "a 1.2 m pole fits the mouth")
	var left: float = interior.room_left()
	print("pack interior: room left %.1f l" % (left * 1000.0))
	## Flat boxes that pass the mouth, one just over the room left and one well under it.
	var flat := Vector2(0.36, 0.22)
	_check(interior.refusal_for(AABB(Vector3.ZERO, Vector3(flat.x, left * 1.1 / (flat.x * flat.y), flat.y))) == PackInterior.NO_ROOM,
		"a box bigger than the room left went in")
	_check(interior.refusal_for(AABB(Vector3.ZERO, Vector3(flat.x, left * 0.5 / (flat.x * flat.y), flat.y))) == &"",
		"a box half the room left was refused")
	var waited: float = 0.0
	var frames: int = 0
	var started_us: int = Time.get_ticks_usec()
	while not interior.is_settled() and waited < SETTLE_LIMIT_S:
		await physics_frame
		waited += 1.0 / 60.0
		frames += 1
	var frame_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0 / maxf(frames, 1)
	## Headless, a frame is almost all physics: the whole frame's wall time is the honest upper bound.
	print("pack interior: settled in %.2f s, %.2f ms per headless frame" % [waited, frame_ms])
	for i: int in interior.items.size():
		if float(interior.items[i]["still_s"]) < PackInterior.SETTLE_S:
			print("pack interior:   restless %s v %.3f" % [interior.items[i]["id"], interior.speed(i)])
	_check(interior.is_settled(), "the items did not settle within %.0f s" % SETTLE_LIMIT_S)
	_check_inside(interior, "after settling")
	## Closed and carried off: poses kept; reopened elsewhere it settles calmly.
	var kept: Array[AABB] = interior.boxes()
	interior.set_open(false)
	pack.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, 1.2), Vector3(3.0, 1.0, -2.0))
	for _f: int in range(30):
		await physics_frame
	var moved: float = 0.0
	var now: Array[AABB] = interior.boxes()
	for i: int in kept.size():
		moved = maxf(moved, kept[i].get_center().distance_to(now[i].get_center()))
	_check(moved < 0.002, "closed items moved inside the carried pack (%.1f mm)" % (moved * 1000.0))
	interior.set_open(true)
	var fastest: float = 0.0
	for _f: int in range(60):
		await physics_frame
		for i: int in interior.items.size():
			fastest = maxf(fastest, interior.speed(i))
	print("pack interior: fastest item after reopening %.2f m/s" % fastest)
	_check(fastest < 0.6, "items flew about on reopening (%.2f m/s)" % fastest)
	_check_inside(interior, "after reopening")
	print("pack interior: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_inside(interior: PackInterior, when: String) -> void:
	var room: AABB = PackInterior.inside().grow(WALL_SLOP_M)
	var worst: float = 0.0
	for box: AABB in interior.boxes():
		var out: Vector3 = (room.position - box.position).max(box.end - room.end).max(Vector3.ZERO)
		## The mouth side (front, +z) is open: only the walls count.
		out.z = maxf(room.position.z - box.position.z, 0.0)
		var deep: float = maxf(out.x, maxf(out.y, out.z))
		if deep > 0.0005:
			print("pack interior:   past a wall: %s by %s" % [box, out])
		worst = maxf(worst, deep)
	print("pack interior: deepest past a wall %s %.1f mm" % [when, worst * 1000.0])
	_check(worst <= 0.0005, "an item is through a wall %s (%.1f mm past the slop)" % [when, worst * 1000.0])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pack interior: %s" % message)

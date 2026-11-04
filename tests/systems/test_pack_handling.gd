extends SceneTree

## Hands in the open pack (3D inventory, stage 1). The pack hangs open, the six items are settled, and a camera
## looks in from above. Checks:
## - The ring hovers an item (pale rim, drop hint).
## - LMB takes it: the ring hides, it follows the cursor and stays inside the cloth.
## - The wheel turns it; letting go brings the ring back.
## - RMB shoves a neighbour aside; G throws the hovered item out.
## - The pad's stick moves the ring (hint turns to Y); the boards are refused with the reason shown.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/systems/test_pack_handling.gd [-- <drop seed>]

const ITEMS: Array[StringName] = [&"axe", &"frying_pan", &"hammer", &"water_flask", &"spov_can", &"mug"]
const PACK_AT: Vector3 = Vector3(0.0, 0.9, 0.0)
## The rest of the heap may stir this much on average while one item is dragged through it, m/s.
const STIR_MEAN_LIMIT: float = 0.07
## The heap must come to rest this soon after the item is let go, seconds.
const CALM_AFTER_LIMIT_S: float = 2.5

var _failures: int = 0
var _interior: PackInterior
var _hands: PackHandling
var _camera: Camera3D
var _worst_cloth: float = -1.0
var _phase: String = "settle"
var _worst_phase: String = ""


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	pack.global_position = PACK_AT
	pack.set_open(true)
	_interior = PackInterior.new()
	pack.add_child(_interior)
	_interior.setup(pack)
	_interior.set_open(true)
	var rng := RandomNumberGenerator.new()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	rng.seed = int(args[0]) if not args.is_empty() else 7
	for id: StringName in ITEMS:
		_interior.add(id, Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.34, 0.4), rng.randf_range(0.09, 0.13)))
		await _frames(15)
	await _frames(90)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	root.add_child(_camera)
	_camera.look_at_from_position(PACK_AT + Vector3(0.0, 0.95, 0.62), PACK_AT + Vector3(0.0, 0.2, 0.11))
	_camera.make_current()
	var ring := PackCursor.new()
	root.add_child(ring)
	_hands = PackHandling.new()
	root.add_child(_hands)
	_hands.setup(_interior, _camera, ring)
	var drops: Array[StringName] = []
	_hands.dropped.connect(func(id: StringName, _state: Dictionary) -> void: drops.append(id))

	## Hover: the smallest item whose centre the ring can see (the big pan stands wedged on edge).
	var target: int = await _aim_at_visible(true)
	_check(target >= 0 and _hands.hovered == target, "the ring over an item does not hover it")
	if target < 0:
		_finish()
		return
	var id: StringName = _interior.items[target]["id"]
	_check(_rim_of(target) != null, "the hovered %s has no rim" % id)
	_check(ring.shown and ring.hovering and ring.hint.begins_with("G"), "the ring does not show the drop hint over %s" % id)

	_phase = "take"
	## Take it and lift it: it follows the cursor, the ring hides, nothing goes through the cloth.
	var start: Vector3 = _interior.pose(target).origin
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _frames(2)
	_check(_interior.held() == target, "LMB over %s did not take it" % id)
	_check(not ring.shown, "the ring still shows while %s is held" % id)
	## How much the rest of the heap stirs while one item is dragged through it (mean and peak speed). Before the
	## hand had a strength limit it was 0.097 m/s mean, 0.41 m/s peak.
	var stir_sum: float = 0.0
	var stir_peak: float = 0.0
	var stir_n: int = 0
	for step: int in 50:
		if step < 30:
			_hands.set_cursor(_hands.cursor_at + Vector2(2.0, -4.0))
		await _frames(1)
		for i: int in _interior.items.size():
			if i != target:
				stir_sum += _interior.speed(i)
				stir_peak = maxf(stir_peak, _interior.speed(i))
				stir_n += 1
	var stir_mean: float = stir_sum / maxf(stir_n, 1)
	print("pack handling: the rest of the heap stirred %.3f m/s mean, %.3f m/s peak while dragging" % [stir_mean, stir_peak])
	_check(stir_mean < STIR_MEAN_LIMIT, "the heap stirs too much while one item is dragged (%.3f m/s mean)" % stir_mean)
	var moved: float = _interior.pose(target).origin.distance_to(start)
	print("pack handling: %s moved %.0f mm with the cursor" % [id, moved * 1000.0])
	_check(moved > 0.04, "%s did not follow the cursor (%.0f mm)" % [id, moved * 1000.0])
	var follow: Vector3 = _cursor_on_held_plane()
	var lag: float = _interior.held_point().distance_to(follow)
	print("pack handling: grab point %.0f mm from the cursor's point" % (lag * 1000.0))
	_check(lag < 0.03 or _interior.overshoot(target) > -0.002, "%s lags the cursor by %.0f mm away from any wall" % [id, lag * 1000.0])

	_phase = "turn"
	## The wheel turns it about the line of sight.
	var before: Basis = _interior.pose(target).basis
	for _n: int in 3:
		_hands.press(PackHandling.TURN_LEFT_ACTION, true)
		_hands.press(PackHandling.TURN_LEFT_ACTION, false)
	await _frames(40)
	var turned: float = rad_to_deg((before.inverse() * _interior.pose(target).basis).get_rotation_quaternion().get_angle())
	print("pack handling: three wheel notches turned %s by %.0f deg" % [id, turned])
	_check(turned > 25.0, "the wheel did not turn %s (%.0f deg)" % [id, turned])

	_phase = "let go"
	## Let go: the ring is back and the heap settles inside the cloth.
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(2)
	_check(_interior.held() < 0 and ring.shown, "letting go did not bring the ring back")
	var calm_after: float = 0.0
	while not _interior.is_settled() and calm_after < 4.0:
		await _frames(1)
		calm_after += 1.0 / 60.0
	print("pack handling: the heap settled %.2f s after letting go" % calm_after)
	for i: int in _interior.items.size():
		if float(_interior.items[i]["still_s"]) < PackInterior.SETTLE_S:
			print("pack handling:   still moving: %s at %.3f m/s" % [_interior.items[i]["id"], _interior.speed(i)])
	_check(calm_after < CALM_AFTER_LIMIT_S, "the heap kept moving %.1f s after letting go" % calm_after)
	await _frames(30)

	_phase = "shove"
	## RMB sweeps the heap: something under the hand moves.
	var other: int = await _aim_at_visible(true)
	if other >= 0:
		var was: Array[Vector3] = []
		for i: int in _interior.items.size():
			was.append(_interior.pose(i).origin)
		_hands.press(PackHandling.SHOVE_ACTION, true)
		for step: int in 30:
			_hands.set_cursor(_hands.cursor_at + Vector2(6.0, 2.0))
			await _frames(1)
		_hands.press(PackHandling.SHOVE_ACTION, false)
		await _frames(30)
		var shoved: float = 0.0
		var who: StringName = &""
		for i: int in _interior.items.size():
			var moved_by: float = _interior.pose(i).origin.distance_to(was[i])
			if moved_by > shoved:
				shoved = moved_by
				who = _interior.items[i]["id"]
		print("pack handling: RMB swept %s by %.0f mm" % [who, shoved * 1000.0])
		_check(shoved > 0.015, "RMB moved nothing (%.0f mm at most)" % (shoved * 1000.0))
	else:
		_check(false, "nothing to aim the shove at")

	_phase = "drop"
	## G throws the hovered item out.
	var gone: int = await _aim_at_visible()
	var count: int = _interior.items.size()
	if gone >= 0:
		var gone_id: StringName = _interior.items[gone]["id"]
		_hands.press(PackHandling.DROP_ACTION, true)
		await _frames(2)
		_check(_interior.items.size() == count - 1 and drops == [gone_id], "G over %s did not throw it out" % gone_id)

	_phase = "pad"
	## The pad's left stick moves the ring and the hint names the pad's button.
	var was_at: Vector2 = _hands.cursor_at
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	await _frames(20)
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	await _frames(2)
	print("pack handling: the stick moved the ring %.0f px" % (_hands.cursor_at.x - was_at.x))
	_check(_hands.cursor_at.x - was_at.x > 40.0, "the pad's stick did not move the ring")
	_check(ring.hint.begins_with("Y"), "the hint does not name the pad's button after the stick moved")

	_phase = "boards"
	## The boards are refused, with the reason under the ring.
	_interior.add(&"boards")
	await _frames(2)
	_check(ring.warning != "" and ring.warning_s > 0.0, "the refused boards show no reason")
	print("pack handling: deepest past the cloth through it all %.1f mm (%s)" % [_worst_cloth * 1000.0, _worst_phase])
	_check(_worst_cloth <= 0.002, "an item came through the canvas (%.1f mm)" % (_worst_cloth * 1000.0))
	_finish()


func _finish() -> void:
	print("pack handling: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Puts the ring on the first (or the smallest) item whose centre it can see; returns its index or -1.
func _aim_at_visible(smallest: bool = false) -> int:
	var order: Array = range(_interior.items.size())
	if smallest:
		order.sort_custom(func(a: int, b: int) -> bool: return _interior.extent(a).get_volume() < _interior.extent(b).get_volume())
	for i: int in order:
		var centre: Vector3 = _interior.model.global_transform * _interior.extent(i).get_center()
		_hands.set_cursor(_camera.unproject_position(centre))
		await _frames(2)
		if _hands.hovered == i:
			return i
	return -1


func _cursor_on_held_plane() -> Vector3:
	var to_pack: Transform3D = _interior.model.global_transform.affine_inverse()
	var origin: Vector3 = to_pack * _camera.project_ray_origin(_hands.cursor_at)
	var direction: Vector3 = (to_pack.basis * _camera.project_ray_normal(_hands.cursor_at)).normalized()
	var plane := Plane((to_pack.basis * -_camera.global_basis.z).normalized(), _interior.held_point())
	var at: Variant = plane.intersects_ray(origin, direction)
	return at if at != null else _interior.held_point()


func _rim_of(i: int) -> Material:
	for mesh: Node in (_interior.items[i]["visual"] as Node3D).find_children("*", "MeshInstance3D", true, false):
		return (mesh as MeshInstance3D).material_overlay
	return null


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame
		var now: float = PackClothCheck.worst_past(_interior)
		if now > _worst_cloth:
			_worst_cloth = now
			_worst_phase = _phase


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pack handling: %s" % message)

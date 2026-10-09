extends SceneTree

## The pickup ring is one segmented marker: three equal arcs and F (tap). A hold frames
## the same F in place, shows the hand and fills the arcs from the top down both sides
## over arc length only, gaps kept. A refusal is a red key and one centre ✕, with no
## per-arc meaning. Nothing stale, nothing moves the camera shoulder.
## Run: godot --headless --script tests/systems/test_pickup_marker_ui.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const STEP: float = 1.0 / 60.0

var _failures: int = 0
var _player: Player
var _ic: InteractComponent
var _marker: PickupMarkerUI
var _camera: TpsCamera
var _inventory: InventoryComponent
var _max_shoulder_weight: float = 0.0
var _idle_key_point: Vector2 = Vector2.INF


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.1, 0.0)
	root.add_child(ground)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_ic = _player.get_node(^"InteractComponent") as InteractComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_marker = _player.get_node(^"PickupMarkerUI") as PickupMarkerUI
	_marker.set_process(false)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.current = true
	await _frames(20)
	_check_fill_math()
	var knife: ItemPickup = await _spawn_ahead(&"knife")
	await _check_idle(knife)
	await _check_hold_and_success()
	await _check_cancel_leaves_nothing_stale()
	await _check_storage_refusal()
	await _check_hold_refusal()
	await _check_world_suppresses()
	_check(_max_shoulder_weight == 0.0, "the pickup ring moved the camera shoulder (weight %.4f)" % _max_shoulder_weight)
	print("test_pickup_marker_ui: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Pure fill math: top-centre start, symmetric, arc length only, three arcs at 1.0.
func _check_fill_math() -> void:
	var arcs: Array[Vector2] = PickupMarkerUI.arc_ranges()
	var visible_total: float = 0.0
	for span: Vector2 in arcs:
		visible_total += span.y - span.x
	_check(is_equal_approx(visible_total, 240.0), "the three arcs do not add up to 240° (%.1f)" % visible_total)
	_check(PickupMarkerUI.fill_segments(0.0).is_empty(), "the fill shows at 0 progress")
	var first: Array[Vector2] = PickupMarkerUI.fill_segments(0.05)
	_check(first.size() == 2 and is_equal_approx(first[0].x, PickupMarkerUI.TOP_DEG) and is_equal_approx(first[1].y, PickupMarkerUI.TOP_DEG),
		"the fill does not start at the top-arc centre: %s" % [first])
	for i: int in range(1, 21):
		var p: float = float(i) / 20.0
		var pieces: Array[Vector2] = PickupMarkerUI.fill_segments(p)
		var length: float = 0.0
		for piece: Vector2 in pieces:
			length += piece.y - piece.x
			_check(_inside_an_arc(piece, arcs), "fill piece %s at %.2f lies in a gap" % [piece, p])
			var mirror := Vector2(2.0 * PickupMarkerUI.TOP_DEG - piece.y, 2.0 * PickupMarkerUI.TOP_DEG - piece.x)
			_check(_has_piece(pieces, mirror), "fill at %.2f is not symmetric about the top" % p)
		_check(absf(length - visible_total * p) < 0.01, "fill at %.2f covers %.2f°, expected %.2f°" % [p, length, visible_total * p])
	var past_top: Array[Vector2] = PickupMarkerUI.fill_segments(1.0 / 3.0 + 0.01)
	_check(past_top.size() == 4 and past_top[2].y - past_top[2].x > 0.0, "the fill stalls in the gap after the top arc")
	var full: Array[Vector2] = PickupMarkerUI.fill_segments(1.0)
	var covered: float = 0.0
	for piece: Vector2 in full:
		covered += piece.y - piece.x
		_check(piece.y - piece.x < 359.0, "the full fill became a solid circle")
	_check(absf(covered - visible_total) < 0.01 and full.size() == 4, "at 1.0 the three arcs are not exactly filled (%.1f°)" % covered)


## Idle: three equal arcs, F above, nothing of the hold yet.
func _check_idle(knife: ItemPickup) -> void:
	await _settle(0.5)
	var v: Dictionary = _marker.get_visual_state()
	_check(_marker.get_marked_target() == knife and v["mode"] == &"idle", "the idle ring is not on the dominant pickup (%s)" % v["mode"])
	var alphas: Array = v["arc_alphas"]
	_check(alphas.size() == 3 and is_equal_approx(alphas[0], alphas[1]) and is_equal_approx(alphas[1], alphas[2]) and alphas[0] > 0.5,
		"the idle arcs are not one equal ring: %s" % [alphas])
	_check(v["plain_f_alpha"] > 0.95, "idle lacks the plain F")
	_check(v["key_framed_alpha"] < 0.01 and v["hand_alpha"] < 0.01 and v["fill_progress"] == 0.0, "idle shows hold-mode pieces")
	var layout: Dictionary = v["layout"]
	_idle_key_point = layout["key_point"]
	_check(is_zero_approx(_idle_key_point.x) and _idle_key_point.y < -_marker.ring_radius_px,
		"the idle F is not centred above the ring (%s)" % _idle_key_point)


## Hold: F framed in place, hand in the centre, fill grows from the top, all three at 1.0.
func _check_hold_and_success() -> void:
	_ic.try_interact()
	await _hold_to(0.3)
	await _settle(0.3, 0.3)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["mode"] == &"hold", "hold mode did not switch the ring (%s)" % v["mode"])
	_check(v["plain_f_alpha"] < 0.01 and v["key_framed_alpha"] > 0.95 and v["hand_alpha"] > 0.95, "hold mode lacks the framed [F] or hand")
	var alphas: Array = v["arc_alphas"]
	_check(alphas[0] > 0.0 and is_equal_approx(alphas[0], alphas[2]), "the arcs disappeared in hold mode")
	var layout: Dictionary = v["layout"]
	_check(layout["key_point"] == _idle_key_point, "F moved on entering hold: %s -> %s" % [_idle_key_point, layout["key_point"]])
	_check((layout["key_rect"] as Rect2).get_center().is_equal_approx(_idle_key_point), "the [F] frame is not around the idle F spot")
	_check((layout["hand_rect"] as Rect2).get_center().is_zero_approx(), "the hand is not inside the ring")
	var fills: Array[float] = []
	for t: float in [0.45, 0.65, 0.85, 0.99]:
		await _hold_to(t)
		_marker.refresh(STEP)
		fills.append(float(_marker.get_visual_state()["fill_progress"]))
	_check(fills[0] > 0.0 and fills[0] < fills[1] and fills[1] < fills[2] and fills[2] < fills[3],
		"the hold fill did not grow steadily: %s" % [fills])
	_check(fills[3] > 0.98, "the arcs are not nearly full just before 1.0 s (%.3f)" % fills[3])
	await _hold_to(1.0)
	_ic.release_interact(1.0)
	_marker.refresh(STEP)
	v = _marker.get_visual_state()
	_check(v["fading"] and v["fade_hands"], "at 1.0 s the ring did not fade out as the full three-arc ring with the hand")
	var next: ItemPickup = await _spawn_ahead(&"mug")
	_marker.refresh(STEP)
	v = _marker.get_visual_state()
	_check(_marker.get_marked_target() == next and v["hand_alpha"] < 0.01 and v["key_framed_alpha"] < 0.01 and v["fill_progress"] == 0.0,
		"the next pickup inherited the finished hold: %s" % [v])
	next.queue_free()
	await _settle(0.4)
	v = _marker.get_visual_state()
	_check(not v["fading"] and _marker.get_marked_target() == null, "the success fade left a stale ring")
	_player.animation_component.abort_action()
	(_player.get_node(^"HeldItemComponent") as HeldItemComponent).put_away()


## Cancel: the fill drains back to zero; nothing of the hold stays.
func _check_cancel_leaves_nothing_stale() -> void:
	var mug: ItemPickup = await _spawn_ahead(&"mug")
	_ic.try_interact()
	await _hold_to(0.6)
	_ic.release_interact(0.6)
	await _settle(0.6)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["mode"] == &"idle" and _marker.get_marked_target() == mug, "cancel did not return the ring to idle")
	_check(v["fill_progress"] == 0.0 and (v["fill_segments"] as Array).is_empty() and v["key_framed_alpha"] < 0.01 and v["hand_alpha"] < 0.01,
		"cancel left hold pieces behind: %s" % [v])
	mug.queue_free()
	await _frames(3)


## Tap refusal: red F, centre ✕, the whole ring pulses; no arc of its own.
func _check_storage_refusal() -> void:
	var max_weight: float = _inventory.max_carry_weight
	_inventory.max_carry_weight = _inventory.get_total_weight() + 0.01
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	_ic.try_interact()
	_ic.release_interact(0.05)
	_marker.refresh(STEP)
	await _settle(0.1)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["refusal"] and v["refusal_kind"] == &"tap", "a storage refusal was not shown")
	_check_red_key(v, "tap refusal")
	_check(v["key_framed_alpha"] < 0.01, "a tap refusal framed the F")
	_check((v["layout"]["cross_point"] as Vector2).is_zero_approx(), "the refusal ✕ is not in the ring centre")
	var alphas: Array = v["arc_alphas"]
	_check(is_equal_approx(alphas[0], alphas[1]) and is_equal_approx(alphas[1], alphas[2]) and alphas[0] > PickupMarkerUI.ARC_IDLE_ALPHA + 0.1,
		"the refusal did not pulse the ring as one: %s" % [alphas])
	await _settle(1.0)
	v = _marker.get_visual_state()
	_check(not v["refusal"] and Color(v["key_glyph_color"], 1.0).is_equal_approx(PickupMarkerUI.DOT_COLOR), "the tap refusal did not settle back")
	_inventory.max_carry_weight = max_weight
	tin.queue_free()
	await _frames(3)


## Hold refusal: red [F], centre ✕, the hand gone, the fill frozen, then idle again.
func _check_hold_refusal() -> void:
	var max_weight: float = _inventory.max_carry_weight
	_inventory.max_carry_weight = _inventory.get_total_weight() + 0.01
	var knife: ItemPickup = await _spawn_ahead(&"knife")
	await _settle(0.3)
	_ic.try_interact()
	await _hold_to(0.3)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["refusal"] and v["refusal_kind"] == &"hold", "a hold refusal was not shown")
	_check_red_key(v, "hold refusal")
	_check(v["key_framed_alpha"] > 0.9, "the hold refusal key is not the framed [F]")
	_check(v["hand_alpha"] < 0.01, "the hand competes with the refusal ✕ (%.2f)" % v["hand_alpha"])
	_check((v["layout"]["cross_point"] as Vector2).is_zero_approx() and v["layout"]["key_point"] == _idle_key_point,
		"the hold refusal moved the ✕ or the key")
	var frozen: float = float(v["fill_progress"])
	await _settle(0.2)
	_check(is_equal_approx(float(_marker.get_visual_state()["fill_progress"]), frozen), "the refused fill did not hold still")
	_ic.release_interact(0.3)
	await _settle(1.2)
	v = _marker.get_visual_state()
	_check(not v["refusal"] and v["mode"] == &"idle" and v["key_framed_alpha"] < 0.01 and v["fill_progress"] == 0.0,
		"the hold refusal did not return to idle")
	_check(Color(v["key_glyph_color"], 1.0).is_equal_approx(PickupMarkerUI.DOT_COLOR), "the F did not return to cream after the refusal")
	_inventory.max_carry_weight = max_weight
	knife.queue_free()
	await _frames(3)


## The refused press turns its key red at its own spot.
func _check_red_key(v: Dictionary, what: String) -> void:
	var c: Color = v["key_glyph_color"]
	_check(c.r > 0.7 and c.g < 0.4 and c.b < 0.4 and c.a > 0.9, "%s did not turn the key red (%s)" % [what, c])


## 23: a world mechanism under the view suppresses the ring entirely.
func _check_world_suppresses() -> void:
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	var plain := Camera3D.new()
	root.add_child(plain)
	plain.current = true
	var mechanism := (load(AREA_SCENE) as PackedScene).instantiate() as InteractiveArea
	root.add_child(mechanism)
	mechanism.global_position = _player.global_position + Vector3(0.5, -0.1, -0.5)
	plain.global_position = _player.global_position + Vector3(0.0, 0.62, 0.0)
	plain.look_at(mechanism.get_focus_point(_player.global_position), Vector3.UP)
	await _settle(0.5)
	var v: Dictionary = _marker.get_visual_state()
	_check(_ic.get_world_target() == mechanism, "the fixture's mechanism is not the world target")
	_check(v["mode"] != &"idle" and v["mode"] != &"hold" and not _marker.is_key_shown(), "the ring stayed under a world target (%s)" % v["mode"])
	_camera.current = true
	plain.queue_free()
	mechanism.queue_free()
	tin.queue_free()
	await _frames(3)


func _hold_to(seconds: float) -> void:
	var t: float = _ic._gesture.elapsed if _ic._gesture != null else 0.0
	while t < seconds - 0.0001:
		t = minf(seconds, t + STEP)
		_ic.hold_interact(t)
		_marker.refresh(STEP)
		await physics_frame
		_sample_shoulder()


func _settle(seconds: float, hold_at: float = -1.0) -> void:
	for _i: int in range(int(seconds / STEP)):
		if hold_at >= 0.0:
			_ic.hold_interact(hold_at)
		_marker.refresh(STEP)
		await physics_frame
		_sample_shoulder()


func _sample_shoulder() -> void:
	if _ic.get_world_target() == null:
		_max_shoulder_weight = maxf(_max_shoulder_weight, _camera._shoulder.get_interaction_weight())


func _spawn_ahead(item_id: StringName) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = item_id
	root.add_child(pickup)
	pickup.global_position = Vector3(_player.global_position.x, 0.0, _player.global_position.z - 0.6)
	_player.face_work_target(pickup.global_position)
	await _frames(6)
	return pickup


func _inside_an_arc(piece: Vector2, arcs: Array[Vector2]) -> bool:
	for span: Vector2 in arcs:
		if piece.x >= span.x - 0.001 and piece.y <= span.y + 0.001:
			return true
	return false


## Angles compare modulo 360°: the lower-left arc is 110°..190°, its mirror -250°..-170°.
func _has_piece(pieces: Array[Vector2], wanted: Vector2) -> bool:
	for piece: Vector2 in pieces:
		if is_zero_approx(fposmod(piece.x - wanted.x + 180.0, 360.0) - 180.0) \
			and is_zero_approx(fposmod(piece.y - wanted.y + 180.0, 360.0) - 180.0):
			return true
	return false


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("pickup marker ui: " + message)

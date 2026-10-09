extends SceneTree

## The pickup ring reads as one action plus one deliberate alternative: top arc + F
## (store), lower-left arc (hold to hands) growing from both ends into a full circle,
## and a near-background lower-right arc that only lights up with ✕ on a storage
## refusal. Success fades, cancel leaves nothing stale, a world target suppresses it,
## and none of it moves the camera shoulder.
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
	var knife: ItemPickup = await _spawn_ahead(&"knife")
	await _check_idle(knife)
	await _check_hold_and_success()
	await _check_cancel_leaves_nothing_stale()
	await _check_storage_refusal()
	await _check_world_suppresses()
	_check(_max_shoulder_weight == 0.0, "the pickup ring moved the camera shoulder (weight %.4f)" % _max_shoulder_weight)
	print("test_pickup_marker_ui: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## 17: three arcs; F over the top; the refusal arc stays in the background.
func _check_idle(knife: ItemPickup) -> void:
	await _settle(0.5)
	var v: Dictionary = _marker.get_visual_state()
	_check(_marker.get_marked_target() == knife and v["mode"] == &"idle", "the idle ring is not on the dominant pickup (%s)" % v["mode"])
	_check(v["top_alpha"] > 0.8 and v["plain_f_alpha"] > 0.95, "idle lacks the top arc and plain F")
	_check(v["left_alpha"] > 0.3, "idle lacks the hold arc for a hand-holdable item")
	_check(v["right_alpha"] <= PickupMarkerUI.RIGHT_ARC_IDLE_ALPHA + 0.001 and v["right_alpha"] < v["left_alpha"] and v["right_alpha"] < v["top_alpha"],
		"the refusal arc competes with the actions in idle (%.2f)" % v["right_alpha"])
	_check(v["key_framed_alpha"] < 0.01 and v["hand_alpha"] < 0.01, "idle shows hold-mode pieces")


## 18–21: hold mode, growth from both ends, full circle, clean success fade.
func _check_hold_and_success() -> void:
	_ic.try_interact()
	await _hold_to(0.3)
	await _settle(0.3, 0.3)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["mode"] == &"hold", "hold mode did not switch the ring (%s)" % v["mode"])
	_check(v["top_alpha"] < 0.01 and v["right_alpha"] < 0.01 and v["plain_f_alpha"] < 0.01, "hold mode kept the top/right arcs or plain F")
	_check(v["key_framed_alpha"] > 0.95 and v["hand_alpha"] > 0.95 and v["left_alpha"] > 0.95, "hold mode lacks the framed [F], hand or hold arc")
	var spans: Array[float] = []
	for t: float in [0.45, 0.65, 0.85, 0.99]:
		await _hold_to(t)
		_marker.refresh(STEP)
		spans.append(float(_marker.get_visual_state()["left_span_deg"]))
	_check(spans[0] > PickupMarkerUI.ARC_SPAN_DEG and spans[0] < spans[1] and spans[1] < spans[2] and spans[2] < spans[3],
		"the hold arc did not grow steadily: %s" % [spans])
	_check(spans[3] > 350.0, "the hold arc did not close into a circle near 1.0 s (%.1f°)" % spans[3])
	await _hold_to(1.0)
	_ic.release_interact(1.0)
	_marker.refresh(STEP)
	v = _marker.get_visual_state()
	_check(v["fading"], "a successful hold popped instead of fading")
	await _settle(0.4)
	v = _marker.get_visual_state()
	_check(not v["fading"] and _marker.get_marked_target() == null, "the success fade left a stale ring")
	_player.animation_component.abort_action()
	(_player.get_node(^"HeldItemComponent") as HeldItemComponent).put_away()


## 22: an unfinished hold collapses back to idle with no hold pieces left.
func _check_cancel_leaves_nothing_stale() -> void:
	var mug: ItemPickup = await _spawn_ahead(&"mug")
	_ic.try_interact()
	await _hold_to(0.6)
	_ic.release_interact(0.6)
	await _settle(0.6)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["mode"] == &"idle" and _marker.get_marked_target() == mug, "cancel did not return the ring to idle")
	_check(absf(float(v["left_span_deg"]) - PickupMarkerUI.ARC_SPAN_DEG) < 0.5 and v["key_framed_alpha"] < 0.01 and v["hand_alpha"] < 0.01,
		"cancel left hold pieces behind: %s" % [v])
	mug.queue_free()
	await _frames(3)


## Storage refusal lights the background arc with ✕, then lets it settle back.
func _check_storage_refusal() -> void:
	var max_weight: float = _inventory.max_carry_weight
	_inventory.max_carry_weight = _inventory.get_total_weight() + 0.01
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	_ic.try_interact()
	_ic.release_interact(0.05)
	_marker.refresh(STEP)
	var v: Dictionary = _marker.get_visual_state()
	_check(v["refusal_right"] and v["right_alpha"] > 0.9, "a storage refusal did not light the right arc with ✕")
	await _settle(1.0)
	v = _marker.get_visual_state()
	_check(not v["refusal_right"] and v["right_alpha"] <= PickupMarkerUI.RIGHT_ARC_IDLE_ALPHA + 0.001,
		"the refusal arc did not settle back into the background")
	_inventory.max_carry_weight = max_weight
	tin.queue_free()
	await _frames(3)


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


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("pickup marker ui: " + message)

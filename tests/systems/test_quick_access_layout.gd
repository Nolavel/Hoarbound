extends SceneTree

## Quick Access cards never overlap: the camera circles Henry at several distances and,
## once the cards settle, no two visible card rectangles may intersect.
## Run: godot --headless --script tests/systems/test_quick_access_layout.gd

const DISTANCES: Array[float] = [1.2, 1.6, 2.0, 2.5, 3.0, 4.0, 5.5]
const YAW_STEP_DEG := 30.0
const SETTLE_SECONDS := 0.8
const TOLERANCE_PX := 1.0

var _failures: int = 0
var _player: Player
var _camera: Camera3D
var _ui: QuickAccessUI


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.1, 0.0)
	root.add_child(ground)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_camera = Camera3D.new()
	_camera.fov = 46.0
	root.add_child(_camera)
	_camera.make_current()
	_ui = _player.find_child("QuickAccess", true, false) as QuickAccessUI
	_check(_ui != null, "player has no QuickAccess UI")
	if _ui == null:
		_finish()
		return
	## Only card crowding may pick the layout here; camera distance alone must not.
	_ui.tight_camera_near_distance = 0.5
	_ui.tight_camera_far_distance = 1.0
	await _frames(20)
	var cross_seen := false
	var spread_seen := false
	for distance: float in DISTANCES:
		var yaw := 0.0
		while yaw < 360.0:
			_place_camera(distance, yaw)
			if not _ui.is_open():
				_ui.show_quick_access()
			await create_timer(SETTLE_SECONDS).timeout
			var crossed := bool(_ui.get("_cross_latched"))
			print("d=%.1f yaw=%3d %s" % [distance, int(yaw), "cross" if crossed else "spread"])
			cross_seen = cross_seen or crossed
			spread_seen = spread_seen or not crossed
			_check_no_overlap("d=%.1f yaw=%d cross=%s" % [distance, int(yaw), crossed])
			yaw += YAW_STEP_DEG
	_check(cross_seen, "the cross layout never engaged, even with the camera close to Henry")
	_check(spread_seen, "the spread layout never held, even with the camera far from Henry")
	_finish()


func _place_camera(distance: float, yaw_deg: float) -> void:
	var target := _player.global_position
	target.y = _ui.hands_anchor.global_position.y + 0.1
	var yaw := deg_to_rad(yaw_deg)
	_camera.global_position = target + Vector3(sin(yaw), 0.25, cos(yaw)) * distance
	_camera.look_at(target, Vector3.UP)


func _check_no_overlap(label: String) -> void:
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	var cards: Array[String] = ["CoatLeft", "CoatRight", "ThighLeft", "PackLid", "Hands"]
	for path: StringName in QuickAccessUI.PACK_ORDER:
		cards.append("Pack_%s" % String(path).get_file())  # the outside-pack cards, while the pack is worn
	for name: String in cards:
		var card := _ui.get_node_or_null(name) as Control
		if card != null and card.visible:
			rects.append(Rect2(card.global_position, card.size * card.scale).grow(-TOLERANCE_PX))
			names.append(name)
	for i: int in range(rects.size()):
		for j: int in range(i + 1, rects.size()):
			_check(not rects[i].intersects(rects[j]), "%s: %s overlaps %s" % [label, names[i], names[j]])


func _finish() -> void:
	print("test_quick_access_layout: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("quick access layout: " + message)

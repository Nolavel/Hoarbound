extends SceneTree

## Presentation capture for production Quick Access in the real Key West scene (Reality, streamed).
## Henry stays a normal live Player: physics, idle animation and AnimationTree run.

const MAIN_SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const METRICS := "res://data/characters/henry_metrics.tres"
const OUT_DIR := "res://docs/runtime_previews/quick_access"
const FRAME_DIR := OUT_DIR + "/frames"
const FPS := 12
const TOTAL_FRAMES := 150
const CAMERA_FOV := 46.0
const CAMERA_DISTANCE := 4.0
const STREET_A := Vector2(-2431.5, 554.8)
const STREET_B := Vector2(-3247.0, 1103.5)
const START_SHARE := 0.45

var _scene: Node3D
var _player: Player
var _visual: HenryUALAnimation
var _camera: Camera3D
var _ui: QuickAccessUI
var _hub: PlayerHubComponent
var _inventory: InventoryComponent
var _heading := Vector3.FORWARD
var _standing_top := 1.8
var _events: Array[String] = []
var _pending_keyframes: Dictionary = {}
var _proof_camera := false
var _proof_body := false
var _proof_cards := false
var _proof_idle := false
var _proof_hands_center_fade := false
var _proof_hands_item := false
var _proof_empty_slot := false


func _initialize() -> void:
	Engine.max_fps = FPS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	var metrics := load(METRICS) as HenryMetrics
	if metrics != null and metrics.standing_top > 1.0:
		_standing_top = metrics.standing_top
	_run.call_deferred()


func _run() -> void:
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	for _i in range(24):
		await process_frame

	_player = get_first_node_in_group(&"player") as Player
	if _player == null:
		push_error("QuickAccessCapture: production Key West has no player.")
		quit(2)
		return
	_visual = _player.animation_component
	_ui = _player.get_node(^"HenryUALVisual/QuickAccess") as QuickAccessUI
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	if _visual == null or _ui == null or _hub == null or _inventory == null:
		push_error("QuickAccessCapture: production Quick Access wiring is incomplete.")
		quit(2)
		return

	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	_release_movement_input()
	await _place_on_street()
	_player.hold_still(30.0)
	_suppress_unrelated_hud()

	# Leave one real physical pocket empty in the demo. This is intentionally not
	# a fake visual state: wheel navigation must skip it and the UI must report EMPTY.
	_clear_zone(QuickAccessUI.PATH_COAT_LEFT)
	_seed(&"lighter", QuickAccessUI.PATH_COAT_RIGHT)
	_seed(&"water_flask", QuickAccessUI.PATH_PACK_LID)
	_seed(&"tinder", QuickAccessUI.PATH_THIGH_LEFT)

	# Let streaming, collision and the ordinary idle AnimationTree settle.
	for _i in range(72):
		await process_frame
	await _place_on_street()
	_player.hold_still(30.0)
	for _i in range(24):
		await process_frame

	_build_camera()
	for _i in range(4):
		await process_frame
	_update_proof()
	if not (_proof_camera and _proof_body and _proof_idle and _proof_hands_center_fade):
		_print_state("initial proof failed")
		quit(1)
		return

	for frame in range(TOTAL_FRAMES):
		_drive_demo(frame)
		_drive_camera(frame)
		_update_proof()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("QuickAccessCapture: viewport image is empty.")
			quit(1)
			return
		image.save_png("%s/frame_%04d.png" % [FRAME_DIR, frame])
		for key: Variant in _pending_keyframes.keys():
			if int(_pending_keyframes[key]) == frame:
				image.save_png("%s/%s.png" % [OUT_DIR, String(key)])

	_write_report()
	quit(0 if _proof_cards and _proof_hands_item and _proof_empty_slot else 1)


func _place_on_street() -> void:
	var start := STREET_A.lerp(STREET_B, START_SHARE)
	var along := (STREET_B - STREET_A).normalized()
	_heading = Vector3(along.x, 0.0, along.y)
	if not await CaptureWorldSupport.wait_streamed(self, _scene, _player, start):
		push_warning("QuickAccessCapture: the street chunk did not stream in")
	_player.global_position = Vector3(start.x, CaptureWorldSupport.height(_scene, start.x, start.y) + 1.0, start.y)
	_player.velocity = Vector3.ZERO
	_player.global_rotation.y = atan2(-_heading.x, -_heading.z)
	_player.reset_physics_interpolation()
	for node: Node in _scene.get_children():
		if node is StreamingSystem:
			(node as StreamingSystem).scan(_player.global_position)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "QuickAccessPresentationCamera"
	_camera.fov = CAMERA_FOV
	_scene.add_child(_camera)
	_camera.make_current()
	_drive_camera(0)


func _drive_camera(frame: int) -> void:
	if _camera == null or _visual == null:
		return
	var focus := _visual.global_position + Vector3.UP * (_standing_top * 0.52)
	var forward := -_player.global_transform.basis.z.normalized()
	var right := _player.global_transform.basis.x.normalized()
	var offset := forward * CAMERA_DISTANCE + right * 0.42 + Vector3.UP * 0.20
	if frame >= 84 and frame <= 108:
		var t := float(frame - 84) / 24.0
		var angle := lerpf(-0.32, 0.32, t)
		offset = offset.rotated(Vector3.UP, angle)
	_camera.look_at_from_position(focus + offset, focus + Vector3.UP * 0.02, Vector3.UP)
	_camera.make_current()


func _drive_demo(frame: int) -> void:
	match frame:
		6:
			_events.append("open")
			_ui.show_quick_access()
			_pending_keyframes["01_open"] = 10
		20:
			_events.append("next_1")
			_ui.navigate_next()
		30:
			_events.append("next_2")
			_ui.navigate_next()
			_pending_keyframes["02_focus"] = 34
		42:
			_events.append("previous")
			_ui.navigate_previous()
		54:
			_events.append("confirm")
			_ui.confirm_current()
			_pending_keyframes["03_confirm"] = 57
		74:
			_events.append("reopen")
			_ui.show_quick_access()
		84:
			_events.append("orbit")
			_pending_keyframes["04_orbit"] = 91
		111:
			_events.append("cancel")
			_ui.cancel()
		122:
			_events.append("direct")
			_ui.direct_draw_slot(2)
			_pending_keyframes["05_direct"] = 126


func _clear_zone(path: StringName) -> void:
	var zone := _zone(path)
	if zone.is_empty():
		return
	if StringName(zone.get("item_id", &"")) != &"":
		_hub.move_to_pack(path)


func _seed(item_id: StringName, path: StringName) -> void:
	var zone := _zone(path)
	if zone.is_empty():
		return
	var current := StringName(zone.get("item_id", &""))
	if current != &"" and current != item_id:
		_hub.move_to_pack(path)
	if current != item_id and not _inventory.has_item(item_id):
		_inventory.try_add(ItemCatalog.get_item(item_id))
	if current != item_id:
		_hub.move_to_zone(item_id, path)


func _zone(path: StringName) -> Dictionary:
	for zone: Dictionary in _hub.get_quick_access_zones():
		if StringName(zone["path"]) == path:
			return zone
	return {}


func _release_movement_input() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"jump"]:
		Input.action_release(action)


func _suppress_unrelated_hud() -> void:
	for path: NodePath in [^"MouseCursorUI", ^"PickupMarkerUI", ^"VitalHUD"]:
		_suppress_canvas_branch(_player.get_node_or_null(path))
	var quick := _player.get_node_or_null(^"QuickAccessComponent")
	if quick != null:
		var readout: Variant = quick.get("_readout")
		if readout is Node:
			_suppress_canvas_branch(readout as Node)
	var held := _player.get_node_or_null(^"HeldItemComponent")
	if held != null:
		var hint: Variant = held.get("_hint")
		if hint is Node:
			_suppress_canvas_branch(hint as Node)


func _suppress_canvas_branch(node: Node) -> void:
	if node == null or node == _ui:
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	for child: Node in node.get_children():
		_suppress_canvas_branch(child)


func _update_proof() -> void:
	if _camera == null or _visual == null:
		return
	_proof_camera = _proof_camera or root.get_camera_3d() == _camera
	var feet := _visual.global_position + Vector3.UP * 0.04
	var crown := _visual.global_position + Vector3.UP * _standing_top
	if not _camera.is_position_behind(feet) and not _camera.is_position_behind(crown):
		var feet_screen := _camera.unproject_position(feet)
		var crown_screen := _camera.unproject_position(crown)
		var rect := Rect2(Vector2.ZERO, Vector2(root.size))
		_proof_body = _proof_body or (rect.has_point(feet_screen) and rect.has_point(crown_screen) and absf(feet_screen.y - crown_screen.y) >= 220.0)
	_proof_idle = _proof_idle or (_player.is_on_floor() and Vector2(_player.velocity.x, _player.velocity.z).length() < 0.05 and _player.process_mode != Node.PROCESS_MODE_DISABLED)

	var hands_bg := _ui.get_node_or_null(^"Hands/Background") as TextureRect
	var hands_material := hands_bg.material as ShaderMaterial if hands_bg != null else null
	if hands_material != null:
		_proof_hands_center_fade = _proof_hands_center_fade or int(hands_material.get_shader_parameter(&"fade_direction")) == 4

	if _ui.is_open():
		var visible_cards := 0
		for path: NodePath in [^"CoatLeft", ^"CoatRight", ^"ThighLeft", ^"PackLid", ^"Hands"]:
			var card := _ui.get_node_or_null(path) as Control
			if _card_on_screen(card):
				visible_cards += 1
		_proof_cards = _proof_cards or visible_cards == 5
		var empty_label := _ui.get_node_or_null(^"CoatLeft/Label") as Label
		if empty_label != null and empty_label.text.contains("EMPTY") and StringName(_zone(QuickAccessUI.PATH_COAT_LEFT).get("item_id", &"")) == &"":
			_proof_empty_slot = true
	var hands_label := _ui.get_node_or_null(^"Hands/Label") as Label
	if hands_label != null and not hands_label.text.contains("EMPTY"):
		_proof_hands_item = true


func _card_on_screen(card: Control) -> bool:
	if card == null or not card.is_visible_in_tree():
		return false
	var rect := card.get_global_rect()
	return rect.size.x >= 100.0 and rect.size.y >= 40.0 and rect.intersects(Rect2(Vector2.ZERO, Vector2(root.size)))


func _print_state(reason: String) -> void:
	print("[QuickAccessCapture] %s player=%s floor=%s velocity=%s camera=%s" % [
		reason,
		str(_player.global_position),
		str(_player.is_on_floor()),
		str(_player.velocity),
		str(_camera.global_position if _camera != null else Vector3.ZERO),
	])


func _write_report() -> void:
	var filled := 0
	for zone: Dictionary in _hub.get_quick_access_zones():
		if StringName(zone["path"]) in [QuickAccessUI.PATH_COAT_LEFT, QuickAccessUI.PATH_COAT_RIGHT, QuickAccessUI.PATH_THIGH_LEFT, QuickAccessUI.PATH_PACK_LID] and StringName(zone["item_id"]) != &"":
			filled += 1
	var report := {
		"scene": MAIN_SCENE,
		"real_key_west_scene": true,
		"frames": TOTAL_FRAMES,
		"fps": FPS,
		"movie_seconds": float(TOTAL_FRAMES) / float(FPS),
		"viewport": [root.size.x, root.size.y],
		"henry_live_player_processing": _player.process_mode != Node.PROCESS_MODE_DISABLED,
		"henry_grounded_idle": _proof_idle,
		"henry_body_framed": _proof_body,
		"presentation_camera_current": _proof_camera,
		"selector_cards_intersect_viewport": _proof_cards,
		"hands_center_to_edge_fade": _proof_hands_center_fade,
		"hands_received_item": _proof_hands_item,
		"three_physical_pockets_filled": filled == 3,
		"one_demo_pocket_empty": _proof_empty_slot,
		"events": _events,
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("[QuickAccessCapture] real_world=true idle=%s body=%s cards=%s hands_fade=%s hands_item=%s empty=%s filled=%d" % [
		str(_proof_idle), str(_proof_body), str(_proof_cards), str(_proof_hands_center_fade), str(_proof_hands_item), str(_proof_empty_slot), filled])
	if filled != 3 or not _proof_camera or not _proof_body or not _proof_idle or not _proof_cards or not _proof_hands_center_fade or not _proof_hands_item or not _proof_empty_slot:
		push_error("Quick Access presentation proof failed.")

extends SceneTree

## One-shot visual review of PR #205 / claudeflow Motion Matching in the real
## Key West world. Selects a broad named city-road segment away from the Fort
## Street shelter, teleports Henry there, then records walk -> sprint -> jump ->
## landing -> sprint -> stop through the production TPS camera.

const MAIN_SCENE := "res://scenes/world/key_west/key_west.tscn"
const CITY_DATA := "res://data/world/key_west/city_preview.json"
const OUT_DIR := "res://docs/runtime_previews/key_west_mm_street_review"
const SHELTER := Vector2(-3579.85, 1574.51)
const FPS := 30.0
const DURATION_SECONDS := 10.5
const MIN_SEGMENT_M := 80.0
const MIN_SHELTER_DISTANCE_M := 220.0
const MAX_SHELTER_DISTANCE_M := 1100.0

var _scene: Node3D
var _player: Player
var _camera: TpsCamera
var _terrain: IslandTerrain
var _weather: WeatherController
var _streaming: StreamingSystem
var _locomotion: MotionMatchingLocomotion
var _label: Label
var _frame_index := 0
var _road: Dictionary = {}
var _road_direction := Vector2.ZERO
var _held: Dictionary = {}
var _jump_released := false


func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/frames"))
	FileAccess.open(OUT_DIR + "/.gdignore", FileAccess.WRITE)
	_run.call_deferred()


func _run() -> void:
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	for _i in range(30):
		await process_frame
	_bind()
	if _player == null or _camera == null or _terrain == null or _locomotion == null:
		push_error("KeyWestMMStreetReview: production Player/camera/terrain/MM wiring is missing")
		quit(2)
		return

	_hide_capture_noise()
	_configure_weather()
	_road = _pick_review_segment()
	if _road.is_empty():
		push_error("KeyWestMMStreetReview: no suitable broad city-road segment found")
		quit(3)
		return
	_place_on_road(_road)
	_add_overlay()

	# Give streaming/city chunks, camera collision and the MM database time to
	# settle after the long teleport before the first recorded frame.
	for _i in range(150):
		await process_frame

	var frame_count := int(DURATION_SECONDS * FPS)
	for frame in range(frame_count):
		var t := float(frame) / FPS
		var phase := _apply_program(t)
		_update_overlay(t, phase)
		await process_frame
		await RenderingServer.frame_post_draw
		_save_frame()

	_release_all()
	_write_report()
	print("[KEY_WEST_MM_STREET] complete road=%s class=%s width=%.1f mm=%s" % [
		String(_road.get("name", "unnamed")), String(_road.get("class", "?")),
		float(_road.get("width", 0.0)), _locomotion.get_state()
	])
	quit(0)


func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_terrain = _scene.get_node_or_null(^"IslandTerrain") as IslandTerrain
	if _player != null:
		_locomotion = _player.get_node_or_null(^"MotionMatchingLocomotion") as MotionMatchingLocomotion
	for node: Node in _scene.get_children():
		if node is WeatherController:
			_weather = node as WeatherController
		elif node is StreamingSystem:
			_streaming = node as StreamingSystem


func _hide_capture_noise() -> void:
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	for path in [^"StatsDisplay", ^"Player/VitalHUD", ^"Player/MouseCursorUI"]:
		var node := _scene.get_node_or_null(path)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = false


func _configure_weather() -> void:
	# This is an animation review, not a weather proof: keep the production world
	# but clear the blizzard so feet, handovers and landings remain readable.
	if _weather != null:
		_weather.scheduler_enabled = false
		_weather.set_weather(&"calm", true, 24.0)


func _pick_review_segment() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CITY_DATA))
	if not parsed is Dictionary:
		return {}
	var best: Dictionary = {}
	var best_score := -INF
	var class_bonus := {
		"primary": 420.0,
		"secondary": 330.0,
		"tertiary": 220.0,
		"residential": 80.0,
		"unclassified": 40.0,
	}
	for road_variant: Variant in (parsed as Dictionary).get("roads", []):
		var road := road_variant as Dictionary
		var road_class := String(road.get("class", ""))
		if not class_bonus.has(road_class):
			continue
		var width := float(road.get("width", 0.0))
		if width < 6.0:
			continue
		var points: Array = road.get("points", [])
		for i in range(points.size() - 1):
			var a_arr := points[i] as Array
			var b_arr := points[i + 1] as Array
			var a := Vector2(float(a_arr[0]), float(a_arr[1]))
			var b := Vector2(float(b_arr[0]), float(b_arr[1]))
			var length := a.distance_to(b)
			if length < MIN_SEGMENT_M:
				continue
			var midpoint := (a + b) * 0.5
			var shelter_distance := midpoint.distance_to(SHELTER)
			if shelter_distance < MIN_SHELTER_DISTANCE_M or shelter_distance > MAX_SHELTER_DISTANCE_M:
				continue
			if _terrain.get_height(midpoint.x, midpoint.y) < -0.5:
				continue
			var name := String(road.get("name", ""))
			var preferred_name := 0.0
			if name.contains("Truman"):
				preferred_name = 240.0
			elif name.contains("Roosevelt"):
				preferred_name = 200.0
			elif not name.is_empty():
				preferred_name = 35.0
			var score: float = float(class_bonus[road_class]) + width * 22.0 + minf(length, 160.0) * 1.5 + preferred_name
			# Prefer a recognisable city street, but keep well away from the shelter.
			score -= absf(shelter_distance - 500.0) * 0.08
			if score <= best_score:
				continue
			best_score = score
			best = {
				"name": name,
				"class": road_class,
				"width": width,
				"a": a,
				"b": b,
				"length": length,
				"shelter_distance": shelter_distance,
			}
	return best


func _place_on_road(segment: Dictionary) -> void:
	var a := segment["a"] as Vector2
	var b := segment["b"] as Vector2
	_road_direction = (b - a).normalized()
	var midpoint := (a + b) * 0.5
	# Leave enough road ahead for two sprint bursts and the landing.
	var backoff := minf(30.0, float(segment["length"]) * 0.28)
	var start := midpoint - _road_direction * backoff
	var y := maxf(_terrain.get_height(start.x, start.y), 0.0) + 1.0
	_player.global_position = Vector3(start.x, y, start.y)
	_player.velocity = Vector3.ZERO
	var yaw := atan2(-_road_direction.x, -_road_direction.y)
	_player.global_rotation.y = yaw
	_player.reset_physics_interpolation()
	_camera.set_look(yaw, -8.0)
	if _streaming != null:
		_streaming.scan(_player.global_position)


func _apply_program(t: float) -> String:
	var move := true
	var sprint := false
	var jump_hold := false
	var phase := "walk"
	if t < 2.0:
		phase = "walk"
	elif t < 4.5:
		phase = "sprint"
		sprint = true
	elif t < 4.85:
		phase = "sprint + jump charge"
		sprint = true
		jump_hold = true
	elif t < 7.1:
		phase = "jump / landing"
	elif t < 9.0:
		phase = "sprint after landing"
		sprint = true
	else:
		phase = "stop"
		move = false

	_set_action(&"move_forward", 1.0 if move else 0.0)
	_set_action(&"sprint", 1.0 if sprint else 0.0)
	_set_action(&"jump", 1.0 if jump_hold else 0.0)
	if t >= 4.85:
		_jump_released = true
	return phase


func _set_action(action: StringName, strength: float) -> void:
	var value := clampf(strength, 0.0, 1.0) if strength > 0.001 else 0.0
	if is_equal_approx(float(_held.get(action, 0.0)), value):
		return
	if value > 0.0:
		Input.action_press(action, value)
	else:
		Input.action_release(action)
	_held[action] = value


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"jump"]:
		_set_action(action, 0.0)


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(18.0, 14.0)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_label)
	_scene.add_child(layer)


func _update_overlay(t: float, phase: String) -> void:
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var road_name := String(_road.get("name", "unnamed road"))
	var lines := PackedStringArray()
	lines.append("CLAUDEFLOW ab551bf  |  KEY WEST  |  MOTION MATCHING ON")
	lines.append("%s  |  %s %.1fm  |  t %.1fs  |  %s" % [
		road_name, String(_road.get("class", "?")), float(_road.get("width", 0.0)), t, phase
	])
	lines.append("body %.2f m/s  |  MM %s  |  weight %.2f" % [speed, _locomotion.get_state(), _locomotion.get_weight()])
	var controller := _locomotion.get_controller()
	if controller != null and _locomotion.get_weight() > 0.01:
		var snapshot: Dictionary = controller.get_snapshot()
		lines.append("clip %s @ %.2fs  |  %s" % [
			String(snapshot.get("current_clip", "?")), float(snapshot.get("current_time", 0.0)),
			String(snapshot.get("decision", ""))
		])
	_label.text = "\n".join(lines)


func _save_frame() -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("KeyWestMMStreetReview: empty frame %d" % _frame_index)
		return
	image.save_png("%s/frames/%04d.png" % [OUT_DIR, _frame_index])
	_frame_index += 1


func _write_report() -> void:
	var report := {
		"source_branch": "claudeflow",
		"source_sha": "ab551bf357a61b9a6a9006cd68fada8f93283687",
		"scene": MAIN_SCENE,
		"motion_matching": _locomotion.get_report(),
		"road": {
			"name": String(_road.get("name", "")),
			"class": String(_road.get("class", "")),
			"width_m": float(_road.get("width", 0.0)),
			"segment_length_m": float(_road.get("length", 0.0)),
			"distance_from_shelter_m": float(_road.get("shelter_distance", 0.0)),
		},
		"duration_seconds": DURATION_SECONDS,
		"fps": FPS,
		"frames": _frame_index,
		"weather": "calm (capture-only visibility override)",
		"end_position": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()

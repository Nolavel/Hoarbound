extends SceneTree

## In-game Motion Matching proof on the real Player in TestScene (#202): the
## same analog program with HOARBOUND_MOTION_MATCHING=1 (matched) or unset (tree).
## Run with --fixed-fps 30 so both runs see identical physics ticks.

const SCENE_PATH := "res://tests/scenes/TestScene.tscn"
const DEFAULT_OUT_DIR := "res://docs/runtime_previews/motion_matching_player"
const RENDER_SIZE := Vector2i(960, 540)
const PROGRAM_SECONDS := 30.0
const FPS := 30.0
const START := Vector3(20.0, 1.0, 20.0)
## MM_PROGRAM=drift: TestScene's deepest drift (0.34-0.40 m, lee of a wall),
## crossed facing -Z and back. Needs MM_KEEP_SNOW=1.
const DRIFT_START := Vector3(3.5, 1.0, -2.0)
## The drift lies along a wall on +X: the side view looks from -X.
const DRIFT_CAMERA_OFFSET := Vector3(-3.2, 1.2, 0.8)
const CAMERA_OFFSET := Vector3(2.4, 1.3, 2.9)
const CAMERA_FOLLOW_RATE := 4.0
## Foot skating after Zhang et al. 2018 (MANN): horizontal ball-joint speed
## weighted by clamp(2 - 2^(h/H), 0, 1), h above the flat-foot ball height.
const SKATE_HEIGHT_M := 0.025
const FLAT_BALL_HEIGHT_M := 0.015
## SnowFootModifier's ankle height above the sole, metres.
const SNOW_ANKLE_M := 0.08

## MM_OUT_DIR=<res:// dir> lets two runs (tree and matched) render side by side.
var _out_dir := DEFAULT_OUT_DIR
## MM_STICK_SCALE scales every stick magnitude: neighbouring runs of a chaotic
## matcher, so one program is not read as the whole truth.
var _stick_scale := 1.0
var _drift := false
var _scene: Node
var _player: Player
var _locomotion: MotionMatchingLocomotion
var _camera: Camera3D
## The side view renders here; the game's TpsCamera stays current so WASD keeps
## its real camera-relative meaning.
var _view: SubViewport
var _tps: TpsCamera
var _label: Label
var _focus := Vector3.ZERO
var _heading := Vector3.FORWARD
var _frame_index := 0
var _feet: Array[int] = []
var _balls: Array[int] = []
var _previous_balls: Dictionary = {}
var _previous_snow_balls: Dictionary = {}
var _skate_sum := 0.0
var _skate_weight := 0.0
var _skate_frames := 0
var _moving_skate_sum := 0.0
var _moving_skate_weight := 0.0
var _stance_height_sum := 0.0
## Per program segment: [weighted slide sum, weight, mm weight sum, frames].
var _segments: Dictionary = {}
## With the snow shell kept, per segment: [print slide sum, planted samples,
## |sole - print floor| sum, depth sum, wade sum, frames].
var _snow_segments: Dictionary = {}
var _segment := ""
## Last strength per action: Input only hears changes, never a repeated release
## (that reads as just_released every frame and fires the sprint release boost).
var _held: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_environment("MM_OUT_DIR").is_empty():
		_out_dir = OS.get_environment("MM_OUT_DIR")
	var headless := OS.get_environment("MM_HEADLESS_PROOF") == "1"
	if not OS.get_environment("MM_STICK_SCALE").is_empty():
		_stick_scale = clampf(OS.get_environment("MM_STICK_SCALE").to_float(), 0.5, 1.0)
	# Weather picks its profile with the global RNG: one seed, one snow cover.
	seed(202)
	_scene = (load(SCENE_PATH) as PackedScene).instantiate()
	_player = _scene.get_node_or_null(^"Player") as Player
	_locomotion = _player.get_node_or_null(^"MotionMatchingLocomotion") as MotionMatchingLocomotion if _player != null else null
	if _player == null or _locomotion == null:
		push_error("MotionMatchingPlayerCapture: Player or its MotionMatchingLocomotion is missing.")
		quit(2)
		return
	_view = SubViewport.new()
	_view.size = RENDER_SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var hud := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(8.0, 6.0)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)
	var debug_view := MotionMatchingDebugView.new()
	debug_view.hud_label = Label.new()
	_locomotion.debug_view = debug_view
	_scene.add_child(debug_view)
	root.add_child(_scene)
	root.add_child(_view)
	_view.add_child(hud)
	root.disable_3d = true
	# Bare ground by default. MM_KEEP_SNOW=1 keeps the shell; its field rebuilds
	# then finish in the step they start (wall-clock budgets vary by machine).
	if OS.get_environment("MM_KEEP_SNOW") == "1":
		for node in root.find_children("*", "", true, false):
			if node is SnowShell:
				node.rebuild_budget_usec = 1 << 30
				node.urgent_budget_usec = 1 << 30
	else:
		for _frame in range(3):
			await process_frame
		for node in root.find_children("*", "", true, false):
			if node is SnowShell:
				node.queue_free()
		# The shell already wrote its first readings into the body and the rig.
		_player.movement.snow_speed_multiplier = 1.0
		_player.movement.snow_accel_multiplier = 1.0
		var wade := _player.animation_component.skeleton.get_node_or_null(^"Wade") as WadeModifier
		if wade != null:
			wade.wade = 0.0
	for _frame in range(20):
		await process_frame
	for path in [^"StatsDisplay", ^"Player/VitalHUD", ^"Player/MouseCursorUI"]:
		var noise := _scene.get_node_or_null(path)
		if noise is CanvasItem:
			(noise as CanvasItem).visible = false
		elif noise is CanvasLayer:
			(noise as CanvasLayer).visible = false
	_drift = OS.get_environment("MM_PROGRAM") == "drift"
	_player.global_position = DRIFT_START if _drift else START
	if _drift:
		_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_heading = -_player.global_transform.basis.z
	_heading = Vector3(_heading.x, 0.0, _heading.z).normalized()
	_tps = root.get_camera_3d() as TpsCamera
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_view.add_child(_camera)
	_camera.make_current()
	_focus = _player.animation_component.global_position + Vector3(0.0, 0.9, 0.0)
	_camera.look_at_from_position(_focus + (DRIFT_CAMERA_OFFSET if _drift else CAMERA_OFFSET), _focus)
	for side in ["l", "r"]:
		_feet.append(_player.animation_component.skeleton.find_bone("foot_" + side))
		_balls.append(_player.animation_component.skeleton.find_bone("ball_" + side))
	if not headless:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir + "/frames"))
		FileAccess.open(_out_dir + "/.gdignore", FileAccess.WRITE)
	for _frame in range(30):
		await process_frame

	var timeline: Array[Dictionary] = []
	# MM_SECONDS shortens a rendered review to the part being looked at.
	var seconds := clampf(OS.get_environment("MM_SECONDS").to_float(), 1.0, PROGRAM_SECONDS) \
		if not OS.get_environment("MM_SECONDS").is_empty() else PROGRAM_SECONDS
	var frame_count := int(seconds * FPS)
	for frame in range(frame_count):
		var t := float(frame) / FPS
		var intent := _program(t)
		_segment = intent["label"]
		_apply_input(intent["direction"], bool(intent["sprint"]))
		await process_frame
		_follow_camera()
		_measure()
		_label.text = _hud_text(t, intent["label"])
		if not headless:
			await RenderingServer.frame_post_draw
			_save_frame()
		if frame % 5 == 0:
			timeline.append({
				"t": t, "label": intent["label"],
				"speed": Vector2(_player.velocity.x, _player.velocity.z).length(),
				"weight": _locomotion.get_weight(),
			})
	_release_input()

	var report := {
		"issue": 202,
		"scene": SCENE_PATH,
		"snow": OS.get_environment("MM_KEEP_SNOW") == "1",
		"stick_scale": _stick_scale,
		"motion_matching": _locomotion.get_report(),
		"frames": frame_count,
		"fps": FPS,
		"skating_rule": "MANN: ball speed x clamp(2 - 2^(h/%.3f), 0, 1), h above %.3f m; same for both systems" % [SKATE_HEIGHT_M, FLAT_BALL_HEIGHT_M],
		"foot_skating_m_s": _ratio(_skate_sum, float(_skate_frames)),
		"planted_slide_m_s": _ratio(_skate_sum, _skate_weight),
		"planted_slide_while_moving_m_s": _ratio(_moving_skate_sum, _moving_skate_weight),
		"stance_ball_height_m": _ratio(_stance_height_sum, _skate_weight),
		"segments": _segment_report(),
		"timeline": timeline,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var file := FileAccess.open(_out_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var mm: Dictionary = report["motion_matching"]
	print("[MM_PLAYER] %s / active %.0f%% / handovers %d / planted slide %.3f m/s (moving %.3f) / skating %.3f / stance ball %.3f m / frames %d" % [
		mm["state"], float(mm["active_fraction"]) * 100.0, int(mm["handovers"]),
		float(report["planted_slide_m_s"]), float(report["planted_slide_while_moving_m_s"]),
		float(report["foot_skating_m_s"]), float(report["stance_ball_height_m"]), _frame_index,
	])
	quit(0)


## World-space analog program relative to Henry's spawn facing.
func _program(t: float) -> Dictionary:
	if _drift:
		return _drift_program(t)
	var angle := 0.0
	var magnitude := 1.0
	var sprint := false
	var label := ""
	if t < 2.0:
		magnitude = 0.0
		label = "idle"
	elif t < 6.0:
		label = "walk forward"
	elif t < 9.0:
		angle = PI * 0.5 * smoothstep(0.0, 1.0, (t - 6.0) / 3.0)
		label = "smooth curve left"
	elif t < 11.0:
		angle = PI * 0.5
		label = "walk"
	elif t < 12.5:
		magnitude = 0.0
		label = "stop"
	elif t < 15.0:
		label = "start, 90 deg right of the last heading"
	elif t < 18.0:
		angle = PI
		label = "sharp reversal"
	elif t < 21.0:
		angle = PI
		sprint = true
		label = "sprint (tree owns it)"
	elif t < 24.0:
		angle = PI
		label = "walk after sprint"
	elif t < 26.0:
		angle = PI * 0.75
		magnitude = 0.5
		label = "half stick"
	else:
		magnitude = 0.0
		label = "stop, idle"
	return {"direction": _heading.rotated(Vector3.UP, angle) * magnitude * _stick_scale, "sprint": sprint, "label": label}


## Into the drift and back out: plain walking where wading should show.
func _drift_program(t: float) -> Dictionary:
	var label := "idle"
	var magnitude := 0.0
	var angle := 0.0
	if t >= 2.0 and t < 12.0:
		label = "drift, walking in"
		magnitude = 1.0
	elif t >= 12.0 and t < 14.0:
		label = "drift, stop"
	elif t >= 14.0 and t < 24.0:
		label = "drift, walking back"
		magnitude = 1.0
		angle = PI
	elif t >= 24.0:
		label = "drift, stop and idle"
	return {"direction": _heading.rotated(Vector3.UP, angle) * magnitude * _stick_scale, "sprint": false, "label": label}


## Player turns WASD by the TpsCamera's control yaw (fixed without a mouse);
## the world direction is converted back through it.
func _apply_input(direction: Vector3, sprint: bool) -> void:
	var yaw := _tps.get_yaw() if _tps != null else _player.global_rotation.y
	var local := direction.rotated(Vector3.UP, -yaw)
	_set_action(&"move_right", maxf(local.x, 0.0))
	_set_action(&"move_left", maxf(-local.x, 0.0))
	_set_action(&"move_backward", maxf(local.z, 0.0))
	_set_action(&"move_forward", maxf(-local.z, 0.0))
	_set_action(&"sprint", 1.0 if sprint else 0.0)


func _set_action(action: StringName, strength: float) -> void:
	var value := clampf(strength, 0.0, 1.0) if strength > 0.001 else 0.0
	if is_equal_approx(float(_held.get(action, 0.0)), value):
		return
	if value > 0.0:
		Input.action_press(action, value)
	else:
		Input.action_release(action)
	_held[action] = value


func _release_input() -> void:
	for action in [&"move_right", &"move_left", &"move_forward", &"move_backward", &"sprint"]:
		_set_action(action, 0.0)


func _follow_camera() -> void:
	var visual := _player.animation_component.global_position
	_focus = _focus.lerp(visual + Vector3(0.0, 0.9, 0.0), 1.0 - exp(-CAMERA_FOLLOW_RATE / FPS))
	_camera.look_at_from_position(_focus + (DRIFT_CAMERA_OFFSET if _drift else CAMERA_OFFSET), _focus)


## Planted-foot slide of the drawn pose, the same rule for both systems. TestScene
## is flat: the floor is the body's capsule base, 1 m under its origin.
func _measure() -> void:
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length() > 0.2
	var floor_y := _player.global_position.y - 1.0
	for side in range(2):
		var ball := _joint(_balls[side])
		if _previous_balls.has(side):
			var speed := Vector2(ball.x - _previous_balls[side].x, ball.z - _previous_balls[side].z).length() * FPS
			var height := ball.y - floor_y
			var weight := clampf(2.0 - pow(2.0, maxf(height - FLAT_BALL_HEIGHT_M, 0.0) / SKATE_HEIGHT_M), 0.0, 1.0)
			_skate_sum += speed * weight
			_skate_weight += weight
			_skate_frames += 1
			_stance_height_sum += height * weight
			var segment: Array = _segments.get(_segment, [0.0, 0.0, 0.0, 0])
			segment[0] += speed * weight
			segment[1] += weight
			segment[2] += _locomotion.get_weight()
			segment[3] += 1
			_segments[_segment] = segment
			if moving:
				_moving_skate_sum += speed * weight
				_moving_skate_weight += weight
		_previous_balls[side] = ball
	_measure_snow()


## In snow MANN undercounts (boots ride on the snow top): a boot the shell holds
## on its print should not slide, and its sole should sit on the print floor.
func _measure_snow() -> void:
	var shell := SnowShell.active
	if not is_instance_valid(shell):
		return
	var at := _player.global_position
	var snow: Array = _snow_segments.get(_segment, [0.0, 0, 0.0, 0.0, 0.0, 0])
	snow[3] += maxf(shell.field.get_depth(at.x, at.z), 0.0)
	var wade := _player.animation_component.skeleton.get_node_or_null(^"Wade") as WadeModifier
	snow[4] += wade.wade if wade != null else 0.0
	snow[5] += 1
	for side in range(2):
		var top := shell.get_foot_snow_top(side)
		var ball := _joint(_balls[side])
		var previous: Variant = _previous_snow_balls.get(side)
		_previous_snow_balls[side] = ball if top != -INF else null
		if top == -INF or previous == null:
			continue
		snow[0] += Vector2(ball.x - (previous as Vector3).x, ball.z - (previous as Vector3).z).length() * FPS
		snow[1] += 1
		var sole := _joint(_feet[side]).y - SNOW_ANKLE_M
		snow[2] += absf(sole - (top - shell.get_foot_sink(side)))
	_snow_segments[_segment] = snow


func _segment_report() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for label in _segments:
		var segment: Array = _segments[label]
		var entry := {
			"segment": label,
			"planted_slide_m_s": _ratio(segment[0], segment[1]),
			"motion_matching_weight": _ratio(segment[2], float(segment[3])),
		}
		if _snow_segments.has(label):
			var snow: Array = _snow_segments[label]
			entry["snow_print_slide_m_s"] = _ratio(snow[0], float(snow[1]))
			entry["snow_sole_error_m"] = _ratio(snow[2], float(snow[1]))
			entry["snow_depth_m"] = _ratio(snow[3], float(snow[5]))
			entry["snow_wade"] = _ratio(snow[4], float(snow[5]))
		result.append(entry)
	return result


func _ratio(total: float, count: float) -> float:
	return 0.0 if count <= 0.0 else total / count


func _joint(bone: int) -> Vector3:
	var skeleton := _player.animation_component.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _hud_text(t: float, label: String) -> String:
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var lines := PackedStringArray()
	lines.append("HENRY IN TESTSCENE  |  %s  |  t %.1f s  |  %s" % [
		"MOTION MATCHING (flag on)" if _locomotion.enabled else "PRODUCTION AnimationTree (flag off)",
		t, label,
	])
	lines.append("body speed %.2f m/s   MM %s   weight %.2f" % [speed, _locomotion.get_state(), _locomotion.get_weight()])
	var controller := _locomotion.get_controller()
	if controller != null and _locomotion.get_weight() > 0.0:
		var snapshot := controller.get_snapshot()
		var lock := controller.get_foot_lock()
		lines.append("clip %s @ %.2fs   %s   lock L%d R%d" % [
			snapshot["current_clip"], float(snapshot["current_time"]), snapshot["decision"],
			int(lock != null and lock.is_locked(0)), int(lock != null and lock.is_locked(1)),
		])
	return "\n".join(lines)


func _save_frame() -> void:
	var image := _view.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("MotionMatchingPlayerCapture: empty frame %d" % _frame_index)
		return
	image.save_png(ProjectSettings.globalize_path("%s/frames/%04d.png" % [_out_dir, _frame_index]))
	_frame_index += 1

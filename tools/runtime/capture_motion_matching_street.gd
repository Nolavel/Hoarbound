extends SceneTree

## Production street review: in the real Key West scene Henry walks, sprints and stops
## on Southard Street; side-follow frames plus a per-frame gait trace (report.json).

const MAIN_SCENE := "res://scenes/world/key_west/key_west.tscn"
const DEFAULT_OUT_DIR := "res://docs/runtime_previews/motion_matching_street"
## A straight 980 m stretch of Southard Street (Old Town), world x/z.
const STREET_A := Vector2(-2431.5, 554.8)
const STREET_B := Vector2(-3247.0, 1103.5)
const START_SHARE := 0.45
const RENDER_SIZE := Vector2i(960, 540)
const FPS := 30.0
const PROGRAM_SECONDS := 17.0
const WARMUP_FRAMES := 150
## Camera beside Henry (right of his path), slightly ahead, at hip height.
const CAMERA_SIDE := 3.4
const CAMERA_AHEAD := 0.8
const CAMERA_HEIGHT := 1.1
const CAMERA_FOLLOW_RATE := 4.0

var _out_dir := DEFAULT_OUT_DIR
var _scene: Node3D
var _player: Player
var _locomotion: MotionMatchingLocomotion
var _tps: TpsCamera
var _view: SubViewport
var _camera: Camera3D
var _label: Label
var _heading := Vector3.FORWARD
var _focus := Vector3.ZERO
var _held: Dictionary = {}
var _feet: Array[int] = []
var _balls: Array[int] = []
var _pelvis := -1
var _trace: Array[Dictionary] = []


func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	_run.call_deferred()


func _run() -> void:
	if not OS.get_environment("MM_OUT_DIR").is_empty():
		_out_dir = OS.get_environment("MM_OUT_DIR")
	var headless := OS.get_environment("MM_HEADLESS_PROOF") == "1"
	seed(202)
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	for _frame in range(20):
		await process_frame
	_player = get_first_node_in_group(&"player") as Player
	_tps = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	if _player == null:
		push_error("MotionMatchingStreetCapture: no player in %s" % MAIN_SCENE)
		quit(2)
		return
	_locomotion = _player.get_node_or_null(^"MotionMatchingLocomotion") as MotionMatchingLocomotion
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	_place_on_street()
	_build_view()
	for side in ["l", "r"]:
		_feet.append(_player.animation_component.skeleton.find_bone("foot_" + side))
		_balls.append(_player.animation_component.skeleton.find_bone("ball_" + side))
	_pelvis = _player.animation_component.skeleton.find_bone("pelvis")
	for _frame in range(WARMUP_FRAMES):
		await process_frame
	_place_on_street()
	for _frame in range(30):
		await process_frame
	if not headless:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir + "/frames"))
		FileAccess.open(_out_dir + "/.gdignore", FileAccess.WRITE)
	var seconds := clampf(OS.get_environment("MM_SECONDS").to_float(), 1.0, PROGRAM_SECONDS) \
		if not OS.get_environment("MM_SECONDS").is_empty() else PROGRAM_SECONDS
	for frame in range(int(seconds * FPS)):
		var t := float(frame) / FPS
		var intent := _program(t)
		_apply_input(intent["direction"], bool(intent["sprint"]))
		await process_frame
		_follow_camera()
		_record(t, intent["label"])
		_label.text = _hud_text(t, intent["label"])
		if not headless:
			await RenderingServer.frame_post_draw
			var image := _view.get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path("%s/frames/%04d.png" % [_out_dir, frame]))
	_apply_input(Vector3.ZERO, false)
	var report := {
		"issue": 202,
		"scene": MAIN_SCENE,
		"street": "Southard Street",
		"start": [_player.global_position.x, _player.global_position.z],
		"motion_matching": _locomotion.get_report() if _locomotion != null else {},
		"fps": FPS,
		"gait_trace": _trace,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var file := FileAccess.open(_out_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("[MM_STREET] %s / frames %d / out %s" % [
		_locomotion.get_state() if _locomotion != null else "no motion matching", _trace.size(), _out_dir])
	quit(0)


## Plain walking first, then the build-up into a sprint, then a stop.
func _program(t: float) -> Dictionary:
	if t < 2.0:
		return {"direction": Vector3.ZERO, "sprint": false, "label": "idle"}
	if t < 10.0:
		return {"direction": _heading, "sprint": false, "label": "walk"}
	if t < 14.0:
		return {"direction": _heading, "sprint": true, "label": "sprint"}
	return {"direction": Vector3.ZERO, "sprint": false, "label": "stop, idle"}


func _place_on_street() -> void:
	var start := STREET_A.lerp(STREET_B, START_SHARE)
	var along := (STREET_B - STREET_A).normalized()
	_heading = Vector3(along.x, 0.0, along.y)
	var terrain := _scene.get_node_or_null(^"IslandTerrain") as IslandTerrain
	var ground := maxf(terrain.get_height(start.x, start.y), 0.0) if terrain != null else 0.0
	_player.global_position = Vector3(start.x, ground + 1.0, start.y)
	_player.velocity = Vector3.ZERO
	_player.global_rotation.y = atan2(-_heading.x, -_heading.z)
	_player.reset_physics_interpolation()
	if _tps != null:
		_tps.set_look(_player.global_rotation.y, _tps.start_pitch_deg)
	for node: Node in _scene.get_children():
		if node is StreamingSystem:
			(node as StreamingSystem).scan(_player.global_position)


## The side view renders into its own viewport; the game's TpsCamera stays current
## so WASD keeps its real camera-relative meaning.
func _build_view() -> void:
	_view = SubViewport.new()
	_view.size = RENDER_SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.cull_mask &= ~SnowShell.CONTACT_LAYER
	_view.add_child(_camera)
	_camera.make_current()
	var hud := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(8.0, 6.0)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)
	_view.add_child(hud)
	_focus = _player.global_position
	_follow_camera(true)


func _follow_camera(snap: bool = false) -> void:
	var target := _player.animation_component.global_position + Vector3(0.0, 0.9, 0.0)
	_focus = target if snap else _focus.lerp(target, 1.0 - exp(-CAMERA_FOLLOW_RATE / FPS))
	var side := _heading.cross(Vector3.UP).normalized()
	var eye := _focus + side * CAMERA_SIDE + _heading * CAMERA_AHEAD + Vector3(0.0, CAMERA_HEIGHT - 0.9, 0.0)
	_camera.look_at_from_position(eye, _focus)


func _apply_input(direction: Vector3, sprint: bool) -> void:
	var yaw := _tps.get_yaw() if _tps != null else _player.global_rotation.y
	var local := direction.rotated(Vector3.UP, -yaw)
	_set_action(&"move_right", maxf(local.x, 0.0))
	_set_action(&"move_left", maxf(-local.x, 0.0))
	_set_action(&"move_backward", maxf(local.z, 0.0))
	_set_action(&"move_forward", maxf(-local.z, 0.0))
	_set_action(&"sprint", 1.0 if sprint else 0.0)


## Input only hears changes; a repeated release would read as just_released.
func _set_action(action: StringName, strength: float) -> void:
	var value := clampf(strength, 0.0, 1.0) if strength > 0.001 else 0.0
	if is_equal_approx(float(_held.get(action, 0.0)), value):
		return
	if value > 0.0:
		Input.action_press(action, value)
	else:
		Input.action_release(action)
	_held[action] = value


func _record(t: float, label: String) -> void:
	var entry := {
		"t": t, "label": label,
		"speed": Vector2(_player.velocity.x, _player.velocity.z).length(),
		"floor_y": _player.global_position.y - 1.0,
		"body": _vec(_player.global_position),
		"pelvis": _vec(_joint(_pelvis)),
		"ball": [_vec(_joint(_balls[0])), _vec(_joint(_balls[1]))],
		"foot": [_vec(_joint(_feet[0])), _vec(_joint(_feet[1]))],
		"weight": _locomotion.get_weight() if _locomotion != null else 0.0,
		"snow_speed": _player.movement.snow_speed_multiplier,
	}
	var controller := _locomotion.get_controller() if _locomotion != null else null
	if controller != null and _locomotion.get_weight() > 0.0:
		var snapshot := controller.get_snapshot()
		entry["clip"] = snapshot["current_clip"]
		entry["contacts"] = snapshot["contacts"]
	_trace.append(entry)


func _hud_text(t: float, label: String) -> String:
	var mm := _locomotion != null and _locomotion.enabled
	var lines := PackedStringArray()
	lines.append("HENRY ON SOUTHARD STREET, KEY WEST  |  %s  |  t %.1f s  |  %s" % [
		"MOTION MATCHING" if mm else "AnimationTree", t, label])
	lines.append("speed %.2f m/s   %s" % [Vector2(_player.velocity.x, _player.velocity.z).length(),
		_locomotion.get_state() if mm else ""])
	return "\n".join(lines)


func _joint(bone: int) -> Vector3:
	var skeleton := _player.animation_component.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]

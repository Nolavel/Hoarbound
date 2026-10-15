extends SceneTree

## Production shelter doorway (Key West, 1.5 x 2.25 m): through every normal traversal
## Henry is never dithered, stays on screen and unoccluded, the camera stays out of walls,
## nothing pops, and only the mouse turns the control yaw.
## Run: godot --headless --path . --script res://tests/systems/test_doorway_camera.gd [-- <label> [pivot=<share>] [scenario...]]
## With a label, rows and a summary go to user://traces/tps_doorway/<label>/; add --fixed-fps 144 for frame-exact traces.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_ROOT: String = "user://traces/tps_doorway"
## Radians of turn per pixel, as InputSystems.MOUSE_SENSITIVITY.
const MOUSE_SENSITIVITY: float = 0.003
## Sphere around the render origin that covers the near-plane corners, metres.
const NEAR_PROBE_RADIUS: float = 0.08
## A pop: the camera jumps against Henry by more than this in one frame, faster than POP_SPEED.
const POP_LIMIT: float = 0.15
const POP_SPEED: float = 6.0
## Fastest the FOV may change, degrees per second.
const FOV_RATE_LIMIT: float = 45.0
## Henry starts this far outside the door plane and walks until this far inside.
const START_OUT: float = 2.6
const END_IN: float = 2.2
## After an explicit traversal Henry rests at least this far from the door plane.
const CLEAR_OF_PLANE: float = 0.6
const SETTLE_TICKS: int = 90
const SCENARIOS: PackedStringArray = [
	"straight", "angled", "stop_short", "release_inside", "reverse", "back_s",
	"yaw_swing", "pitch_swing", "left_shoulder", "crouch", "half_open", "stand_sweep",
]


## Runs last in each rendered frame, after the camera.
class FrameProbe extends Node:
	signal frame_done

	var delta: float = 1.0 / 60.0

	func _init() -> void:
		process_priority = 4096

	func _process(frame_delta: float) -> void:
		delta = frame_delta
		frame_done.emit()


var _label: String = ""
var _selected: PackedStringArray = []
var _pivot_share: float = -1.0
var _failures: int = 0
var _scene: Node
var _player: Player
var _cam: TpsCamera
var _probe: FrameProbe
var _skeleton: Skeleton3D
var _head_bone: int = -1
var _door: Node3D
var _center: Vector3
var _inward: Vector3
var _across: Vector3
var _summary: Dictionary = {}
var _rows: Array[Dictionary] = []
var _stats: Dictionary = {}
var _last_rel: Vector3 = Vector3.INF
var _last_fov: float = -1.0
var _last_control: float = 0.0
var _mouse_this_frame: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_label = args[0]
	for i: int in range(1, args.size()):
		if args[i].begins_with("pivot="):
			_pivot_share = float(args[i].trim_prefix("pivot="))
		else:
			_selected.append(args[i])
	if _selected.is_empty():
		_selected = SCENARIOS
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(960, 540)
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_probe = FrameProbe.new()
	root.add_child(_probe)
	_run.call_deferred()


func _run() -> void:
	await _ticks(120)
	_player = _scene.find_child("Player", true, false) as Player
	_cam = _scene.find_child("PlayerCamera", true, false) as TpsCamera
	var skeletons: Array[Node] = _player.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_head_bone = _skeleton.find_bone("Head")
	if _pivot_share >= 0.0:
		_cam.framing_pivot_share = _pivot_share
	if not _find_door():
		_fail("no shelter door in %s" % SCENE)
		_finish()
		return
	if not await _wait_for_streamed_door():
		_fail("the door's chunk never streamed in")
		_finish()
		return
	for scenario: String in _selected:
		print("[doorway] %s" % scenario)
		_open_door(float(_door.get("open_angle_deg")))
		match scenario:
			"straight": await _straight(&"straight")
			"angled": await _angled()
			"stop_short": await _stop_short()
			"release_inside": await _release_inside()
			"reverse": await _reverse()
			"back_s": await _back_s()
			"yaw_swing": await _yaw_swing()
			"pitch_swing": await _pitch_swing()
			"left_shoulder": await _left_shoulder()
			"crouch": await _crouch()
			"half_open": await _half_open()
			"stand_sweep": await _stand_sweep()
			_: _fail("unknown scenario %s" % scenario)
	_finish()


# --- Scenarios ----------------------------------------------------------------

## W along the axis from outside, through the door and into the room.
func _straight(tag: StringName) -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(tag)
	await _hold(&"move_forward", func() -> bool: return _along() >= END_IN, 8.0)
	await _settle_sampled(60)
	_end(tag, true, 1.0)
	await _mouse_freedom(tag)


## W held 35 degrees off the axis from the left, turned right at the door centre.
func _angled() -> void:
	var off: float = deg_to_rad(35.0)
	await _place(-START_OUT * cos(off), -START_OUT * sin(off), -off, -10.0)
	_begin(&"angled")
	await _hold(&"move_forward", func() -> bool: return _along() >= END_IN, 10.0)
	await _settle_sampled(60)
	_end(&"angled", true, 1.0)


## W released 0.7 m before the door plane: Henry stays outside, nothing walks him in.
func _stop_short() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"stop_short")
	await _hold(&"move_forward", func() -> bool: return _along() >= -0.7, 8.0)
	var released: float = _along()
	await _settle_sampled(150)
	var drift: float = _along() - released
	_end(&"stop_short", false, 0.0)
	_check(drift < 0.3, "stop_short: released %.2f m before the door, Henry drifted %.2f m on" % [-released, drift])
	_stats_note(&"stop_short", "drift_after_release_m", drift)


## W released just past the door plane: the traversal carries Henry clear of the frame.
func _release_inside() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"release_inside")
	await _hold(&"move_forward", func() -> bool: return _along() >= 0.05, 8.0)
	await _settle_sampled(240)
	_end(&"release_inside", true, 1.0)


## W into the door, S from the door plane: Henry goes back out the way he came.
func _reverse() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"reverse")
	await _hold(&"move_forward", func() -> bool: return _along() >= 0.0, 8.0)
	await _hold(&"move_backward", func() -> bool: return _along() <= -END_IN, 8.0)
	await _settle_sampled(60)
	_end(&"reverse", true, -1.0)


## From inside, facing into the room, S walks Henry backwards out: the camera leads.
func _back_s() -> void:
	await _place(END_IN, 0.0, 0.0, -10.0)
	_begin(&"back_s")
	await _hold(&"move_backward", func() -> bool: return _along() <= -START_OUT, 10.0)
	await _settle_sampled(60)
	_end(&"back_s", true, -1.0)


## W into the door; from the threshold on the mouse swings hard left, right and back.
func _yaw_swing() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"yaw_swing")
	var swing: Array = [[100.0, 0.7], [-200.0, 1.2], [100.0, 0.7]]
	var leg: int = 0
	var leg_left: float = 0.0
	Input.action_press(&"move_forward")
	var ticks: int = Engine.get_physics_frames()
	while _along() < END_IN and Engine.get_physics_frames() - ticks < 600:
		if _along() >= -0.3 and leg_left <= 0.0 and leg < swing.size():
			leg_left = float(swing[leg][1])
			leg += 1
		if leg_left > 0.0:
			var dt: float = _probe.delta
			var rate: float = float(swing[leg - 1][0]) / float(swing[leg - 1][1])
			_mouse_deg(-rate * dt, 0.0)
			leg_left -= dt
		await _frame()
	Input.action_release(&"move_forward")
	await _settle_sampled(60)
	_end(&"yaw_swing", true, 1.0)


## W through the door while the mouse pitches down hard, then up, from 1.2 m before it.
func _pitch_swing() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"pitch_swing")
	var swing: Array = [[-50.0, 0.8], [100.0, 1.4], [-40.0, 0.6]]
	var leg: int = 0
	var leg_left: float = 0.0
	Input.action_press(&"move_forward")
	var ticks: int = Engine.get_physics_frames()
	while _along() < END_IN and Engine.get_physics_frames() - ticks < 600:
		if _along() >= -1.2 and leg_left <= 0.0 and leg < swing.size():
			leg_left = float(swing[leg][1])
			leg += 1
		if leg_left > 0.0:
			var dt: float = _probe.delta
			var rate: float = float(swing[leg - 1][0]) / float(swing[leg - 1][1])
			_mouse_deg(0.0, -rate * dt)
			leg_left -= dt
		await _frame()
	Input.action_release(&"move_forward")
	await _settle_sampled(60)
	_end(&"pitch_swing", true, 1.0)


func _left_shoulder() -> void:
	_switch_shoulder()
	await _straight(&"left_shoulder")
	_switch_shoulder()
	await _ticks(30)


## Crouched at the door and through it.
func _crouch() -> void:
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	Input.action_press(&"crouch")
	await _ticks(SETTLE_TICKS)
	_begin(&"crouch")
	await _hold(&"move_forward", func() -> bool: return _along() >= END_IN, 12.0)
	await _settle_sampled(60)
	Input.action_release(&"crouch")
	_end(&"crouch", true, 1.0)
	await _ticks(SETTLE_TICKS)


## The leaf stands 40 degrees open; Henry pushes it on the way through.
func _half_open() -> void:
	_open_door(signf(float(_door.get("open_angle_deg"))) * 40.0)
	await _place(-START_OUT, 0.0, 0.0, -10.0)
	_begin(&"half_open")
	await _hold(&"move_forward", func() -> bool: return _along() >= END_IN, 12.0)
	await _settle_sampled(60)
	_end(&"half_open", true, 1.0)


## Standing in the door plane, the mouse sweeps a full turn each way at three pitches.
func _stand_sweep() -> void:
	for pitch: float in [-10.0, -40.0, 30.0]:
		var tag := StringName("stand_sweep_%d" % int(pitch))
		await _place(0.0, 0.0, 0.0, pitch)
		_begin(tag)
		for direction: float in [1.0, -1.0, -1.0, 1.0]:
			for i: int in range(180):
				_mouse_deg(direction * 360.0 / 360.0, 0.0)
				await _frame()
		await _settle_sampled(30)
		_end(tag, false, 0.0)


## Once the frame has opened back out, the mouse turns a full 90 degrees, unresisted.
func _mouse_freedom(tag: StringName) -> void:
	await _ticks(180)
	var before: float = _cam.get_yaw()
	for i: int in range(45):
		_mouse_deg(2.0, 0.0)
		await _frame()
	await _ticks(2)
	var turned: float = rad_to_deg(angle_difference(_cam.get_yaw(), before))
	_check(absf(absf(turned) - 90.0) < 0.5, "%s: after the door 90 deg of mouse turned the yaw %.1f deg" % [tag, absf(turned)])


# --- Door frame ---------------------------------------------------------------

## Reality streams the walls around the door: stand Henry there and wait until its chunk is live and quiet.
func _wait_for_streamed_door() -> bool:
	var ground := _scene.find_child("RealityGround", true, false) as KeyWestRealityGround
	if ground == null:
		return true
	await _place(-2.0, 0.0, 0.0, -10.0)
	var quiet: int = 0
	for i: int in range(6000):
		var live: bool = ground.has_ground_at(_center.x, _center.z)
		var busy: bool = false
		for streaming: Node in _scene.find_children("*", "StreamingSystem", true, false):
			busy = busy or not (streaming as StreamingSystem)._transient.is_empty()
		quiet = quiet + 1 if live and not busy else 0
		if quiet >= 30:
			return true
		await _ticks(1)
	return false


func _find_door() -> bool:
	var zone := _scene.find_child("ShelterZone", true, false) as Node3D
	var breach: Node3D = zone.find_child("Door", true, false) as Node3D if zone != null else null
	if breach == null:
		return false
	var best: float = 4.0
	for node: Node in get_nodes_in_group(&"hinged_doors"):
		var door := node as Node3D
		if door != null and door.global_position.distance_to(breach.global_position) < best:
			_door = door
			best = door.global_position.distance_to(breach.global_position)
	if _door == null:
		return false
	var opening: Vector2 = _door.get("opening_size")
	_center = _door.global_position - Vector3.UP * opening.y * 0.5
	var axis: Vector3 = _door.global_basis.z
	axis.y = 0.0
	axis = axis.normalized()
	var to_room: Vector3 = zone.global_position - _center
	_inward = axis if to_room.dot(axis) >= 0.0 else -axis
	_across = _inward.cross(Vector3.UP).normalized()
	return true


func _open_door(angle_deg: float) -> void:
	_door.call(&"load_door_save_data", {"latched": false, "angle_deg": angle_deg})


## Henry's distance past the door plane into the room, metres.
func _along() -> float:
	var offset: Vector3 = _player.global_position - _center
	offset.y = 0.0
	return offset.dot(_inward)


## Puts Henry on the floor at `along` into the room and `lateral` across, with the
## control yaw `yaw` off the inward axis, and lets the camera settle.
func _place(along: float, lateral: float, yaw: float, pitch: float) -> void:
	_release_actions()
	var at: Vector3 = _floor_point(_center + _inward * along + _across * lateral)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	var heading: float = atan2(-_inward.x, -_inward.z) + yaw
	_player.rotation.y = heading
	_player.reset_physics_interpolation()
	_cam.set_look(heading, pitch)
	_cam.snap_to_target()
	await _ticks(SETTLE_TICKS)


## Henry's origin on the floor under `at`, cast from below the lintel.
func _floor_point(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at + Vector3.DOWN * 4.0)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = _space().intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 1.0 if not hit.is_empty() else at + Vector3.UP * 1.0


# --- Driving --------------------------------------------------------------------

func _hold(action: StringName, done: Callable, timeout: float) -> void:
	Input.action_press(action)
	var start: int = Engine.get_physics_frames()
	while not done.call() and float(Engine.get_physics_frames() - start) < timeout * Engine.physics_ticks_per_second:
		await _frame()
	Input.action_release(action)


func _release_actions() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"crouch"]:
		Input.action_release(action)


func _switch_shoulder() -> void:
	var event := InputEventAction.new()
	event.action = &"switch_shoulder"
	event.pressed = true
	Input.parse_input_event(event)
	var up := InputEventAction.new()
	up.action = &"switch_shoulder"
	up.pressed = false
	Input.parse_input_event(up)


func _mouse_deg(yaw_deg: float, pitch_deg: float) -> void:
	var per_px: float = rad_to_deg(MOUSE_SENSITIVITY)
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(yaw_deg / (per_px * _cam.look_sensitivity_x),
		pitch_deg / (per_px * _cam.look_sensitivity_y * _cam.pitch_sensitivity_ratio))
	event.relative = event.screen_relative
	Input.parse_input_event(event)
	_mouse_this_frame = true


func _ticks(count: int) -> void:
	for i: int in range(count):
		await physics_frame


func _settle_sampled(ticks: int) -> void:
	var start: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < ticks:
		await _frame()


## One rendered frame, then a sample of it.
func _frame() -> void:
	var moused: bool = _mouse_this_frame
	_mouse_this_frame = false
	await _probe.frame_done
	_sample(moused)


# --- Measuring ------------------------------------------------------------------

func _begin(tag: StringName) -> void:
	_rows.clear()
	_last_rel = Vector3.INF
	_last_fov = _cam.fov
	_last_control = _cam.get_yaw()
	_stats = {"tag": String(tag), "frames": 0, "faded": 0, "max_fade": 0.0, "inside": 0, "near_clip": 0,
		"occluded": 0, "off_screen": 0, "pops": 0, "max_step_m": 0.0, "max_fov_rate": 0.0, "fov_max": _cam.fov,
		"share_sum": 0.0, "share_sq": 0.0,
		"auto_yaw": 0, "min_head_m": INF, "min_height_share": INF, "max_height_share": 0.0}


func _sample(moused: bool) -> void:
	if _stats.is_empty():
		return
	var render: Vector3 = _cam.get_camera_transform().origin
	var head: Vector3 = _head()
	var henry: Vector3 = _player.get_global_transform_interpolated().origin
	var fade: float = _cam.get_body_fade()
	var rel: Vector3 = render - henry
	var step: float = 0.0 if _last_rel == Vector3.INF else rel.distance_to(_last_rel)
	_last_rel = rel
	var fov_rate: float = absf(_cam.fov - _last_fov) / maxf(_probe.delta, 1e-4)
	_last_fov = _cam.fov
	var popped: bool = step > POP_LIMIT and step / maxf(_probe.delta, 1e-4) > POP_SPEED
	var control: float = _cam.get_yaw()
	var auto_turned: bool = not moused and absf(angle_difference(control, _last_control)) > 1e-5
	_last_control = control
	var inside: bool = _point_inside(render)
	var near: bool = _near_clipped(render)
	var occluded: bool = _segment_blocked(render, head)
	var on_screen: bool = _cam.is_position_in_frustum(head) and _cam.is_position_in_frustum(henry)
	var share: float = _height_share(head)
	_stats["frames"] += 1
	if fade > 0.0:
		_stats["faded"] += 1
	_stats["max_fade"] = maxf(_stats["max_fade"], fade)
	_stats["inside"] += int(inside)
	_stats["near_clip"] += int(near)
	_stats["occluded"] += int(occluded)
	_stats["off_screen"] += int(not on_screen)
	_stats["pops"] += int(popped)
	_stats["max_step_m"] = maxf(_stats["max_step_m"], step)
	_stats["max_fov_rate"] = maxf(_stats["max_fov_rate"], fov_rate)
	_stats["share_sum"] += share
	_stats["share_sq"] += share * share
	_stats["fov_max"] = maxf(_stats["fov_max"], _cam.fov)
	_stats["auto_yaw"] += int(auto_turned)
	_stats["min_head_m"] = minf(_stats["min_head_m"], render.distance_to(head))
	_stats["min_height_share"] = minf(_stats["min_height_share"], share)
	_stats["max_height_share"] = maxf(_stats["max_height_share"], share)
	if not _label.is_empty():
		_rows.append({"tag": _stats["tag"], "along": _along(), "cam_x": render.x, "cam_y": render.y, "cam_z": render.z,
			"view_yaw": rad_to_deg(_cam.global_rotation.y), "control_yaw": rad_to_deg(control),
			"pitch": rad_to_deg(_cam.global_rotation.x), "fov": _cam.fov, "boom": _cam.get_boom_length(),
			"head_m": render.distance_to(head), "fade": fade,
			"passage": float(_cam.call(&"get_passage_blend")) if _cam.has_method(&"get_passage_blend") else 0.0, "inside": inside, "near_clip": near,
			"occluded": occluded, "on_screen": on_screen, "step_m": step, "height_share": share})


## Closes a scenario: checks and stores it. `expect_side` is +1 into the room, -1 out,
## 0 when Henry need not leave the door.
func _end(tag: StringName, traversed: bool, expect_side: float) -> void:
	var stats: Dictionary = _stats.duplicate()
	_stats = {}
	stats["end_along_m"] = _along()
	var frames: float = maxf(float(stats["frames"]), 1.0)
	var mean: float = float(stats["share_sum"]) / frames
	stats["height_share_mean"] = mean
	stats["height_share_std"] = sqrt(maxf(float(stats["share_sq"]) / frames - mean * mean, 0.0))
	stats.erase("share_sum")
	stats.erase("share_sq")
	var name: String = String(tag)
	_check(stats["faded"] == 0, "%s: Henry dithered in %d frames (max %.2f)" % [name, stats["faded"], stats["max_fade"]])
	_check(stats["inside"] == 0, "%s: camera inside geometry in %d frames" % [name, stats["inside"]])
	_check(stats["near_clip"] == 0, "%s: near plane clipped in %d frames" % [name, stats["near_clip"]])
	_check(stats["occluded"] == 0, "%s: head hidden behind geometry in %d frames" % [name, stats["occluded"]])
	_check(stats["off_screen"] == 0, "%s: Henry off screen in %d frames" % [name, stats["off_screen"]])
	_check(stats["pops"] == 0, "%s: %d one-frame pops, largest %.2f m" % [name, stats["pops"], stats["max_step_m"]])
	_check(stats["max_fov_rate"] <= FOV_RATE_LIMIT, "%s: FOV changed at %.1f deg/s" % [name, stats["max_fov_rate"]])
	_check(stats["auto_yaw"] == 0, "%s: control yaw turned without the mouse in %d frames" % [name, stats["auto_yaw"]])
	if traversed:
		var past: float = stats["end_along_m"] * expect_side
		_check(past >= CLEAR_OF_PLANE, "%s: Henry rests %.2f m from the door plane, not clear of it" % [name, stats["end_along_m"]])
	_summary[name] = stats
	if not _label.is_empty():
		_write_csv(name + ".csv")


func _stats_note(tag: StringName, key: String, value: Variant) -> void:
	if _summary.has(String(tag)):
		(_summary[String(tag)] as Dictionary)[key] = value


func _head() -> Vector3:
	if _skeleton != null and _head_bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin
	return _cam.get_eye_position()


## Henry's drawn height, crown to feet, as a share of the screen height.
func _height_share(head: Vector3) -> float:
	var feet: Vector3 = _player.get_global_transform_interpolated().origin - Vector3.UP
	if _cam.is_position_behind(head) or _cam.is_position_behind(feet):
		return 0.0
	var size: Vector2 = root.get_visible_rect().size
	return absf(_cam.unproject_position(feet).y - _cam.unproject_position(head + Vector3.UP * 0.15).y) / maxf(size.y, 1.0)


func _point_inside(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.exclude = [_player.get_rid()]
	return not _space().intersect_point(query, 1).is_empty()


func _near_clipped(point: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = NEAR_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.exclude = [_player.get_rid()]
	return not _space().intersect_shape(query, 1).is_empty()


func _segment_blocked(from: Vector3, to: Vector3) -> bool:
	if from.distance_to(to) < 0.001:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.hit_from_inside = true
	return not _space().intersect_ray(query).is_empty()


func _space() -> PhysicsDirectSpaceState3D:
	return _cam.get_world_3d().direct_space_state


# --- Output ---------------------------------------------------------------------

func _out_dir() -> String:
	var dir: String = ProjectSettings.globalize_path(OUT_ROOT.path_join(_label))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _write_csv(file_name: String) -> void:
	if _rows.is_empty():
		return
	var file := FileAccess.open(_out_dir().path_join(file_name), FileAccess.WRITE)
	var keys: Array = _rows[0].keys()
	file.store_line(",".join(PackedStringArray(keys)))
	for row: Dictionary in _rows:
		var cells: PackedStringArray = []
		for key: Variant in keys:
			cells.append(str(row[key]))
		file.store_line(",".join(cells))


func _finish() -> void:
	_release_actions()
	if not _label.is_empty():
		var file := FileAccess.open(_out_dir().path_join("summary.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(_summary, "  "))
	print(JSON.stringify(_summary, "  "))
	if _failures > 0:
		push_error("doorway camera: %d check(s) failed" % _failures)
		quit(1)
		return
	print("doorway camera: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	push_error("doorway camera: %s" % message)

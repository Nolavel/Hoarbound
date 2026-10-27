extends SceneTree

## The #240 camera measure: Henry walks one route through the 727 as a player would (W held,
## the mouse steering the camera at the next waypoint), with a full mouse turn at each stop.
## Per frame it logs eyes in frame, body fade, camera jumps, wall share and mouse deviation;
## report.json sums them per leg and for the whole route against the #240 criteria.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 1280x720 --fixed-fps 30 --script res://tools/runtime/trace_camera_route.gd -- [out_dir]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WARMUP_FRAMES: int = 300
## Steering: share of the yaw error the mouse closes per frame, and its cap.
const STEER_GAIN: float = 0.18
const STEER_MAX_RAD: float = deg_to_rad(5.0)
const REACH_M: float = 0.45
## A leg with no progress this long counts as stuck and Henry is moved to its waypoint.
const STUCK_FRAMES: int = 150
const TURN_FRAMES: int = 240
## Wall share: rays through a grid on screen; one hitting within WALL_NEAR_M counts as wall.
const WALL_GRID: Vector2i = Vector2i(8, 5)
const WALL_NEAR_M: float = 0.6
## #240 criteria.
const JUMP_M: float = 0.3
const EYE_MARGIN: float = 0.02
## Legs: [name, waypoints (u, v) in the shelter plan, turn a full circle at the end].
const LEGS: Array = [
	["street_to_door", [Vector2(6.23, 5.4), Vector2(6.23, 3.6)], false],
	["door_to_lobby", [Vector2(6.23, 2.4), Vector2(4.6, 1.6)], false],
	["arch_to_stove", [Vector2(2.4, 1.8), Vector2(1.2, 4.6), Vector2(0.4, 6.6)], true],
	["stove_to_corridor", [Vector2(-1.0, 2.2), Vector2(-1.0, 0.7), Vector2(-1.0, -0.7)], false],
	["corridor_to_exam_corner", [Vector2(-4.5, -0.7), Vector2(-4.5, -2.3), Vector2(-6.2, -5.7)], true],
	["exam_to_restroom", [Vector2(-4.5, -2.3), Vector2(-4.5, -0.7), Vector2(-11.1, -0.7), Vector2(-11.1, 0.6), Vector2(-11.1, 1.7)], true],
	["restroom_to_stove", [Vector2(-11.1, 0.6), Vector2(-11.1, -0.7), Vector2(-1.0, -0.7), Vector2(-1.0, 0.7), Vector2(-1.0, 2.6), Vector2(0.4, 6.6)], true],
]

var _out: String = "user://shots/camera_route_trace"
var _world: Node3D
var _house: Node3D
var _floor_y: float = 0.15
var _player: CharacterBody3D
var _camera: TpsCamera
var _input: Node
var _space: PhysicsDirectSpaceState3D
var _frame: int = 0
var _leg: int = -1
var _point: int = 0
var _phase: String = ""
var _phase_frame: int = 0
var _best_distance: float = INF
var _since_progress: int = 0
var _stuck: Array[String] = []
var _prev_cam: Vector3 = Vector3.INF
var _rows: Array[Dictionary] = []
var _csv: FileAccess


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_abs(_out))
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	_world.set(&"spawn_at_shelter", true)
	root.add_child(_world)
	## The numbers need physics and the camera, not pixels: 3D draws only for the saved shots.
	root.disable_3d = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	if _camera == null and not _bind():
		quit(1)
		return true
	_phase_frame += 1
	match _phase:
		"":
			_next_leg()
		"walk":
			_walk()
		"turn":
			_feed_look(Vector2(TAU / float(TURN_FRAMES), 0.0))
			if _phase_frame >= TURN_FRAMES:
				_phase = ""
	if _leg >= LEGS.size():
		_finish()
		return true
	if _phase != "":
		_record()
		if _phase_frame % 90 == 89:
			root.disable_3d = false
		elif _phase_frame % 90 == 0:
			_shot("%02d_%s_%s_%04d" % [_leg, LEGS[_leg][0], _phase, _phase_frame])
	return false


func _bind() -> bool:
	var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
	_player = _world.get(&"player") as CharacterBody3D
	_camera = _world.get(&"camera") as TpsCamera
	_input = root.get_node_or_null(^"InputSystems")
	if shelter == null or _player == null or _camera == null or _input == null:
		push_error("camera route: shelter, player, TpsCamera or InputSystems missing")
		return false
	_house = shelter.get_node(^"House") as Node3D
	_floor_y = float(shelter.interior["floor_y"])
	_space = _player.get_world_3d().direct_space_state
	for door: HingedDoor in _world.find_children("*", "HingedDoor", true, false):
		if _house.is_ancestor_of(door) and not door.is_open():
			door.interact()
	_csv = FileAccess.open(_abs(_out).path_join("trace.csv"), FileAccess.WRITE)
	_csv.store_line("leg,phase,frame,eye_sx,eye_sy,eye_in,body_fade,cam_step,wall_share,body_share,mouse_dev_deg,pitch,boom,side,lift,room,cam_x,cam_y,cam_z,view_yaw,fov")
	return true


func _next_leg() -> void:
	_leg += 1
	if _leg >= LEGS.size():
		return
	_point = 0
	_begin(&"walk")
	Input.action_press(&"move_forward")


func _walk() -> void:
	var points: Array = LEGS[_leg][1]
	var target: Vector3 = _plan(points[_point])
	var to: Vector3 = target - _player.global_position
	to.y = 0.0
	var distance: float = to.length()
	if distance < _best_distance - 0.02:
		_best_distance = distance
		_since_progress = 0
	else:
		_since_progress += 1
	if distance < REACH_M or _since_progress > STUCK_FRAMES:
		if _since_progress > STUCK_FRAMES:
			_stuck.append("%s#%d" % [LEGS[_leg][0], _point])
			_player.global_position = Vector3(target.x, _player.global_position.y, target.z)
			_player.velocity = Vector3.ZERO
			_prev_cam = Vector3.INF  # the move is the trace's, not the camera's
		_point += 1
		_best_distance = INF
		_since_progress = 0
		if _point >= points.size():
			Input.action_release(&"move_forward")
			_phase = "turn" if bool(LEGS[_leg][2]) else ""
			_phase_frame = 0
		return
	## The mouse turns the camera toward the waypoint, as a player steers with W held.
	var want: float = atan2(-to.x, -to.z)
	var error: float = wrapf(want - _camera.get_yaw(), -PI, PI)
	_feed_look(Vector2(clampf(error * STEER_GAIN, -STEER_MAX_RAD, STEER_MAX_RAD), 0.0))


func _begin(phase: StringName) -> void:
	_phase = String(phase)
	_phase_frame = 0
	_best_distance = INF
	_since_progress = 0


## Mouse travel in radians of camera turn, through the input system the camera reads.
func _feed_look(turn: Vector2) -> void:
	var sens: float = _camera.look_sensitivity_x * float(_camera.get(&"_user_mouse_sensitivity_multiplier"))
	var look := Vector2(-turn.x / maxf(sens, 1e-4), -rad_to_deg(turn.y) / maxf(_camera.look_sensitivity_y, 1e-4) / 57.2958)
	_input.set(&"_look_accum", _input.get(&"_look_accum") + look)


func _record() -> void:
	var state: Dictionary = _camera.get_debug_state()
	var size: Vector2 = root.get_viewport().get_visible_rect().size
	var eye_world: Vector3 = _camera.get_eye_position()
	var eye: Vector2 = _camera.unproject_position(eye_world) / size
	var eye_in: bool = not _camera.is_position_behind(eye_world) and eye.x > EYE_MARGIN and eye.x < 1.0 - EYE_MARGIN \
			and eye.y > EYE_MARGIN and eye.y < 1.0 - EYE_MARGIN
	var cam: Vector3 = _camera.global_position
	var step: float = 0.0 if _prev_cam == Vector3.INF else cam.distance_to(_prev_cam)
	_prev_cam = cam
	var dev: float = absf(rad_to_deg(wrapf(float(state.view_yaw) - float(state.yaw), -PI, PI)))
	var row: Dictionary = {"leg": LEGS[_leg][0], "phase": _phase, "frame": _phase_frame, "eye_sx": eye.x, "eye_sy": eye.y,
		"eye_in": eye_in, "body_fade": float(state.get("body_fade", _camera.get_body_fade())), "cam_step": step,
		"wall_share": _wall_share(size), "body_share": _body_share(size), "mouse_dev_deg": dev, "pitch": float(state.pitch), "boom": float(state.boom),
		"side": float(state.side), "lift": float(state.lift), "room": str(state.get("room", ""))}
	_rows.append(row)
	_csv.store_line("%s,%s,%d,%.4f,%.4f,%d,%.3f,%.4f,%.3f,%.3f,%.2f,%.2f,%.3f,%.3f,%.3f,%s,%.6f,%.6f,%.6f,%.6f,%.4f" % [row.leg, row.phase, row.frame,
		row.eye_sx, row.eye_sy, int(eye_in), row.body_fade, step, row.wall_share, row.body_share, dev, row.pitch, row.boom, row.side,
		row.lift, row.room, cam.x, cam.y, cam.z, float(state.view_yaw), _camera.fov])


## Share of a screen grid whose rays hit geometry within WALL_NEAR_M of the lens; Henry is excluded.
func _wall_share(size: Vector2) -> float:
	var near: int = 0
	var exclude: Array[RID] = [_player.get_rid()]
	for gx: int in range(WALL_GRID.x):
		for gy: int in range(WALL_GRID.y):
			var pixel := Vector2((float(gx) + 0.5) / float(WALL_GRID.x), (float(gy) + 0.5) / float(WALL_GRID.y)) * size
			var origin: Vector3 = _camera.project_ray_origin(pixel)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(pixel) * WALL_NEAR_M)
			query.exclude = exclude
			if not _space.intersect_ray(query).is_empty():
				near += 1
	return float(near) / float(WALL_GRID.x * WALL_GRID.y)


## Share of a finer screen grid whose first hit is Henry's own body (capsule and carried pack).
func _body_share(size: Vector2) -> float:
	var hits: int = 0
	var grid := Vector2i(16, 9)
	for gx: int in range(grid.x):
		for gy: int in range(grid.y):
			var pixel := Vector2((float(gx) + 0.5) / float(grid.x), (float(gy) + 0.5) / float(grid.y)) * size
			var origin: Vector3 = _camera.project_ray_origin(pixel)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(pixel) * 6.0)
			var hit: Dictionary = _space.intersect_ray(query)
			if not hit.is_empty() and hit.collider == _player:
				hits += 1
	return float(hits) / float(grid.x * grid.y)


func _finish() -> void:
	_csv.close()
	var report: Dictionary = {"stuck": _stuck}
	var groups: Dictionary = {"_route": _rows}
	for row: Dictionary in _rows:
		groups.get_or_add("%s/%s" % [row.leg, row.phase], []).append(row)
	for key: String in groups:
		report[key] = _summarise(groups[key])
	var total: Dictionary = report["_route"]
	report["_criteria"] = {"eyes_in_frame_pct >= 99": total.eyes_in_frame_pct >= 99.0,
		"faded_pct <= 0.5": total.faded_pct <= 0.5, "jumps_over_0.3m == 0": total.jumps_over_0_3m == 0}
	var file: FileAccess = FileAccess.open(_abs(_out).path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("camera route: ", JSON.stringify(total))
	print("camera route: criteria ", JSON.stringify(report["_criteria"]), " stuck ", _stuck)
	print("camera route: done -> ", _abs(_out))
	quit(0)


func _summarise(rows: Array) -> Dictionary:
	var n: int = maxi(rows.size(), 1)
	var eyes: int = 0
	var low: int = 0
	var faded: int = 0
	var jumps: int = 0
	var walled: int = 0
	var max_step: float = 0.0
	var wall_sum: float = 0.0
	var dev_sum: float = 0.0
	var dev_max: float = 0.0
	var body_sum: float = 0.0
	var body_max: float = 0.0
	for row: Dictionary in rows:
		body_sum += float(row.body_share)
		body_max = maxf(body_max, float(row.body_share))
		eyes += int(row.eye_in)
		low += int(float(row.eye_sy) > 0.85)
		faded += int(float(row.body_fade) > 0.01)
		jumps += int(float(row.cam_step) > JUMP_M)
		walled += int(float(row.wall_share) >= 0.5)
		max_step = maxf(max_step, float(row.cam_step))
		wall_sum += float(row.wall_share)
		dev_sum += float(row.mouse_dev_deg)
		dev_max = maxf(dev_max, float(row.mouse_dev_deg))
	return {"frames": rows.size(), "eyes_in_frame_pct": snappedf(100.0 * eyes / n, 0.01),
		"eyes_low_pct": snappedf(100.0 * low / n, 0.01), "faded_pct": snappedf(100.0 * faded / n, 0.01),
		"jumps_over_0_3m": jumps, "max_step_m": snappedf(max_step, 0.001), "wall_half_frame_pct": snappedf(100.0 * walled / n, 0.01),
		"wall_share_mean": snappedf(wall_sum / n, 0.001), "mouse_dev_mean_deg": snappedf(dev_sum / n, 0.01),
		"mouse_dev_max_deg": snappedf(dev_max, 0.1), "body_share_mean": snappedf(body_sum / n, 0.001),
		"body_share_max": snappedf(body_max, 0.001)}


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_viewport().get_texture().get_image().save_png(_abs(_out).path_join(shot_name + ".png"))
	root.disable_3d = true


## Plan point (u, v) on the shelter floor in world space.
func _plan(uv: Vector2) -> Vector3:
	return _house.global_transform * Vector3(uv.x, _floor_y + 0.05, uv.y)


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") else path

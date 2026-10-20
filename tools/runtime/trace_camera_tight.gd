extends SceneTree

## Tight-space camera trace in the real 727 shelter: at each spot Henry stands still while the
## mouse turns the camera a full circle, then rests, then sweeps pitch. Every frame logs the
## framing state; report.json sums how much the frame moves on its own while the player turns.
## Run (windowed, headless is 64x64): godot --path . --resolution 1280x720 --fixed-fps 30 --script res://tools/runtime/trace_camera_tight.gd -- [out_dir]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WARMUP_FRAMES: int = 300
const SETTLE_FRAMES: int = 60
const TURN_FRAMES: int = 240
const IDLE_FRAMES: int = 150
const PITCH_FRAMES: int = 150
## Frames saved during the turn, one every this many.
const SHOT_EVERY: int = 30
## [name, Henry (u, v), facing point (u, v)] in the shelter plan frame.
const SPOTS: Array = [
	["stove", Vector2(1.3, 8.6), Vector2(-1.2, 6.4)],
	["corridor", Vector2(-3.0, -0.7), Vector2(6.0, -0.7)],
	["exam_corner", Vector2(-6.3, -5.9), Vector2(-4.5, -4.0)],
	["restroom", Vector2(-11.1, 1.6), Vector2(-11.1, 0.4)],
]

var _out: String = "user://shots/camera_tight_trace"
var _world: Node3D
var _house: Node3D
var _floor_y: float = 0.15
var _player: CharacterBody3D
var _camera: TpsCamera
var _input: Node
var _frame: int = 0
var _spot: int = -1
var _phase: String = ""
var _phase_frame: int = 0
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
			_next_spot()
		"settle":
			if _phase_frame >= SETTLE_FRAMES:
				_begin(&"turn")
		"turn":
			if _phase_frame == 1:
				_print_passage()
			_feed_look(Vector2(TAU / float(TURN_FRAMES), 0.0))
			_record()
			if _phase_frame % SHOT_EVERY == 0:
				_shot("%s_turn_%03d" % [SPOTS[_spot][0], _phase_frame])
			if _phase_frame >= TURN_FRAMES:
				_begin(&"idle")
		"idle":
			_record()
			if _phase_frame >= IDLE_FRAMES:
				_begin(&"pitch")
		"pitch":
			var step: float = deg_to_rad(80.0) / float(PITCH_FRAMES) * 2.0
			_feed_look(Vector2(0.0, -step if _phase_frame < PITCH_FRAMES / 4 or _phase_frame > PITCH_FRAMES * 3 / 4 else step))
			_record()
			if _phase_frame >= PITCH_FRAMES:
				_phase = ""
	if _spot >= SPOTS.size():
		_finish()
		return true
	return false


func _bind() -> bool:
	var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
	_player = _world.get(&"player") as CharacterBody3D
	_camera = _world.get(&"camera") as TpsCamera
	_input = root.get_node_or_null(^"InputSystems")
	if shelter == null or _player == null or _camera == null or _input == null:
		push_error("camera trace: shelter, player, TpsCamera or InputSystems missing")
		return false
	_house = shelter.get_node(^"House") as Node3D
	_floor_y = float(shelter.interior["floor_y"])
	_csv = FileAccess.open(_abs(_out).path_join("trace.csv"), FileAccess.WRITE)
	_csv.store_line("spot,phase,frame,yaw_deg,view_yaw_deg,pitch,auto_yaw_deg,auto_pitch_deg,openness,boom,side,shoulder_pct,recompose,composition,lift,eye_distance,passage_blend,traversal,eye_sx,eye_sy,cam_x,cam_y,cam_z")
	return true


func _next_spot() -> void:
	_spot += 1
	if _spot >= SPOTS.size():
		return
	var spot: Array = SPOTS[_spot]
	var at: Vector3 = _plan(spot[1])
	var face: Vector3 = _plan(spot[2])
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(face.x, at.y, face.z), Vector3.UP)
	var to: Vector3 = face - at
	_camera.set_look(atan2(-to.x, -to.z), -10.0)
	_camera.snap_to_target()
	_begin(&"settle")


func _begin(phase: StringName) -> void:
	_phase = String(phase)
	_phase_frame = 0


## Mouse travel in radians of camera turn, through the input system the camera reads.
func _feed_look(turn: Vector2) -> void:
	var sens: float = _camera.look_sensitivity_x * float(_camera.get(&"_user_mouse_sensitivity_multiplier"))
	var look := Vector2(-turn.x / maxf(sens, 1e-4), -rad_to_deg(turn.y) / maxf(_camera.look_sensitivity_y, 1e-4) / 57.2958)
	_input.set(&"_look_accum", _input.get(&"_look_accum") + look)


func _record() -> void:
	var state: Dictionary = _camera.get_debug_state()
	var size: Vector2 = root.get_viewport().get_visible_rect().size
	var eye: Vector2 = _camera.unproject_position(_camera.get_eye_position()) / size
	var cam: Vector3 = _camera.global_position
	state.merge({"spot": SPOTS[_spot][0], "phase": _phase, "frame": _phase_frame, "eye_sx": eye.x, "eye_sy": eye.y,
		"cam": cam})
	_rows.append(state)
	_csv.store_line("%s,%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.3f,%.3f,%.3f" % [
		state.spot, state.phase, state.frame, rad_to_deg(state.yaw), rad_to_deg(state.view_yaw), state.pitch,
		state.auto_yaw_deg, state.auto_pitch_deg, state.openness, state.boom, state.side, state.shoulder_pct,
		state.recompose, state.composition, state.lift, state.eye_distance, state.passage_blend, state.traversal, eye.x, eye.y,
		cam.x, cam.y, cam.z])


## Per spot and phase: how far boom, side and Henry's screen position travel, their largest
## single-frame jumps, recompose flips and the largest automatic turn.
func _finish() -> void:
	_csv.close()
	var report: Dictionary = {}
	var groups: Dictionary = {}
	for row: Dictionary in _rows:
		var key: String = "%s/%s" % [row.spot, row.phase]
		groups.get_or_add(key, []).append(row)
	for key: String in groups:
		var rows: Array = groups[key]
		var sum: Dictionary = {"frames": rows.size()}
		for field: String in ["boom", "side", "composition", "lift", "eye_sx", "eye_sy", "openness"]:
			var lo: float = INF
			var hi: float = -INF
			var jump: float = 0.0
			for i: int in range(rows.size()):
				var v: float = float(rows[i][field])
				lo = minf(lo, v)
				hi = maxf(hi, v)
				if i > 0:
					jump = maxf(jump, absf(v - float(rows[i - 1][field])))
			sum[field] = {"min": snappedf(lo, 0.001), "max": snappedf(hi, 0.001), "range": snappedf(hi - lo, 0.001), "max_step": snappedf(jump, 0.0001)}
		var flips: int = 0
		var auto_max: float = 0.0
		for i: int in range(rows.size()):
			auto_max = maxf(auto_max, maxf(absf(float(rows[i].auto_yaw_deg)), absf(float(rows[i].auto_pitch_deg))))
			if i > 0 and (float(rows[i].recompose) > 0.5) != (float(rows[i - 1].recompose) > 0.5):
				flips += 1
		sum["recompose_flips"] = flips
		var off: int = 0
		var close: int = 0
		for row: Dictionary in rows:
			if float(row.eye_sx) < 0.0 or float(row.eye_sx) > 1.0 or float(row.eye_sy) < 0.0 or float(row.eye_sy) > 1.0:
				off += 1
			if float(row.eye_distance) < 0.8:
				close += 1
		sum["eye_off_frames"] = off
		sum["close_frames"] = close
		sum["auto_turn_max_deg"] = snappedf(auto_max, 0.1)
		report[key] = sum
	var file: FileAccess = FileAccess.open(_abs(_out).path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("camera trace: done -> ", _abs(_out))
	quit(0)


func _print_passage() -> void:
	var traversal: PassageTraversalComponent = _player.get_node_or_null(^"PassageTraversalComponent") as PassageTraversalComponent
	var info: PassageInfo = traversal.get_nearby_passage() if traversal != null else null
	if info == null:
		print("camera trace: %s no passage" % SPOTS[_spot][0])
		return
	var feet: Vector3 = _player.global_position
	print("camera trace: %s passage engaged=%s along=%.2f lateral=%.2f half_depth=%.2f width=%.2f" % [SPOTS[_spot][0],
		traversal.is_active(), info.along_of(feet), info.lateral_of(feet), info.half_depth(), info.clear_width])


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_viewport().get_texture().get_image().save_png(_abs(_out).path_join(shot_name + ".png"))


## Plan point (u, v) on the shelter floor in world space.
func _plan(uv: Vector2) -> Vector3:
	return _house.global_transform * Vector3(uv.x, _floor_y + 0.05, uv.y)


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") else path

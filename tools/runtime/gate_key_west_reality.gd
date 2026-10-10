extends SceneTree
## Production gate: the real World (Henry, camera, snow, weather, streaming) on generated chunks.
## Henry walks the First Exit + Old Town route by input; frame, streaming, memory, errors are logged.
## godot --path . --script res://tools/runtime/gate_key_west_reality.gd -- [--fast] [--legs=N] [--out=DIR] [--shots]

const DEFAULT_SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const ROUTE: String = "res://data/world/key_west/reality/routes/first_exit_gate.json"
const THERMAL: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const REACH_M: float = 2.0
const LOOKAHEAD_M: float = 4.0
## Blocked = forward held but under STUCK_MOVE_M of real displacement in STUCK_WINDOW_S.
## Reported velocity is not enough: a capsule pinned in thin geometry reports full speed.
const STUCK_MOVE_M: float = 1.0
const STUCK_WINDOW_S: float = 4.0
const HITCH_MS: float = 50.0
const CHUNK_M: float = 512.0
const WARMUP_FRAMES: int = 30


class GateLogger:
	extends Logger
	var errors: int = 0
	var warnings: int = 0
	## Headless only: the dummy renderer has no textures, so texture reads fail there and nowhere else.
	var headless_renderer_errors: int = 0
	var samples: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array) -> void:
		_mutex.lock()
		if file.contains("servers/rendering/dummy"):
			headless_renderer_errors += 1
			_mutex.unlock()
			return
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
		if samples.size() < 40:
			samples.append("%s %s (%s:%d %s)" % ["W" if error_type == ERROR_TYPE_WARNING else "E", rationale if rationale != "" else code, file, line, function])
		_mutex.unlock()


var _out: String = "user://gate_key_west_reality"
var _fast: bool = false
var _shots: bool = false
var _trace: bool = false
var _max_legs: int = 1 << 20
var _logger: GateLogger = GateLogger.new()
var _world: Node3D
var _player: CharacterBody3D
var _cam: Node
var _streaming: StreamingSystem
var _snow: Node
var _mover: Node
var _thermal: Node
var _route: Dictionary
var _points: PackedVector2Array
var _leg_starts: Array = []
var _seg: int = 0
var _leg: int = 0
var _frame: int = 0
var _last_usec: int = 0
var _t0: int = 0
var _game_s: float = 0.0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _activation_frames: Dictionary = {}
var _activations: Array = []
var _unloaded_s: float = 0.0
var _unloaded_ids: Dictionary = {}
var _stuck: Array = []
var _window_s: float = 0.0
var _window_walked: float = 0.0
var _orbits: Array = []
var _disable: PackedStringArray = PackedStringArray()
var _scene: String = DEFAULT_SCENE
var _window_from: Vector3
var _arrivals: Array = []
var _distance_walked: float = 0.0
var _last_pos: Vector3
var _peak: Dictionary = {"static_mb": 0.0, "video_mb": 0.0, "nodes": 0, "draw_calls": 0, "primitives": 0, "active_chunks": 0}
var _min_y: float = INF
var _hitches: Array = []
var _done: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--fast":
			_fast = true
		elif arg == "--shots":
			_shots = true
		elif arg == "--trace":
			_trace = true
		elif arg.begins_with("--scene="):
			_scene = arg.get_slice("=", 1)
		elif arg.begins_with("--disable="):
			_disable = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--legs="):
			_max_legs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	OS.add_logger(_logger)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_route = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	for p: Array in _route["points"]:
		_points.append(Vector2(float(p[0]), float(p[1])))
	for leg: Dictionary in _route["legs"]:
		_leg_starts.append(int(leg["first_point"]))
	_t0 = Time.get_ticks_usec()
	_world = (load(_scene) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _physics_process(delta: float) -> bool:
	if _done:
		return false  # quit(code) is already requested; returning true would reset it to 0
	if _player == null and not _bind():
		return false
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	_game_s += delta
	var pos: Vector3 = _player.global_position
	var step: float = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_distance_walked += step
	_window_walked += step
	_last_pos = pos
	_min_y = minf(_min_y, pos.y)
	if _fast:
		_assist()
	var here: Vector2 = Vector2(pos.x, pos.z)
	var aim: Vector2 = _steer(here)
	if _done:
		_finish()
		return false
	_window_s += delta
	if _window_s >= STUCK_WINDOW_S:
		if Vector2(pos.x - _window_from.x, pos.z - _window_from.z).length() < STUCK_MOVE_M:
			if _window_walked < STUCK_MOVE_M:
				_unstick(pos, _points[mini(_seg + 1, _points.size() - 1)])
			else:
				## Moving but circling a vertex: a steering artefact, not a blocked world.
				_orbits.append({"game_s": snappedf(_game_s, 0.1), "at": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "walked_m": snappedf(_window_walked, 0.1)})
				_seg = mini(_seg + 1, _points.size() - 2)
				_reached(_seg)
		_window_s = 0.0
		_window_walked = 0.0
		_window_from = _player.global_position
	var to: Vector2 = aim - here
	_cam.call(&"set_look", atan2(-to.x, -to.y), -12.0)
	if _trace and _frame % 60 == 0:
		print("trace seg=%d/%d leg=%d pos=%s aim=%s speed=%.2f slow=%.1f" % [_seg, _points.size(), _leg, pos, aim,
			Vector2(_player.velocity.x, _player.velocity.z).length(), _window_s])
	Input.action_press(&"move_forward")
	if _fast:
		Input.action_press(&"sprint")
	return false


func _process(_delta: float) -> bool:
	if _player == null or _frame < WARMUP_FRAMES:
		_last_usec = Time.get_ticks_usec()
		return false
	var now: int = Time.get_ticks_usec()
	var ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	_frames.append(ms)
	if ms > HITCH_MS and _hitches.size() < 400:
		_hitches.append({"frame": _frames.size() - 1, "ms": snappedf(ms, 0.1),
			"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
			"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
			"game_s": snappedf(_game_s, 0.1), "at": [snappedf(_player.global_position.x, 0.1), snappedf(_player.global_position.z, 0.1)]})
	var pos: Vector3 = _player.global_position
	var own: StringName = StringName("kw_gen_%d_%d" % [floori(pos.x / CHUNK_M), floori(pos.z / CHUNK_M)])
	if _streaming._chunks.has(own) and _streaming.get_state(own) != StreamingSystem.CellState.ACTIVE:
		_unloaded_s += ms / 1000.0
		_unloaded_ids[String(own)] = true
	_peak["static_mb"] = maxf(_peak["static_mb"], Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	_peak["video_mb"] = maxf(_peak["video_mb"], Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	_peak["nodes"] = maxi(_peak["nodes"], int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_peak["draw_calls"] = maxi(_peak["draw_calls"], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_peak["primitives"] = maxi(_peak["primitives"], int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_peak["active_chunks"] = maxi(_peak["active_chunks"], _streaming.get_active_chunks().size())
	return false


func _bind() -> bool:
	var ctx: WorldContext = _world.call(&"get_context") if _world.has_method(&"get_context") else null
	if ctx == null:
		return false
	_player = ctx.player as CharacterBody3D
	_cam = ctx.camera
	_thermal = ctx.get_system(THERMAL)
	for system: Node in ctx.systems:
		if system is StreamingSystem:
			_streaming = system
		elif &"deep_snow_speed" in system:
			_snow = system
	_mover = _player.get_node_or_null(^"MovementController")
	for system: Node in ctx.systems:
		var path: String = (system.get_script() as Script).resource_path if system.get_script() != null else ""
		for key: String in _disable:
			if key != "" and path.contains(key):
				system.process_mode = Node.PROCESS_MODE_DISABLED
				print("gate: diagnosis disabled ", path)
	_streaming.cell_state_changed.connect(_on_cell)
	_last_pos = _player.global_position
	_window_from = _last_pos
	print("gate: bound after %.2f s; spawn %s; route %.0f m, %d legs" % [(Time.get_ticks_usec() - _t0) / 1e6, _last_pos,
		float(_route["length_m"]), _leg_starts.size()])
	return true


func _on_cell(id: StringName, state: StreamingSystem.CellState) -> void:
	if state == StreamingSystem.CellState.ACTIVE:
		_activation_frames[_frames.size()] = String(id)


## Fast mode keeps Henry at sprint speed so a CPU container covers 3.8 km in minutes.
func _assist() -> void:
	var stamina: Node = _player.find_child("StaminaManager", true, false)
	if stamina != null:
		stamina.call(&"restore_stamina")
	if _snow != null:
		_snow.set(&"deep_snow_speed", 1.0)
		_snow.set(&"deep_snow_accel", 1.0)


## Pure pursuit: follow the projection on the current segment, aim LOOKAHEAD_M further along.
func _steer(here: Vector2) -> Vector2:
	var t: float = 0.0
	while _seg < _points.size() - 1:
		var a: Vector2 = _points[_seg]
		var ab: Vector2 = _points[_seg + 1] - a
		t = clampf((here - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if t < 0.999 and here.distance_to(_points[_seg + 1]) > REACH_M:
			break
		_seg += 1
		_reached(_seg)
		if _done:
			return here
		t = 0.0
	if _seg >= _points.size() - 1:
		return _points[_points.size() - 1]
	var p: Vector2 = _points[_seg].lerp(_points[_seg + 1], t)
	var left: float = LOOKAHEAD_M
	var k: int = _seg + 1
	while k < _points.size():
		var step: float = p.distance_to(_points[k])
		if step >= left:
			return p.move_toward(_points[k], left)
		left -= step
		p = _points[k]
		k += 1
	return p


func _reached(vertex: int) -> void:
	var leg_end: int = (int(_leg_starts[_leg + 1]) - 1) if _leg + 1 < _leg_starts.size() else _points.size() - 1
	if vertex < leg_end:
		return
	_arrive(_leg)
	_leg += 1
	if _leg >= mini(_max_legs, _leg_starts.size()):
		_done = true


func _arrive(leg: int) -> void:
	var info: Dictionary = _route["legs"][leg]
	var rec: Dictionary = {"leg": info["to"], "game_s": snappedf(_game_s, 0.1), "walked_m": snappedf(_distance_walked, 0.1),
		"position": [snappedf(_player.global_position.x, 0.01), snappedf(_player.global_position.y, 0.01), snappedf(_player.global_position.z, 0.01)]}
	if String(info["to"]).begins_with("727"):
		rec["sheltered"] = _thermal != null and bool(_thermal.call(&"is_sheltered"))
		rec["entry"] = "blocked: the measured 727 asset has no opening (Legistar plans or an owner-approved game door needed)"
	_arrivals.append(rec)
	print("gate: arrived %s at %.0f s game, %.0f m walked" % [info["to"], _game_s, _distance_walked])
	if _shots:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("arrive_%02d_%s.png" % [leg, info["to"]]))


func _unstick(pos: Vector3, target: Vector2) -> void:
	var slide: KinematicCollision3D = _player.get_last_slide_collision()
	_stuck.append({"game_s": snappedf(_game_s, 0.1), "at": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"target": [snappedf(target.x, 0.01), snappedf(target.y, 0.01)], "leg": _route["legs"][mini(_leg, _route["legs"].size() - 1)]["to"],
		"speed_mps": snappedf(Vector2(_player.velocity.x, _player.velocity.z).length(), 0.01), "on_floor": _player.is_on_floor(),
		"snow_speed_multiplier": snappedf(float(_mover.get(&"snow_speed_multiplier")), 0.01) if _mover != null else null,
		"collider": str((slide.get_collider() as Node).get_path()) if slide != null and slide.get_collider() is Node else null,
		"collision_normal": var_to_str(slide.get_normal()) if slide != null else null})
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(target.x, 80.0, target.y), Vector3(target.x, -20.0, target.y)))
	var y: float = float(hit["position"].y) + 1.2 if not hit.is_empty() else pos.y + 1.0
	_player.global_position = Vector3(target.x, y, target.y)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_window_s = 0.0
	_window_walked = 0.0
	_window_from = _player.global_position


func _finish() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	var sorted: PackedFloat32Array = _frames.duplicate()
	sorted.sort()
	var hitch_frames: Array = []
	for i: int in range(_frames.size()):
		if _frames[i] > HITCH_MS:
			hitch_frames.append(i)
	var act_ms: Array = []
	for i: int in _activation_frames.keys():
		var worst: float = 0.0
		for k: int in range(i, mini(i + 3, _frames.size())):
			worst = maxf(worst, _frames[k])
		act_ms.append(worst)
		_activations.append({"id": _activation_frames[i], "frame": i, "frame_ms_max_next3": snappedf(worst, 0.01)})
	act_ms.sort()
	var report: Dictionary = {
		"gate": "key_west_reality_first_exit", "scene": _scene, "mode": "fast (sprint, stamina+snow assist)" if _fast else "realistic",
		"engine": Engine.get_version_info()["string"], "renderer": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "route_m": _route["length_m"], "legs_requested": _max_legs,
		"game_seconds": snappedf(_game_s, 0.1), "walked_m": snappedf(_distance_walked, 0.1),
		"arrivals": _arrivals, "stuck_events": _stuck, "steering_orbits": _orbits, "disabled_for_diagnosis": _disable, "lowest_y": snappedf(_min_y, 0.01),
		"frames": _frames.size(),
		"frame_ms": {"p50": _pct(sorted, 0.5), "p95": _pct(sorted, 0.95), "p99": _pct(sorted, 0.99), "max": sorted[-1] if not sorted.is_empty() else 0.0,
			"over_16_7": _count_over(sorted, 16.7), "over_33_3": _count_over(sorted, 33.3), "over_hitch_50": hitch_frames.size()},
		"activations": {"count": _activations.size(), "frame_ms_p50": _pct(act_ms, 0.5), "frame_ms_max": act_ms.back() if not act_ms.is_empty() else 0.0,
			"worst": _worst(_activations, 8)},
		"hitches": _attribute_hitches(),
		"player_in_inactive_chunk": {"seconds": snappedf(_unloaded_s, 0.001), "chunks": _unloaded_ids.keys()},
		"peaks": _peak, "errors": _logger.errors, "warnings": _logger.warnings,
		"headless_renderer_errors": _logger.headless_renderer_errors, "log_samples": _logger.samples,
	}
	report["verdict"] = {
		"reached_all_requested_legs": _arrivals.size() >= mini(_max_legs, _leg_starts.size()),
		"no_stuck": _stuck.is_empty(), "never_on_unloaded_chunk": _unloaded_s == 0.0, "no_engine_errors": _logger.errors == 0,
		"no_hitch_over_50ms": hitch_frames.is_empty(),
	}
	var path: String = ProjectSettings.globalize_path(_out).path_join("gate_report.json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("gate: report -> ", path)
	print("gate: verdict ", JSON.stringify(report["verdict"]))
	quit(0 if not report["verdict"].values().has(false) else 1)


## Splits slow frames into those within 3 frames of a chunk activation and the rest.
func _attribute_hitches() -> Dictionary:
	var near: int = 0
	var other: Array = []
	for h: Dictionary in _hitches:
		var hit: bool = false
		for d: int in range(-3, 1):
			if _activation_frames.has(int(h["frame"]) + d):
				hit = true
		if hit:
			near += 1
		else:
			other.append(h)
	return {"over_50ms": _hitches.size(), "near_activation": near, "not_activation": other.size(), "not_activation_samples": other.slice(0, 25)}


func _pct(sorted: PackedFloat32Array, q: float) -> float:
	return 0.0 if sorted.is_empty() else snappedf(sorted[clampi(int(round(q * (sorted.size() - 1))), 0, sorted.size() - 1)], 0.01)


func _count_over(sorted: PackedFloat32Array, limit: float) -> int:
	var n: int = 0
	for v: float in sorted:
		if v > limit:
			n += 1
	return n


func _worst(items: Array, n: int) -> Array:
	var copy: Array = items.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame_ms_max_next3"] > b["frame_ms_max_next3"])
	return copy.slice(0, n)

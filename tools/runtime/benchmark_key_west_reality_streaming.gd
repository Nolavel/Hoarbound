extends SceneTree
## Streams the generated Key West chunks through the production StreamingSystem in real time.
## godot --headless --path . --script tools/runtime/benchmark_key_west_reality_streaming.gd -- [out_dir] [route] [speed]

const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
const CHUNK_M: float = 512.0
const FRAME_BUDGET_MS: float = 1000.0 / 60.0
const ROUTES: Dictionary = {
	"first_exit": {"speed": 6.0, "points": [Vector2(-4052.73, 1924.69), Vector2(-3531.78, 1590.28)]},
	"island": {"speed": 25.0, "points": [Vector2(-4052.73, 1924.69), Vector2(-2600.0, 1000.0), Vector2(-500.0, 300.0),
		Vector2(1500.0, -300.0), Vector2(3400.0, -1500.0), Vector2(5400.0, -1360.0), Vector2(6800.0, -1800.0)]},
}

var _out: String = ""
var _route: String = ""
var _speed: float = 0.0
var _streaming: StreamingSystem
var _player: Node3D
var _container: Node3D
var _path: PackedVector2Array
var _travelled: float = 0.0
var _length: float = 0.0
var _phase: String = "boot"
var _last_usec: int = 0
var _frames: Array = []
var _activations: Array = []
var _queued_at: Dictionary = {}
var _uncovered_frames: int = 0
var _uncovered_s: float = 0.0
var _uncovered_ids: Dictionary = {}
var _boot_s: float = -1.0
var _t0: int = 0
var _baseline_nodes: int = 0
var _settle: int = 0
var _peak_static: float = 0.0
var _peak_active: int = 0
var _peak_cache: int = 0
var _start_static_mb: float = 0.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://kw_stream_bench"
	_route = args[1] if args.size() > 1 else "first_exit"
	var spec: Dictionary = ROUTES[_route]
	_speed = float(args[2]) if args.size() > 2 else float(spec["speed"])
	_path = PackedVector2Array(spec["points"])
	for i: int in range(_path.size() - 1):
		_length += _path[i].distance_to(_path[i + 1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("user://") or _out.begins_with("res://") else _out)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	_container = Node3D.new()
	_container.name = "StreamContainer"
	world.add_child(_container)
	_player = Node3D.new()
	_player.name = "Player"
	world.add_child(_player)
	_player.global_position = Vector3(_path[0].x, 2.0, _path[0].y)
	_baseline_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_start_static_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_streaming = StreamingSystem.new()
	_streaming.world_data_path = WORLD_DATA
	world.add_child(_streaming)
	_streaming.set_process(false)
	_streaming.cell_state_changed.connect(_on_state)
	_t0 = Time.get_ticks_usec()
	_streaming.initialize(_container, _player)
	_last_usec = Time.get_ticks_usec()


func _on_state(id: StringName, state: StreamingSystem.CellState) -> void:
	var now: int = Time.get_ticks_usec()
	if state == StreamingSystem.CellState.QUEUED:
		_queued_at[id] = now
	elif state == StreamingSystem.CellState.ACTIVE:
		_activations.append({"id": String(id), "t_s": (now - _t0) / 1e6, "latency_ms": (now - int(_queued_at.get(id, now))) / 1000.0,
			"phase": _phase})


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	var real_dt: float = (now - _last_usec) / 1e6
	_last_usec = now
	var before: int = _activations.size()
	var t: int = Time.get_ticks_usec()
	_streaming._process(real_dt)
	var cost_ms: float = (Time.get_ticks_usec() - t) / 1000.0
	var active: int = _streaming.get_active_chunks().size()
	var static_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_peak_static = maxf(_peak_static, static_mb)
	_peak_active = maxi(_peak_active, active)
	_peak_cache = maxi(_peak_cache, _streaming._packed_cache.size())
	if _activations.size() > before:
		(_activations[-1] as Dictionary)["activate_ms"] = cost_ms
		(_activations[-1] as Dictionary)["nodes_after"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pos: Vector3 = _player.global_position
	var own: StringName = StringName("kw_gen_%d_%d" % [floori(pos.x / CHUNK_M), floori(pos.z / CHUNK_M)])
	var covered: bool = _streaming._chunks.has(own) == false or _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE
	match _phase:
		"boot":
			if covered and _all_near_active(pos):
				_boot_s = (now - _t0) / 1e6
				_phase = "move"
			elif (now - _t0) > 120_000_000:
				_phase = "move"
		"move":
			if not covered:
				_uncovered_frames += 1
				_uncovered_s += real_dt
				_uncovered_ids[String(own)] = true
			_frames.append([snappedf(cost_ms, 0.01), snappedf(real_dt * 1000.0, 0.01)])
			_travelled += _speed * minf(real_dt, 0.25)
			if _travelled >= _length:
				_phase = "leave"
				_player.global_position = Vector3(20000.0, 0.0, 20000.0)
				_streaming.scan(_player.global_position)
			else:
				var p: Vector2 = _along(_travelled)
				_player.global_position = Vector3(p.x, 2.0, p.y)
		"leave":
			_settle += 1
			if active == 0 and _settle > 30:
				_finish()
				return true
			if _settle > 600:
				_finish()
				return true
	return false


func _all_near_active(pos: Vector3) -> bool:
	for id: StringName in _streaming._chunks:
		var chunk: ChunkData = _streaming._chunks[id]
		if Vector2(pos.x - chunk.position.x, pos.z - chunk.position.z).length() <= chunk.radius + _streaming.load_margin_m:
			if _streaming.get_state(id) != StreamingSystem.CellState.ACTIVE:
				return false
	return true


func _along(d: float) -> Vector2:
	for i: int in range(_path.size() - 1):
		var seg: float = _path[i].distance_to(_path[i + 1])
		if d <= seg:
			return _path[i].lerp(_path[i + 1], d / seg)
		d -= seg
	return _path[_path.size() - 1]


func _finish() -> void:
	var costs: Array = _frames.map(func(f: Array) -> float: return f[0])
	costs.sort()
	var act: Array = _activations.filter(func(a: Dictionary) -> bool: return a.has("activate_ms"))
	var act_ms: Array = act.map(func(a: Dictionary) -> float: return a["activate_ms"])
	act_ms.sort()
	var lat: Array = _activations.map(func(a: Dictionary) -> float: return a["latency_ms"])
	lat.sort()
	var report: Dictionary = {
		"route": _route, "speed_mps": _speed, "length_m": snappedf(_length, 0.1),
		"engine": Engine.get_version_info()["string"], "display": DisplayServer.get_name(),
		"streaming": {"load_margin_m": _streaming.load_margin_m, "unload_hysteresis_m": _streaming.unload_hysteresis_m,
			"rescan_distance_m": _streaming.rescan_distance_m, "max_concurrent_loads": _streaming.max_concurrent_loads,
			"instantiation_budget_per_frame": _streaming.instantiation_budget_per_frame, "chunks": _streaming.get_chunk_count()},
		"boot_to_all_near_active_s": snappedf(_boot_s, 0.001),
		"moving_frames": costs.size(),
		"streaming_cost_ms": {"p50": _pct(costs, 0.5), "p99": _pct(costs, 0.99), "max": costs.back() if not costs.is_empty() else 0.0,
			"frames_over_16_7": costs.filter(func(c: float) -> bool: return c > FRAME_BUDGET_MS).size(),
			"frames_over_33_3": costs.filter(func(c: float) -> bool: return c > 2.0 * FRAME_BUDGET_MS).size()},
		"activations": {"count": _activations.size(), "activate_ms_p50": _pct(act_ms, 0.5), "activate_ms_p95": _pct(act_ms, 0.95),
			"activate_ms_max": act_ms.back() if not act_ms.is_empty() else 0.0,
			"queued_to_active_ms_p50": _pct(lat, 0.5), "queued_to_active_ms_p95": _pct(lat, 0.95), "queued_to_active_ms_max": lat.back() if not lat.is_empty() else 0.0},
		"player_in_inactive_chunk": {"frames": _uncovered_frames, "seconds": snappedf(_uncovered_s, 0.001), "chunks": _uncovered_ids.keys()},
		"static_memory_mb_at_start": snappedf(_start_static_mb, 0.1),
		"peaks": {"active_chunks": _peak_active, "packed_cache_entries": _peak_cache, "static_memory_mb": snappedf(_peak_static, 0.1)},
		"after_leaving": {"active_chunks": _streaming.get_active_chunks().size(), "packed_cache_entries": _streaming._packed_cache.size(),
			"nodes_over_baseline": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - _baseline_nodes,
			"static_memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)},
		"slowest_activations": _slowest(act, 8),
	}
	var path: String = _out.path_join("stream_report_%s.json" % _route)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("benchmark_key_west_reality_streaming: ", JSON.stringify(report))


func _pct(sorted: Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return snappedf(float(sorted[clampi(int(round(q * (sorted.size() - 1))), 0, sorted.size() - 1)]), 0.01)


func _slowest(act: Array, n: int) -> Array:
	var copy: Array = act.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["activate_ms"] > b["activate_ms"])
	return copy.slice(0, n)

extends SceneTree

## HLOD boundary stress: entering the sector from afar (proxy burst), then four passes in and out across one
## cluster's load and unload edges (first pass cold, later passes warm). One streamer pump per real frame;
## per phase it reports pump and frame time, proxies made per frame and the slowest stage, and fails on a hole,
## a double, a wrong final tier or a pump over FRAME_BUDGET_MS. Frames are judged headless only: under a real
## renderer they carry rendering and first-use pipeline compiles, so they are reported, not judged.

const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
## Same threshold as the production gate's hitch.
const FRAME_BUDGET_MS: float = 50.0
const QUIET_FRAMES: int = 10
const MAX_PHASE_FRAMES: int = 3000
const PASSES: int = 4
const FAR: Vector3 = Vector3(-1200.0, 0.0, 1000.0)
const TRANSIENT: Array[int] = [1, 2, 3, 5]  # QUEUED, LOADING, READY, ASSEMBLING

var _failures: int = 0
var _system: StreamingSystem
var _hlod: KeyWestRealityHLOD
var _container: Node3D
var _player: Node3D
var _cluster: String = ""
var _phases: Array[Dictionary] = []
var _phase: int = -1
var _frames: int = 0
var _quiet: int = 0
var _last_usec: int = 0
var _rec: Dictionary = {}
var _rows: Array = []
var _to_hlod: int = 0


func _initialize() -> void:
	_container = Node3D.new()
	_container.name = "StreamContainer"
	root.add_child(_container)
	_player = Node3D.new()
	root.add_child(_player)
	_system = StreamingSystem.new()
	_system.world_data_path = WORLD_DATA
	_system.measure_stages = true
	root.add_child(_system)
	_hlod = KeyWestRealityHLOD.new()
	_hlod.measure_stages = true
	root.add_child(_hlod)
	_check(_hlod.load_manifest(), "no HLOD manifest")
	_hlod.set_container(_container)
	_system.cell_state_changed.connect(_hlod._on_cell)
	_system.stage_timed.connect(_on_stage)
	_hlod.stage_timed.connect(func(id: String, stage: StringName, usec: int) -> void: _on_stage(StringName("hlod:" + id), stage, usec))
	_player.position = FAR
	_system.initialize(_container, _player)
	## The real far view: its 2,500 m cells are what start the proxy loads, long before a chunk comes in.
	var far: KeyWestRealityFar = KeyWestRealityFar.new()
	root.add_child(far)
	far._streaming = _system
	_system.cell_state_changed.connect(far._on_cell_state_changed)
	_system.register_runtime_source(far)
	_hlod.sync_with(_system)
	_cluster = _inner_cluster()
	var centre: Vector3 = KeyWestChunkBuilder.cluster_centre(_cluster)
	var load_edge: float = KeyWestChunkBuilder.detail_band_m()
	var cfg: Dictionary = KeyWestChunkBuilder.hlod_config()
	var unload_edge: float = load_edge + float(cfg.get("streamer_unload_hysteresis_m", 120))
	_phases.append({"name": "burst_entry", "at": centre + Vector3.RIGHT * (unload_edge + 20.0), "want": "hlod"})
	for p: int in range(1, PASSES + 1):
		_phases.append({"name": "pass%d_in" % p, "at": centre + Vector3.RIGHT * (load_edge - 10.0), "want": "detail"})
		_phases.append({"name": "pass%d_out" % p, "at": centre + Vector3.RIGHT * (unload_edge + 20.0), "want": "hlod"})


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if _phase < 0:
		## After _ready, which turns processing back on: pumped once per frame below, so its cost can be timed.
		_system.set_process(false)
		_next_phase()
		return false
	var before: int = int(_hlod.stats["to_hlod"])
	var t0: int = Time.get_ticks_usec()
	_system.pump()
	var pump_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	var made: int = int(_hlod.stats["to_hlod"]) - before
	_rec["max_pump_ms"] = maxf(float(_rec["max_pump_ms"]), pump_ms)
	if _frames > 0:
		_rec["max_frame_ms"] = maxf(float(_rec["max_frame_ms"]), frame_ms)
	_rec["max_proxies_per_frame"] = maxi(int(_rec["max_proxies_per_frame"]), made)
	_frames += 1
	_check_invariant()
	var busy: bool = _system._states.values().any(func(s: int) -> bool: return TRANSIENT.has(s))
	_quiet = 0 if busy else _quiet + 1
	if (_quiet >= QUIET_FRAMES and _frames > 3) or _frames >= MAX_PHASE_FRAMES:
		_close_phase()
		_next_phase()
	return _phase >= _phases.size()


func _next_phase() -> void:
	_phase += 1
	if _phase >= _phases.size():
		_finish()
		return
	var ph: Dictionary = _phases[_phase]
	_frames = 0
	_quiet = 0
	_rec = {"phase": ph["name"], "max_pump_ms": 0.0, "max_frame_ms": 0.0, "max_proxies_per_frame": 0, "stages": {}}
	_to_hlod = int(_hlod.stats["to_hlod"])
	## The scan releases cells at once (detail free, proxy add), so it is timed like a pump.
	_player.position = ph["at"]
	var t0: int = Time.get_ticks_usec()
	_system.scan(ph["at"])
	_rec["max_pump_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_rec["max_proxies_per_frame"] = int(_hlod.stats["to_hlod"]) - _to_hlod


func _close_phase() -> void:
	var ph: Dictionary = _phases[_phase]
	_rec["frames"] = _frames
	_rec["proxies_made"] = int(_hlod.stats["to_hlod"]) - _to_hlod
	_rec["tier"] = _hlod.representation(_cluster)
	_check(_frames < MAX_PHASE_FRAMES, "%s did not settle" % ph["name"])
	_check(_rec["tier"] == ph["want"], "%s ended in %s, wanted %s" % [ph["name"], _rec["tier"], ph["want"]])
	_check(float(_rec["max_pump_ms"]) < FRAME_BUDGET_MS, "%s: a pump took %.1f ms" % [ph["name"], _rec["max_pump_ms"]])
	if DisplayServer.get_name() == "headless":
		_check(float(_rec["max_frame_ms"]) < FRAME_BUDGET_MS, "%s: a frame took %.1f ms" % [ph["name"], _rec["max_frame_ms"]])
	_rows.append(_rec)


func _on_stage(id: StringName, stage: StringName, usec: int) -> void:
	if _rec.is_empty():
		return
	var stages: Dictionary = _rec["stages"]
	var key: String = String(stage)
	if float(stages.get(key, [0.0, ""])[0]) < usec / 1000.0:
		stages[key] = [snappedf(usec / 1000.0, 0.01), String(id)]


func _check_invariant() -> void:
	for cluster_id: String in _hlod.cluster_ids():
		var rep: String = _hlod.representation(cluster_id)
		if rep == "both" or rep == "none":
			_check(false, "%s shows %s in %s" % [cluster_id, rep, _phases[_phase]["name"]])


## An inner cluster of its chunk: the chunk stays in while the cluster crosses its own edges.
func _inner_cluster() -> String:
	var best: String = ""
	var best_d: float = INF
	for cluster_id: String in _hlod.cluster_ids():
		var c: Vector3 = KeyWestChunkBuilder.cluster_centre(cluster_id)
		var chunk_centre: Vector3 = Vector3((floorf(c.x / 512.0) + 0.5) * 512.0, 0.0, (floorf(c.z / 512.0) + 0.5) * 512.0)
		if c.distance_to(chunk_centre) < best_d:
			best_d = c.distance_to(chunk_centre)
			best = cluster_id
	return best


func _finish() -> void:
	print("hlod boundary: cluster %s, budget %.0f ms, display %s, renderer %s" % [_cluster, FRAME_BUDGET_MS, DisplayServer.get_name(), RenderingServer.get_video_adapter_name()])
	for r: Dictionary in _rows:
		var worst: String = ""
		var worst_ms: float = 0.0
		for stage: String in r["stages"].keys():
			if float(r["stages"][stage][0]) > worst_ms:
				worst_ms = float(r["stages"][stage][0])
				worst = "%s %s" % [stage, r["stages"][stage][1]]
		var proxy_ms: PackedStringArray = PackedStringArray()
		for stage: String in ["proxy_fetch", "proxy_add", "proxy_free"]:
			proxy_ms.append("%s %.2f" % [stage.trim_prefix("proxy_"), float(r["stages"].get(stage, [0.0])[0])])
		print("hlod boundary: %-11s frames %4d  pump max %6.2f ms  frame max %6.2f ms  proxies %2d (max %2d/frame)  tier %-6s  slowest stage %.2f ms (%s); proxy max ms: %s" % [
			r["phase"], r["frames"], r["max_pump_ms"], r["max_frame_ms"], r["proxies_made"], r["max_proxies_per_frame"], r["tier"], worst_ms, worst, ", ".join(proxy_ms)])
	if _rows.size() >= 3:
		var first: float = float(_rows[1]["max_pump_ms"])
		var later: float = 0.0
		for i: int in range(3, _rows.size(), 2):
			later = maxf(later, float(_rows[i]["max_pump_ms"]))
		print("hlod boundary: first entry pump max %.2f ms, repeat entries %.2f ms" % [first, later])
	print("hlod boundary: HLOD stats %s" % _hlod.stats)
	_check(int(_hlod.stats["sync_loads"]) == 0, "%d proxy loads blocked the main thread" % _hlod.stats["sync_loads"])
	if _failures > 0:
		push_error("hlod boundary: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hlod boundary: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hlod boundary: %s" % message)

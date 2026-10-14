extends SceneTree
## HLOD baseline and after-measurement on a fixed route over the Old Town sector, in the real Reality scene.
## xvfb-run godot --script <this> -- <out_dir> <label> [--all-detail] [station ...]; writes <label>.json and PNGs.
## --all-detail swaps every proxy for its detail scene after settling: the pre-HLOD frame on the same build.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const CHUNK_M: float = 512.0
const HENRY_HALF_HEIGHT: float = 1.0
## Frames after streaming settles before sampling, then frames sampled.
const WARM_FRAMES: int = 10
const SAMPLE_FRAMES: int = 20
const SETTLE_QUIET_FRAMES: int = 5
const MAX_SETTLE_FRAMES: int = 900
const ABLATION_FRAMES: int = 2
## Groups hidden one at a time to attribute draw calls; "Far" and "HLOD" are the far views.
const GROUPS: Array[String] = ["Buildings", "Winter", "Vegetation", "Roads", "Infrastructure", "Barriers", "LandUse", "Coastal", "Terrain", "Far", "HLOD"]
const BANDS: Array[float] = [150.0, 300.0, 500.0, 800.0, INF]
## The sector: chunks -6:1 -5:1 -6:2 -5:2 (x -3072..-2048, z 512..1536). Eye y is metres above ground when "rel".
const STATIONS: Array[Dictionary] = [
	{"name": "s1_street_core", "eye": [-2600.0, 1050.0, 1.7], "rel": true, "look": [-2450.0, 980.0, 3.0]},
	{"name": "s2_street_edge", "eye": [-3100.0, 1450.0, 1.7], "rel": true, "look": [-2700.0, 1150.0, 3.0]},
	{"name": "s3_roof_overview", "eye": [-3200.0, 1650.0, 60.0], "rel": false, "look": [-2560.0, 1024.0, 0.0]},
	{"name": "s4_from_727", "eye": [-3530.0, 1583.0, 40.0], "rel": false, "look": [-2560.0, 1024.0, 0.0]},
	{"name": "s5_far_east", "eye": [-1300.0, 300.0, 60.0], "rel": false, "look": [-2560.0, 1024.0, 0.0]},
]

var _out: String = ""
var _label: String = ""
var _only: PackedStringArray = PackedStringArray()
var _world: Node3D
var _ctx: WorldContext
var _streaming: StreamingSystem
var _camera: Camera3D
var _states: Dictionary = {}  # chunk id -> CellState, from the streamer's signal
var _station: int = -1
var _phase: String = ""
var _frames: int = 0
var _quiet: int = 0
var _t0: int = 0
var _samples: Array = []
var _ablation: Dictionary = {}
var _ablate_at: int = 0
var _hidden: Array[Node] = []
var _report: Dictionary = {}
var _tri_cache: Dictionary = {}
var _all_detail: bool = false
var _forced: Array[Node] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0]
	_label = args[1]
	_only = args.slice(2)
	_all_detail = _only.has("--all-detail")
	_only.erase("--all-detail")
	DirAccess.make_dir_recursive_absolute(_out)
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	_report = {"label": _label, "scene": SCENE, "stations": {}, "godot": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_video_adapter_name(), "all_detail": _all_detail}


func _process(_delta: float) -> bool:
	if _ctx == null:
		_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
		if _ctx != null:
			_streaming = _ctx.get_system(STREAMING) as StreamingSystem
			_streaming.cell_state_changed.connect(func(id: StringName, s: StreamingSystem.CellState) -> void: _states[id] = s)
			RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
			_camera = Camera3D.new()
			_camera.fov = 70.0
			_camera.far = 4000.0
			root.add_child(_camera)
		return false
	_frames += 1
	match _phase:
		"":
			_next_station()
		"settle":
			_aim()
			if _transient() == 0:
				_quiet += 1
			else:
				_quiet = 0
			if (_quiet >= SETTLE_QUIET_FRAMES and _frames > 20) or _frames >= MAX_SETTLE_FRAMES:
				var st: Dictionary = _report["stations"][_name()]
				st["settle_frames"] = _frames
				st["settle_ms"] = Time.get_ticks_msec() - _t0
				st["settled"] = _transient() == 0
				_place()  # ground heights are known now
				if _all_detail:
					_force_detail(true)
				_phase = "warm"
				_frames = 0
		"warm":
			_aim()
			if _frames >= WARM_FRAMES:
				_phase = "sample"
				_frames = 0
				_samples = []
		"sample":
			_samples.append(_sample())
			if _frames >= SAMPLE_FRAMES:
				_finish_sampling()
				_phase = "ablate"
				_ablate_at = 0
				_frames = 0
				_ablation = {}
				_hide(GROUPS[0])
		"ablate":
			if _frames < ABLATION_FRAMES:
				return false
			var s: Dictionary = _sample()
			_ablation[GROUPS[_ablate_at]] = {"draw_calls": s["draw_calls"], "primitives": s["primitives"], "objects": s["objects"]}
			_unhide()
			_ablate_at += 1
			_frames = 0
			if _ablate_at < GROUPS.size():
				_hide(GROUPS[_ablate_at])
			else:
				_finish_ablation()
				_force_detail(false)
				_phase = ""
	return false


## Every cluster showing its proxy gets its detail scene instead, as before HLOD (same as the tier capture).
func _force_detail(on: bool) -> void:
	var hlod: KeyWestRealityHLOD = _world.find_child("HLODView", true, false) as KeyWestRealityHLOD
	if hlod == null:
		return
	if not on:
		for n: Node in _forced:
			n.queue_free()
		_forced.clear()
		for proxy: Node in hlod.get_children():
			(proxy as Node3D).visible = true
		return
	for proxy: Node in hlod.get_children():
		var cluster_id: String = String(proxy.get_meta("cluster_id", ""))
		if proxy.is_queued_for_deletion() or hlod.representation(cluster_id) != "hlod":
			continue
		var detail: Node3D = (load(KeyWestChunkGenerator.cluster_path_of(cluster_id)) as PackedScene).instantiate() as Node3D
		detail.name = "ForcedDetail_" + cluster_id  # never the streamer's own cell name
		detail.position = KeyWestChunkBuilder.cluster_centre(cluster_id)
		_ctx.stream_container.add_child(detail)
		_forced.append(detail)
		(proxy as Node3D).visible = false


func _name() -> String:
	return String(STATIONS[_station]["name"])


func _next_station() -> void:
	_station += 1
	while _station < STATIONS.size() and not _only.is_empty() and not _only.has(_name()):
		_station += 1
	if _station >= STATIONS.size():
		var f: FileAccess = FileAccess.open(_out.path_join(_label + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(_report, " ", false))
		f.close()
		print("hlod measure: wrote ", _out.path_join(_label + ".json"))
		quit(0)
		return
	_report["stations"][_name()] = {}
	_place()
	_camera.make_current()
	_phase = "settle"
	_frames = 0
	_quiet = 0
	_t0 = Time.get_ticks_msec()
	print("hlod measure: %s" % _name())


func _eye() -> Vector3:
	var e: Array = STATIONS[_station]["eye"]
	var y: float = float(e[2]) + (_ground(float(e[0]), float(e[1])) if STATIONS[_station]["rel"] else 0.0)
	return Vector3(float(e[0]), y, float(e[1]))


func _place() -> void:
	var e: Array = STATIONS[_station]["eye"]
	var player: CharacterBody3D = _ctx.player as CharacterBody3D
	player.global_position = Vector3(float(e[0]), _ground(float(e[0]), float(e[1])) + HENRY_HALF_HEIGHT, float(e[1]))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	_aim()


func _aim() -> void:
	var l: Array = STATIONS[_station]["look"]
	var look: Vector3 = Vector3(float(l[0]), float(l[2]) + (_ground(float(l[0]), float(l[1])) if STATIONS[_station]["rel"] else 0.0), float(l[1]))
	_camera.look_at_from_position(_eye(), look)


func _ground(x: float, z: float) -> float:
	var ground: Node = _world.find_child("RealityGround", true, false)
	return float(ground.get_height(x, z)) if ground is KeyWestRealityGround else 0.0


func _transient() -> int:
	var n: int = 0
	for s: int in _states.values():
		if s in [StreamingSystem.CellState.QUEUED, StreamingSystem.CellState.LOADING, StreamingSystem.CellState.READY, StreamingSystem.CellState.ASSEMBLING]:
			n += 1
	return n


func _sample() -> Dictionary:
	var vp: RID = root.get_viewport_rid()
	return {
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_mem_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mem_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"ticks_usec": Time.get_ticks_usec(),
	}


func _finish_sampling() -> void:
	var st: Dictionary = _report["stations"][_name()]
	var agg: Dictionary = {}
	for key: String in ["process_ms", "render_cpu_ms", "render_gpu_ms", "fps", "draw_calls", "primitives", "objects", "nodes", "static_mem_mib", "video_mem_mib"]:
		var total: float = 0.0
		var peak: float = -INF
		for s: Dictionary in _samples:
			total += float(s[key])
			peak = maxf(peak, float(s[key]))
		agg[key] = {"avg": snappedf(total / _samples.size(), 0.001), "max": snappedf(peak, 0.001)}
	var wall: float = float(_samples[-1]["ticks_usec"] - _samples[0]["ticks_usec"]) / 1000.0 / maxf(_samples.size() - 1, 1)
	agg["wall_frame_ms"] = snappedf(wall, 0.01)
	st["sample"] = agg
	st["resolution"] = [root.get_visible_rect().size.x, root.get_visible_rect().size.y]
	st["forced_detail_clusters"] = _forced.size()
	st["instances"] = _instances()
	st["buildings_by_distance"] = _buildings_by_distance()
	st["active_chunks"] = _active_ids()
	var hlod: Node = _world.find_child("HLODView", true, false)
	if hlod is KeyWestRealityHLOD:
		var reps: Dictionary = {}
		for cluster_id: String in (hlod as KeyWestRealityHLOD).cluster_ids():
			var rep: String = (hlod as KeyWestRealityHLOD).representation(cluster_id)
			reps[rep] = int(reps.get(rep, 0)) + 1
		st["hlod"] = {"representations": reps, "proxies": (hlod as KeyWestRealityHLOD).proxy_count(), "stats": (hlod as KeyWestRealityHLOD).stats.duplicate()}
	var shot: String = _out.path_join("%s_%s.png" % [_label, _name()])
	root.get_viewport().get_texture().get_image().save_png(shot)
	print("hlod measure: %s draw calls %d, primitives %d, cpu %.2f ms" % [_name(), int(agg["draw_calls"]["avg"]), int(agg["primitives"]["avg"]), agg["render_cpu_ms"]["avg"]])


func _finish_ablation() -> void:
	var st: Dictionary = _report["stations"][_name()]
	var full: int = int(st["sample"]["draw_calls"]["avg"])
	var full_p: int = int(st["sample"]["primitives"]["avg"])
	var share: Dictionary = {}
	for g: String in _ablation:
		share[g] = {"draw_calls": full - int(_ablation[g]["draw_calls"]), "primitives": full_p - int(_ablation[g]["primitives"])}
	st["draw_calls_by_group"] = share


## Hides every node named group under streamed chunks, or the far / HLOD view roots.
func _hide(group: String) -> void:
	_hidden = []
	var roots: Array[Node] = []
	match group:
		"Far":
			roots.append(_world.find_child("FarView", true, false))
		"HLOD":
			roots.append(_world.find_child("HLODView", true, false))
		_:
			for chunk: Node in _ctx.stream_container.get_children():
				var g: Node = chunk.get_node_or_null(NodePath(group))
				if g != null:
					roots.append(g)
	for n: Node in roots:
		if n is Node3D and (n as Node3D).visible:
			(n as Node3D).visible = false
			_hidden.append(n)


func _unhide() -> void:
	for n: Node in _hidden:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden = []


func _instances() -> Dictionary:
	var out: Dictionary = {"geometry_instances": 0, "visible_geometry_instances": 0, "mesh_instances": 0, "multimesh_instances": 0, "collision_shapes": 0}
	for top: Node in [_ctx.stream_container, _world.find_child("FarView", true, false), _world.find_child("HLODView", true, false)]:
		if top == null:
			continue
		for n: Node in top.find_children("*", "", true, false):
			if n is GeometryInstance3D:
				out["geometry_instances"] += 1
				if (n as GeometryInstance3D).is_visible_in_tree():
					out["visible_geometry_instances"] += 1
				if n is MeshInstance3D:
					out["mesh_instances"] += 1
				elif n is MultiMeshInstance3D:
					out["multimesh_instances"] += 1
			elif n is CollisionShape3D:
				out["collision_shapes"] += 1
	return out


## Building mesh instances in the camera frustum by distance band: count, surfaces, triangles.
func _buildings_by_distance() -> Array:
	var bands: Array = []
	for b: float in BANDS:
		bands.append({"to_m": b if b != INF else -1.0, "instances": 0, "surfaces": 0, "triangles": 0})
	var eye: Vector3 = _camera.global_position
	var planes: Array[Plane] = _camera.get_frustum()
	for chunk: Node in _ctx.stream_container.get_children():
		var g: Node = chunk.get_node_or_null(^"Buildings")
		if g == null or not (g as Node3D).is_visible_in_tree():
			continue
		for n: Node in g.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if not _in_frustum(planes, box):
				continue
			var d: float = eye.distance_to(box.get_center())
			for i: int in range(BANDS.size()):
				if d < BANDS[i]:
					bands[i]["instances"] += 1
					bands[i]["surfaces"] += mi.mesh.get_surface_count()
					bands[i]["triangles"] += _triangles(mi.mesh)
					break
	return bands


func _in_frustum(planes: Array[Plane], box: AABB) -> bool:
	for p: Plane in planes:
		var far_corner: Vector3 = box.position + Vector3(box.size.x if p.normal.x < 0.0 else 0.0, box.size.y if p.normal.y < 0.0 else 0.0, box.size.z if p.normal.z < 0.0 else 0.0)
		if p.distance_to(far_corner) > 0.0:
			return false
	return true


func _triangles(mesh: Mesh) -> int:
	var key: int = mesh.get_instance_id()
	if not _tri_cache.has(key):
		var t: int = 0
		for s: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		_tri_cache[key] = t
	return _tri_cache[key]


func _active_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: StringName in _states:
		if _states[id] == StreamingSystem.CellState.ACTIVE:
			out.append(String(id))
	out.sort()
	return out

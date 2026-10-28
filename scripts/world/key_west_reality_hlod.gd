class_name KeyWestRealityHLOD
extends Node3D
## Tier 1 HLOD view: while a chunk is in, each of its building clusters shows either its detail cell (streamed by
## StreamingSystem) or its merged proxy, never both. Distances and hysteresis are the streamer's own bands.

const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const MANIFEST_PATH: String = "res://scenes/world/key_west/generated/hlod/hlod_manifest.json"
const CHUNK_PREFIX: String = "kw_gen_"
const DETAIL_PREFIX: String = "kw_bld_"
## The chunk's far-view cell (KeyWestRealityFar, 2,500 m band): proxies load while it is in, long before the chunk.
const FAR_PREFIX: String = "kw_far_"
## Debug tier tint: proxies (Tier 1) and detail clusters (Tier 0).
const TINT_PROXY: Color = Color(1.0, 0.45, 0.1)
const TINT_DETAIL: Color = Color(0.2, 0.55, 1.0)

## Main-thread cost of one HLOD step (proxy_fetch, proxy_add, proxy_free), only while measure_stages is on.
signal stage_timed(cluster_id: String, stage: StringName, usec: int)

## Emits stage_timed and tracks proxies created per frame; for gates and stress tests.
@export var measure_stages: bool = false

## Swap counts, blocking proxy loads and the largest burst of proxies created in one frame.
var stats: Dictionary = {"to_detail": 0, "to_hlod": 0, "sync_loads": 0, "max_proxies_per_frame": 0}

var _streaming: StreamingSystem
var _container: Node3D
var _clusters: Dictionary = {}  # cluster id -> {"chunk": "x_z", "centre": Vector3, "proxy": path}
var _by_chunk: Dictionary = {}  # "x_z" -> Array of cluster ids
var _chunk_in: Dictionary = {}  # "x_z" -> true while ACTIVE or ASSEMBLING (terrain is in)
var _detail_in: Dictionary = {}  # cluster id -> true while its detail cell is ACTIVE
var _proxies: Dictionary = {}  # cluster id -> MeshInstance3D
var _meshes: Dictionary = {}  # proxy path -> Mesh (null while loading), kept while the far cell or the chunk is in
var _far_in: Dictionary = {}  # "x_z" -> true while the chunk's far cell is ACTIVE
var _burst_frame: int = -1
var _burst: int = 0
var _tint_tiers: bool = false
var _tint_proxy: StandardMaterial3D
var _tint_detail: StandardMaterial3D


func on_world_ready(context: WorldContext) -> void:
	_streaming = context.get_system(STREAMING) as StreamingSystem
	_container = context.stream_container
	if _streaming == null or not load_manifest():
		return
	_streaming.cell_state_changed.connect(_on_cell)
	sync_with(_streaming)
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if OS.is_debug_build() and input_systems != null and input_systems.has_signal(&"hlod_tiers_toggle_pressed"):
		input_systems.connect(&"hlod_tiers_toggle_pressed", func() -> void: set_tint_tiers(not _tint_tiers))


## Reads the cluster list; false when no HLOD was built.
func load_manifest(path: String = MANIFEST_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary):
		return false
	for entry: Dictionary in doc.get("clusters", []):
		var chunk: String = String(entry["chunk"]).replace(":", "_")
		var c: Array = entry["centre_local"]
		_clusters[entry["cluster_id"]] = {"chunk": chunk, "centre": Vector3(float(c[0]), 0.0, float(c[1])), "proxy": entry["proxy_path"]}
		(_by_chunk.get_or_add(chunk, []) as Array).append(entry["cluster_id"])
	return not _clusters.is_empty()


## Picks up states the streamer reached before this node connected (boot prewarm).
func sync_with(streaming: StreamingSystem) -> void:
	_streaming = streaming
	for chunk: String in _by_chunk.keys():
		_on_cell(StringName(FAR_PREFIX + chunk), streaming.get_state(StringName(FAR_PREFIX + chunk)))
	for chunk: String in _by_chunk.keys():
		_on_cell(StringName(CHUNK_PREFIX + chunk), streaming.get_state(StringName(CHUNK_PREFIX + chunk)))
	for cluster_id: String in _clusters.keys():
		_on_cell(StringName(DETAIL_PREFIX + cluster_id), streaming.get_state(StringName(DETAIL_PREFIX + cluster_id)))


func set_container(container: Node3D) -> void:
	_container = container


## "detail", "hlod", "far" (chunk out: the far mesh stands in) or "none" (chunk in, nothing drawn: a hole).
func representation(cluster_id: String) -> String:
	var info: Dictionary = _clusters.get(cluster_id, {})
	if info.is_empty() or not _chunk_in.has(info["chunk"]):
		return "far"
	var detail: Node3D = _detail_node(cluster_id)
	var detail_drawn: bool = detail != null and detail.visible
	var proxy_drawn: bool = _proxies.has(cluster_id)
	if detail_drawn and proxy_drawn:
		return "both"
	return "detail" if detail_drawn else ("hlod" if proxy_drawn else "none")


func cluster_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_clusters.keys())
	out.sort()
	return out


func proxy_count() -> int:
	return _proxies.size()


## Debug view: tints every proxy orange and every drawn detail cluster blue; off restores the materials.
func set_tint_tiers(on: bool) -> void:
	_tint_tiers = on
	if on and _tint_proxy == null:
		_tint_proxy = _flat(TINT_PROXY)
		_tint_detail = _flat(TINT_DETAIL)
	for proxy: MeshInstance3D in _proxies.values():
		proxy.material_override = _tint_proxy if on else null
	for cluster_id: String in _detail_in:
		_tint(_detail_node(cluster_id), on)
	print("HLOD tiers tint: on (orange = proxy, blue = detail)" if on else "HLOD tiers tint: off")


func is_tinting_tiers() -> bool:
	return _tint_tiers


func _on_cell(id: StringName, state: StreamingSystem.CellState) -> void:
	var s: String = String(id)
	if s.begins_with(FAR_PREFIX):
		var far_chunk: String = s.trim_prefix(FAR_PREFIX)
		if not _by_chunk.has(far_chunk):
			return
		if state == StreamingSystem.CellState.ACTIVE:
			_far_in[far_chunk] = true
			_warm(far_chunk)
		elif state == StreamingSystem.CellState.UNLOADED:
			_far_in.erase(far_chunk)
			_drop_meshes(far_chunk)
	elif s.begins_with(CHUNK_PREFIX):
		var chunk: String = s.trim_prefix(CHUNK_PREFIX)
		if not _by_chunk.has(chunk):
			return
		match state:
			StreamingSystem.CellState.QUEUED, StreamingSystem.CellState.LOADING, StreamingSystem.CellState.READY:
				_warm(chunk)
			StreamingSystem.CellState.ACTIVE, StreamingSystem.CellState.ASSEMBLING:
				_chunk_in[chunk] = true
			StreamingSystem.CellState.UNLOADED:
				_chunk_in.erase(chunk)
		for cluster_id: String in _by_chunk[chunk]:
			_apply(cluster_id)
		if state == StreamingSystem.CellState.UNLOADED:
			_drop_meshes(chunk)
	elif s.begins_with(DETAIL_PREFIX):
		var cluster_id: String = s.trim_prefix(DETAIL_PREFIX)
		if not _clusters.has(cluster_id):
			return
		if state == StreamingSystem.CellState.ACTIVE:
			_detail_in[cluster_id] = true
		else:
			_detail_in.erase(cluster_id)
		_apply(cluster_id)


## One representation per cluster: detail over its own chunk, else the proxy while the chunk is in.
func _apply(cluster_id: String) -> void:
	var info: Dictionary = _clusters[cluster_id]
	var chunk_in: bool = _chunk_in.has(info["chunk"])
	var detail_in: bool = _detail_in.has(cluster_id)
	var detail: Node3D = _detail_node(cluster_id)
	if detail != null:
		detail.visible = chunk_in  # a detail cell that beat its chunk in waits; the far mesh still stands in
		if _tint_tiers and detail_in:
			_tint(detail, true)
	var want_proxy: bool = chunk_in and not detail_in
	if want_proxy and not _proxies.has(cluster_id):
		var t0: int = Time.get_ticks_usec()
		var mesh: Mesh = _mesh(info["proxy"])
		if mesh == null:
			return
		var t1: int = Time.get_ticks_usec()
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.name = "HLOD_" + cluster_id
		proxy.mesh = mesh
		proxy.position = info["centre"]
		proxy.set_meta("cluster_id", cluster_id)
		proxy.set_meta("tier", 1)
		if _tint_tiers:
			proxy.material_override = _tint_proxy
		add_child(proxy)
		_proxies[cluster_id] = proxy
		stats["to_hlod"] += 1
		_count_burst()
		if measure_stages:
			stage_timed.emit(cluster_id, &"proxy_fetch", t1 - t0)
			stage_timed.emit(cluster_id, &"proxy_add", Time.get_ticks_usec() - t1)
	elif not want_proxy and _proxies.has(cluster_id):
		var t2: int = Time.get_ticks_usec()
		var proxy: Node = _proxies[cluster_id]
		_proxies.erase(cluster_id)
		remove_child(proxy)
		proxy.queue_free()
		if detail_in:
			stats["to_detail"] += 1
		if measure_stages:
			stage_timed.emit(cluster_id, &"proxy_free", Time.get_ticks_usec() - t2)


func _tint(cluster: Node3D, on: bool) -> void:
	if cluster == null:
		return
	for n: Node in cluster.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = _tint_detail if on else null


func _flat(colour: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.disable_fog = true  # readable through blizzard fog
	return mat


func _count_burst() -> void:
	var frame: int = Engine.get_process_frames()
	_burst = _burst + 1 if frame == _burst_frame else 1
	_burst_frame = frame
	stats["max_proxies_per_frame"] = maxi(int(stats["max_proxies_per_frame"]), _burst)


func _detail_node(cluster_id: String) -> Node3D:
	return _container.get_node_or_null(NodePath("Cluster_" + cluster_id)) as Node3D if _container != null else null


## Releases a chunk's proxy meshes once neither its far cell nor the chunk itself is in.
func _drop_meshes(chunk: String) -> void:
	if _far_in.has(chunk) or _chunk_in.has(chunk):
		return
	for cluster_id: String in _by_chunk[chunk]:
		var path: String = _clusters[cluster_id]["proxy"]
		if _meshes.get(path) == null and _meshes.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)  # collect a finished request so the loader does not keep it
		_meshes.erase(path)


## Starts background loads of a chunk's proxies: when its far cell comes in, or at the latest while it loads.
func _warm(chunk: String) -> void:
	for cluster_id: String in _by_chunk[chunk]:
		var path: String = _clusters[cluster_id]["proxy"]
		if not _meshes.has(path):
			if ResourceLoader.load_threaded_request(path, "Mesh") == OK:
				_meshes[path] = null


func _mesh(path: String) -> Mesh:
	var cached: Variant = _meshes.get(path)
	if cached is Mesh:
		return cached
	var mesh: Mesh
	if _meshes.has(path) and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			stats["sync_loads"] += 1
		mesh = ResourceLoader.load_threaded_get(path) as Mesh
	else:
		stats["sync_loads"] += 1
		mesh = ResourceLoader.load(path) as Mesh
	_meshes[path] = mesh
	return mesh

class_name KeyWestRealityHLOD
extends Node3D
## Tier 1 HLOD view: while a chunk is in, each of its building clusters shows either its detail cell (streamed by
## StreamingSystem) or its merged proxy, never both. Distances and hysteresis are the streamer's own bands.

const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const MANIFEST_PATH: String = "res://scenes/world/key_west/generated/hlod/hlod_manifest.json"
const CHUNK_PREFIX: String = "kw_gen_"
const DETAIL_PREFIX: String = "kw_bld_"

## Swap counts and blocking proxy loads, for the measurement tools and tests.
var stats: Dictionary = {"to_detail": 0, "to_hlod": 0, "sync_loads": 0}

var _streaming: StreamingSystem
var _container: Node3D
var _clusters: Dictionary = {}  # cluster id -> {"chunk": "x_z", "centre": Vector3, "proxy": path}
var _by_chunk: Dictionary = {}  # "x_z" -> Array of cluster ids
var _chunk_in: Dictionary = {}  # "x_z" -> true while ACTIVE or ASSEMBLING (terrain is in)
var _detail_in: Dictionary = {}  # cluster id -> true while its detail cell is ACTIVE
var _proxies: Dictionary = {}  # cluster id -> MeshInstance3D
var _meshes: Dictionary = {}  # proxy path -> Mesh, kept while its chunk is on its way in or in


func on_world_ready(context: WorldContext) -> void:
	_streaming = context.get_system(STREAMING) as StreamingSystem
	_container = context.stream_container
	if _streaming == null or not load_manifest():
		return
	_streaming.cell_state_changed.connect(_on_cell)
	sync_with(_streaming)


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


func _on_cell(id: StringName, state: StreamingSystem.CellState) -> void:
	var s: String = String(id)
	if s.begins_with(CHUNK_PREFIX):
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
			for cluster_id: String in _by_chunk[chunk]:
				_meshes.erase(_clusters[cluster_id]["proxy"])
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
	var want_proxy: bool = chunk_in and not detail_in
	if want_proxy and not _proxies.has(cluster_id):
		var mesh: Mesh = _mesh(info["proxy"])
		if mesh == null:
			return
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.name = "HLOD_" + cluster_id
		proxy.mesh = mesh
		proxy.position = info["centre"]
		proxy.set_meta("cluster_id", cluster_id)
		proxy.set_meta("tier", 1)
		add_child(proxy)
		_proxies[cluster_id] = proxy
		stats["to_hlod"] += 1
	elif not want_proxy and _proxies.has(cluster_id):
		var proxy: Node = _proxies[cluster_id]
		_proxies.erase(cluster_id)
		remove_child(proxy)
		proxy.queue_free()
		if detail_in:
			stats["to_detail"] += 1


func _detail_node(cluster_id: String) -> Node3D:
	return _container.get_node_or_null(NodePath("Cluster_" + cluster_id)) as Node3D if _container != null else null


## Starts background loads of a chunk's proxies while the chunk itself loads.
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

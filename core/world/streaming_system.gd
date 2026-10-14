# =============================================================================
# streaming_system.gd — the only owner of streamed world content.
#
# Reads archive/graciosa/data/world_data.tres and nothing else. There is no per-chunk variable
# and no per-chunk match arm anywhere in this file: adding a chunk means
# re-running tools/world/generate_world_data.gd, not editing code.
#
# Cell lifecycle, taken from ADT's pipeline:
#   UNLOADED -(entered the load band)-> QUEUED
#   QUEUED   -(picked up, load_threaded_request)-> LOADING
#   LOADING  -(THREAD_LOAD_LOADED)-> READY
#   READY    -(frame instantiation budget)-> ACTIVE, or ASSEMBLING when the chunk has
#              parts: they attach under it within assembly_budget_usec per frame, then ACTIVE
#   ACTIVE   -(left the unload band)-> UNLOADED
#   Rollback: QUEUED/READY leaving early return to UNLOADED without
#   instantiating; the threaded cache stays warm.
#
# Two rules that are not negotiable without a measurement:
#   * One distance metric. Chunks are compared on XZ distance against their own
#     authored radius plus a margin. Hysteresis is the gap between the load and
#     unload bands.
#   * Background loading is cheap, instantiate() + add_child() is what costs a
#     frame. That is why the instantiation budget is 1.
# =============================================================================
class_name StreamingSystem
extends Node

## Emitted on every cell state change, for debug readouts.
signal cell_state_changed(chunk_id: StringName, state: CellState)
## Emitted once the pipeline has its data and its ring 0.
signal initialized(chunk_count: int)
## Main-thread cost of one streaming stage (instantiate, add_child, attach_part, free), only while measure_stages is on.
signal stage_timed(chunk_id: StringName, stage: StringName, usec: int)

## Where a chunk is in the pipeline.
enum CellState { UNLOADED, QUEUED, LOADING, READY, ACTIVE, ASSEMBLING }

const DEFAULT_WORLD_DATA: String = "res://archive/graciosa/data/world_data.tres"
## Side of a scan grid bucket, metres. Cells are indexed by load band, so any size is exact.
const GRID_BUCKET_M: float = 256.0

@export_group("Distance")
## Metres added to a chunk's own radius to get its load band.
@export var load_margin_m: float = 140.0
## Extra metres beyond the load band before a chunk unloads. This gap is the
## hysteresis; without it a chunk on the boundary thrashes.
@export var unload_hysteresis_m: float = 120.0
## Metres the player must travel before the bands are re-evaluated.
@export var rescan_distance_m: float = 40.0

@export_group("Budgets")
## Concurrent background loads. Raising this does not make loading faster.
@export var max_concurrent_loads: int = 2
## instantiate() + add_child() per frame. One, on purpose.
@export var instantiation_budget_per_frame: int = 1
## Main-thread time per frame for attaching chunk parts; at least one part always attaches.
@export var assembly_budget_usec: int = 4000
## Packed scenes kept warm after their chunk unloads (LRU). Bounds memory on long trips.
@export var cold_cache_limit: int = 8

@export_group("Data")
@export_file("*.tres") var world_data_path: String = DEFAULT_WORLD_DATA
## Logs every state transition. Noisy; for checking a run.
@export var log_transitions: bool = false
## Emits stage_timed for every instantiate, add_child, part attach and free; for gates and stress tests.
@export var measure_stages: bool = false

var _world_data: WorldData
var _states: Dictionary = {}
var _chunks: Dictionary = {}
var _instances: Dictionary = {}
## Threaded loads hand a resource over exactly once, so the result is cached
## here. Two chunks sharing a scene path would false-fail without it.
var _packed_cache: Dictionary = {}
## Cached scene paths whose chunk is UNLOADED, oldest first.
var _cold_paths: Array[String] = []
## Chunks whose root is live and whose parts are still attaching: id -> next part index.
var _assembling: Dictionary = {}
var _loads_in_flight: int = 0
var _last_scan_position: Vector3 = Vector3(INF, INF, INF)
## Where the player was at the most recent scan. A background load that lands
## after the player has walked away must not be instantiated, so both the poll
## and the activation re-check the band against this.
var _known_player_position: Vector3 = Vector3(INF, INF, INF)
var _container: Node3D
var _player: Node3D
var _ring0: Node3D
## Runtime sources feed generated/in-memory chunks into this same state machine.
## Static WorldData remains untouched; runtime chunks skip ResourceLoader and
## activate through their source's callbacks.
var _runtime_chunks: Dictionary = {}
var _runtime_sources: Dictionary = {}
var _runtime_ring0_built: Dictionary = {}
var _initialized: bool = false
var _runtime_only_profile: bool = false
## Profile asks for the world under the spawn to exist before the first frame.
var _prewarm: bool = false
## Cells in QUEUED, LOADING, READY or ASSEMBLING: the only ones pump() walks.
var _transient: Dictionary = {}
## Cells not UNLOADED: the only ones scan() can release outside the grid query.
var _live: Dictionary = {}
## Registration order; READY cells activate in it, as the full walk did.
var _order: Dictionary = {}
## Spatial grid over load bands: bucket key -> ids whose load band overlaps the bucket.
var _grid: Dictionary = {}
## load_margin_m the grid was built with; a changed margin rebuilds it on the next scan.
var _grid_margin: float = NAN
## Static cells sharing a content scene path: path -> ids, for the cold cache.
var _ids_by_path: Dictionary = {}


func apply_world_profile(profile: WorldProfile) -> void:
	if profile == null:
		return
	_runtime_only_profile = profile.world_data_path == ""
	_prewarm = profile.prewarm_before_first_frame
	if not _runtime_only_profile:
		world_data_path = profile.world_data_path


## The composition root's lifecycle hook.
func on_world_ready(context: WorldContext) -> void:
	## A test scene has its own floor; the island's chunks do not belong in it.
	if not context.streaming_enabled:
		set_process(false)
		return
	if _runtime_only_profile:
		initialize_runtime_only(context.stream_container, context.player)
	else:
		initialize(context.stream_container, context.player)


## Loads the data, builds ring 0 and starts streaming. Public and idempotent
## so tests and tools can drive it without the composition root.
func initialize(container: Node3D, player: Node3D) -> void:
	if _initialized:
		return
	_container = container
	_player = player
	_world_data = load(world_data_path) as WorldData
	if _world_data == null:
		push_error("StreamingSystem: cannot load %s" % world_data_path)
		return
	for chunk: ChunkData in _world_data.get_streamable_chunks():
		_chunks[chunk.id] = chunk
		_states[chunk.id] = CellState.UNLOADED
		_index(chunk.id, chunk.position, chunk.radius)
		(_ids_by_path.get_or_add(chunk.content_scene_path, []) as Array).append(chunk.id)
	_build_ring0()
	_build_registered_runtime_ring0()
	_initialized = true
	if _prewarm and _player != null:
		prewarm(_player.global_position)
	initialized.emit(get_chunk_count())
	if _player != null:
		scan(_player.global_position)


## Loads and activates every static chunk in the load band synchronously. Boot-time only:
## physics must not run over a spawn whose content is still on a loader thread.
func prewarm(player_position: Vector3) -> int:
	_known_player_position = player_position
	var activated: int = 0
	for id: StringName in _chunks:
		var chunk: ChunkData = _chunks[id]
		if _plane_distance(player_position, chunk.position) > chunk.radius + load_margin_m:
			continue
		if _states.get(id, CellState.UNLOADED) == CellState.ACTIVE:
			continue
		var missing: bool = false
		for path: String in _scene_paths(chunk):
			if not _packed_cache.has(path):
				var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
				if packed == null:
					missing = true
					break
				_packed_cache[path] = packed
		if missing:
			continue
		_set_state(id, CellState.READY)
		_activate(id)
		if _assembling.has(id):
			for path: String in chunk.part_scene_paths.slice(int(_assembling[id])):
				_attach_part(id, path)
			_assembling.erase(id)
			_set_state(id, CellState.ACTIVE)
		activated += 1
	return activated


## Runtime-only initialization for tools/experimental worlds that do not use
## archive/graciosa/data/world_data.tres. The owner and state machine are still StreamingSystem.
func initialize_runtime_only(container: Node3D, player: Node3D) -> void:
	if _initialized:
		return
	_container = container
	_player = player
	_build_registered_runtime_ring0()
	_initialized = true
	initialized.emit(get_chunk_count())
	if _player != null:
		scan(_player.global_position)


## Registers generated chunks without converting them into PackedScenes.
## The source must implement:
##   get_stream_chunks() -> Array[Dictionary{id, position, radius}]
##   activate_stream_chunk(id, container) -> Node3D
##   deactivate_stream_chunk(id)
## Optional:
##   build_stream_ring0(container)
func register_runtime_source(source: Node) -> int:
	if source == null or not source.has_method(&"get_stream_chunks"):
		push_error("StreamingSystem: runtime source has no get_stream_chunks()")
		return 0
	var descriptors: Variant = source.call(&"get_stream_chunks")
	if not descriptors is Array:
		push_error("StreamingSystem: runtime source returned non-array descriptors")
		return 0

	var added: int = 0
	for descriptor_variant: Variant in descriptors:
		if not descriptor_variant is Dictionary:
			continue
		var descriptor := descriptor_variant as Dictionary
		var id := StringName(String(descriptor.get("id", "")))
		if id == &"":
			continue
		if _chunks.has(id) or _runtime_chunks.has(id):
			push_warning("StreamingSystem: duplicate runtime chunk '%s'" % id)
			continue
		var position_variant: Variant = descriptor.get("position", Vector3.ZERO)
		if not position_variant is Vector3:
			push_warning("StreamingSystem: runtime chunk '%s' has no Vector3 position" % id)
			continue
		var radius: float = float(descriptor.get("radius", 0.0))
		if radius <= 0.0:
			push_warning("StreamingSystem: runtime chunk '%s' has non-positive radius" % id)
			continue
		_runtime_chunks[id] = {
			"position": position_variant as Vector3,
			"radius": radius,
		}
		_runtime_sources[id] = source
		_states[id] = CellState.UNLOADED
		_index(id, position_variant as Vector3, radius)
		added += 1

	if _container != null:
		_build_runtime_source_ring0(source)
	if _initialized and _player != null:
		scan(_player.global_position)
	return added


func _build_registered_runtime_ring0() -> void:
	var seen: Dictionary = {}
	for source_variant: Variant in _runtime_sources.values():
		var source := source_variant as Node
		if not is_instance_valid(source):
			continue
		var key: int = source.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		_build_runtime_source_ring0(source)


func _build_runtime_source_ring0(source: Node) -> void:
	if _container == null or not is_instance_valid(source):
		return
	var key: int = source.get_instance_id()
	if _runtime_ring0_built.has(key):
		return
	if source.has_method(&"build_stream_ring0"):
		source.call(&"build_stream_ring0", _container)
	_runtime_ring0_built[key] = true


func _process(_delta: float) -> void:
	if not _initialized or _player == null:
		return
	pump()
	var position: Vector3 = _player.global_position
	if _plane_distance(position, _last_scan_position) < rescan_distance_m:
		return
	_last_scan_position = position
	scan(position)


## Re-evaluates the chunks near the player and every live one. Public so a test can
## place the player anywhere without moving a node.
func scan(player_position: Vector3) -> void:
	_known_player_position = player_position
	if _grid_margin != load_margin_m:
		_rebuild_grid()
	var near: Array = _grid.get(_bucket(player_position), [])
	var seen: Dictionary = {}
	for id: StringName in near:
		seen[id] = true
		_scan_id(id, player_position)
	## A cell whose load band misses the player's bucket can only need a release.
	for id: StringName in _live.keys():
		if not seen.has(id):
			_scan_id(id, player_position)


func _scan_id(id: StringName, player_position: Vector3) -> void:
	if _chunks.has(id):
		var chunk: ChunkData = _chunks[id]
		_scan_one(id, player_position, chunk.position, chunk.radius)
		return
	var descriptor: Dictionary = _runtime_chunks[id]
	_scan_one(id, player_position, descriptor["position"] as Vector3, float(descriptor["radius"]))


func _scan_one(id: StringName, player_position: Vector3, position: Vector3, radius: float) -> void:
	var distance: float = _plane_distance(player_position, position)
	if distance <= radius + load_margin_m:
		_request(id)
	elif distance > radius + load_margin_m + unload_hysteresis_m:
		_release(id)


## Advances loads and instantiations within their budgets. One call per frame.
func pump() -> void:
	_poll_loads()
	_start_queued_loads()
	_assemble()
	var budget: int = instantiation_budget_per_frame
	var ready: Array[StringName] = []
	for id: StringName in _transient:
		if _states[id] == CellState.READY:
			ready.append(id)
	if ready.size() > 1:
		ready.sort_custom(func(a: StringName, b: StringName) -> bool: return _order[a] < _order[b])
	for id: StringName in ready:
		if budget <= 0:
			break
		if not _is_within_unload_band(id):
			## The player left while this was loading. Roll back without ever
			## instantiating; the packed scene stays cached for the next approach.
			_set_state(id, CellState.UNLOADED)
			continue
		_activate(id)
		budget -= 1


func get_state(id: StringName) -> CellState:
	return _states.get(id, CellState.UNLOADED)


## Ids of every chunk whose content is live in the scene.
func get_active_chunks() -> Array[StringName]:
	var active: Array[StringName] = []
	for id: StringName in _states:
		if _states[id] == CellState.ACTIVE:
			active.append(id)
	return active


func get_chunk_count() -> int:
	return _chunks.size() + _runtime_chunks.size()


func get_runtime_chunk_count() -> int:
	return _runtime_chunks.size()


## Frees every streamed instance and returns the pipeline to its start state.
func reset() -> void:
	for id: StringName in _instances.keys():
		_free_instance(id)
	for id: StringName in _states:
		_states[id] = CellState.UNLOADED
	_packed_cache.clear()
	_cold_paths.clear()
	_assembling.clear()
	_transient.clear()
	_live.clear()
	_loads_in_flight = 0
	_last_scan_position = Vector3(INF, INF, INF)


## Ring 0: light stand-ins, built once, never unloaded. A chunk without a
## silhouette scene simply has none — the island's terrain is the floor.
func _build_ring0() -> void:
	if _container == null:
		return
	_ring0 = Node3D.new()
	_ring0.name = "Ring0"
	_container.add_child(_ring0)
	for id: StringName in _chunks:
		var chunk: ChunkData = _chunks[id]
		if chunk.silhouette_scene_path == "":
			continue
		var packed := load(chunk.silhouette_scene_path) as PackedScene
		if packed == null:
			push_warning("StreamingSystem: silhouette missing for '%s'" % id)
			continue
		var instance := packed.instantiate() as Node3D
		if instance == null:
			continue
		_ring0.add_child(instance)
		instance.global_position = chunk.position


## Moves a chunk toward being live, one step per call.
func _request(id: StringName) -> void:
	if _runtime_chunks.has(id):
		match _states.get(id, CellState.UNLOADED):
			CellState.UNLOADED:
				_set_state(id, CellState.QUEUED)
				_set_state(id, CellState.READY)
			CellState.QUEUED:
				_set_state(id, CellState.READY)
			_:
				pass
		return
	match _states.get(id, CellState.UNLOADED):
		CellState.UNLOADED:
			_set_state(id, CellState.QUEUED)
			_try_start_load(id)
		CellState.QUEUED:
			_try_start_load(id)
		_:
			pass


## Fills free load slots from the queue, nearest chunk first. Without this a queued
## chunk waited for the next rescan, i.e. for the player to walk 40 m.
func _start_queued_loads() -> void:
	if _loads_in_flight >= max_concurrent_loads:
		return
	var queued: Array[StringName] = []
	for id: StringName in _transient:
		if _states[id] == CellState.QUEUED and _chunks.has(id):
			queued.append(id)
	if queued.is_empty():
		return
	queued.sort_custom(func(a: StringName, b: StringName) -> bool: return _queue_distance(a) < _queue_distance(b))
	for id: StringName in queued:
		if _loads_in_flight >= max_concurrent_loads:
			return
		_try_start_load(id)


func _queue_distance(id: StringName) -> float:
	if _known_player_position.x == INF:
		return 0.0
	return _plane_distance(_known_player_position, (_chunks[id] as ChunkData).position)


## Starts a background load if the concurrency budget allows it.
func _try_start_load(id: StringName) -> void:
	if _loads_in_flight >= max_concurrent_loads:
		return
	var chunk: ChunkData = _chunks[id]
	_cold_paths.erase(chunk.content_scene_path)
	var missing: PackedStringArray = PackedStringArray()
	for path: String in _scene_paths(chunk):
		if not _packed_cache.has(path):
			missing.append(path)
	if missing.is_empty():
		_set_state(id, CellState.READY)
		return
	for path: String in missing:
		var error: Error = ResourceLoader.load_threaded_request(path, "PackedScene", true)
		if error != OK:
			push_warning("StreamingSystem: cannot start loading '%s' (%d)" % [path, error])
			_set_state(id, CellState.UNLOADED)
			return
	_loads_in_flight += 1
	_set_state(id, CellState.LOADING)


## The content scene first, then its parts in attach order.
func _scene_paths(chunk: ChunkData) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray([chunk.content_scene_path])
	paths.append_array(chunk.part_scene_paths)
	return paths


## Collects finished background loads.
func _poll_loads() -> void:
	for id: StringName in _transient.keys():
		if _states[id] != CellState.LOADING or not _chunks.has(id):
			continue
		var chunk: ChunkData = _chunks[id]
		var pending: bool = false
		var failed: bool = false
		for path: String in _scene_paths(chunk):
			if _packed_cache.has(path):
				continue
			match ResourceLoader.load_threaded_get_status(path):
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					pending = true
				ResourceLoader.THREAD_LOAD_LOADED:
					var packed := ResourceLoader.load_threaded_get(path) as PackedScene
					if packed == null:
						failed = true
					else:
						_packed_cache[path] = packed
				_:
					failed = true
		if pending and not failed:
			continue
		_loads_in_flight = maxi(0, _loads_in_flight - 1)
		if failed:
			push_warning("StreamingSystem: load failed for '%s'" % id)
			_set_state(id, CellState.UNLOADED)
		elif _is_within_unload_band(id):
			_set_state(id, CellState.READY)
		else:
			_set_state(id, CellState.UNLOADED)


## Instantiates a ready chunk. This is the expensive step the budget guards.
func _activate(id: StringName) -> void:
	if _runtime_chunks.has(id):
		var source := _runtime_sources.get(id) as Node
		if not is_instance_valid(source) or _container == null:
			_set_state(id, CellState.UNLOADED)
			return
		if not source.has_method(&"activate_stream_chunk"):
			push_warning("StreamingSystem: runtime source cannot activate '%s'" % id)
			_set_state(id, CellState.UNLOADED)
			return
		var instance := source.call(&"activate_stream_chunk", id, _container) as Node3D
		if instance == null:
			_set_state(id, CellState.UNLOADED)
			return
		_instances[id] = instance
		_set_state(id, CellState.ACTIVE)
		return

	var chunk: ChunkData = _chunks[id]
	var packed := _packed_cache.get(chunk.content_scene_path) as PackedScene
	if packed == null or _container == null:
		_set_state(id, CellState.UNLOADED)
		return
	var t0: int = Time.get_ticks_usec()
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_set_state(id, CellState.UNLOADED)
		return
	var t1: int = Time.get_ticks_usec()
	_container.add_child(instance)
	instance.global_position = chunk.position
	if measure_stages:
		stage_timed.emit(id, &"instantiate", t1 - t0)
		stage_timed.emit(id, &"add_child", Time.get_ticks_usec() - t1)
	_instances[id] = instance
	if chunk.part_scene_paths.is_empty():
		_set_state(id, CellState.ACTIVE)
		return
	_assembling[id] = 0
	_set_state(id, CellState.ASSEMBLING)


## Attaches chunk parts under their live root within assembly_budget_usec, nearest chunk first.
## Parts were decoded on loader threads; only instantiate() + add_child() run here.
func _assemble() -> void:
	if _assembling.is_empty():
		return
	var deadline: int = Time.get_ticks_usec() + assembly_budget_usec
	var ids: Array = _assembling.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _queue_distance(a) < _queue_distance(b))
	var attached: int = 0
	for id: StringName in ids:
		var parts: PackedStringArray = (_chunks[id] as ChunkData).part_scene_paths
		var next: int = _assembling[id]
		while next < parts.size():
			if attached > 0 and Time.get_ticks_usec() >= deadline:
				_assembling[id] = next
				return
			_attach_part(id, parts[next])
			next += 1
			attached += 1
		_assembling.erase(id)
		_set_state(id, CellState.ACTIVE)


func _attach_part(id: StringName, path: String) -> void:
	var packed := _packed_cache.get(path) as PackedScene
	var root_instance := _instances.get(id) as Node3D
	if packed == null or not is_instance_valid(root_instance):
		return
	var t0: int = Time.get_ticks_usec()
	attach_part(root_instance, packed.instantiate())
	if measure_stages:
		stage_timed.emit(id, &"attach_part", Time.get_ticks_usec() - t0)


## Attaches a part scene under its chunk root, or under the node its "attach_to" meta names.
static func attach_part(chunk_root: Node, part: Node) -> void:
	var parent: Node = chunk_root.get_node_or_null(NodePath(String(part.get_meta("attach_to", "")))) if part.has_meta("attach_to") else null
	(parent if parent != null else chunk_root).add_child(part)


## Drops a chunk back to UNLOADED. A queued or ready chunk rolls back without
## ever instantiating, and the threaded cache stays warm for the next approach.
func _release(id: StringName) -> void:
	var state: CellState = _states.get(id, CellState.UNLOADED)
	if state == CellState.UNLOADED:
		return
	if state == CellState.LOADING:
		return
	if state == CellState.ACTIVE or state == CellState.ASSEMBLING:
		_free_instance(id)
		_assembling.erase(id)
	_set_state(id, CellState.UNLOADED)


## True while a chunk is still inside the band that keeps it alive. Unknown
## player position counts as inside, so a pipeline nobody has scanned yet
## behaves as it did before.
func _is_within_unload_band(id: StringName) -> bool:
	if _known_player_position.x == INF:
		return true
	if _runtime_chunks.has(id):
		var descriptor: Dictionary = _runtime_chunks[id]
		var position := descriptor["position"] as Vector3
		var radius: float = float(descriptor["radius"])
		var runtime_distance: float = _plane_distance(_known_player_position, position)
		return runtime_distance <= radius + load_margin_m + unload_hysteresis_m
	var chunk: ChunkData = _chunks[id]
	var distance: float = _plane_distance(_known_player_position, chunk.position)
	return distance <= chunk.radius + load_margin_m + unload_hysteresis_m


func _free_instance(id: StringName) -> void:
	if _runtime_chunks.has(id):
		var source := _runtime_sources.get(id) as Node
		if is_instance_valid(source) and source.has_method(&"deactivate_stream_chunk"):
			source.call(&"deactivate_stream_chunk", id)
		_instances.erase(id)
		return
	var instance: Node = _instances.get(id)
	var t0: int = Time.get_ticks_usec()
	if is_instance_valid(instance):
		if instance.get_parent() != null:
			instance.get_parent().remove_child(instance)
		instance.queue_free()
	if measure_stages:
		stage_timed.emit(id, &"free", Time.get_ticks_usec() - t0)
	_instances.erase(id)


func _set_state(id: StringName, state: CellState) -> void:
	if _states.get(id, CellState.UNLOADED) == state:
		return
	_states[id] = state
	if state in [CellState.QUEUED, CellState.LOADING, CellState.READY, CellState.ASSEMBLING]:
		_transient[id] = true
	else:
		_transient.erase(id)
	if state == CellState.UNLOADED:
		_live.erase(id)
		_cool(id)
	else:
		_live[id] = true
	if log_transitions:
		print("[Streaming] %s -> %s" % [id, CellState.keys()[state]])
	cell_state_changed.emit(id, state)


## A released chunk's packed scene becomes cold; beyond the limit the oldest cold one is dropped.
func _cool(id: StringName) -> void:
	var chunk: ChunkData = _chunks.get(id)
	if chunk == null or not _packed_cache.has(chunk.content_scene_path):
		return
	_cold_paths.erase(chunk.content_scene_path)
	_cold_paths.append(chunk.content_scene_path)
	while _cold_paths.size() > maxi(cold_cache_limit, 0):
		var path: String = _cold_paths.pop_front()
		if not _path_in_use(path):
			_packed_cache.erase(path)
			for other: StringName in _ids_by_path.get(path, []):
				for part: String in (_chunks[other] as ChunkData).part_scene_paths:
					_packed_cache.erase(part)


func _path_in_use(path: String) -> bool:
	for other: StringName in _ids_by_path.get(path, []):
		if _live.has(other):
			return true
	return false


## Registers a cell's order and adds it to every grid bucket its load band overlaps.
func _index(id: StringName, position: Vector3, radius: float) -> void:
	_order[id] = _order.size()
	if _grid_margin == load_margin_m:
		_grid_add(id, position, radius)


func _rebuild_grid() -> void:
	_grid.clear()
	_grid_margin = load_margin_m
	for id: StringName in _order:
		if _chunks.has(id):
			_grid_add(id, (_chunks[id] as ChunkData).position, (_chunks[id] as ChunkData).radius)
		else:
			_grid_add(id, _runtime_chunks[id]["position"] as Vector3, float(_runtime_chunks[id]["radius"]))


func _grid_add(id: StringName, position: Vector3, radius: float) -> void:
	var reach: float = radius + load_margin_m
	var lo: Vector2i = _bucket(position - Vector3(reach, 0.0, reach))
	var hi: Vector2i = _bucket(position + Vector3(reach, 0.0, reach))
	for bx: int in range(lo.x, hi.x + 1):
		for bz: int in range(lo.y, hi.y + 1):
			(_grid.get_or_add(Vector2i(bx, bz), []) as Array).append(id)


func _bucket(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / GRID_BUCKET_M), floori(position.z / GRID_BUCKET_M))


## XZ distance. Chunks are full-height, so height never enters the metric.
func _plane_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

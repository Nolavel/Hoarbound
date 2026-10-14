extends SceneTree
## StreamingSystem bookkeeping cost against cell count: the Reality world data (523 cells) and the island in 128 m
## clusters (16 per chunk). Every cell loads an empty scene, so only scan() and pump() themselves are timed.
## godot --headless --script <this> -- [out.json]

const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
const EMPTY_SCENE: String = "user://bench_streaming_empty.scn"
const CHUNK_M: float = 512.0
const CLUSTER_M: float = 128.0
const RUNS: int = 200
## Off the island (nothing in band) and the Old Town core (cells in band, settled).
const SPOTS: Dictionary = {"off_island": Vector3(30000.0, 0.0, 30000.0), "old_town": Vector3(-2560.0, 0.0, 1024.0)}


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	var packed: PackedScene = PackedScene.new()
	packed.pack(root_node)
	ResourceSaver.save(packed, EMPTY_SCENE)
	root_node.free()
	var source: WorldData = load(WORLD_DATA) as WorldData
	var report: Dictionary = {"godot": Engine.get_version_info()["string"], "runs": RUNS, "cases": {}}
	for scale: String in ["reality", "island_c128"]:
		var data: WorldData = _data(source, scale == "island_c128")
		for spot: String in SPOTS:
			var r: Dictionary = await _measure(data, SPOTS[spot])
			report["cases"]["%s_%s" % [scale, spot]] = r
			print("streaming scale: %s %s cells %d  scan %.3f ms  idle pump %.3f ms  active %d" % [scale, spot, r["cells"], r["scan_ms"], r["idle_pump_ms"], r["active"]])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		var f: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(report, " ", false))
		f.close()
	quit(0)


## Every cell of the source with its scene swapped for the empty one; with island set, 16 cluster cells per chunk.
func _data(source: WorldData, island: bool) -> WorldData:
	var data: WorldData = WorldData.new()
	var ids: Dictionary = {}
	for chunk: ChunkData in source.get_streamable_chunks():
		data.chunks.append(_cell(chunk.id, chunk.position, chunk.radius))
		ids[chunk.id] = true
	if not island:
		return data
	for chunk: ChunkData in source.get_streamable_chunks():
		if not String(chunk.id).begins_with("kw_gen_"):
			continue
		var corner: Vector3 = chunk.position - Vector3(CHUNK_M, 0.0, CHUNK_M) * 0.5
		for i: int in range(16):
			var gx: int = floori(corner.x / CLUSTER_M) + i % 4
			var gz: int = floori(corner.z / CLUSTER_M) + i / 4
			var id: StringName = StringName("kw_bld_c128_%d_%d" % [gx, gz])
			if ids.has(id):
				continue
			ids[id] = true
			var centre: Vector3 = Vector3((gx + 0.5) * CLUSTER_M, 0.0, (gz + 0.5) * CLUSTER_M)
			data.chunks.append(_cell(id, centre, CLUSTER_M * 0.5 * sqrt(2.0)))
	return data


func _cell(id: StringName, position: Vector3, radius: float) -> ChunkData:
	var cell: ChunkData = ChunkData.new()
	cell.id = id
	cell.position = position
	cell.radius = radius
	cell.content_scene_path = EMPTY_SCENE
	return cell


## Settles the streamer at the spot, then times RUNS scans and RUNS idle pumps.
func _measure(data: WorldData, at: Vector3) -> Dictionary:
	var container: Node3D = Node3D.new()
	root.add_child(container)
	var streaming: StreamingSystem = StreamingSystem.new()
	streaming.max_concurrent_loads = 64
	streaming.instantiation_budget_per_frame = 64
	root.add_child(streaming)
	streaming.set_process(false)
	var path: String = "user://bench_streaming_world_%d.tres" % data.chunks.size()
	ResourceSaver.save(data, path)
	streaming.world_data_path = path
	streaming.initialize(container, null)
	streaming.scan(at)
	for i: int in range(2000):
		streaming.pump()
		if _settled(streaming):
			break
		await process_frame
	var t0: int = Time.get_ticks_usec()
	for i: int in range(RUNS):
		streaming.scan(at)
	var scan_us: float = float(Time.get_ticks_usec() - t0) / RUNS
	t0 = Time.get_ticks_usec()
	for i: int in range(RUNS):
		streaming.pump()
	var pump_us: float = float(Time.get_ticks_usec() - t0) / RUNS
	var result: Dictionary = {"cells": streaming.get_chunk_count(), "active": streaming.get_active_chunks().size(),
		"settled": _settled(streaming), "scan_ms": snappedf(scan_us / 1000.0, 0.001), "idle_pump_ms": snappedf(pump_us / 1000.0, 0.001)}
	streaming.queue_free()
	container.queue_free()
	await process_frame
	return result


func _settled(streaming: StreamingSystem) -> bool:
	for state: int in (streaming.get(&"_states") as Dictionary).values():
		if state in [StreamingSystem.CellState.QUEUED, StreamingSystem.CellState.LOADING, StreamingSystem.CellState.READY, StreamingSystem.CellState.ASSEMBLING]:
			return false
	return true

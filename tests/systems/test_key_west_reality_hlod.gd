extends SceneTree

## HLOD v1 in the real StreamingSystem: every cluster of a loaded chunk shows exactly one representation after
## every pump on a walk detail -> HLOD -> detail, proxies carry no collision, and a boundary wobble does not swap.
## Run: godot --headless --script tests/systems/test_key_west_reality_hlod.gd

const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
const SETTLE_DEADLINE_MS: int = 20000
const SETTLE_QUIET_PUMPS: int = 30
const STEP_M: float = 40.0
## East of the sector, through its core, out west, and back to the core (local metres, z fixed).
const ROUTE_X: Array[float] = [-1200.0, -2560.0, -3500.0, -2560.0]
const ROUTE_Z: float = 1000.0

var _failures: int = 0
var _system: StreamingSystem
var _hlod: KeyWestRealityHLOD
var _container: Node3D
var _player: Node3D
var _history: Dictionary = {}  # cluster id -> PackedStringArray of representations, deduplicated
var _checked_pumps: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_check_build()
	_check_dirty_isolation()
	_check_far_view_after_prewarm()
	_make_rig()
	_walk()
	_check_round_trip()
	_check_hysteresis()
	print("hlod: %d pumps checked, %d proxies now, stats %s" % [_checked_pumps, _hlod.proxy_count(), _hlod.stats])
	if _failures > 0:
		push_error("hlod: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hlod: all checks passed")
	quit(0)


## Offline output: manifest, proxies and detail cells agree; HLOD chunks keep no generated building of their own.
func _check_build() -> void:
	var manifest: Dictionary = KeyWestHLODBuilder.load_manifest()
	_check(not manifest.is_empty(), "no HLOD manifest")
	var data: WorldData = load(WORLD_DATA) as WorldData
	var cells: Dictionary = {}
	for chunk: ChunkData in data.get_streamable_chunks():
		cells[String(chunk.id)] = chunk
	for entry: Dictionary in manifest.get("clusters", []):
		_check(cells.has(entry["detail_cell"]), "%s has no detail cell in WorldData" % entry["cluster_id"])
		var proxy: Mesh = load(entry["proxy_path"]) as Mesh
		_check(proxy != null and proxy.get_surface_count() == int(entry["surfaces"]), "%s proxy missing or surfaces differ" % entry["cluster_id"])
		_check(int(entry["triangles"]) <= int(entry["detail_triangles"]), "%s proxy has more triangles than its detail" % entry["cluster_id"])
	var first: Dictionary = (manifest.get("clusters", [{}]) as Array)[0]
	var detail: Node = (load(first.get("detail_scene", "")) as PackedScene).instantiate() if first.has("detail_scene") else null
	_check(detail != null and detail.find_child("BuildingCollision", true, false) != null, "detail cluster carries no building collision")
	if detail != null:
		detail.free()
	for chunk_id: String in manifest.get("chunks", []):
		var p: PackedStringArray = chunk_id.split(":")
		var chunk: Node = KeyWestChunkGenerator.instantiate_assembled("res://scenes/world/key_west/generated/chunks/Chunk_%s_%s.scn" % [p[0], p[1]])
		var buildings: Node = chunk.get_node_or_null(^"Buildings")
		var own: int = 0
		if buildings != null:
			for n: Node in buildings.get_children():
				if n is MeshInstance3D and String(n.get_meta("regen_action", "")) == "generate":
					own += 1
		_check(own == 0, "chunk %s still holds %d generated buildings" % [chunk_id, own])
		_check(chunk.get_meta("hlod_clusters", []).size() > 0, "chunk %s lists no clusters" % chunk_id)
		chunk.free()


## Changing one source building dirties exactly its own cluster; the others keep their hash.
func _check_dirty_isolation() -> void:
	var builder: KeyWestHLODBuilder = KeyWestHLODBuilder.new()
	var clusters: Dictionary = builder.sources()["clusters"]
	var before: Dictionary = {}
	for cluster_id: String in clusters.keys():
		before[cluster_id] = builder.source_hash(clusters[cluster_id]["features"])
	var target: String = (clusters.keys() as Array)[0]
	var feature: Dictionary = clusters[target]["features"][0]
	feature["mesh"]["base_y"] = float(feature["mesh"]["base_y"]) + 0.5
	var changed: PackedStringArray = PackedStringArray()
	for cluster_id: String in clusters.keys():
		if builder.source_hash(clusters[cluster_id]["features"]) != before[cluster_id]:
			changed.append(cluster_id)
	_check(changed == PackedStringArray([target]), "editing one building in %s dirtied %s" % [target, changed])
	_check(KeyWestHLODBuilder.new().status().values().all(func(st: String) -> bool: return st == "fresh"), "the committed HLOD is not fresh")


## Chunks the streamer prewarmed before the far view connected must still hide their far meshes (727 door bug).
func _check_far_view_after_prewarm() -> void:
	var container: Node3D = Node3D.new()
	root.add_child(container)
	var player: Node3D = Node3D.new()
	player.position = Vector3(-3531.0, 0.0, 1582.0)  # 727 Fort St
	root.add_child(player)
	var system: StreamingSystem = StreamingSystem.new()
	system.world_data_path = WORLD_DATA
	root.add_child(system)
	system.initialize(container, player)
	system.prewarm(player.position)
	var context: WorldContext = WorldContext.new()
	context.systems = [system]
	context.stream_container = container
	var far: KeyWestRealityFar = KeyWestRealityFar.new()
	root.add_child(far)
	far.on_world_ready(context)
	system.instantiation_budget_per_frame = 1000
	system.scan(player.position)
	system.pump()
	var checked: int = 0
	for id: StringName in system.get_active_chunks():
		var far_node: Node3D = far.get_node_or_null(NodePath("Far_" + String(id).trim_prefix("kw_gen_"))) as Node3D
		if String(id).begins_with("kw_gen_") and far_node != null:
			checked += 1
			_check(not far_node.visible, "far mesh of prewarmed %s draws over its detail" % id)
	_check(checked > 0, "no prewarmed chunk had a far mesh to check")
	system.reset()
	for n: Node in [far, system, player, container]:
		n.free()


func _make_rig() -> void:
	_container = Node3D.new()
	_container.name = "StreamContainer"
	root.add_child(_container)
	_player = Node3D.new()
	root.add_child(_player)
	_system = StreamingSystem.new()
	_system.world_data_path = WORLD_DATA
	root.add_child(_system)
	_hlod = KeyWestRealityHLOD.new()
	root.add_child(_hlod)
	_check(_hlod.load_manifest(), "runtime could not read the manifest")
	_hlod.set_container(_container)
	_system.cell_state_changed.connect(_hlod._on_cell)
	_player.position = Vector3(ROUTE_X[0], 0.0, ROUTE_Z)
	_system.initialize(_container, _player)
	_hlod.sync_with(_system)


func _walk() -> void:
	for leg: int in range(ROUTE_X.size() - 1):
		var x: float = ROUTE_X[leg]
		var to: float = ROUTE_X[leg + 1]
		var dir: float = signf(to - x)
		while (to - x) * dir > 0.0:
			x += dir * minf(STEP_M, absf(to - x))
			_go(Vector3(x, 0.0, ROUTE_Z))


func _go(at: Vector3) -> void:
	_player.position = at
	_system.scan(at)
	var until: int = Time.get_ticks_msec() + SETTLE_DEADLINE_MS
	var quiet: int = 0
	while Time.get_ticks_msec() < until and quiet < SETTLE_QUIET_PUMPS:
		var before: String = str(_system._states)
		_system.pump()
		OS.delay_msec(1)
		_check_invariant()
		var busy: bool = _system._states.values().any(func(st: int) -> bool:
			return st in [StreamingSystem.CellState.QUEUED, StreamingSystem.CellState.LOADING, StreamingSystem.CellState.READY, StreamingSystem.CellState.ASSEMBLING])
		quiet = quiet + 1 if str(_system._states) == before and not busy else 0
	_check(quiet >= SETTLE_QUIET_PUMPS, "streaming did not settle at %s" % at)
	for cluster_id: String in _hlod.cluster_ids():
		var rep: String = _hlod.representation(cluster_id)
		var seen: PackedStringArray = _history.get(cluster_id, PackedStringArray())
		if seen.is_empty() or seen[-1] != rep:
			seen.append(rep)
		_history[cluster_id] = seen


## After every pump: no cluster draws both representations or neither; proxies have no collision.
func _check_invariant() -> void:
	_checked_pumps += 1
	for cluster_id: String in _hlod.cluster_ids():
		var rep: String = _hlod.representation(cluster_id)
		if rep == "both" or rep == "none":
			_check(false, "%s shows %s at %s" % [cluster_id, rep, _player.position])
	for proxy: Node in _hlod.get_children():
		_check(proxy.get_child_count() == 0, "%s has children (collision or gameplay)" % proxy.name)


func _check_round_trip() -> void:
	var trips: int = 0
	var hlod_seen: int = 0
	for cluster_id: String in _history.keys():
		var seq: String = ",".join(_history[cluster_id])
		if seq.contains("hlod"):
			hlod_seen += 1
		if seq.contains("detail,hlod") and seq.contains("hlod,detail"):
			trips += 1
	print("hlod: %d clusters went detail -> hlod and back, %d showed a proxy on the walk" % [trips, hlod_seen])
	_check(hlod_seen > 0, "no cluster ever showed its proxy")
	_check(trips > 0, "no cluster made the detail -> HLOD -> detail round trip")


## Crossing a cluster's load edge by less than the hysteresis back and forth must not swap that cluster.
## An inner cluster of its chunk is used, so the chunk itself stays in throughout.
func _check_hysteresis() -> void:
	var cluster_id: String = ""
	var best: float = INF
	for candidate: String in _hlod.cluster_ids():
		var c: Vector3 = KeyWestChunkBuilder.cluster_centre(candidate)
		var chunk_centre: Vector3 = Vector3((floorf(c.x / 512.0) + 0.5) * 512.0, 0.0, (floorf(c.z / 512.0) + 0.5) * 512.0)
		if c.distance_to(chunk_centre) < best:
			best = c.distance_to(chunk_centre)
			cluster_id = candidate
	var centre: Vector3 = KeyWestChunkBuilder.cluster_centre(cluster_id)
	var load_edge: float = KeyWestChunkBuilder.detail_band_m()
	var reps: PackedStringArray = PackedStringArray()
	for offset: float in [load_edge - 5.0, load_edge + 40.0, load_edge - 5.0, load_edge + 80.0, load_edge - 5.0]:
		_go(centre + Vector3.RIGHT * offset)
		reps.append(_hlod.representation(cluster_id))
	_check(not reps.has("hlod") and reps[0] == "detail", "%s swapped inside the hysteresis band: %s" % [cluster_id, reps])
	_go(centre + Vector3.RIGHT * (load_edge + 130.0))
	_check(_hlod.representation(cluster_id) == "hlod", "%s kept its detail past the unload edge" % cluster_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hlod: %s" % message)

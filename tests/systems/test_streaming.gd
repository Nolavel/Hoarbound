extends SceneTree

## Covers the data-driven streaming pipeline: the generated data, the cell
## state machine, hysteresis, the budgets, and rollback without instantiating.
## Run: godot --headless --script tests/systems/test_streaming.gd

const WORLD_DATA: String = "res://archive/graciosa/data/world_data.tres"

## Upper bound on how long a settle may wait for the loader thread.
const SETTLE_DEADLINE_MS: int = 5000
## Consecutive pumps with no state change before a settle counts as done.
const SETTLE_QUIET_PUMPS: int = 60

class RuntimeSource:
	extends Node

	var ring0_built: bool = false
	var active: Dictionary = {}

	func get_stream_chunks() -> Array:
		return [{
			"id": &"runtime_test",
			"position": Vector3.ZERO,
			"radius": 30.0,
		}]

	func build_stream_ring0(container: Node3D) -> void:
		ring0_built = true
		var marker := Node3D.new()
		marker.name = "RuntimeRing0"
		container.add_child(marker)

	func activate_stream_chunk(id: StringName, container: Node3D) -> Node3D:
		var instance := Node3D.new()
		instance.name = "RuntimeActive_%s" % id
		container.add_child(instance)
		active[id] = instance
		return instance

	func deactivate_stream_chunk(id: StringName) -> void:
		var instance := active.get(id) as Node3D
		if is_instance_valid(instance):
			if instance.get_parent() != null:
				instance.get_parent().remove_child(instance)
			instance.free()
		active.erase(id)


var _failures: int = 0


## The pipeline instantiates scenes, which only works from inside the tree.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_generated_data_is_usable()
	_test_chunks_load_when_the_player_approaches()
	_test_hysteresis_keeps_a_boundary_chunk_loaded()
	_test_instantiation_budget_is_respected()
	_test_queued_loads_start_while_standing_still()
	_test_cold_cache_is_bounded()
	_test_prewarm_profile_activates_spawn_band_before_first_frame()
	_test_leaving_early_rolls_back_without_instantiating()
	_test_reset_clears_everything()
	_test_runtime_source_uses_same_state_machine()
	if _failures > 0:
		push_error("streaming: %d check(s) failed" % _failures)
		quit(1)
		return
	print("streaming: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("streaming: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_system() -> Dictionary:
	var container := Node3D.new()
	root.add_child(container)
	var player := Node3D.new()
	root.add_child(player)
	var system := StreamingSystem.new()
	root.add_child(system)
	system.initialize(container, player)
	return {"system": system, "container": container, "player": player}


func _dispose_rig(rig: Dictionary) -> void:
	(rig["system"] as StreamingSystem).reset()
	for key: String in ["system", "player", "container"]:
		_dispose(rig[key])


## Pumps until every load settles, with a bound so a stall fails rather than hangs.
## Loads run on a worker thread, so a burst of pumps with no wall time between
## them can finish before the thread does. Pump with real time between calls,
## up to a deadline, so the result depends on the code and not machine load.
func _settle(system: StreamingSystem, deadline_ms: int = SETTLE_DEADLINE_MS) -> void:
	var until: int = Time.get_ticks_msec() + deadline_ms
	var quiet: int = 0
	while Time.get_ticks_msec() < until:
		var before: String = str(system._states)
		system.pump()
		OS.delay_msec(1)
		quiet = quiet + 1 if str(system._states) == before else 0
		if quiet >= SETTLE_QUIET_PUMPS:
			return


func _first_chunk() -> ChunkData:
	var data := load(WORLD_DATA) as WorldData
	return data.get_streamable_chunks()[0]


func _test_generated_data_is_usable() -> void:
	var data := load(WORLD_DATA) as WorldData
	_check(data != null, "world_data.tres did not load as WorldData")
	if data == null:
		return
	var streamable: Array[ChunkData] = data.get_streamable_chunks()
	_check(streamable.size() >= 9, "expected at least 9 chunks, got %d" % streamable.size())

	var seen: Dictionary = {}
	for chunk: ChunkData in streamable:
		_check(chunk.id != &"", "a chunk has no id")
		_check(not seen.has(chunk.id), "duplicate chunk id '%s'" % chunk.id)
		seen[chunk.id] = true
		_check(chunk.radius > 0.0, "%s has a non-positive radius" % chunk.id)
		_check(
			ResourceLoader.exists(chunk.content_scene_path),
			"%s points at a missing scene: %s" % [chunk.id, chunk.content_scene_path]
		)
	_check(
		data.find_chunk(streamable[0].id) == streamable[0],
		"find_chunk did not return the chunk it was asked for"
	)
	_check(data.find_chunk(&"not_a_chunk") == null, "find_chunk invented a chunk")


func _test_chunks_load_when_the_player_approaches() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(Vector3(100000.0, 0.0, 100000.0))
	_settle(system)
	_check(
		system.get_active_chunks().is_empty(),
		"chunks were active with the player on the other side of the world"
	)

	system.scan(chunk.position)
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"standing on a chunk did not make it active (state %d)" % system.get_state(chunk.id)
	)
	_check(
		(rig["container"] as Node3D).get_child_count() > 1,
		"an active chunk put nothing into the stream container"
	)
	_dispose_rig(rig)


## Without the gap, a chunk on the boundary thrashes between states.
func _test_hysteresis_keeps_a_boundary_chunk_loaded() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"the rig chunk did not become active"
	)

	## Just past the load band, but inside the hysteresis gap.
	var just_outside: float = chunk.radius + system.load_margin_m + 10.0
	system.scan(chunk.position + Vector3(just_outside, 0.0, 0.0))
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"a chunk just past the load band unloaded; the hysteresis gap does nothing"
	)

	## Beyond the gap it must go.
	var far: float = chunk.radius + system.load_margin_m + system.unload_hysteresis_m + 50.0
	system.scan(chunk.position + Vector3(far, 0.0, 0.0))
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"a chunk past the unload band stayed loaded"
	)
	_dispose_rig(rig)


## instantiate() is what costs a frame, so the budget must actually bind.
func _test_instantiation_budget_is_respected() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	system.instantiation_budget_per_frame = 1

	## Sit at the island's centre of mass so several chunks qualify at once.
	var data := load(WORLD_DATA) as WorldData
	var centre: Vector3 = Vector3.ZERO
	for chunk: ChunkData in data.get_streamable_chunks():
		centre += chunk.position
	centre /= float(data.get_streamable_chunks().size())

	system.scan(centre)
	_settle(system)
	var ready_now: int = 0
	for chunk: ChunkData in data.get_streamable_chunks():
		if system.get_state(chunk.id) == StreamingSystem.CellState.READY:
			ready_now += 1

	var before: int = system.get_active_chunks().size()
	if ready_now > 0:
		system.pump()
		_check(
			system.get_active_chunks().size() - before <= 1,
			"one pump activated more than the budget of one chunk"
		)
	_check(before > 0, "sitting in the middle of the island activated nothing")
	_dispose_rig(rig)


## Loads beyond the concurrency limit must start as slots free up, not only after the player moves.
func _test_queued_loads_start_while_standing_still() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	system.max_concurrent_loads = 1
	var data := load(WORLD_DATA) as WorldData
	var centre: Vector3 = Vector3.ZERO
	for chunk: ChunkData in data.get_streamable_chunks():
		centre += chunk.position
	centre /= float(data.get_streamable_chunks().size())

	system.scan(centre)
	_settle(system)
	var in_band: int = 0
	var inactive: Array[StringName] = []
	for chunk: ChunkData in data.get_streamable_chunks():
		if Vector2(centre.x - chunk.position.x, centre.z - chunk.position.z).length() <= chunk.radius + system.load_margin_m:
			in_band += 1
			if system.get_state(chunk.id) != StreamingSystem.CellState.ACTIVE:
				inactive.append(chunk.id)
	_check(in_band >= 2, "the rig needs at least two chunks in the band, got %d" % in_band)
	_check(inactive.is_empty(), "standing still left chunks in the band inactive: %s" % [inactive])
	_dispose_rig(rig)


## Visiting chunk after chunk must not keep every packed scene alive.
func _test_cold_cache_is_bounded() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	system.cold_cache_limit = 1
	var data := load(WORLD_DATA) as WorldData
	for chunk: ChunkData in data.get_streamable_chunks():
		system.scan(chunk.position)
		_settle(system)
	system.scan(Vector3(100000.0, 0.0, 100000.0))
	_settle(system)
	_check(system.get_active_chunks().is_empty(), "chunks stayed active far away")
	_check(system._packed_cache.size() <= 1, "cold cache kept %d scenes over a limit of 1" % system._packed_cache.size())
	## A cold entry still serves the next approach without a reload.
	var last: ChunkData = data.get_streamable_chunks()[-1]
	system.scan(last.position)
	_settle(system)
	_check(system.get_state(last.id) == StreamingSystem.CellState.ACTIVE, "the last cold chunk did not come back")
	_dispose_rig(rig)


## With a prewarm profile the player must never fall before the content under the spawn exists.
func _test_prewarm_profile_activates_spawn_band_before_first_frame() -> void:
	var chunk: ChunkData = _first_chunk()
	var container := Node3D.new()
	root.add_child(container)
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = chunk.position
	var profile := WorldProfile.new()
	profile.world_data_path = WORLD_DATA
	profile.prewarm_before_first_frame = true
	var system := StreamingSystem.new()
	system.apply_world_profile(profile)
	root.add_child(system)
	system.initialize(container, player)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"prewarm left the spawn chunk %s (state %d) for later frames" % [chunk.id, system.get_state(chunk.id)]
	)
	system.reset()
	for node: Node in [system, player, container]:
		_dispose(node)


## Walking away mid-load must not leave an instance behind.
func _test_leaving_early_rolls_back_without_instantiating() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	var far: float = chunk.radius + system.load_margin_m + system.unload_hysteresis_m + 200.0
	system.scan(chunk.position + Vector3(far, 0.0, 0.0))
	_settle(system)

	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"a chunk left behind did not return to UNLOADED"
	)
	_check(
		not system.get_active_chunks().has(chunk.id),
		"a chunk the player walked away from was instantiated anyway"
	)
	_dispose_rig(rig)


func _test_reset_clears_everything() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	_settle(system)
	_check(not system.get_active_chunks().is_empty(), "nothing was active before reset")

	system.reset()
	_check(system.get_active_chunks().is_empty(), "reset left chunks active")
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"reset left a chunk in a loaded state"
	)
	_dispose_rig(rig)


func _test_runtime_source_uses_same_state_machine() -> void:
	var container := Node3D.new()
	root.add_child(container)
	var player := Node3D.new()
	root.add_child(player)
	var source := RuntimeSource.new()
	root.add_child(source)
	var system := StreamingSystem.new()
	root.add_child(system)

	var added: int = system.register_runtime_source(source)
	_check(added == 1, "runtime source did not register its chunk")
	system.initialize_runtime_only(container, player)
	_check(source.ring0_built, "runtime source Ring 0 was not built")
	_check(system.get_runtime_chunk_count() == 1, "runtime chunk count is wrong")

	system.scan(Vector3.ZERO)
	system.pump()
	_check(
		system.get_state(&"runtime_test") == StreamingSystem.CellState.ACTIVE,
		"runtime chunk did not reach ACTIVE"
	)
	_check(source.active.has(&"runtime_test"), "runtime source did not create active content")

	system.scan(Vector3(1000.0, 0.0, 1000.0))
	system.pump()
	_check(
		system.get_state(&"runtime_test") == StreamingSystem.CellState.UNLOADED,
		"runtime chunk did not unload after leaving its band"
	)
	_check(source.active.is_empty(), "runtime source kept active geometry after unload")

	system.reset()
	for node: Node in [system, source, player, container]:
		_dispose(node)

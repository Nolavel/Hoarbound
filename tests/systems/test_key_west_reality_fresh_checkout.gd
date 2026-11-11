extends SceneTree

## Zero-setup review: key_west_reality.tscn boots from the committed snapshot (no unpack or generation);
## Henry stands on the streamed chunk at the scene's chosen start (bunker, or 727 with spawn_at_shelter) and far
## meshes register. Not the rebuild check.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
const ROUTE_PATH: String = "res://data/world/key_west/reality/routes/first_exit_gate.json"
## How far from the start's landmark (bunker door, 727 entrance goal) Henry may wake.
const START_RADIUS_M: float = 12.0
const CHUNK_M: float = 512.0
const MAX_FRAMES: int = 1800
## Frames after the spawn chunk is active: collision registers, far meshes take a frame each.
const SETTLE_FRAMES: int = 90

var _failures: int = 0
var _world: Node3D
var _ctx: WorldContext
var _frames: int = 0
var _active_at: int = -1


class ErrorCounter:
	extends Logger
	var count: int = 0
	var samples: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array) -> void:
		if error_type == ERROR_TYPE_WARNING or file.contains("servers/rendering/dummy"):
			return
		count += 1
		if samples.size() < 10:
			samples.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])


var _log: ErrorCounter = ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_log)
	var data: WorldData = load(WORLD_DATA) as WorldData
	_check(data != null and data.chunks.size() > 400, "committed world_data.tres is missing or empty")
	if data != null:
		var missing: int = 0
		for chunk: ChunkData in data.chunks:
			missing += 0 if ResourceLoader.exists(chunk.content_scene_path) else 1
		_check(missing == 0, "%d chunk scenes named by world_data.tres are not in the checkout" % missing)
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _ctx == null:
		_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
		return false
	var player: Node3D = _ctx.player
	var streaming: StreamingSystem = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	var own: StringName = StringName("kw_gen_%d_%d" % [floori(player.global_position.x / CHUNK_M), floori(player.global_position.z / CHUNK_M)])
	var active: bool = streaming.get_state(own) == StreamingSystem.CellState.ACTIVE
	if active and _active_at < 0:
		_active_at = _frames
	if (not active and _frames < MAX_FRAMES) or (active and _frames - _active_at < SETTLE_FRAMES):
		return false
	_check(active, "chunk %s under the spawn never became active" % own)
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var feet: Vector3 = player.global_position
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(feet + Vector3.UP, feet + Vector3.DOWN * 4.0)
	q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	_check(not hit.is_empty() and feet.y - (hit["position"] as Vector3).y < 1.6, "Henry at %s has no ground under him" % feet)
	_check_start(Vector2(feet.x, feet.z))
	var far: int = 0
	for id: StringName in streaming.get_active_chunks():
		far += 1 if String(id).begins_with("kw_far_") else 0
	_check(far > 0, "no far-view meshes streamed in")
	## The dynamic snow reads the wind field baked from Reality's own buildings, not the legacy one.
	_check(SnowChunkCover.wind_field_path.ends_with("snow_wind_reality.png"), "chunk snow reads %s" % SnowChunkCover.wind_field_path)
	_check(_log.count == 0, "%d engine errors while booting: %s" % [_log.count, _log.samples])
	if _failures > 0:
		push_error("reality fresh checkout: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("reality fresh checkout: chunk %s active after %d frames, %d far meshes; all checks passed" % [own, _frames, far])
		quit(0)
	return true


## Henry wakes where the scene says: before the 727 door with spawn_at_shelter, else before the bunker.
func _check_start(feet: Vector2) -> void:
	if bool(_world.get(&"spawn_at_shelter")):
		var route: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))
		var entrance: Vector2 = Vector2.INF
		for goal: Dictionary in (route as Dictionary).get("goals", []) if route is Dictionary else []:
			if goal["name"] == "727_fort_st_entrance":
				entrance = Vector2(float(goal["xz"][0]), float(goal["xz"][1]))
		_check(entrance.distance_to(feet) < START_RADIUS_M, "Henry at %s does not wake in front of the 727 shelter" % feet)
		return
	var bunker: Node3D = _world.find_child("BunkerPortal", true, false) as Node3D
	_check(bunker != null and Vector2(bunker.global_position.x, bunker.global_position.z).distance_to(feet) < START_RADIUS_M,
		"Henry does not wake in front of the bunker")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("reality fresh checkout: %s" % message)

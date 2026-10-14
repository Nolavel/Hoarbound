extends SceneTree
## Review shots from the real key_west_reality.tscn: Henry moves to each spot, its chunk streams in, the game
## camera (free camera for far views) shoots. xvfb-run godot --script <this> -- <out_dir> [shot ...]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const SITES: String = "res://data/world/key_west/reality/overrides/first_exit_gameplay.json"
const CHUNK_M: float = 512.0
const SETTLE_FRAMES: int = 40
const MAX_WAIT_FRAMES: int = 600
const HENRY_HALF_HEIGHT: float = 1.0

## name, mode (game | free | plan), feet or eye [x, z(, y)], look [x, z(, y)]; plan uses 727 plan u/v.
const SHOTS: Array[Dictionary] = [
	{"name": "battery_start", "mode": "spawn_out"},
	{"name": "battery_door", "mode": "spawn_in"},
	{"name": "street_petronia", "mode": "game", "at": [-3163.0, 1363.0], "look": [-3115.0, 1331.0]},
	{"name": "residential_block", "mode": "game", "at": [-3385.0, 1513.0], "look": [-3340.0, 1480.0]},
	{"name": "vegetation_deep_snow", "mode": "game", "at": [-4121.0, 1723.0], "look": [-4128.0, 1715.0]},
	{"name": "coast_frozen_sea", "mode": "game", "at": [-4276.6, 1876.3], "look": [-4340.0, 1876.0]},
	{"name": "approach_727", "mode": "game", "at": [-3593.0, 1601.0], "look": [-3538.75, 1594.38]},
	{"name": "exterior_727", "mode": "game", "at": [-3545.0, 1606.0], "look": [-3530.0, 1583.0]},
	{"name": "interior_727", "mode": "plan", "at": [2.4, 3.0], "look": [-1.2, 6.4]},
	{"name": "winter_roofs_727", "mode": "free", "at": [-3478.0, 1640.0, 34.0], "look": [-3536.0, 1578.0, 6.0]},
	{"name": "winter_lee_eaves", "mode": "free", "at": [-3600.0, 1548.0, 13.0], "look": [-3548.0, 1572.0, 8.0]},
	{"name": "far_city_from_727", "mode": "free", "at": [-3530.0, 1583.0, 70.0], "look": [-4060.0, 1910.0, 0.0]},
	{"name": "far_island_from_fort", "mode": "free", "at": [-4060.0, 1930.0, 40.0], "look": [-3300.0, 1300.0, 0.0]},
]

var _out: String = ""
var _only: PackedStringArray = PackedStringArray()
var _world: Node3D
var _ctx: WorldContext
var _free: Camera3D
var _shot: int = -1
var _frames: int = 0
var _active_at: int = -1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0]
	_only = args.slice(1)
	DirAccess.make_dir_recursive_absolute(_out)
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	if _ctx == null:
		_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
		return false
	if _shot < 0 or _done_waiting():
		if _shot >= 0:
			_save(SHOTS[_shot]["name"])
		_shot = _next(_shot)
		if _shot >= SHOTS.size():
			quit(0)
			return true
		_place(SHOTS[_shot])
		_frames = 0
		_active_at = -1
	_frames += 1
	_aim(SHOTS[_shot])
	return false


func _next(i: int) -> int:
	i += 1
	while i < SHOTS.size() and not _only.is_empty() and not _only.has(SHOTS[i]["name"]):
		i += 1
	return i


func _done_waiting() -> bool:
	var p: Vector3 = _ctx.player.global_position
	var streaming: StreamingSystem = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	var own: StringName = StringName("kw_gen_%d_%d" % [floori(p.x / CHUNK_M), floori(p.z / CHUNK_M)])
	if _active_at < 0 and streaming.get_state(own) == StreamingSystem.CellState.ACTIVE:
		_active_at = _frames
		_place(SHOTS[_shot])  # heights are known once the chunk under Henry is in
	return (_active_at >= 0 and _frames - _active_at >= SETTLE_FRAMES) or _frames >= MAX_WAIT_FRAMES


func _place(shot: Dictionary) -> void:
	var player: CharacterBody3D = _ctx.player as CharacterBody3D
	var feet: Vector3 = _feet(shot)
	player.global_position = feet + Vector3.UP * HENRY_HALF_HEIGHT
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if _free != null:
		_free.queue_free()
		_free = null
	if shot["mode"] == "free":
		_free = Camera3D.new()
		_free.fov = 60.0
		_free.far = 4000.0
		root.add_child(_free)
		_free.make_current()
	else:
		_ctx.camera.make_current()
	print("capture set: %s at %s" % [shot["name"], feet])


func _aim(shot: Dictionary) -> void:
	var player: Node3D = _ctx.player
	var look: Vector3 = _look(shot)
	if shot["mode"] == "free":
		var at: Array = shot["at"]
		_free.look_at_from_position(Vector3(float(at[0]), float(at[2]), float(at[1])), look)
		return
	var to: Vector3 = look - player.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	_ctx.camera.call(&"set_look", atan2(-to.x, -to.z), -8.0)


func _feet(shot: Dictionary) -> Vector3:
	match String(shot["mode"]):
		"spawn_out", "spawn_in":
			var spawn: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(SITES)) as Dictionary)["spawn"]
			return Vector3(float(spawn["xz"][0]), float(spawn["y"]), float(spawn["xz"][1]))
		"plan":
			return _plan(shot["at"])
	var at: Array = shot["at"]
	return Vector3(float(at[0]), _ground(float(at[0]), float(at[1])), float(at[1]))


func _look(shot: Dictionary) -> Vector3:
	var sites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SITES))
	match String(shot["mode"]):
		"spawn_out":
			var door: Array = sites["bunker"]["door_xz"]
			var spawn: Array = sites["spawn"]["xz"]
			var out: Vector2 = (Vector2(float(spawn[0]), float(spawn[1])) - Vector2(float(door[0]), float(door[1]))).normalized()
			return _feet(shot) + Vector3(out.x, 0.0, out.y) * 30.0 + Vector3.UP * 1.5
		"spawn_in":
			var door2: Array = sites["bunker"]["door_xz"]
			return Vector3(float(door2[0]), float(sites["bunker"]["ground_y"]) + 1.6, float(door2[1]))
		"plan":
			return _plan(shot["look"]) + Vector3.UP * 0.8
		"free":
			var lf: Array = shot["look"]
			return Vector3(float(lf[0]), float(lf[2]), float(lf[1]))
	var l: Array = shot["look"]
	return Vector3(float(l[0]), _ground(float(l[0]), float(l[1])) + 1.2, float(l[1]))


func _plan(uv: Array) -> Vector3:
	var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
	var house: Node3D = shelter.get_node(^"House") as Node3D
	return house.to_global(shelter.plan_point(uv, float(shelter.interior["floor_y"])))


func _ground(x: float, z: float) -> float:
	var ground: Node = _world.find_child("RealityGround", true, false)
	return float(ground.get_height(x, z)) if ground is KeyWestRealityGround else 0.0


func _save(shot_name: String) -> void:
	var path: String = _out.path_join(shot_name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("capture set: ", path)

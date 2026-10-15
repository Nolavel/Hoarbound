extends SceneTree
## F6 teleport trace in the real Reality scene: per target, where Henry stands after the jump settles against the
## ground of the active chunk under him, and whether he is inside a building outline. Writes teleport_trace.json.
## godot --headless --path . --script tools/runtime/trace_dev_teleport.gd -- <out_dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const SETTLE_QUIET_FRAMES: int = 10
## Physics frames Henry gets after the jump before his place is judged.
const AFTER_FRAMES: int = 240
const MAX_WAIT_FRAMES: int = 6000
## Henry's feet (capsule bottom) may sit this far off the active ground; below it is a fall-through.
const GROUND_TOLERANCE_M: float = 0.6

var _out: String = "res://docs/runtime_previews/key_west_dev_teleport"
var _world: Node3D
var _ctx: WorldContext
var _streaming: StreamingSystem
var _ground: KeyWestRealityGround
var _waypoints: KeyWestDevWaypoints
var _index: RealityIndex = RealityIndex.new()
var _phase: String = "boot"
var _frames: int = 0
var _quiet: int = 0
var _target: int = 0
var _names: PackedStringArray = PackedStringArray()
var _rows: Array = []
var _failures: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_index.load_index()
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		"boot":
			_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
			if _ctx == null:
				return false
			_streaming = _ctx.get_system(STREAMING) as StreamingSystem
			_ground = _world.find_child("RealityGround", true, false) as KeyWestRealityGround
			_waypoints = _world.find_child("*DevWaypoints*", true, false) as KeyWestDevWaypoints
			if _waypoints == null:
				push_error("teleport trace: no KeyWestDevWaypoints in the scene")
				quit(1)
				return true
			_names = _waypoints.target_names()
			_phase = "settle"
			_frames = 0
		"settle":
			_quiet = 0 if _busy() else _quiet + 1
			if _quiet >= SETTLE_QUIET_FRAMES and _frames > 30:
				_jump()
		"after":
			if _waypoints.has_method(&"is_teleporting") and _waypoints.call(&"is_teleporting"):
				if _frames < MAX_WAIT_FRAMES:
					return false
			if _frames >= AFTER_FRAMES or _frames >= MAX_WAIT_FRAMES:
				_judge()
				_target += 1
				if _target >= _names.size():
					return _finish()
				_phase = "settle"
				_frames = 0
				_quiet = 0
	return false


func _jump() -> void:
	while _waypoints.current_target().get("name", "") != _names[_target]:
		_waypoints.next_target()
	_waypoints.teleport()
	_phase = "after"
	_frames = 0


func _judge() -> void:
	var p: Vector3 = _ctx.player.global_position
	var own: StringName = StringName("kw_gen_%d_%d" % [floori(p.x / 512.0), floori(p.z / 512.0)])
	var active: bool = _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE
	var ground_y: float = _ground.get_height(p.x, p.z)
	var shape: CollisionShape3D = _ctx.player.get_node(^"Main_Collision") as CollisionShape3D
	var feet: float = p.y + shape.position.y - (shape.shape as CapsuleShape3D).height * 0.5
	var inside: Dictionary = _index.pick(p.x, p.z)
	var row: Dictionary = {
		"target": _names[_target], "at": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"chunk": String(own), "chunk_active": active, "ground_y": snappedf(ground_y, 0.01),
		"feet_minus_ground": snappedf(feet - ground_y, 0.01), "on_floor": (_ctx.player as CharacterBody3D).is_on_floor(),
		"inside_building": String(inside.get("id", "")),
	}
	row["ok"] = active and absf(feet - ground_y) < GROUND_TOLERANCE_M and row["inside_building"] == ""
	if not row["ok"]:
		_failures += 1
	_rows.append(row)
	print("teleport trace: ", JSON.stringify(row))


func _finish() -> bool:
	var f: FileAccess = FileAccess.open(_out.path_join("teleport_trace.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"targets": _rows, "failures": _failures}, " ", true))
	print("teleport trace: %d of %d targets wrong" % [_failures, _rows.size()])
	quit(1 if _failures > 0 else 0)
	return true


func _busy() -> bool:
	for id: StringName in _streaming._transient:
		return true
	return false

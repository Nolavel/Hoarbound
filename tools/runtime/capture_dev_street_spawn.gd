extends SceneTree
## Boots the Reality scene with World.dev_spawn_street set, waits until Henry is set down and streaming is quiet,
## then saves a third-person frame and where he stands. Needs a renderer (lavapipe via tools/ci/render.sh setup).
## godot --path . --rendering-driver vulkan --script tools/runtime/capture_dev_street_spawn.gd -- <out_dir> <street> [...]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const QUIET_FRAMES: int = 30
## Frames Henry stands after landing before the shot, so camera and snow settle.
const AFTER_FRAMES: int = 90
const MAX_FRAMES: int = 9000

var _out: String = "res://docs/runtime_previews/dev_street_spawns"
var _streets: PackedInt32Array = PackedInt32Array()
var _world: World
var _phase: String = "boot"
var _frames: int = 0
var _quiet: int = 0
var _rows: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	for i: int in range(1, args.size()):
		_streets.append(int(args[i]))
	if _streets.is_empty():
		_streets.append(1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_boot()


func _process(_delta: float) -> bool:
	_frames += 1
	var ctx: WorldContext = _world.get_context()
	if ctx == null:
		return false
	var waypoints: KeyWestDevWaypoints = _world.find_child("*DevWaypoints*", true, false) as KeyWestDevWaypoints
	var streaming: StreamingSystem = ctx.get_system(STREAMING) as StreamingSystem
	var busy: bool = waypoints.is_teleporting() or not streaming._transient.is_empty()
	_quiet = 0 if busy else _quiet + 1
	if _quiet < QUIET_FRAMES + AFTER_FRAMES and _frames < MAX_FRAMES:
		return false
	_shoot(ctx)
	_streets.remove_at(0)
	if _streets.is_empty():
		var f: FileAccess = FileAccess.open(_out.path_join("dev_street_spawns.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(_rows, " ") + "\n")
		print("dev street capture: %d shot(s) in %s" % [_rows.size(), _out])
		return true
	_world.queue_free()
	_boot()
	return false


func _boot() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as World
	_world.dev_spawn_street = _streets[0]
	root.add_child(_world)
	_frames = 0
	_quiet = 0


func _shoot(ctx: WorldContext) -> void:
	var street: Dictionary = _world.dev_spawn()
	var ground: KeyWestRealityGround = _world.find_child("RealityGround", true, false) as KeyWestRealityGround
	var at: Vector3 = ctx.player.global_position
	var file: String = "street_%02d_%s.png" % [_streets[0], String(street["name"]).to_lower().replace(" ", "_")]
	root.get_texture().get_image().save_png(_out.path_join(file))
	var row: Dictionary = {"street": street["name"], "area": street["area"], "wanted": [street["at"].x, street["at"].y],
		"henry": [at.x, at.y, at.z], "ground_y": ground.get_height(at.x, at.z), "frames": _frames, "png": file}
	_rows.append(row)
	print("dev street capture: ", row)

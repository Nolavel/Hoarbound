extends SceneTree
## HLOD visual acceptance in the real Reality scene, calm weather: per camera the runtime frame (near detail, far
## proxies), the same frame with proxies tinted, and every cluster forced to detail; reports runtime vs all-detail.
## xvfb-run godot --script <this> -- <out_dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const HENRY_AT: Vector2 = Vector2(-2560.0, 1024.0)  # sector core
## name, eye [x, z, y], look [x, z, y] in local metres.
const CAMERAS: Array[Dictionary] = [
	{"name": "oblique", "eye": [-2200.0, 1420.0, 170.0], "look": [-2620.0, 930.0, 0.0]},
	{"name": "low_east", "eye": [-2560.0, 1024.0, 35.0], "look": [-2050.0, 900.0, 5.0]},
]
const SETTLE_QUIET_FRAMES: int = 10
const RENDER_FRAMES: int = 6
const TINT: Color = Color(1.0, 0.45, 0.1)

var _out: String = ""
var _world: Node3D
var _ctx: WorldContext
var _streaming: StreamingSystem
var _hlod: KeyWestRealityHLOD
var _camera: Camera3D
var _states: Dictionary = {}
var _frames: int = 0
var _quiet: int = 0
var _phase: String = "boot"
var _cam: int = 0
var _forced: Array[Node] = []
var _report: Dictionary = {}


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
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
			_streaming.cell_state_changed.connect(func(id: StringName, s: StreamingSystem.CellState) -> void: _states[id] = s)
			_hlod = _world.find_child("HLODView", true, false) as KeyWestRealityHLOD
			for system: Node in _ctx.systems:
				if system is WeatherController:
					(system as WeatherController).set_weather(&"calm", true)
			_camera = Camera3D.new()
			_camera.fov = 60.0
			_camera.far = 4000.0
			root.add_child(_camera)
			_camera.make_current()
			_place_henry()
			_phase = "settle"
			_frames = 0
		"settle":
			_aim()
			var busy: bool = _states.values().any(func(s: int) -> bool: return s in [1, 2, 3, 5])
			_quiet = 0 if busy else _quiet + 1
			if _quiet >= SETTLE_QUIET_FRAMES and _frames > 30:
				_place_henry()
				_phase = "runtime"
				_frames = 0
		"runtime":
			_aim()
			if _frames >= RENDER_FRAMES:
				_shot("runtime")
				_report["representations_" + String(CAMERAS[_cam]["name"])] = _reps()
				_tint(true)
				_phase = "tinted"
				_frames = 0
		"tinted":
			if _frames >= RENDER_FRAMES:
				_shot("tiers")
				_tint(false)
				_force_detail(true)
				_phase = "detail"
				_frames = 0
		"detail":
			if _frames >= RENDER_FRAMES:
				_shot("all_detail")
				_force_detail(false)
				_compare()
				_cam += 1
				if _cam >= CAMERAS.size():
					var f: FileAccess = FileAccess.open(_out.path_join("hlod_tiers.json"), FileAccess.WRITE)
					f.store_string(JSON.stringify(_report, " ", true))
					print("hlod tiers: done ", _report)
					quit(0)
					return true
				_phase = "runtime"
				_frames = 0
	return false


func _place_henry() -> void:
	var player: CharacterBody3D = _ctx.player as CharacterBody3D
	var ground: Node = _world.find_child("RealityGround", true, false)
	var y: float = float(ground.get_height(HENRY_AT.x, HENRY_AT.y)) if ground is KeyWestRealityGround else 0.0
	player.global_position = Vector3(HENRY_AT.x, y + 1.0, HENRY_AT.y)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _aim() -> void:
	var c: Dictionary = CAMERAS[_cam]
	_camera.look_at_from_position(Vector3(float(c["eye"][0]), float(c["eye"][2]), float(c["eye"][1])),
		Vector3(float(c["look"][0]), float(c["look"][2]), float(c["look"][1])))


func _name(kind: String) -> String:
	return "%s_%s" % [CAMERAS[_cam]["name"], kind]


func _shot(kind: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(_name(kind) + ".png"))
	print("hlod tiers: ", _name(kind))


func _tint(on: bool) -> void:
	var mat: StandardMaterial3D = null
	if on:
		mat = StandardMaterial3D.new()
		mat.albedo_color = TINT
	for proxy: Node in _hlod.get_children():
		if proxy is MeshInstance3D:
			(proxy as MeshInstance3D).material_override = mat


## Capture-only: every cluster showing its proxy gets its detail scene instead, as before HLOD.
func _force_detail(on: bool) -> void:
	if not on:
		for n: Node in _forced:
			n.queue_free()
		_forced.clear()
		for proxy: Node in _hlod.get_children():
			(proxy as Node3D).visible = true
		return
	for proxy: Node in _hlod.get_children():
		var cluster_id: String = String(proxy.get_meta("cluster_id", ""))
		var detail: Node3D = (load(KeyWestChunkGenerator.cluster_path_of(cluster_id)) as PackedScene).instantiate() as Node3D
		detail.position = KeyWestChunkBuilder.cluster_centre(cluster_id)
		_ctx.stream_container.add_child(detail)
		_forced.append(detail)
		(proxy as Node3D).visible = false


## Pixel difference of runtime vs all-detail: mean, and the share of pixels off by more than 10 %.
func _compare() -> void:
	var a: Image = Image.load_from_file(_out.path_join(_name("runtime") + ".png"))
	var b: Image = Image.load_from_file(_out.path_join(_name("all_detail") + ".png"))
	var total: float = 0.0
	var off: int = 0
	var diff: Image = Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d: float = (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			total += d
			if d > 0.1:
				off += 1
			diff.set_pixel(x, y, Color(minf(d * 4.0, 1.0), minf(d * 4.0, 1.0), minf(d * 4.0, 1.0)))
	diff.save_png(_out.path_join(_name("diff") + ".png"))
	var px: float = float(a.get_width() * a.get_height())
	_report[CAMERAS[_cam]["name"]] = {"mean_abs_diff": snappedf(total / px, 0.0001), "pixels_off_10pct": snappedf(off / px, 0.0001)}


func _reps() -> Dictionary:
	var reps: Dictionary = {}
	for cluster_id: String in _hlod.cluster_ids():
		var rep: String = _hlod.representation(cluster_id)
		reps[rep] = int(reps.get(rep, 0)) + 1
	return reps

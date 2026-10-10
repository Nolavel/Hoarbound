extends SceneTree
## Proof capture of generated Key West chunks along the First Exit corridor (lavapipe-friendly).
## godot --script tools/world/reality_gen/capture_key_west_route.gd -- <out_dir> [fly_frames] [island]

const CHUNK_DIR: String = "res://scenes/world/key_west/generated/chunks"
const START: Vector2 = Vector2(-4052.73, 1924.69)
const SHELTER: Vector2 = Vector2(-3531.78, 1590.28)
const MSL_Y: float = -0.265
const SETTLE_FRAMES: int = 3

var _out: String = ""
var _camera: Camera3D
var _shots: Array[Dictionary] = []
var _shot: int = 0
var _wait: int = 0
var _ready_frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/kw_route"
	var fly: int = int(args[1]) if args.size() > 1 else 60
	var island: bool = args.size() > 2 and args[2] == "island"
	DirAccess.make_dir_recursive_absolute(_out)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var dir: DirAccess = DirAccess.open(CHUNK_DIR)
	for file_name: String in dir.get_files():
		if file_name.ends_with(".scn"):
			world.add_child((load(CHUNK_DIR.path_join(file_name)) as PackedScene).instantiate())
	_environment(world, island)
	_highlight_landmarks(world)
	for anchor: Vector2 in [START, SHELTER]:
		var beacon: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.8
		cyl.bottom_radius = 0.8
		cyl.height = 60.0
		var bm: StandardMaterial3D = StandardMaterial3D.new()
		bm.albedo_color = Color(1.0, 0.85, 0.1)
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = bm
		beacon.mesh = cyl
		beacon.position = Vector3(anchor.x, 30.0, anchor.y)
		world.add_child(beacon)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 20000.0 if island else 6000.0
	world.add_child(_camera)
	_camera.current = true
	if island:
		_shots.append({"name": "island_overview", "eye": Vector3(-5200.0, 2600.0, 6200.0), "at": Vector3(-300.0, 0.0, -600.0)})
		_shots.append({"name": "island_old_town", "eye": Vector3(-3600.0, 380.0, 1900.0), "at": Vector3(-2500.0, 0.0, 700.0)})
		_shots.append({"name": "island_bridge_severed", "eye": Vector3(4900.0, 160.0, -1150.0), "at": Vector3(5400.0, 0.0, -1360.0)})
		_shots.append({"name": "island_northeast_added", "eye": Vector3(1500.0, 900.0, 600.0), "at": Vector3(3400.0, 0.0, -2600.0)})
		return
	var mid: Vector2 = (START + SHELTER) * 0.5
	_shots.append({"name": "overview_corridor", "eye": Vector3(mid.x - 420.0, 330.0, mid.y + 520.0), "at": Vector3(mid.x, 0.0, mid.y)})
	_shots.append({"name": "overview_start_battery", "eye": Vector3(START.x - 90.0, 70.0, START.y + 110.0), "at": Vector3(START.x, 2.0, START.y)})
	_shots.append({"name": "overview_shelter_727", "eye": Vector3(SHELTER.x - 70.0, 45.0, SHELTER.y + 80.0), "at": Vector3(SHELTER.x, 3.0, SHELTER.y)})
	_shots.append({"name": "topdown_shelter_727", "eye": Vector3(SHELTER.x, 160.0, SHELTER.y + 0.1), "at": Vector3(SHELTER.x, 0.0, SHELTER.y)})
	_shots.append({"name": "topdown_start_battery", "eye": Vector3(START.x, 220.0, START.y + 0.1), "at": Vector3(START.x, 0.0, START.y)})
	for i: int in range(fly):
		var t: float = float(i) / float(maxi(fly - 1, 1))
		var p: Vector2 = START.lerp(SHELTER, t)
		var ahead: Vector2 = START.lerp(SHELTER, minf(t + 0.18, 1.08))
		_shots.append({"name": "fly_%03d" % i, "eye": Vector3(p.x, 28.0, p.y), "at": Vector3(ahead.x, 2.0, ahead.y)})
	for k: int in range(5):
		var t2: float = float(k) / 4.0
		var q: Vector2 = START.lerp(SHELTER, t2 * 0.97)
		var look: Vector2 = START.lerp(SHELTER, minf(t2 * 0.97 + 0.08, 1.0))
		_shots.append({"name": "street_%d" % k, "eye": Vector3(q.x, -1.0, q.y), "at": Vector3(look.x, -1.0, look.y), "street": true})


## Landmark-role buildings (overrides) drawn in a flat signal colour for verification shots.
func _highlight_landmarks(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.has_meta("landmark_role"):
			var m: StandardMaterial3D = StandardMaterial3D.new()
			m.albedo_color = Color(0.95, 0.75, 0.10)
			(child as MeshInstance3D).material_override = m
		_highlight_landmarks(child)


func _environment(world: Node3D, island: bool) -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.66, 0.74, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.63, 0.68)
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color(0.70, 0.76, 0.83)
	e.fog_density = 0.00003 if island else 0.0006  # 7-9 km island views need thin haze
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	world.add_child(sun)
	var sea: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(24000.0, 24000.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.45, 0.55, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.material = mat
	sea.mesh = plane
	sea.position = Vector3(0.0, MSL_Y, 0.0)
	world.add_child(sea)


func _process(_delta: float) -> bool:
	_ready_frames += 1
	if _ready_frames < 4:
		return false
	if _shot >= _shots.size():
		print("capture_key_west_route: %d shots -> %s" % [_shots.size(), _out])
		return true
	var s: Dictionary = _shots[_shot]
	if _wait == 0:
		var eye: Vector3 = s["eye"]
		var at: Vector3 = s["at"]
		if s.get("street", false):
			eye.y = _ground(eye) + 1.7
			at.y = _ground(at) + 1.5
		_camera.look_at_from_position(eye, at)
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return false
	_wait = 0
	root.get_texture().get_image().save_png(_out.path_join("%s.png" % s["name"]))
	_shot += 1
	return false


func _ground(p: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.z), Vector3(p.x, -50.0, p.z)))
	return float(hit["position"].y) if not hit.is_empty() else 1.0

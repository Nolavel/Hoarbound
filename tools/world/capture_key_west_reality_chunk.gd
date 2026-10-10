extends SceneTree
## Renders a generated Reality Library chunk scene from an oblique camera (proof capture).
## Usage: godot --script tools/world/capture_key_west_reality_chunk.gd -- <chunk.scn> <out.png> <cx> <cz>

const FRAMES: int = 12

var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var packed: PackedScene = load(args[0]) as PackedScene
	_out = args[1]
	var centre: Vector3 = Vector3((float(args[2]) + 0.5) * 512.0, 0.0, (float(args[3]) + 0.5) * 512.0)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	world.add_child(packed.instantiate())
	var env: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(700.0, 700.0)
	ground.mesh = plane
	ground.position = centre + Vector3(0.0, 0.6, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.70, 0.62)
	plane.material = mat
	world.add_child(ground)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 50.0
	camera.far = 4000.0
	world.add_child(camera)
	camera.look_at_from_position(centre + Vector3(-260.0, 260.0, 330.0), centre + Vector3(0.0, 0.0, 0.0))
	camera.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	image.save_png(_out)
	print("capture_key_west_reality_chunk: wrote %s" % _out)
	return true

extends SceneTree

## Isolated A/B/C camera witness for shadow mass and edge controls.
## No production scene or shader global is changed by this experiment.

const SHADER := preload("res://shaders/experimental/shadow_reference_lab/controlled_shadow_mass.gdshader")
const FRAMES_PER_SHOT := 24
const FPS := 12
const ARMS := ["baseline", "mass", "mass_edge"]
const SHOTS := ["wide", "boundary", "warm_corner"]

var _arm := ""
var _out := ""
var _frame_dir := ""
var _world: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _warm: OmniLight3D
var _saved := 0
var _poses: Array[Dictionary] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ARMS.has(String(args[0])):
		push_error("SHADOW_STYLE: expected <baseline|mass|mass_edge> <res://output>")
		quit(2)
		return
	_arm = String(args[0])
	_out = String(args[1])
	_frame_dir = _out.path_join("frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_frame_dir))
	call_deferred("_run")


func _run() -> void:
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_interior_mode", 0.0)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_brush_mix", 1.0)
	_build_scene()
	await _wait_frames(16)
	for shot in range(SHOTS.size()):
		_aim_camera(shot)
		await _wait_frames(8)
		await RenderingServer.frame_post_draw
		var pose := {
			"shot": SHOTS[shot],
			"camera": str(_camera.global_transform),
			"sun": str(_sun.global_transform),
			"sun_energy": _sun.light_energy,
			"warm": str(_warm.global_transform),
			"warm_energy": _warm.light_energy,
		}
		_poses.append(pose)
		for frame in range(FRAMES_PER_SHOT):
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_viewport().get_texture().get_image()
			if not _save(image, _frame_dir.path_join("frame_%04d.png" % _saved)):
				return
			if frame == 12:
				if not _save(image, _out.path_join("%s.png" % SHOTS[shot])):
					return
			_saved += 1

	_write_report()
	if _saved != SHOTS.size() * FRAMES_PER_SHOT:
		_fail("frame count %d" % _saved)
		return
	print("SHADOW_STYLE pass arm=%s frames=%d driver=%s" % [
		_arm, _saved, RenderingServer.get_current_rendering_driver_name()])
	quit(0)


func _build_scene() -> void:
	RenderingServer.set_default_clear_color(Color(0.47, 0.57, 0.63))
	_world = Node3D.new()
	_world.name = "ShadowStyleWitness"
	root.add_child(_world)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.47, 0.57, 0.63)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.40, 0.49, 0.54)
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_world.add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, -37.0, 0.0)
	_sun.light_color = Color(0.79, 0.89, 1.0)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	_sun.shadow_blur = 2.0
	_sun.directional_shadow_max_distance = 30.0
	_world.add_child(_sun)

	_warm = OmniLight3D.new()
	_warm.position = Vector3(2.8, 2.1, -2.6)
	_warm.light_color = Color(1.0, 0.64, 0.35)
	_warm.light_energy = 0.60
	_warm.omni_range = 4.0
	_warm.shadow_enabled = true
	_world.add_child(_warm)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12.0, 10.0)
	_add_mesh("Floor", floor_mesh, Vector3.ZERO,
		Color(0.83, 0.86, 0.86), Color(0.21, 0.30, 0.38))
	_add_box("BackWallLeft", Vector3(-3.4, 1.6, -3.9), Vector3(5.2, 3.2, 0.25),
		Color(0.74, 0.69, 0.63), Color(0.29, 0.29, 0.34))
	_add_box("BackWallRight", Vector3(3.3, 1.6, -3.9), Vector3(3.0, 3.2, 0.25),
		Color(0.74, 0.69, 0.63), Color(0.29, 0.29, 0.34))
	_add_box("ShadowCaster", Vector3(-1.65, 1.2, 0.10), Vector3(1.8, 2.4, 1.2),
		Color(0.44, 0.52, 0.56), Color(0.16, 0.26, 0.34))
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.55
	cylinder.bottom_radius = 0.55
	cylinder.height = 2.4
	_add_mesh("RoundCaster", cylinder, Vector3(1.3, 1.2, 0.7),
		Color(0.52, 0.60, 0.65), Color(0.17, 0.27, 0.36))
	_add_box("WarmStep", Vector3(2.65, 0.22, -1.70), Vector3(2.2, 0.44, 1.15),
		Color(0.52, 0.44, 0.37), Color(0.23, 0.24, 0.27))

	_camera = Camera3D.new()
	_camera.fov = 48.0
	_world.add_child(_camera)
	_camera.current = true


func _material(surface: Color, pigment: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("surface_color", Vector3(surface.r, surface.g, surface.b))
	material.set_shader_parameter("shadow_pigment", Vector3(pigment.r, pigment.g, pigment.b))
	material.set_shader_parameter("mass_strength", 0.0 if _arm == "baseline" else 1.0)
	material.set_shader_parameter("edge_strength", 1.0 if _arm == "mass_edge" else 0.0)
	return material


func _add_mesh(name: String, mesh: Mesh, at: Vector3, surface: Color, pigment: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = at
	node.material_override = _material(surface, pigment)
	_world.add_child(node)


func _add_box(name: String, at: Vector3, size: Vector3, surface: Color, pigment: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(name, mesh, at, surface, pigment)


func _aim_camera(shot: int) -> void:
	match shot:
		0:
			_camera.fov = 48.0
			_camera.look_at_from_position(Vector3(7.2, 5.1, 8.4),
				Vector3(0.0, 0.75, -1.0), Vector3.UP)
		1:
			_camera.fov = 46.0
			_camera.look_at_from_position(Vector3(2.9, 2.3, 4.5),
				Vector3(-0.8, 0.45, -0.2), Vector3.UP)
		2:
			_camera.fov = 52.0
			_camera.look_at_from_position(Vector3(4.4, 3.3, 1.2),
				Vector3(1.9, 0.65, -2.5), Vector3.UP)


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _save(image: Image, path: String) -> bool:
	var error := image.save_png(path)
	if error != OK:
		_fail("cannot save %s (%d)" % [path, error])
		return false
	return true


func _write_report() -> void:
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write report")
		return
	file.store_string(JSON.stringify({
		"experiment": "independent shadow colour mass and edge controls",
		"arm": _arm,
		"production_path_modified": false,
		"mass_strength": 0.0 if _arm == "baseline" else 1.0,
		"edge_strength": 1.0 if _arm == "mass_edge" else 0.0,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"camera_poses": _poses,
		"shots": SHOTS,
		"frames_per_shot": FRAMES_PER_SHOT,
		"frames": _saved,
		"fps": FPS,
	}, "\t"))


func _fail(message: String) -> void:
	push_error("SHADOW_STYLE fail: %s" % message)
	quit(1)

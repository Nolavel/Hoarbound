extends SceneTree
## Tree snow check: a palm and a bare winter tree (WinterTreeMeshes) at snow cover 0, 0.5 and 1, one frame each.
## xvfb-run godot --path . --rendering-driver vulkan --script tools/runtime/capture_tree_snow.gd -- <out_dir>

const COVERS: Array[float] = [0.0, 0.5, 1.0]

var _out: String = ""
var _frame: int = 0
var _shot: int = 0


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	ground.material_override = StylizedEnvironmentMaterial.make(Color(0.85, 0.87, 0.9), 0.9)
	root.add_child(ground)
	var mats: Dictionary = WinterTreeMeshes.materials()
	var palm := MeshInstance3D.new()
	palm.mesh = WinterTreeMeshes.palm(mats)
	palm.position = Vector3(-3.0, 0.0, 0.0)
	root.add_child(palm)
	var bare := MeshInstance3D.new()
	bare.mesh = WinterTreeMeshes.bare_tree(mats)
	bare.position = Vector3(3.5, 0.0, 0.0)
	bare.scale = Vector3.ONE * 1.4
	root.add_child(bare)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 6.5, 15.0), Vector3(0.0, 4.5, 0.0))
	cam.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 6 == 1:
		RenderingServer.global_shader_parameter_set(&"snow_cover", COVERS[_shot])
		RenderingServer.global_shader_parameter_set(&"frost_amount", COVERS[_shot] * 0.6)
		RenderingServer.global_shader_parameter_set(&"snow_wind", Vector2(1.0, 0.0))  # wind from the camera's left
	if _frame % 6 == 5:
		root.get_texture().get_image().save_png(_out.path_join("tree_snow_%d.png" % int(COVERS[_shot] * 100.0)))
		_shot += 1
		if _shot >= COVERS.size():
			print("tree snow capture: done")
			quit(0)
			return true
	return false

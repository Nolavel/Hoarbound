extends Node3D

## Single deterministic control. Disable autoplay to scrub this in the Inspector.
@export_range(0.0,1.0) var burn_progress: float = 0.0
@export var autoplay: bool = true
var frame: int = 0
var wood: ShaderMaterial
var flame_materials: Array[ShaderMaterial] = []
var fire_light: OmniLight3D

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--progress="):
			burn_progress = clampf(float(arg.split("=")[1]),0.0,1.0)
			autoplay = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018,0.026,0.042)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38,0.46,0.62)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(3.4,2.5,6.2)
	camera.look_at(Vector3(0,0.9,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48,-30,0)
	key.light_color = Color(0.82,0.86,1)
	key.light_energy = 1.35
	key.shadow_enabled = true
	add_child(key)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.045,0.057,0.075)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var log_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.38
	cylinder.bottom_radius = 0.41
	cylinder.height = 3.2
	cylinder.radial_segments = 32
	cylinder.rings = 12
	log_mesh.mesh = cylinder
	log_mesh.rotation.z = -PI/2.0
	log_mesh.position.y = 0.45
	wood = ShaderMaterial.new()
	wood.shader = load("res://wood.gdshader")
	log_mesh.material_override = wood
	add_child(log_mesh)
	# Tongues share the wood's arrival field; no second burn simulation.
	for i in range(11):
		var x := -1.4+float(i)*0.25
		var root := Vector3(x,0.77,0.23)
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var height := 0.95+0.28*sin(float(i)*2.7)
		quad.size = Vector2(0.47,height)
		flame.mesh = quad
		flame.position = root+Vector3(0,height/2.0,0)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://flame.gdshader")
		mat.set_shader_parameter("seed",float(i)*3.17)
		mat.set_shader_parameter("root_position",root)
		flame.material_override = mat
		flame_materials.append(mat)
		add_child(flame)
	fire_light = OmniLight3D.new()
	fire_light.position = Vector3(-0.5,1.0,0.7)
	fire_light.light_color = Color(1.0,0.36,0.055)
	fire_light.omni_range = 3.0
	add_child(fire_light)
	apply_progress()

func _process(_delta: float) -> void:
	if autoplay:
		burn_progress = minf(float(frame)/299.0,1.0)
		frame += 1
	apply_progress()

func apply_progress() -> void:
	wood.set_shader_parameter("burn_progress",burn_progress)
	for mat in flame_materials:
		mat.set_shader_parameter("burn_progress",burn_progress)
	fire_light.light_energy = smoothstep(0.03,0.23,burn_progress)*(1.0-smoothstep(0.62,0.9,burn_progress))*0.65

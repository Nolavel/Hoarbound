extends SceneTree

## Shadow style review: one lab (sun, receiver plane, four casters, one camera) rendered with
## the production stylized shadow outdoors and indoors, and with each of Codex's shadow-lab
## candidates (`codex` branch, shaders/experimental/shadow_reference_lab). Writes a contact sheet.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_shadow_style_sheet.gd -- <out dir> <lab shader dir>

const SETTLE_FRAMES: int = 10
const CELL := Vector2i(640, 400)
const COLUMNS: int = 4
const RECEIVER_COLOR := Color(0.84, 0.87, 0.88)
## [id, label, lab shader file or "" , {uniform: value}]; "prod_*" use the production material.
const VARIANTS: Array = [
	["00_physical", "Physical (stock Godot)", "", {}],
	["01_prod_outdoor", "IN GAME: outdoor (dry brush)", "prod", {"interior": 0.0}],
	["02_prod_indoor", "IN GAME: indoor (torn islands)", "prod", {"interior": 1.0}],
	["03_flat_wash", "Codex: flat wash", "flat_wash.gdshader", {}],
	["04_toon_warble", "Codex: toon warble", "toon_warble.gdshader", {}],
	["05_fuzzy_painterly", "Codex: fuzzy painterly", "fuzzy_painterly.gdshader", {}],
	["06_watercolour_pool", "Codex: watercolour pool", "watercolour_pool.gdshader", {}],
	["07_ink_hatch", "Codex: ink hatch", "ink_hatch.gdshader", {}],
	["08_pigment_mass", "Codex: pigment mass", "pigment_mass.gdshader", {}],
	["09_controlled_mass", "Codex: controlled mass", "controlled_shadow_mass.gdshader", {"mass_strength": 1.0, "edge_strength": 0.0}],
	["10_controlled_mass_edge", "Codex: mass + edge", "controlled_shadow_mass.gdshader", {"mass_strength": 1.0, "edge_strength": 1.0}],
]

var _out: String = "user://shots/shadow_style_sheet"
var _lab_dir: String = "res://shaders/experimental/shadow_reference_lab"
var _receiver: MeshInstance3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_lab_dir = args[1]
	DirAccess.make_dir_recursive_absolute(_abs(_out))
	_run()


func _run() -> void:
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_brush_mix", 1.0)
	_build_lab()
	await _frames(SETTLE_FRAMES)
	var images: Array[Image] = []
	for variant: Array in VARIANTS:
		var material: Material = _material(variant)
		if material == null:
			push_error("shadow sheet: no material for %s" % variant[0])
			quit(1)
			return
		_receiver.material_override = material
		await _frames(SETTLE_FRAMES)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		image.save_png(_abs(_out).path_join(String(variant[0]) + ".png"))
		images.append(image)
		print("[shadow] ", variant[0])
	_sheet(images)
	print("[shadow] done")
	quit(0)


func _material(variant: Array) -> Material:
	var source: String = variant[2]
	var params: Dictionary = variant[3]
	if source == "":
		var physical := StandardMaterial3D.new()
		physical.albedo_color = RECEIVER_COLOR
		physical.roughness = 1.0
		return physical
	if source == "prod":
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_interior_mode", float(params["interior"]))
		return StylizedEnvironmentMaterial.make_static(RECEIVER_COLOR, 1.0)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_interior_mode", 0.0)
	var path: String = _lab_dir.path_join(source)
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(path if path.begins_with("res://") else _abs(path))
	if shader.code.is_empty():
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in params:
		material.set_shader_parameter(StringName(key), params[key])
	return material


func _build_lab() -> void:
	RenderingServer.set_default_clear_color(Color(0.72, 0.78, 0.82))
	var world := Node3D.new()
	root.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.78, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.50)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 2.2
	sun.directional_shadow_max_distance = 30.0
	world.add_child(sun)
	_receiver = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 10.0)
	_receiver.mesh = plane
	world.add_child(_receiver)
	_caster(world, BoxMesh.new(), Vector3(-2.35, 1.15, -0.55), Vector3(1.65, 2.30, 1.65), Color(0.45, 0.50, 0.52))
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.78
	cylinder.bottom_radius = 0.78
	cylinder.height = 3.10
	_caster(world, cylinder, Vector3(0.35, 1.55, -0.35), Vector3.ONE, Color(0.34, 0.40, 0.43))
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.52
	capsule.height = 2.55
	_caster(world, capsule, Vector3(2.35, 1.28, 0.40), Vector3.ONE, Color(0.50, 0.43, 0.38))
	_caster(world, BoxMesh.new(), Vector3(1.95, 0.22, 2.35), Vector3(2.20, 0.44, 1.15), Color(0.38, 0.44, 0.46))
	var camera := Camera3D.new()
	camera.fov = 38.0
	world.add_child(camera)
	## Close on the penumbrae of the capsule and the low box, where the styles differ.
	camera.look_at_from_position(Vector3(5.2, 3.0, 5.6), Vector3(1.7, 0.0, 0.9))
	camera.current = true


func _caster(world: Node3D, mesh: PrimitiveMesh, at: Vector3, size: Vector3, colour: Color) -> void:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	node.material_override = mat
	world.add_child(node)


func _sheet(images: Array[Image]) -> void:
	var rows: int = ceili(float(images.size()) / COLUMNS)
	var sheet := Image.create(CELL.x * COLUMNS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i: int in range(images.size()):
		var cell: Image = images[i].duplicate()
		cell.convert(Image.FORMAT_RGBA8)
		cell.resize(CELL.x, CELL.y)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % COLUMNS) * CELL.x, (i / COLUMNS) * CELL.y))
	sheet.save_png(_abs(_out).path_join("sheet.png"))


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path

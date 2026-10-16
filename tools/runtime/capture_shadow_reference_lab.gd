extends SceneTree

## Isolated visual reference lab for comparing shadow-language families under one
## camera/light/geometry setup. This does not touch the production shadow include.

const OUT := "res://docs/runtime_previews/stylized_shadows"
const SETTLE_FRAMES := 8
const CONTACT_CELL := Vector2i(600, 400)
const CONTACT_GAP := 8

const VARIANTS := [
	{
		"id": "00_physical",
		"label": "Physical / stock Godot",
		"shader": "",
		"source": "control",
	},
	{
		"id": "01_flat_wash",
		"label": "Flat coloured shadow wash",
		"shader": "res://shaders/experimental/shadow_reference_lab/flat_wash.gdshader",
		"source": "Godot simple shadow-catcher family (ATTENUATION as an artistic mask)",
	},
	{
		"id": "02_toon_warble",
		"label": "Toon warble",
		"shader": "res://shaders/experimental/shadow_reference_lab/toon_warble.gdshader",
		"source": "BoTW/toon warbly-shadow family; clean-room stock-Godot adaptation",
	},
	{
		"id": "03_fuzzy_painterly",
		"label": "Fuzzy painterly border",
		"shader": "res://shaders/experimental/shadow_reference_lab/fuzzy_painterly.gdshader",
		"source": "Painterly border-band family; clean-room adaptation of the public concept",
	},
	{
		"id": "04_watercolour_pool",
		"label": "Watercolour pooling",
		"shader": "res://shaders/experimental/shadow_reference_lab/watercolour_pool.gdshader",
		"source": "Watercolour/NPR wash family: broad wash plus darker pigment rim",
	},
	{
		"id": "05_ink_hatch",
		"label": "Ink cross-hatch",
		"shader": "res://shaders/experimental/shadow_reference_lab/ink_hatch.gdshader",
		"source": "Classic NPR hatching family, world-space and shadow-density driven",
	},
]

var _world: Node3D
var _receiver: MeshInstance3D
var _physical_material: StandardMaterial3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run()


func _run() -> void:
	_build_lab()
	await _wait_frames(SETTLE_FRAMES)

	var captured: Array[String] = []
	var images: Array[Image] = []
	for variant: Dictionary in VARIANTS:
		var id := String(variant["id"])
		var shader_path := String(variant["shader"])
		if shader_path.is_empty():
			_receiver.material_override = _physical_material
		else:
			var shader := load(shader_path) as Shader
			if shader == null:
				_fail("cannot load shader %s" % shader_path)
				return
			var material := ShaderMaterial.new()
			material.shader = shader
			_receiver.material_override = material

		await _wait_frames(SETTLE_FRAMES)
		await RenderingServer.frame_post_draw
		var path := OUT.path_join(id + ".png")
		var image := root.get_viewport().get_texture().get_image()
		var err := image.save_png(path)
		if err != OK:
			_fail("save failed %s (%d)" % [path, err])
			return
		captured.append(path)
		images.append(image.duplicate())
		print("SHADOW_REFERENCE_LAB captured %s" % id)

	if not _write_contact_sheet(images):
		return
	_write_report(captured)
	print("SHADOW_REFERENCE_LAB pass variants=%d driver=%s" % [
		captured.size(),
		RenderingServer.get_current_rendering_driver_name(),
	])
	quit(0)


func _build_lab() -> void:
	RenderingServer.set_default_clear_color(Color(0.72, 0.78, 0.82))
	_world = Node3D.new()
	_world.name = "ShadowReferenceLab"
	root.add_child(_world)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.72, 0.78, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.46, 0.50)
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	_world.add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "ReferenceSun"
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 2.2
	sun.directional_shadow_max_distance = 30.0
	_world.add_child(sun)

	_receiver = MeshInstance3D.new()
	_receiver.name = "Receiver"
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 10.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	_receiver.mesh = plane
	_world.add_child(_receiver)

	_physical_material = StandardMaterial3D.new()
	_physical_material.albedo_color = Color(0.84, 0.87, 0.88)
	_physical_material.roughness = 1.0
	_physical_material.metallic = 0.0
	_receiver.material_override = _physical_material

	_add_box(Vector3(-2.35, 1.15, -0.55), Vector3(1.65, 2.30, 1.65), Color(0.45, 0.50, 0.52))
	_add_cylinder(Vector3(0.35, 1.55, -0.35), 0.78, 3.10, Color(0.34, 0.40, 0.43))
	_add_capsule(Vector3(2.35, 1.28, 0.40), 0.52, 2.55, Color(0.50, 0.43, 0.38))
	_add_box(Vector3(1.95, 0.22, 2.35), Vector3(2.20, 0.44, 1.15), Color(0.38, 0.44, 0.46))

	var camera := Camera3D.new()
	camera.name = "ReferenceCamera"
	camera.fov = 44.0
	_world.add_child(camera)
	camera.look_at_from_position(Vector3(8.8, 6.7, 10.6), Vector3(0.0, 0.45, 0.25), Vector3.UP)
	camera.current = true


func _matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	return material


func _add_box(position: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = _matte(color)
	_world.add_child(node)


func _add_cylinder(position: Vector3, radius: float, height: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = position
	node.material_override = _matte(color)
	_world.add_child(node)


func _add_capsule(position: Vector3, radius: float, height: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = position
	node.material_override = _matte(color)
	_world.add_child(node)


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _write_contact_sheet(images: Array[Image]) -> bool:
	if images.size() != VARIANTS.size():
		_fail("contact sheet image count mismatch")
		return false
	var width := CONTACT_CELL.x * 3 + CONTACT_GAP * 4
	var height := CONTACT_CELL.y * 2 + CONTACT_GAP * 3
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.09, 1.0))
	for i in range(images.size()):
		var tile := images[i].duplicate()
		tile.resize(CONTACT_CELL.x, CONTACT_CELL.y, Image.INTERPOLATE_LANCZOS)
		tile.convert(Image.FORMAT_RGBA8)
		var col := i % 3
		var row := i / 3
		var at := Vector2i(CONTACT_GAP + col * (CONTACT_CELL.x + CONTACT_GAP), CONTACT_GAP + row * (CONTACT_CELL.y + CONTACT_GAP))
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, CONTACT_CELL), at)
	var err := sheet.save_png(OUT.path_join("contact_sheet_3x2.png"))
	if err != OK:
		_fail("contact sheet save failed (%d)" % err)
		return false
	return true


func _write_report(captured: Array[String]) -> void:
	var variants: Array[Dictionary] = []
	for variant: Dictionary in VARIANTS:
		variants.append({
			"id": String(variant["id"]),
			"label": String(variant["label"]),
			"shader": String(variant["shader"]),
			"source_family": String(variant["source"]),
		})
	var report := {
		"diagnostic": "isolated shadow reference lab",
		"production_path_modified": false,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"contact_sheet_order": ["00_physical", "01_flat_wash", "02_toon_warble", "03_fuzzy_painterly", "04_watercolour_pool", "05_ink_hatch"],
		"variants": variants,
		"captured": captured,
		"notes": [
			"All variants use the same camera, sun, caster geometry and physical shadow map.",
			"External projects are used as visual/technical references only; no third-party textures or source code are copied.",
			"The lab is for author selection, not production acceptance or performance measurement.",
		],
	}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _fail(message: String) -> void:
	push_error("SHADOW_REFERENCE_LAB fail: %s" % message)
	quit(1)

extends SceneTree

## Stage 5 Key West proof for issue #138 — final EYW verification run:
## NOAA terrain + ocean-connected ice + chunk-aware OSM city + airport block.
## No Blender edits and no production First Exit migration.
const HEIGHT_IMAGE: String = "res://world/terrain/key_west_preview_2m_la8.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"
const OCEAN_MASK: String = "res://docs/runtime_previews/key_west/ocean_connected_mask.png"
const CITY_JSON: String = "res://docs/runtime_previews/key_west/city_preview.json"
const OUT_DIR: String = "res://docs/runtime_previews/key_west"
const WARMUP_FRAMES: int = 100
const BETWEEN_SHOTS_FRAMES: int = 42
const SHOT_NAMES: Array[String] = [
	"01_cluster_top",
	"02_key_west_top",
	"03_chunk_debug",
	"04_city_metadata",
	"05_airport_top",
	"06_airport_oblique",
	"07_street_scale",
]

var _frame: int = 0
var _shot: int = -1
var _next_capture_frame: int = WARMUP_FRAMES
var _camera: Camera3D
var _terrain: IslandTerrain
var _city: ChunkedCityMassing
var _meta: Dictionary
var _centre: Vector3
var _span_x: float = 1.0
var _span_z: float = 1.0
var _dense_focus: Vector2
var _airport_focus: Vector2
var _overlay: Label
var _city_ready: bool = false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var parsed_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(HEIGHT_META))
	if typeof(parsed_meta) != TYPE_DICTIONARY:
		push_error("key west capture: missing metadata")
		quit(1)
		return
	_meta = parsed_meta as Dictionary
	_span_x = float(_meta["width"] - 1) * float(_meta["m_per_px"])
	_span_z = float(_meta["height"] - 1) * float(_meta["m_per_px"])
	_centre = Vector3(
		float(_meta["origin_x"]) + _span_x * 0.5,
		0.0,
		float(_meta["origin_z"]) + _span_z * 0.5
	)
	_build_stage()
	_add_overlay()


func _process(_delta: float) -> bool:
	_frame += 1
	if not _city_ready and _frame >= 3:
		_city = ChunkedCityMassing.new()
		_city.name = "ChunkedCity"
		root.add_child(_city)
		if not _city.configure(_terrain, CITY_JSON):
			quit(1)
			return true
		_dense_focus = _city.get_densest_chunk_center()
		_airport_focus = _city.get_airport_center()
		_city_ready = true
		print(
			"key west stage5: dense_focus=%s airport_focus=%s stats=%s" %
			[_dense_focus, _airport_focus, _city.get_stats()]
		)

	if not _city_ready or _frame < WARMUP_FRAMES:
		return false
	if _frame < _next_capture_frame:
		return false
	if _shot >= 0:
		_capture()
	_shot += 1
	if _shot >= SHOT_NAMES.size():
		print("key west stage5 capture: complete")
		quit()
		return true
	_apply_shot(_shot)
	_next_capture_frame = _frame + BETWEEN_SHOTS_FRAMES
	return false


func _build_stage() -> void:
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.far = 30000.0
	_camera.near = 0.25
	root.add_child(_camera)
	_camera.make_current()

	_terrain = IslandTerrain.new()
	_terrain.name = "KeyWestTerrain"
	_terrain.heightmap_image_path = HEIGHT_IMAGE
	_terrain.heightmap_meta_path = HEIGHT_META
	_terrain.min_visible_height_m = -6.0
	_terrain.collision_radius_m = -100000.0
	_terrain.builds_per_frame = 24
	root.add_child(_terrain)

	_build_masked_ice()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12000.0
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.64, 0.67, 0.70)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.83, 0.85, 0.88)
	env.ambient_light_energy = 0.76
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	_snowify_terrain()


func _build_masked_ice() -> void:
	var mask_image: Image = Image.load_from_file(OCEAN_MASK)
	if mask_image == null or mask_image.is_empty():
		push_error("key west capture: missing ocean mask")
		return
	var mask_texture := ImageTexture.create_from_image(mask_image)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D ocean_mask : filter_nearest, repeat_disable;
uniform vec2 world_origin;
uniform vec2 world_size;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - world_origin) / world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	float ocean = texture(ocean_mask, uv).r;
	if (ocean < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.50, 0.57, 0.64);
	ROUGHNESS = 0.37;
	METALLIC = 0.05;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ocean_mask", mask_texture)
	material.set_shader_parameter(
		"world_origin",
		Vector2(float(_meta["origin_x"]), float(_meta["origin_z"]))
	)
	material.set_shader_parameter("world_size", Vector2(_span_x, _span_z))

	var ice := MeshInstance3D.new()
	ice.name = "FrozenSea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_span_x, _span_z)
	plane.material = material
	ice.mesh = plane
	ice.position = _centre + Vector3(0.0, -0.04, 0.0)
	root.add_child(ice)


func _add_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	_overlay = Label.new()
	_overlay.position = Vector2(18.0, 18.0)
	_overlay.add_theme_font_size_override("font_size", 17)
	_overlay.add_theme_color_override("font_color", Color(0.96, 0.96, 0.97))
	_overlay.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.03, 0.85))
	_overlay.add_theme_constant_override("shadow_offset_x", 2)
	_overlay.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_overlay)

	var attribution := Label.new()
	attribution.text = "NOAA terrain  •  Map data © OpenStreetMap contributors — ODbL"
	attribution.position = Vector2(18.0, 968.0)
	attribution.add_theme_font_size_override("font_size", 13)
	attribution.modulate = Color(0.95, 0.95, 0.95, 0.88)
	canvas.add_child(attribution)
	root.add_child(canvas)


func _set_overlay(title: String, extra: String = "") -> void:
	var stats: Dictionary = _city.get_stats() if _city != null else {}
	var airport: Dictionary = _city.get_airport_metadata() if _city != null else {}
	var airport_name: String = String(airport.get("name", "Key West airport"))
	var airport_codes: String = "%s / %s" % [
		String(airport.get("iata", "")),
		String(airport.get("icao", "")),
	]
	_overlay.text = (
		"%s\n"
		+ "chunks %s  |  buildings %s  |  roads %s  |  airport features %s\n"
		+ "%s  %s%s"
	) % [
		title,
		stats.get("chunks", 0),
		stats.get("buildings", 0),
		stats.get("roads", 0),
		stats.get("airport_features", 0),
		airport_name,
		airport_codes,
		("\n" + extra) if not extra.is_empty() else "",
	]


func _apply_shot(index: int) -> void:
	_city.clear_metadata_labels()
	_city.set_chunk_grid_visible(false)

	match index:
		0:
			_set_overlay("KEY WEST CLUSTER — CHUNK-AWARE RING 0")
			_city.set_focus(Vector2.ZERO, true)
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = maxf(_span_z * 1.08, _span_x / 1.55 * 1.08)
			_camera.look_at_from_position(
				_centre + Vector3(0.0, 9000.0, 0.0),
				_centre,
				Vector3(0.0, 0.0, -1.0)
			)
		1:
			_set_overlay("KEY WEST — REAL FOOTPRINT DETAIL + FAR MASSING")
			_city.set_focus(_dense_focus, true)
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 4300.0
			var target := Vector3(_dense_focus.x, 0.0, _dense_focus.y)
			_camera.look_at_from_position(
				target + Vector3(0.0, 6500.0, 0.0),
				target,
				Vector3(0.0, 0.0, -1.0)
			)
		2:
			_set_overlay("512 M CONTENT CHUNKS", "red grid = streaming/content partition")
			_city.set_focus(_dense_focus, true)
			_city.set_chunk_grid_visible(true)
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 3600.0
			var target := Vector3(_dense_focus.x, 0.0, _dense_focus.y)
			_camera.look_at_from_position(
				target + Vector3(0.0, 6000.0, 0.0),
				target,
				Vector3(0.0, 0.0, -1.0)
			)
		3:
			_set_overlay("CITY METADATA", "labels use OSM name / addr:* data")
			_city.set_focus(_dense_focus, false)
			_city.show_metadata_labels(_dense_focus, 520.0)
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 52.0
			var target := Vector3(_dense_focus.x, 4.0, _dense_focus.y)
			_camera.look_at_from_position(
				target + Vector3(650.0, 620.0, 1050.0),
				target
			)
		4:
			_set_overlay("KEY WEST INTERNATIONAL AIRPORT — TOP")
			_city.set_focus(_airport_focus, true)
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 3100.0
			var target := Vector3(_airport_focus.x, 0.0, _airport_focus.y)
			_camera.look_at_from_position(
				target + Vector3(0.0, 5500.0, 0.0),
				target,
				Vector3(0.0, 0.0, -1.0)
			)
		5:
			_set_overlay("KEY WEST INTERNATIONAL AIRPORT — OBLIQUE")
			_city.set_focus(_airport_focus, false)
			_city.show_metadata_labels(_airport_focus, 650.0)
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 50.0
			var target := Vector3(_airport_focus.x, 2.0, _airport_focus.y)
			_camera.look_at_from_position(
				target + Vector3(-1100.0, 760.0, 1500.0),
				target
			)
		6:
			_set_overlay("STREET SCALE — EXACT FOOTPRINT CHUNKS")
			_city.set_focus(_dense_focus, false)
			_city.show_metadata_labels(_dense_focus, 300.0)
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 48.0
			var ground: float = maxf(_terrain.get_height(_dense_focus.x, _dense_focus.y), 0.0)
			var target := Vector3(_dense_focus.x, ground + 8.0, _dense_focus.y)
			_camera.look_at_from_position(
				target + Vector3(-170.0, 75.0, 250.0),
				target
			)

	if _terrain != null:
		_terrain.update_now()
	_snowify_terrain()


func _snowify_terrain() -> void:
	if _terrain == null:
		return
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.79, 0.82, 0.85, 1.0)
	snow.roughness = 0.93
	for child: Node in _terrain.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = snow


func _capture() -> void:
	var path: String = "%s/%s.png" % [OUT_DIR, SHOT_NAMES[_shot]]
	var error: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("key west stage5 capture: cannot save %s (%d)" % [path, error])
	else:
		print("key west stage5 capture: ", path)

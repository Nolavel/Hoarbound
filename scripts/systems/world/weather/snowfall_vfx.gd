extends Node3D
class_name SnowfallVFX

const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")
const SNOW_SHADER: Shader = preload("res://shaders/environment/weather/wind_driven_snow.gdshader")
const WEATHER_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")

const WORLD_MAX_PARTICLES: int = 3072
const WORLD_EMITTER_HEIGHT: float = 6.0
const MAX_UPWIND_OFFSET: float = 9.0
const FOREGROUND_MAX_PARTICLES: int = 32
const FOREGROUND_DENSITY_SCALE: float = 0.08
const FOREGROUND_DISTANCE: float = 2.4
const FOREGROUND_HEIGHT: float = 1.0

var weather_controller: WeatherController
var follow_target: Node3D
var foreground_target: Node3D
var particles: GPUParticles3D
var foreground_particles: GPUParticles3D
var _process_material: ShaderMaterial
var _foreground_material: ShaderMaterial
var _visual_wind_velocity: Vector3 = Vector3.ZERO
var _last_direction: Vector3 = Vector3.FORWARD
var heightfield_service: SnowHeightFieldService
var _snow_door: HingedDoor
var _door_check_left: float = 0.0
var _runtime_visuals_enabled: bool = true
var _quality_density_scale: float = 1.0


func on_world_ready(context: WorldContext) -> void:
	follow_target = context.player
	foreground_target = context.camera
	weather_controller = context.get_system(WEATHER_CONTROLLER_SCRIPT) as WeatherController
	if not _runtime_visuals_enabled:
		return
	_ensure_heightfield_service()
	if heightfield_service != null:
		heightfield_service.configure(follow_target)
	_bind_weather()
	if weather_controller == null:
		push_warning("SnowfallVFX: authoritative WeatherController is missing")


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_runtime_visuals_enabled = DisplayServer.get_name() != "headless"
	_quality_density_scale = float(GRAPHICS.profile_for(GRAPHICS.load_quality())["snow_particle_density"])
	add_to_group(&"graphics_quality_consumer")
	if not _runtime_visuals_enabled:
		set_process(false)
		return
	_ensure_heightfield_service()
	_build_particles()
	_bind_weather()


func apply_graphics_quality(_quality: StringName, profile: Dictionary) -> void:
	_quality_density_scale = float(profile["snow_particle_density"])
	sync_from_weather()


func _ensure_heightfield_service() -> void:
	if heightfield_service != null:
		return
	heightfield_service = SnowHeightFieldService.new()
	heightfield_service.name = "HeightFieldService"
	add_child(heightfield_service)


func _process(delta: float) -> void:
	if not _runtime_visuals_enabled:
		return
	_update_door_barrier(delta)
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position + Vector3.UP * WORLD_EMITTER_HEIGHT
	if foreground_particles != null and is_instance_valid(foreground_target):
		var camera_forward: Vector3 = -foreground_target.global_transform.basis.z.normalized()
		foreground_particles.global_position = (
			foreground_target.global_position
			+ camera_forward * FOREGROUND_DISTANCE
			+ Vector3.UP * FOREGROUND_HEIGHT
			- _last_direction * minf(_visual_wind_velocity.length() * 0.25, 1.5)
		)


func _build_particles() -> void:
	_process_material = _make_process_material(Vector3(24.0, 1.8, 18.0), 0.55, 1.00)
	particles = _make_particle_layer(
		"WorldSnow", WORLD_MAX_PARTICLES, 6.5, 0.012,
		_build_snowflake_mesh(0.010, 0.0016, 0.0042, 0.00115, false),
		_process_material
	)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_process_material.set_shader_parameter("velocity_stretch_enabled", true)
	_process_material.set_shader_parameter("stretch_speed_start", 4.0)
	_process_material.set_shader_parameter("stretch_speed_full", 7.0)
	_process_material.set_shader_parameter("stretch_max", 1.90)
	particles.visibility_aabb = AABB(Vector3(-48.0, -26.0, -48.0), Vector3(96.0, 52.0, 96.0))
	add_child(particles)

	_foreground_material = _make_process_material(Vector3(4.2, 2.0, 2.8), 0.66, 1.10)
	foreground_particles = _make_particle_layer(
		"ForegroundSnow", FOREGROUND_MAX_PARTICLES, 3.4, 0.026,
		_build_snowflake_mesh(0.022, 0.0030, 0.0085, 0.0022, true),
		_foreground_material
	)
	foreground_particles.randomness = 0.42
	_foreground_material.set_shader_parameter("velocity_stretch_enabled", false)
	foreground_particles.visibility_aabb = AABB(Vector3(-10.0, -8.0, -10.0), Vector3(20.0, 16.0, 20.0))
	add_child(foreground_particles)


func _make_process_material(emit_size: Vector3, size_min: float, size_max: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SNOW_SHADER
	material.set_shader_parameter("box_emit_size", emit_size)
	material.set_shader_parameter("size_min", size_min)
	material.set_shader_parameter("size_max", size_max)
	return material


func _make_particle_layer(
	layer_name: String,
	amount: int,
	lifetime: float,
	collision_size: float,
	mesh: Mesh,
	material: ShaderMaterial
) -> GPUParticles3D:
	var layer := GPUParticles3D.new()
	layer.name = layer_name
	layer.amount = amount
	layer.amount_ratio = 0.0
	layer.lifetime = lifetime
	layer.randomness = 0.22
	layer.preprocess = 2.0
	layer.local_coords = false
	layer.fixed_fps = 30
	layer.interpolate = true
	layer.collision_base_size = collision_size
	layer.process_material = material
	layer.draw_pass_1 = mesh
	return layer


func _build_snowflake_mesh(
	arm_length: float,
	arm_width: float,
	branch_length: float,
	branch_width: float,
	use_material_billboard: bool
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for arm_index: int in range(6):
		var angle: float = deg_to_rad(float(arm_index) * 60.0)
		var direction := Vector2(cos(angle), sin(angle))
		_append_strip(vertices, indices, Vector2.ZERO, direction * arm_length, arm_width)
		var branch_root: Vector2 = direction * arm_length * 0.56
		for side: float in [-1.0, 1.0]:
			var branch_direction: Vector2 = direction.rotated(deg_to_rad(42.0 * side))
			_append_strip(vertices, indices, branch_root, branch_root + branch_direction * branch_length, branch_width)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if use_material_billboard:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(0.94, 0.97, 1.0, 0.94)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, material)
	else:
		var material := ShaderMaterial.new()
		var draw_shader := Shader.new()
		draw_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

void vertex() {
	VERTEX.y *= max(INSTANCE_CUSTOM.z, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""
		material.shader = draw_shader
		mesh.surface_set_material(0, material)
	return mesh


func _append_strip(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	from: Vector2,
	to: Vector2,
	width: float
) -> void:
	var direction: Vector2 = (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x) * width * 0.5
	var base: int = vertices.size()
	vertices.append(Vector3(from.x + normal.x, from.y + normal.y, 0.0))
	vertices.append(Vector3(from.x - normal.x, from.y - normal.y, 0.0))
	vertices.append(Vector3(to.x - normal.x, to.y - normal.y, 0.0))
	vertices.append(Vector3(to.x + normal.x, to.y + normal.y, 0.0))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _bind_weather() -> void:
	if not is_instance_valid(weather_controller):
		return
	if not weather_controller.conditions_updated.is_connected(_on_conditions_updated):
		weather_controller.conditions_updated.connect(_on_conditions_updated)
	if not weather_controller.weather_changed.is_connected(_on_weather_changed):
		weather_controller.weather_changed.connect(_on_weather_changed)
	sync_from_weather()


func sync_from_weather() -> void:
	if not is_instance_valid(weather_controller) or _process_material == null:
		return
	_apply_conditions(weather_controller.get_wind_speed_mps(), weather_controller.get_snowfall_density())


func restart_particles() -> void:
	if particles != null:
		particles.restart()
	if foreground_particles != null:
		foreground_particles.restart()


func _on_weather_changed(_profile: WeatherProfile) -> void:
	sync_from_weather()


func _on_conditions_updated(_ambient_offset_c: float, wind_speed_mps: float, snowfall_density: float) -> void:
	_apply_conditions(wind_speed_mps, snowfall_density)


func _apply_conditions(wind_speed_mps: float, snowfall_density: float) -> void:
	if _process_material == null or particles == null:
		return
	var direction: Vector3 = weather_controller.get_wind_direction().normalized()
	var density: float = clampf(snowfall_density, 0.0, 1.0)
	var speed: float = maxf(wind_speed_mps, 0.0)
	var visual_speed: float = minf(speed * 0.26 + sqrt(speed) * 0.20, 7.2)
	_last_direction = direction
	_visual_wind_velocity = direction * visual_speed
	for material: ShaderMaterial in [_process_material, _foreground_material]:
		material.set_shader_parameter("wind_velocity", _visual_wind_velocity)
		material.set_shader_parameter("turbulence_strength", lerpf(0.10, 1.20, clampf(speed / 28.0, 0.0, 1.0)))

	var upwind_offset: float = minf(visual_speed * 1.25, MAX_UPWIND_OFFSET)
	particles.position = -direction * upwind_offset
	particles.amount_ratio = density * _quality_density_scale
	particles.emitting = particles.amount_ratio > 0.005
	if heightfield_service != null:
		heightfield_service.set_active(density > 0.005)

	var foreground_ratio: float = clampf(density * FOREGROUND_DENSITY_SCALE * _quality_density_scale, 0.0, 1.0)
	foreground_particles.amount_ratio = foreground_ratio
	foreground_particles.emitting = foreground_ratio > 0.005


func get_visual_wind_velocity() -> Vector3:
	return _visual_wind_velocity


func _update_door_barrier(delta: float) -> void:
	_door_check_left -= delta
	if _door_check_left <= 0.0:
		_door_check_left = 0.5
		_snow_door = null
		var nearest: float = 50.0
		for candidate: Node in get_tree().get_nodes_in_group(&"snow_doors"):
			var door := candidate as HingedDoor
			var distance: float = door.global_position.distance_to(follow_target.global_position if is_instance_valid(follow_target) else global_position)
			if distance < nearest:
				nearest = distance
				_snow_door = door
	for material: ShaderMaterial in [_process_material, _foreground_material]:
		if material == null:
			continue
		if is_instance_valid(_snow_door):
			_snow_door.apply_snow_barrier(material)
		else:
			material.set_shader_parameter("snow_door_enabled", false)

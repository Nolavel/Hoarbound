class_name SnowLift
extends Node3D

## Ground-hugging drifting snow. The dominant mass stays close to the surface:
## creep slides almost flat, saltation makes short ballistic hops, and only a
## small strong-wind fraction enters suspension. Local +X is downwind and local
## +Y is the sampled surface normal. Each streamer is a sweep: the emitter runs
## downwind along a shallow arc over the snow and leaves a world-space trail, so
## the drift travels like a wave instead of flashing in place.

const MIN_WIND_MPS: float = 6.0
const MAX_WIND_MPS: float = 17.0
const SUSPENSION_START_MPS: float = 11.0
## Seconds one sweep runs, slow to fast wind.
const SWEEP_S: Vector2 = Vector2(2.4, 1.6)
## Sweep head speed as a share of the 10 m wind: grains near the surface run well below it.
const HEAD_WIND_SHARE: float = 0.45
## Arc bow across the wind per metre of sweep.
const BOW_PER_M: float = 0.09
## Highest step the head climbs or drops before the sweep ends (a kerb, not a wall).
const MAX_STEP_M: float = 0.6
## Deepest settled snow over the physics ground, metres.
const DEEPEST_SNOW_M: float = 1.0
## Cover lower than this over a sweep start is a canopy or porch roof.
const CANOPY_M: float = 5.0

@export_group("Patch")
## Length of the moving head that sheds grains; the sweep draws the streamer out behind it.
@export var streamer_length: float = 1.6
@export var streamer_width: float = 0.55

var _creep: GPUParticles3D
var _saltation: GPUParticles3D
var _suspension: GPUParticles3D
var _haze: GPUParticles3D
var _layers: Array[GPUParticles3D] = []
var _ratios: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _start: Transform3D
var _length: float = 0.0
var _bow: float = 0.0
var _sweep_s: float = 1.0
var _age: float = -1.0
var _busy_until_ms: int = 0


func _ready() -> void:
	_creep = _build_creep()
	_saltation = _build_saltation()
	_suspension = _build_suspension()
	_haze = _build_haze()
	_layers = [_creep, _saltation, _suspension, _haze]
	set_physics_process(false)


## Length a sweep at this wind covers, metres (spawners keep it in frame).
static func sweep_length(wind_speed_mps: float) -> float:
	var wind_t: float = clampf(inverse_lerp(MIN_WIND_MPS, MAX_WIND_MPS, wind_speed_mps), 0.0, 1.0)
	return wind_speed_mps * HEAD_WIND_SHARE * lerpf(SWEEP_S.x, SWEEP_S.y, wind_t)


## True when a sweep from the ground point downwind would be seen whole: start, middle and end on screen.
static func in_frame(camera: Camera3D, at: Vector3, along: Vector3, length: float) -> bool:
	for share: float in [0.0, 0.5, 1.0]:
		var point: Vector3 = at + along * length * share + Vector3.UP * 0.1
		if camera.is_position_behind(point) or not camera.is_position_in_frustum(point):
			return false
	return true


## Starts a sweep whose middle passes the ground spot, if the whole sweep is open snow on screen.
func launch_through(spot: Vector3, along: Vector3, wind_speed_mps: float, snow_cover: float,
		camera: Camera3D) -> bool:
	var length: float = sweep_length(wind_speed_mps)
	var start: Vector3 = spot - along * length * 0.5
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from := Vector3(start.x, spot.y + 3.0, start.z)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 9.0))
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	var at: Vector3 = hit["position"]
	if normal.y < 0.55 or not in_frame(camera, at, along, length):
		return false
	## Never under a roof or a low canopy (the grains would hit it at once); palm crowns and wires stand higher.
	var field: SnowField = SnowShell.active.field if is_instance_valid(SnowShell.active) else null
	var end: Vector3 = at + along * length
	if field != null and (field.is_building(Vector2(at.x, at.z)) or field.is_building(Vector2(end.x, end.z))):
		return false
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.UP * CANOPY_M)).is_empty():
		return false
	var surface_along: Vector3 = along - normal * along.dot(normal)
	if surface_along.length_squared() < 0.0025:
		return false
	surface_along = surface_along.normalized()
	global_transform = Transform3D(Basis(surface_along, normal, surface_along.cross(normal)).orthonormalized(),
		_on_snow(at) + normal * 0.025)
	lift(wind_speed_mps, snow_cover)
	return true


## The drawn snow top over a physics ground point: the ground lies a settled depth (~0.2–0.5 m) under it,
## so grains emitted there were buried in the snow.
static func _on_snow(ground: Vector3) -> Vector3:
	var field: SnowField = SnowShell.active.field if is_instance_valid(SnowShell.active) else null
	var top: float = field.get_snow_top(ground.x, ground.z) if field != null else -INF
	return Vector3(ground.x, maxf(ground.y, top), ground.z)


## Plays one irregular ground-drift streamer, sweeping downwind from the current transform.
func lift(wind_speed_mps: float = 8.0, snow_cover: float = 1.0) -> void:
	var wind_t: float = clampf(
		inverse_lerp(MIN_WIND_MPS, MAX_WIND_MPS, wind_speed_mps),
		0.0,
		1.0
	)
	var cover: float = clampf(snow_cover, 0.0, 1.0)
	if cover <= 0.02:
		return

	# Most visible mass belongs to the first centimetres above the ground.
	_ratios[0] = cover * lerpf(0.50, 1.0, wind_t)
	_ratios[1] = cover * lerpf(0.35, 0.85, wind_t)

	# Airborne haze is deliberately a minority and only arrives in strong wind.
	var suspension_t: float = smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(SUSPENSION_START_MPS, MAX_WIND_MPS, wind_speed_mps),
			0.0,
			1.0
		)
	)
	_ratios[2] = cover * suspension_t * 0.32
	_ratios[3] = cover * lerpf(0.5, 1.0, wind_t)

	_start = global_transform
	_sweep_s = lerpf(SWEEP_S.x, SWEEP_S.y, wind_t)
	_length = sweep_length(wind_speed_mps)
	_bow = _length * BOW_PER_M * (1.0 if randf() < 0.5 else -1.0) * randf_range(0.6, 1.0)
	_age = 0.0
	var tail_s: float = 0.0
	for i: int in range(_layers.size()):
		_layers[i].amount_ratio = 0.0
		_layers[i].restart()
		_layers[i].emitting = _ratios[i] > 0.005
		tail_s = maxf(tail_s, _layers[i].lifetime)
	_busy_until_ms = Time.get_ticks_msec() + int((_sweep_s + tail_s) * 1000.0)
	set_physics_process(true)


## True while the last streamer is still sweeping or its trail still drawing.
func is_active() -> bool:
	return Time.get_ticks_msec() < _busy_until_ms


func _physics_process(delta: float) -> void:
	_age += delta
	var t: float = _age / _sweep_s
	if t >= 1.0 or not _follow_ground(t):
		_end_sweep()
		return
	## The wave swells in and dies out over the sweep.
	var swell: float = sqrt(sin(PI * t))
	for i: int in range(_layers.size()):
		_layers[i].amount_ratio = _ratios[i] * swell


## Head on the arc at t, snapped to the ground below; false where the arc leaves open snow.
func _follow_ground(t: float) -> bool:
	var along: Vector3 = _start.basis.x
	var side: Vector3 = _start.basis.z
	var point: Vector3 = _start.origin + along * _length * t + side * _bow * sin(PI * t)
	var tangent: Vector3 = (along * _length + side * _bow * PI * cos(PI * t)).normalized()
	var from: Vector3 = point + Vector3.UP * MAX_STEP_M
	## The head rides the snow top; the physics ground lies up to the deepest drift below it.
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (MAX_STEP_M * 2.0 + DEEPEST_SNOW_M))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	if normal.y < 0.55:
		return false
	tangent = (tangent - normal * tangent.dot(normal)).normalized()
	global_transform = Transform3D(Basis(tangent, normal, tangent.cross(normal)).orthonormalized(),
		_on_snow(hit["position"]) + normal * 0.025)
	return true


func _end_sweep() -> void:
	set_physics_process(false)
	for layer: GPUParticles3D in _layers:
		layer.emitting = false


func _build_creep() -> GPUParticles3D:
	var particles := _new_layer("SurfaceCreep", 180, 0.48, 0.62)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.collision_base_size = 0.012

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		streamer_length * 0.5,
		0.012,
		streamer_width * 0.5
	)
	process.direction = Vector3(1.0, 0.005, 0.0)
	process.spread = 2.5
	process.initial_velocity_min = 5.5
	process.initial_velocity_max = 8.5
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 0.05
	process.damping_max = 0.20
	process.scale_min = 0.55
	process.scale_max = 1.0
	process.color_ramp = _make_ramp(0.70, 0.52)
	_collide(process)
	particles.process_material = process
	particles.draw_pass_1 = _make_quad(Vector2(0.05, 0.32))
	return particles


func _build_saltation() -> GPUParticles3D:
	var particles := _new_layer("Saltation", 120, 0.62, 0.55)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.collision_base_size = 0.018

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		streamer_length * 0.42,
		0.018,
		streamer_width * 0.42
	)
	# A small lift, immediately pulled back down: hop, not climb.
	process.direction = Vector3(1.0, 0.055, 0.0)
	process.spread = 5.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 6.8
	process.gravity = Vector3(0.0, -8.5, 0.0)
	process.damping_min = 0.05
	process.damping_max = 0.22
	process.scale_min = 0.55
	process.scale_max = 1.0
	process.color_ramp = _make_ramp(0.82, 0.58)
	_collide(process)
	particles.process_material = process
	particles.draw_pass_1 = _make_quad(Vector2(0.05, 0.09))
	return particles


func _build_suspension() -> GPUParticles3D:
	var particles := _new_layer("Suspension", 36, 1.05, 0.72)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.collision_base_size = 0.010

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		streamer_length * 0.35,
		0.035,
		streamer_width * 0.55
	)
	process.direction = Vector3(1.0, 0.08, 0.0)
	process.spread = 10.0
	process.initial_velocity_min = 2.8
	process.initial_velocity_max = 4.8
	process.gravity = Vector3(0.0, -0.9, 0.0)
	process.damping_min = 0.15
	process.damping_max = 0.45
	process.scale_min = 0.35
	process.scale_max = 0.75
	process.color_ramp = _make_ramp(0.32, 0.48)
	_collide(process)
	particles.process_material = process
	particles.draw_pass_1 = _make_quad(Vector2(0.03, 0.05))
	return particles


## A thin veil the streamer drags along the ground, so the drift reads from eye height.
func _build_haze() -> GPUParticles3D:
	var particles := _new_layer("GroundHaze", 26, 1.2, 0.5)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(streamer_length * 0.45, 0.05, streamer_width * 0.5)
	process.direction = Vector3(1.0, 0.01, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = 3.5
	process.initial_velocity_max = 5.5
	process.scale_min = 0.7
	process.scale_max = 1.2
	process.color_ramp = _make_ramp(0.28, 0.5)
	_collide(process)
	particles.process_material = process
	particles.position.y = 0.12
	particles.draw_pass_1 = _make_quad(Vector2(0.35, 1.2))
	return particles


func _new_layer(
	layer_name: String,
	particle_count: int,
	lifetime_s: float,
	randomness_value: float
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = layer_name
	particles.position.y = 0.05  # clear of the surface so grains are not buried in it
	particles.emitting = false
	particles.amount = particle_count
	particles.amount_ratio = 0.0
	particles.lifetime = lifetime_s
	particles.randomness = randomness_value
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## The node rides the head; its trail lies up to a full sweep behind.
	particles.visibility_aabb = AABB(Vector3(-20.0, -2.0, -6.0), Vector3(32.0, 6.0, 12.0))
	add_child(particles)
	return particles


## Grains stop on the snowfall height field (SnowHeightFieldService), so they never pass through a roof.
func _collide(process: ParticleProcessMaterial) -> void:
	process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	process.collision_friction = 0.6
	process.collision_bounce = 0.0


func _make_ramp(peak_alpha: float, fade_from: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.8, 0.81, 0.83, 0.0))
	gradient.add_point(0.08, Color(0.8, 0.81, 0.83, peak_alpha))
	gradient.add_point(
		fade_from,
		Color(0.8, 0.81, 0.83, peak_alpha * 0.72)
	)
	gradient.set_color(
		gradient.get_point_count() - 1,
		Color(0.8, 0.81, 0.83, 0.0)
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _make_quad(size: Vector2) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	float edge = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(1.0, 0.2, edge);
}
"""
	material.shader = shader
	mesh.material = material
	return mesh


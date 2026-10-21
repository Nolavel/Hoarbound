class_name SnowLift
extends Node3D

## Ground-hugging drifting snow. The dominant mass stays close to the surface:
## creep slides almost flat, saltation makes short ballistic hops, and only a
## small strong-wind fraction enters suspension. Local +X is downwind and local
## +Y is the sampled surface normal.

const MIN_WIND_MPS: float = 6.0
const MAX_WIND_MPS: float = 17.0
const SUSPENSION_START_MPS: float = 11.0

@export_group("Patch")
@export var streamer_length: float = 5.0
@export var streamer_width: float = 0.55

var _creep: GPUParticles3D
var _saltation: GPUParticles3D
var _suspension: GPUParticles3D
var _haze: GPUParticles3D


func _ready() -> void:
	_creep = _build_creep()
	_saltation = _build_saltation()
	_suspension = _build_suspension()
	_haze = _build_haze()


## Plays one irregular ground-drift streamer at the current transform.
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
	_creep.amount_ratio = cover * lerpf(0.50, 1.0, wind_t)
	_saltation.amount_ratio = cover * lerpf(0.35, 0.85, wind_t)

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
	_suspension.amount_ratio = cover * suspension_t * 0.32

	_restart_if_visible(_creep)
	_restart_if_visible(_saltation)
	_restart_if_visible(_suspension)
	_haze.amount_ratio = cover * lerpf(0.5, 1.0, wind_t)
	_restart_if_visible(_haze)


## True while any layer of the last streamer is still drawing.
func is_active() -> bool:
	for layer: GPUParticles3D in [_creep, _saltation, _suspension, _haze]:
		if layer.emitting:
			return true
	return false


func _build_creep() -> GPUParticles3D:
	var particles := _new_layer("SurfaceCreep", 180, 0.48, 0.18, 0.62)
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
	var particles := _new_layer("Saltation", 120, 0.62, 0.28, 0.55)
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
	var particles := _new_layer("Suspension", 36, 1.05, 0.38, 0.72)
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
	var particles := _new_layer("GroundHaze", 26, 1.2, 0.3, 0.5)
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
	explosiveness_value: float,
	randomness_value: float
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = layer_name
	particles.position.y = 0.05  # clear of the surface so grains are not buried in it
	particles.one_shot = true
	particles.emitting = false
	particles.amount = particle_count
	particles.amount_ratio = 0.0
	particles.lifetime = lifetime_s
	particles.explosiveness = explosiveness_value
	particles.randomness = randomness_value
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(
		Vector3(-8.0, -2.0, -4.0),
		Vector3(24.0, 6.0, 8.0)
	)
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


func _restart_if_visible(particles: GPUParticles3D) -> void:
	if particles.amount_ratio <= 0.005:
		return
	particles.restart()

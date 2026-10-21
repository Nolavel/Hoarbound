class_name SnowSpindrift
extends Node3D

## Spindrift smoking off a drift crest or a lee roof eave: a lofted plume that leaves the lip
## downwind. Local +X is downwind, +Y the surface normal at the lip. Grains are two-tone (white
## core, cool rim) and a soft decal shades the snow under the plume, so it reads on white snow.

const MIN_WIND_MPS: float = 6.0
const MAX_WIND_MPS: float = 22.0
## Plume life and how long the lip keeps feeding it, seconds.
const LIFETIME_S: float = 1.8
const FEED_S: float = 1.4
## Shade under the plume: peak darkening and footprint (downwind length, width), metres.
const SHADE_ALPHA: float = 0.16
const SHADE_SIZE: Vector2 = Vector2(4.5, 1.6)

var _plume: GPUParticles3D
var _shade: Decal
var _shade_tween: Tween


func _ready() -> void:
	_plume = _build_plume()
	_shade = _build_shade()


## Plays one plume from this transform's lip at the given wind and snow cover.
func blow(wind_speed_mps: float, snow_cover: float) -> void:
	var cover: float = clampf(snow_cover, 0.0, 1.0)
	if cover <= 0.02:
		return
	var wind_t: float = clampf(inverse_lerp(MIN_WIND_MPS, MAX_WIND_MPS, wind_speed_mps), 0.0, 1.0)
	var process := _plume.process_material as ParticleProcessMaterial
	process.initial_velocity_min = lerpf(2.5, 6.0, wind_t)
	process.initial_velocity_max = lerpf(4.0, 9.0, wind_t)
	_plume.amount_ratio = cover * lerpf(0.45, 1.0, wind_t)
	_plume.restart()
	_plume.emitting = true
	get_tree().create_timer(FEED_S).timeout.connect(func() -> void: _plume.emitting = false)
	_fade_shade(SHADE_ALPHA * cover * lerpf(0.6, 1.0, wind_t))


## True while the plume is fed or its last puffs are in the air.
func is_active() -> bool:
	return _plume.emitting or (_shade.modulate.a > 0.01)


func _build_plume() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Plume"
	particles.amount = 160
	particles.amount_ratio = 0.0
	particles.lifetime = LIFETIME_S
	particles.one_shot = false
	particles.emitting = false
	particles.explosiveness = 0.0
	particles.randomness = 0.6
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.collision_base_size = 0.03
	particles.visibility_aabb = AABB(Vector3(-3.0, -4.0, -4.0), Vector3(16.0, 8.0, 8.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.15, 0.04, 1.1)
	## Lofted off the lip, then settling: the lee eddy lifts it before gravity wins.
	process.direction = Vector3(1.0, 0.35, 0.0)
	process.spread = 14.0
	process.gravity = Vector3(0.0, -1.6, 0.0)
	process.damping_min = 0.4
	process.damping_max = 1.2
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 2.2
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.18
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.scale_curve = _grow_curve()
	process.color_ramp = _alpha_ramp()
	process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	process.collision_friction = 0.6
	process.collision_bounce = 0.0
	particles.process_material = process
	particles.draw_pass_1 = _puff_quad(0.16)
	add_child(particles)
	return particles


## A soft shade on the snow under the plume, projected straight down from above the lip.
func _build_shade() -> Decal:
	var decal := Decal.new()
	decal.name = "Shade"
	decal.size = Vector3(SHADE_SIZE.x, 6.0, SHADE_SIZE.y)
	decal.position = Vector3(SHADE_SIZE.x * 0.5, 0.0, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.30, 0.36, 0.52, 1.0))
	gradient.set_color(1, Color(0.30, 0.36, 0.52, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	decal.texture_albedo = texture
	decal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	decal.cull_mask = 1
	add_child(decal)
	return decal


func _fade_shade(peak: float) -> void:
	if _shade_tween != null and _shade_tween.is_valid():
		_shade_tween.kill()
	_shade_tween = create_tween()
	_shade_tween.tween_property(_shade, "modulate:a", peak, 0.4)
	_shade_tween.tween_property(_shade, "modulate:a", 0.0, FEED_S + LIFETIME_S * 0.5)


## Puffs swell as they spread downwind.
func _grow_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.5, 0.85))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _alpha_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.1, Color(1.0, 1.0, 1.0, 0.85))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.6))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


## Soft puff with a white core and a cool rim, so a puff reads on white snow and on pale sky.
func _puff_quad(size_m: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size_m, size_m)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(0.98, 0.99, 1.0);
uniform vec3 rim_color : source_color = vec3(0.62, 0.68, 0.80);

void fragment() {
	float r = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = mix(core_color, rim_color, smoothstep(0.25, 0.85, r));
	ALPHA = COLOR.a * (1.0 - smoothstep(0.7, 1.0, r));
}
"""
	material.shader = shader
	mesh.material = material
	return mesh

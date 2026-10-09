@tool
class_name HeldFlare
extends Node3D

## Hand-held signal flare presentation.
##
## Ownership:
## - this node owns burn time, light and particles;
## - inventory/held-item code owns who carries it and when it is consumed;
## - WeatherController remains the only authority for world wind.
##
## The effect intentionally uses several cheap layers instead of one giant
## particle system: emissive core, real OmniLight3D, spark jet, rare hot
## fragments and a slower smoke layer.

signal burning_changed(is_burning: bool)
signal spent

const WEATHER_CONTROLLER_SCRIPT: GDScript = preload(
	"res://scripts/systems/world/WeatherController.gd"
)

@export_group("Burn")
@export var auto_ignite: bool = true
## A real long-burning road flare is available in a 30-minute rating. First
## Exit's 24-hour clock takes 3600 real seconds, so 75 real seconds here equal
## 30 minutes in Henry's world.
@export_range(5.0, 300.0, 1.0) var burn_duration_s: float = 75.0
## Fixed seed keeps local previews reproducible. Set 0 to randomise.
@export var flare_seed: int = 1337

@export_group("Light")
@export var light_color: Color = Color(1.0, 0.19, 0.055, 1.0)
## Tuned after the first in-scene night pass: enough to read Henry and nearby
## geometry without flooding a small shelter in saturated red.
@export_range(0.5, 12.0, 0.1) var base_light_energy: float = 2.8
@export_range(1.0, 16.0, 0.1) var surge_light_energy: float = 6.8
@export_range(2.0, 12.0, 0.1) var light_range_m: float = 4.5
## Shadows are deliberately off for the normal production tier.
@export var enable_shadows: bool = false

@export_group("Wind")
@export_range(0.05, 1.0, 0.05) var wind_sample_interval_s: float = 0.15
@export_range(0.0, 1.0, 0.05) var smoke_wind_response: float = 0.38

var weather_controller: WeatherController

var _body: MeshInstance3D
var _core: MeshInstance3D
var _core_material: StandardMaterial3D
var _light: OmniLight3D
var _tip: Marker3D
var _sparks: GPUParticles3D
var _fragments: GPUParticles3D
var _smoke: GPUParticles3D
var _smoke_process: ParticleProcessMaterial
var _spark_process: ParticleProcessMaterial
## 0..1 gush level: rises in uneven spurts, decays between them, and drives the
## spark fountain and the light's reach together.
var _gush: float = 0.0
var _gush_timer_s: float = 0.0

var _rng := RandomNumberGenerator.new()
var _runtime_visuals_enabled: bool = true
var _burning: bool = false
## Set once the burn time ran out; a spent flare never lights again.
var _spent: bool = false
## Owned by this node alone, so the burn follows the flare from hand to ground.
var _burn_elapsed_s: float = 0.0
var _change_timer_s: float = 0.0
var _wind_timer_s: float = 0.0
var _target_energy: float = 0.92
var _current_energy: float = 0.92
var _smoke_energy: float = 0.75


func _ready() -> void:
	if Engine.is_editor_hint():
		## Item Fitter needs the actual flare body in the editor, but never the
		## live burn simulation or hundreds of preview particles.
		_runtime_visuals_enabled = false
		_build_flare()
		_burning = false
		_apply_burning_state()
		set_process(false)
		return
	_runtime_visuals_enabled = DisplayServer.get_name() != "headless"
	if flare_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = flare_seed
	_build_flare()
	if auto_ignite:
		ignite()
	else:
		_apply_burning_state()


func on_world_ready(context: WorldContext) -> void:
	weather_controller = context.get_system(WEATHER_CONTROLLER_SCRIPT) as WeatherController
	_update_smoke_wind()


func set_weather_controller(controller: WeatherController) -> void:
	weather_controller = controller
	_update_smoke_wind()


## Lights the flare; the burn time is never reset. False when it is spent.
func ignite() -> bool:
	if _spent:
		return false
	if _burning:
		return true
	_change_timer_s = 0.0
	_target_energy = 0.92
	_current_energy = 0.92
	_smoke_energy = 0.72
	_burning = true
	_apply_burning_state()
	burning_changed.emit(true)
	return true


func extinguish() -> void:
	if not _burning:
		return
	_burning = false
	_apply_burning_state()
	burning_changed.emit(false)


func is_burning() -> bool:
	return _burning


func is_spent() -> bool:
	return _spent


func get_remaining_seconds() -> float:
	return maxf(0.0, burn_duration_s - _burn_elapsed_s)


func get_burn_fraction() -> float:
	if burn_duration_s <= 0.0:
		return 1.0
	return clampf(_burn_elapsed_s / burn_duration_s, 0.0, 1.0)


func get_current_energy() -> float:
	return _current_energy if _burning else 0.0


func _process(delta: float) -> void:
	if not _burning:
		return

	_burn_elapsed_s += delta
	if burn_duration_s > 0.0 and _burn_elapsed_s >= burn_duration_s:
		_spent = true
		extinguish()
		spent.emit()
		return

	_change_timer_s -= delta
	if _change_timer_s <= 0.0:
		_pick_next_energy()

	var follow: float = 1.0 - exp(-delta * 15.0)
	_current_energy = lerpf(_current_energy, _target_energy, follow)

	## Smoke follows the burn with a slower response, so a bright spit is
	## followed by a denser puff instead of every layer pulsing in lock-step.
	var smoke_follow: float = 1.0 - exp(-delta * 2.8)
	_smoke_energy = lerpf(_smoke_energy, _current_energy, smoke_follow)

	_update_gush(delta)
	_apply_energy()

	_wind_timer_s -= delta
	if _wind_timer_s <= 0.0:
		_wind_timer_s = wind_sample_interval_s
		_update_smoke_wind()


func _pick_next_energy() -> void:
	var life: float = get_burn_fraction()
	var interval_scale: float = lerpf(1.0, 0.72, smoothstep(0.78, 1.0, life))
	_change_timer_s = _rng.randf_range(0.055, 0.21) * interval_scale

	var target: float = _rng.randf_range(0.78, 1.02)
	var surge_chance: float = lerpf(0.09, 0.05, life)
	var sputter_chance: float = lerpf(0.035, 0.18, smoothstep(0.76, 1.0, life))

	if _rng.randf() < surge_chance:
		target = _rng.randf_range(1.08, 1.30)
	elif _rng.randf() < sputter_chance:
		target = _rng.randf_range(0.46, 0.68)

	## A flare weakens near exhaustion but never becomes a smooth linear fade.
	if life > 0.86:
		target *= lerpf(1.0, 0.62, smoothstep(0.86, 1.0, life))
	_target_energy = target


## Spurts: at random short intervals the tip spits a fountain (gush jumps up),
## which then sags; a surge in burn energy makes a spurt likely.
func _update_gush(delta: float) -> void:
	_gush_timer_s -= delta
	if _gush_timer_s <= 0.0:
		_gush_timer_s = _rng.randf_range(0.12, 0.55)
		var chance: float = 0.35 + clampf(_current_energy - 0.9, 0.0, 0.4) * 1.5
		if _rng.randf() < chance:
			_gush = maxf(_gush, _rng.randf_range(0.55, 1.0))
	_gush = move_toward(_gush, 0.0, delta * _rng.randf_range(1.1, 2.4))


func _apply_energy() -> void:
	if _light != null:
		var light_t: float = clampf((_current_energy - 0.45) / 0.85, 0.0, 1.0)
		_light.light_energy = lerpf(base_light_energy * 0.72, surge_light_energy, light_t)
		## The lit circle on the ground breathes with the burn and each spurt.
		_light.omni_range = light_range_m * lerpf(0.7, 1.15, light_t) * lerpf(1.0, 1.3, _gush)

	if _core_material != null:
		_core_material.emission_energy_multiplier = lerpf(
			3.6,
			9.0,
			clampf((_current_energy - 0.45) / 0.85, 0.0, 1.0)
		)

	if not _runtime_visuals_enabled:
		return

	var hiss: float = sin(_burn_elapsed_s * 24.7) * 0.045 + sin(_burn_elapsed_s * 41.3 + 0.8) * 0.025
	if _sparks != null:
		_sparks.amount_ratio = clampf(0.22 + _gush * 0.78 + (_current_energy - 0.9) * 0.4 + hiss, 0.12, 1.0)
	if _spark_process != null:
		_spark_process.initial_velocity_min = lerpf(1.6, 3.2, _gush)
		_spark_process.initial_velocity_max = lerpf(3.4, 7.2, _gush)
	if _fragments != null:
		_fragments.amount_ratio = clampf((_current_energy - 0.62) * 0.90, 0.06, 0.62)
	if _smoke != null:
		_smoke.amount_ratio = clampf(0.22 + _smoke_energy * 0.42, 0.16, 0.72)


func _apply_burning_state() -> void:
	if _light != null:
		_light.visible = _burning
	if _core != null:
		_core.visible = _burning

	if _runtime_visuals_enabled:
		for layer: GPUParticles3D in [_sparks, _fragments, _smoke]:
			if layer != null:
				layer.emitting = _burning

	if _burning:
		_apply_energy()
	else:
		if _light != null:
			_light.light_energy = 0.0
		for layer: GPUParticles3D in [_sparks, _fragments, _smoke]:
			if layer != null:
				layer.amount_ratio = 0.0


func _update_smoke_wind() -> void:
	if _smoke_process == null:
		return

	var world_wind := Vector3.ZERO
	if is_instance_valid(weather_controller):
		var direction: Vector3 = weather_controller.get_wind_direction().normalized()
		var speed: float = maxf(weather_controller.get_wind_speed_mps(), 0.0)
		world_wind = direction * minf(speed * smoke_wind_response, 5.0)

	var local_wind: Vector3 = global_transform.basis.inverse() * world_wind
	var drift := Vector3.UP * 0.78 + local_wind * 0.22
	if drift.length_squared() < 0.0001:
		drift = Vector3.UP
	_smoke_process.direction = drift.normalized()
	_smoke_process.initial_velocity_min = 0.24 + local_wind.length() * 0.05
	_smoke_process.initial_velocity_max = 0.62 + local_wind.length() * 0.12


func _build_flare() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.014
	tube.bottom_radius = 0.016
	tube.height = 0.22
	_body.mesh = tube
	var tube_material := StandardMaterial3D.new()
	tube_material.albedo_color = Color(0.19, 0.035, 0.026, 1.0)
	tube_material.metallic = 0.18
	tube_material.roughness = 0.58
	_body.material_override = tube_material
	add_child(_body)

	_tip = Marker3D.new()
	_tip.name = "Tip"
	_tip.position = Vector3(0.0, 0.118, 0.0)
	add_child(_tip)

	_core = MeshInstance3D.new()
	_core.name = "HotCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.019
	core_mesh.height = 0.038
	_core.mesh = core_mesh
	_core_material = StandardMaterial3D.new()
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material.emission_enabled = true
	_core_material.emission = Color(1.0, 0.085, 0.018, 1.0)
	_core_material.emission_energy_multiplier = 6.0
	_core_material.albedo_color = Color(1.0, 0.24, 0.055, 1.0)
	_core.material_override = _core_material
	_tip.add_child(_core)

	_light = OmniLight3D.new()
	_light.name = "FlareLight"
	_light.light_color = light_color
	_light.light_energy = base_light_energy
	_light.omni_range = light_range_m
	_light.shadow_enabled = enable_shadows
	_tip.add_child(_light)

	if not _runtime_visuals_enabled:
		return

	_sparks = _make_spark_layer()
	_sparks.name = "SparkJet"
	_tip.add_child(_sparks)

	_fragments = _make_fragment_layer()
	_fragments.name = "HotFragments"
	_tip.add_child(_fragments)

	_smoke = _make_smoke_layer()
	_smoke.name = "LocalSmoke"
	_tip.add_child(_smoke)


func _make_spark_layer() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 520
	particles.lifetime = 0.85
	particles.randomness = 0.68
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.visibility_aabb = AABB(Vector3(-3.0, -3.0, -3.0), Vector3(6.0, 6.0, 6.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process.direction = Vector3.UP
	process.spread = 34.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.4
	## Real gravity, so the jet arcs over and falls as a fountain.
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 0.4
	process.damping_max = 1.6
	process.scale_min = 0.5
	process.scale_max = 1.5
	## Hot sparks read orange-white at the tip, cooling toward red.
	var spark_ramp := Gradient.new()
	spark_ramp.set_color(0, Color(1.0, 0.85, 0.55, 1.0))
	spark_ramp.add_point(0.35, Color(1.0, 0.42, 0.1, 1.0))
	spark_ramp.set_color(spark_ramp.get_point_count() - 1, Color(0.9, 0.08, 0.02, 0.0))
	var spark_ramp_tex := GradientTexture1D.new()
	spark_ramp_tex.gradient = spark_ramp
	process.color_ramp = spark_ramp_tex
	particles.process_material = process
	_spark_process = process
	## Soft radial billboard: avoids the tiny square/diamond read seen under
	## lavapipe while keeping the validated cone width.
	particles.draw_pass_1 = _spark_mesh(0.011, Color(1.0, 0.6, 0.25, 1.0), 7.0)
	return particles


func _make_fragment_layer() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 90
	particles.lifetime = 1.2
	particles.randomness = 0.82
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.visibility_aabb = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process.direction = Vector3.UP
	process.spread = 43.0
	process.initial_velocity_min = 0.9
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0.0, -4.6, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.7
	process.color = Color(1.0, 0.075, 0.012, 1.0)
	particles.process_material = process
	particles.draw_pass_1 = _spark_mesh(0.0090, Color(1.0, 0.075, 0.012, 1.0), 8.5)
	return particles


func _make_smoke_layer() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 42
	particles.lifetime = 2.7
	particles.randomness = 0.74
	particles.local_coords = false
	particles.fixed_fps = 20
	particles.interpolate = true
	particles.visibility_aabb = AABB(Vector3(-8.0, -4.0, -8.0), Vector3(16.0, 12.0, 16.0))

	_smoke_process = ParticleProcessMaterial.new()
	_smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	_smoke_process.direction = Vector3.UP
	_smoke_process.spread = 26.0
	_smoke_process.initial_velocity_min = 0.24
	_smoke_process.initial_velocity_max = 0.62
	_smoke_process.gravity = Vector3(0.0, 0.12, 0.0)
	_smoke_process.scale_min = 0.7
	_smoke_process.scale_max = 1.55

	var gradient := Gradient.new()
	## Smoke needs enough warm midtone to separate from a black night sky, but
	## it still fades back toward neutral grey as it leaves the hot tip.
	gradient.set_color(0, Color(0.52, 0.24, 0.18, 0.0))
	gradient.add_point(0.12, Color(0.48, 0.28, 0.24, 0.42))
	gradient.add_point(0.52, Color(0.38, 0.33, 0.33, 0.24))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.31, 0.32, 0.35, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	_smoke_process.color_ramp = ramp

	particles.process_material = _smoke_process
	particles.draw_pass_1 = _smoke_quad()
	return particles


func _spark_mesh(size: float, tint: Color, emission_energy: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.albedo_texture = _soft_particle_texture(24, 1.9)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = emission_energy
	mesh.material = material
	return mesh


func _smoke_quad() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.085, 0.085)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_particle_texture(32, 1.35)
	material.albedo_color = Color(0.95, 0.78, 0.72, 0.72)
	material.roughness = 1.0
	material.emission_enabled = true
	## Only a faint warm self-lift. The real OmniLight still provides most of
	## the local illumination; this keeps smoke readable once it leaves the
	## strongest part of the light volume.
	material.emission = Color(0.28, 0.045, 0.018, 1.0)
	material.emission_energy_multiplier = 0.24
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	return mesh


func _soft_particle_texture(size: int, falloff_power: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var denom: float = maxf(float(size - 1), 1.0)
	for y: int in range(size):
		for x: int in range(size):
			var uv := Vector2(float(x) / denom, float(y) / denom)
			var radial: float = clampf(1.0 - (uv - Vector2(0.5, 0.5)).length() * 2.0, 0.0, 1.0)
			var alpha: float = pow(radial, falloff_power)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

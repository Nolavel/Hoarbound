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
## fragments and a slower smoke layer. All of it is authored in HeldFlare.tscn;
## the body is the Emberline model (assets/items/road_flare, tools/blender/build_road_flare.py).

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
## The same shadow-casting light follows the flare from hand to ground.
@export var enable_shadows: bool = true
@export_range(0.0, 1.0, 0.01) var shadow_bias: float = 0.03
@export_range(0.0, 2.0, 0.01) var shadow_normal_bias: float = 0.3
## Falloff exponent (Godot omni_attenuation; 2 is about inverse square).
@export_range(0.25, 4.0, 0.05) var light_attenuation: float = 2.0
## How much the light tints the volumetric fog (Light3D.light_volumetric_fog_energy).
@export_range(0.0, 2.0, 0.05) var fog_energy: float = 0.3
## How much the lit circle's radius breathes with the burn and its spurts, 0..1.
@export_range(0.0, 1.0, 0.05) var range_breath: float = 0.0

@export_group("Local scattering")
## Neutral, non-emissive medium; the real flare light supplies its colour.
@export_range(0.0, 0.1, 0.001) var scattering_density: float = 0.018:
	set(value):
		scattering_density = maxf(value, 0.0)
		if _scattering_material != null:
			_scattering_material.density = scattering_density
		if _scattering != null:
			_scattering.visible = _burning and scattering_density > 0.0
@export_range(0.5, 3.0, 0.1) var scattering_diameter_m: float = 1.6:
	set(value):
		scattering_diameter_m = maxf(value, 0.5)
		if _scattering != null:
			_scattering.size = Vector3.ONE * scattering_diameter_m

@export_group("Wind")
@export_range(0.05, 1.0, 0.05) var wind_sample_interval_s: float = 0.15
@export_range(0.0, 1.0, 0.05) var smoke_wind_response: float = 0.38

var weather_controller: WeatherController

var _core_material: StandardMaterial3D
var _scattering_material: FogMaterial
var _smoke_process: ParticleProcessMaterial
var _spark_process: ParticleProcessMaterial
var _flame_process: ParticleProcessMaterial
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

@onready var _tip: Marker3D = $Tip
@onready var _core: MeshInstance3D = $Tip/HotCore
@onready var _light: OmniLight3D = $Tip/FlareLight
@onready var _scattering: FogVolume = $Tip/LocalScattering
@onready var _flame: GPUParticles3D = $Tip/FlameJet
@onready var _sparks: GPUParticles3D = $Tip/SparkJet
@onready var _fragments: GPUParticles3D = $Tip/HotFragments
@onready var _smoke: GPUParticles3D = $Tip/LocalSmoke


func _ready() -> void:
	_bind_scene()
	if Engine.is_editor_hint():
		## Item Fitter needs the actual flare body in the editor, but never the
		## live burn simulation or hundreds of preview particles.
		_runtime_visuals_enabled = false
		_burning = false
		_apply_burning_state()
		set_process(false)
		return
	_runtime_visuals_enabled = DisplayServer.get_name() != "headless"
	if flare_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = flare_seed
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
		var breath: float = lerpf(0.7, 1.15, light_t) * lerpf(1.0, 1.3, _gush)
		_light.omni_range = light_range_m * lerpf(1.0, breath, range_breath)

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
	if _flame != null:
		## The tip never stops burning: the jet only swells with the burn and each spurt.
		_flame.amount_ratio = clampf(0.70 + (_current_energy - 0.9) * 0.6 + _gush * 0.3, 0.45, 1.0)
	if _flame_process != null:
		_flame_process.initial_velocity_max = lerpf(1.1, 1.9, _gush)
	if _fragments != null:
		_fragments.amount_ratio = clampf((_current_energy - 0.62) * 0.90, 0.06, 0.62)
	if _smoke != null:
		_smoke.amount_ratio = clampf(0.22 + _smoke_energy * 0.42, 0.16, 0.72)


func _apply_burning_state() -> void:
	if _scattering != null:
		_scattering.visible = _burning and scattering_density > 0.0
	if _light != null:
		_light.visible = _burning
	if _core != null:
		_core.visible = _burning

	if _runtime_visuals_enabled:
		for layer: GPUParticles3D in [_flame, _sparks, _fragments, _smoke]:
			if layer != null:
				layer.emitting = _burning

	if _burning:
		_apply_energy()
	else:
		if _light != null:
			_light.light_energy = 0.0
		for layer: GPUParticles3D in [_flame, _sparks, _fragments, _smoke]:
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


## Takes the authored layers and applies the exported light and scattering settings to them.
func _bind_scene() -> void:
	_core_material = _core.material_override as StandardMaterial3D
	_scattering_material = _scattering.material as FogMaterial
	_flame_process = _flame.process_material as ParticleProcessMaterial
	_spark_process = _sparks.process_material as ParticleProcessMaterial
	_smoke_process = _smoke.process_material as ParticleProcessMaterial
	_light.light_color = light_color
	_light.omni_range = light_range_m
	_light.omni_attenuation = light_attenuation
	_light.light_volumetric_fog_energy = fog_energy
	_light.shadow_enabled = enable_shadows
	_light.shadow_bias = shadow_bias
	_light.shadow_normal_bias = shadow_normal_bias
	_scattering_material.density = scattering_density
	_scattering.size = Vector3.ONE * scattering_diameter_m
	## The flare's light sits just above its own cap: a shadow-casting body would throw a dark cone below it.
	for mesh: Node in $Body.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

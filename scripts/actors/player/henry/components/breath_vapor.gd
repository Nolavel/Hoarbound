class_name BreathVapor
extends Node3D

## Henry's breath condensing at the mouth in cold air: a puff on every exhale, quicker and
## stronger while he runs or catches his breath, thicker the colder the air, drifting downwind.

## Air at or above this shows no breath (visible breath is common below about 7 °C / 45 °F).
@export var visible_below_c: float = 7.0
## Air at or below this shows the full puff.
@export var dense_below_c: float = -15.0
## Breath cycle at rest and when panting, seconds (about 14 and 45 breaths a minute).
@export var rest_period_s: float = 4.2
@export var panting_period_s: float = 1.35
## Share of the cycle spent breathing in; the rest is the visible exhale.
@export_range(0.2, 0.8) var inhale_share: float = 0.55
## Exhale speed at rest and when panting, metres per second.
@export var rest_speed_mps: float = 0.32
@export var panting_speed_mps: float = 0.85
## Exertion rises within a breath or two and settles over several, seconds.
@export var exertion_rise_s: float = 0.6
@export var exertion_settle_s: float = 5.0
## Lips in Head-bone space (+Z the face, +Y up the skull), measured from the head mesh's midline.
@export var mouth_offset: Vector3 = Vector3(0.0, 0.045, 0.1)
## Share of the wind the puff drifts with, and its slow rise as warm air.
@export var wind_share: float = 0.3
@export var rise_mps2: float = 0.05
@export var visual: HenryUALAnimation
@export var movement: MovementController

var _thermal: ThermalManager
var _weather: WeatherController
var _phase: float = 0.0
var _exertion: float = 0.0
var _density: float = 0.0
var _exhaling: bool = false

@onready var _puff: GPUParticles3D = $Puff
@onready var _process_material: ParticleProcessMaterial = _puff.process_material as ParticleProcessMaterial


## Given by Player once the world's systems exist.
func set_systems(thermal: ThermalManager, weather: WeatherController) -> void:
	_thermal = thermal
	_weather = weather


## 0 in warm air to 1 in deep cold.
func get_density() -> float:
	return _density


## Smoothed effort 0 at rest to 1 panting.
func get_exertion() -> float:
	return _exertion


func get_period_s() -> float:
	return lerpf(rest_period_s, panting_period_s, _exertion)


func is_exhaling() -> bool:
	return _exhaling


func is_puffing() -> bool:
	return _puff != null and _puff.emitting


## Air around Henry's face: the room when inside, the outdoors otherwise.
func get_air_c() -> float:
	if _thermal == null:
		return visible_below_c
	return _thermal.get_room_temperature_c() if _thermal.is_sheltered() else _thermal.get_outdoor_air_c()


## How hard Henry breathes: a sprint pants, an emptied tank keeps him panting while it refills.
func get_target_exertion() -> float:
	if movement == null:
		return 0.0
	var body := movement.get_parent() as CharacterBody3D
	var velocity: Vector3 = body.velocity if body != null else Vector3.ZERO
	var effort: float = 1.0 - movement.get_stamina_ratio()
	if movement.is_currently_sprinting(velocity):
		effort = 1.0
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		effort = maxf(effort, 0.3)
	return clampf(effort, 0.0, 1.0)


func _process(delta: float) -> void:
	step(delta, get_air_c(), get_target_exertion())
	## The mouth is read where the head look's pose is final, as HenryUALAnimation reads its facing.
	if visual != null and visual.skeleton != null and not visual.skeleton.skeleton_updated.is_connected(_follow_mouth):
		visual.skeleton.skeleton_updated.connect(_follow_mouth)


## One breathing step from the air temperature and effort; split out so tests drive it directly.
func step(delta: float, air_c: float, target_exertion: float) -> void:
	_density = clampf(inverse_lerp(visible_below_c, dense_below_c, air_c), 0.0, 1.0)
	var tau: float = exertion_rise_s if target_exertion > _exertion else exertion_settle_s
	_exertion = lerpf(_exertion, target_exertion, 1.0 - exp(-delta / maxf(tau, 0.01)))
	_phase = fmod(_phase + delta / maxf(get_period_s(), 0.1), 1.0)
	var exhaling: bool = _phase >= inhale_share
	if exhaling and not _exhaling:
		var speed: float = lerpf(rest_speed_mps, panting_speed_mps, _exertion)
		_process_material.initial_velocity_min = speed * 0.8
		_process_material.initial_velocity_max = speed * 1.2
	_exhaling = exhaling
	var puff: bool = exhaling and _density > 0.02
	if _puff.emitting != puff:
		_puff.emitting = puff
	var ratio: float = snappedf(clampf(_density, 0.15, 1.0), 0.05)
	if not is_equal_approx(_puff.amount_ratio, ratio):
		_puff.amount_ratio = ratio
	var drift := Vector3.UP * rise_mps2
	if _weather != null:
		drift += _weather.get_wind_direction().normalized() * minf(_weather.get_wind_speed_mps(), 12.0) * wind_share
	_process_material.gravity = drift


func _follow_mouth() -> void:
	if visual == null or visual.skeleton == null or not visual.skeleton.is_inside_tree():
		return
	var bone: int = visual.skeleton.find_bone(visual.head_bone)
	if bone < 0:
		return
	var head: Transform3D = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone)
	global_transform = Transform3D(head.basis.orthonormalized(), head * mouth_offset)

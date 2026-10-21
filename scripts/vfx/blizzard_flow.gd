class_name BlizzardFlow
extends Node3D

## Blizzard as a continuous flow of blown snow down the wide streets that run with the wind
## (FUTURE_INTENT §6, §9, §10). Fog volumes ride those streets near Henry; their density is the
## blowing-snow extinction for the live wind (gusts included), their shape advects downwind.

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const FLOW_SHADER: Shader = preload("res://shaders/environment/weather/blizzard_flow.gdshader")
const POOL_SIZE: int = 6
## Streets within this reach of Henry carry the flow, metres.
const REACH_M: float = 70.0
## |cos| between street and wind below which a street does not channel it (street-canyon effect).
const MIN_ALIGNMENT: float = 0.6
## Tabler (TRB SR185): visibility in blowing snow, metres, = A * U^-B for the 10 m wind in m/s.
const TABLER_A: float = 1.126e8
const TABLER_B: float = 4.85
## Extinction ceiling, 1/m (visibility ~13 m), so a storm never paints a wall.
const MAX_EXTINCTION: float = 0.3
## Flow box height above the street and the e-folding height of blown snow in it, metres.
const FLOW_HEIGHT_M: float = 7.0
const SNOW_SCALE_HEIGHT_M: float = 1.6
## The weather has to have laid snow to blow.
const MIN_COVER: float = 0.2
const RESELECT_S: float = 0.5
## Seconds for a volume to fade in or out, so the flow never pops.
const FADE_S: float = 2.0
## Flakes carried in each volume, and the share of the wind they fly at.
const FLAKES_PER_VOLUME: int = 220
const FLAKE_WIND_SHARE: float = 0.8
## Extinction at which a volume carries all its flakes and its ground drift runs flat out, 1/m.
const FULL_FLOW_EXTINCTION: float = 0.12
## Ground streamers the flow keeps running along its streets, and their spacing at full flow, seconds.
const DRIFT_POOL_SIZE: int = 6
const DRIFT_INTERVAL_S: float = 0.22
## Streamers start this close to Henry, metres.
const DRIFT_REACH_M: float = 22.0

var _weather: WeatherController
var _ground: KeyWestRealityGround
var _player: Node3D
var _volumes: Array[FogVolume] = []
var _materials: Array[ShaderMaterial] = []
var _flakes: Array[GPUParticles3D] = []
var _lifts: Array[SnowLift] = []
var _lift_index: int = 0
var _drift_left: float = 0.0
var _targets: PackedFloat32Array = PackedFloat32Array()
var _levels: PackedFloat32Array = PackedFloat32Array()
var _reselect_left: float = 0.0
var _extinction: float = 0.0


func _ready() -> void:
	top_level = true
	var noise := NoiseTexture3D.new()
	noise.width = 64
	noise.height = 32
	noise.depth = 64
	noise.seamless = true
	var fbm := FastNoiseLite.new()
	fbm.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fbm.frequency = 0.05
	fbm.fractal_octaves = 3
	noise.noise = fbm
	for i: int in range(POOL_SIZE):
		var volume := FogVolume.new()
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.visible = false
		var material := ShaderMaterial.new()
		material.shader = FLOW_SHADER
		material.set_shader_parameter(&"flow_noise", noise)
		volume.material = material
		add_child(volume)
		_volumes.append(volume)
		_materials.append(material)
		var flakes: GPUParticles3D = _build_flakes()
		volume.add_child(flakes)
		_flakes.append(flakes)
	for i: int in range(DRIFT_POOL_SIZE):
		var lift := SnowLift.new()
		add_child(lift)
		_lifts.append(lift)
	_targets.resize(POOL_SIZE)
	_levels.resize(POOL_SIZE)


func on_world_ready(context: WorldContext) -> void:
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_ground = get_parent().find_child("RealityGround", false, false) as KeyWestRealityGround
	_player = context.player


## Blown-snow extinction now, 1/m (0 under the threshold or without snow on the ground).
func get_extinction() -> float:
	return _extinction


## Volumes carrying flow now (debug readout).
func get_active_count() -> int:
	var count: int = 0
	for level: float in _levels:
		count += 1 if level > 0.01 else 0
	return count


func _process(delta: float) -> void:
	if _weather == null or _ground == null or not is_instance_valid(_player):
		return
	var wind: float = _weather.get_wind_speed_mps()
	var target: float = 0.0
	if wind >= WindGusts.blowing_snow_threshold() and _weather.get_snow_cover() >= MIN_COVER:
		target = minf(3.912 / (TABLER_A * pow(wind, -TABLER_B)), MAX_EXTINCTION)
	## Half a second of lag: a gust swells the flow rather than switching it.
	_extinction = lerpf(_extinction, target, 1.0 - exp(-2.0 * delta))
	_reselect_left -= delta
	if _reselect_left <= 0.0:
		_reselect_left = RESELECT_S
		_reselect()
	var along: Vector3 = _wind_along()
	var strength: float = clampf(_extinction / FULL_FLOW_EXTINCTION, 0.0, 1.0)
	for i: int in range(POOL_SIZE):
		_levels[i] = move_toward(_levels[i], _targets[i], delta / FADE_S)
		_volumes[i].visible = _levels[i] > 0.001
		var material: ShaderMaterial = _materials[i]
		material.set_shader_parameter(&"density", _extinction * _levels[i])
		material.set_shader_parameter(&"wind", along * wind)
		_steer_flakes(i, along, wind, strength)
	_drift_left -= delta * strength
	if _drift_left <= 0.0 and strength > 0.05:
		_drift_left = DRIFT_INTERVAL_S * randf_range(0.6, 1.4)
		_spawn_drift(along, wind)


## Puts the pool on the streets near Henry that best channel the wind; others fade out.
func _reselect() -> void:
	var along: Vector3 = _wind_along()
	var wind2 := Vector2(along.x, along.z)
	var centre := Vector2(_player.global_position.x, _player.global_position.z)
	var ranked: Array[Dictionary] = []
	if _extinction > 0.0005:
		for street: Dictionary in _ground.get_wide_streets(centre, REACH_M):
			var a: Vector2 = street["a"]
			var b: Vector2 = street["b"]
			var alignment: float = absf((b - a).normalized().dot(wind2))
			if alignment < MIN_ALIGNMENT:
				continue
			var near: float = Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre)
			street["score"] = alignment * float(street["width"]) / (1.0 + near * 0.05)
			street["alignment"] = alignment
			ranked.append(street)
		ranked.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["score"]) > float(q["score"]))
	var placed: Array[bool] = []
	placed.resize(POOL_SIZE)
	placed.fill(false)
	for street: Dictionary in ranked.slice(0, POOL_SIZE):
		var slot: int = _slot_for(street, placed)
		placed[slot] = true
		_place(slot, street)
	for i: int in range(POOL_SIZE):
		if not placed[i]:
			_targets[i] = 0.0


## The slot already on this street keeps it (no refade); else the dimmest free one.
func _slot_for(street: Dictionary, placed: Array[bool]) -> int:
	var mid: Vector2 = ((street["a"] as Vector2) + (street["b"] as Vector2)) * 0.5
	var best: int = -1
	var best_level: float = INF
	for i: int in range(POOL_SIZE):
		if placed[i]:
			continue
		var at := Vector2(_volumes[i].global_position.x, _volumes[i].global_position.z)
		if _levels[i] > 0.01 and at.distance_to(mid) < 1.0:
			return i
		if _levels[i] < best_level:
			best_level = _levels[i]
			best = i
	return best


func _place(slot: int, street: Dictionary) -> void:
	var a: Vector2 = street["a"]
	var b: Vector2 = street["b"]
	var mid: Vector2 = (a + b) * 0.5
	var volume: FogVolume = _volumes[slot]
	var at := Vector3(mid.x, float(street["y"]) + FLOW_HEIGHT_M * 0.5 - 0.3, mid.y)
	if _levels[slot] > 0.01 and Vector2(volume.global_position.x, volume.global_position.z).distance_to(mid) >= 1.0:
		_targets[slot] = 0.0  # still fading out elsewhere; take it next pass
		return
	var dir: Vector2 = (b - a).normalized()
	volume.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), at)
	## Overhang the segment so neighbouring segments overlap into one flow; widen to the kerbs.
	volume.size = Vector3(a.distance_to(b) + 10.0, FLOW_HEIGHT_M, float(street["width"]) + 6.0)
	_materials[slot].set_shader_parameter(&"scale_height", SNOW_SCALE_HEIGHT_M)
	_targets[slot] = float(street["alignment"])


## Flakes ride the volume: the wind in its frame, as many as the flow is strong.
func _steer_flakes(i: int, along: Vector3, wind: float, strength: float) -> void:
	var flakes: GPUParticles3D = _flakes[i]
	var amount: float = _levels[i] * strength
	flakes.emitting = amount > 0.02
	flakes.amount_ratio = amount
	if not flakes.emitting:
		return
	var volume: FogVolume = _volumes[i]
	var process := flakes.process_material as ParticleProcessMaterial
	process.emission_box_extents = volume.size * Vector3(0.5, 0.25, 0.5)
	process.direction = volume.global_basis.inverse() * (along + Vector3.DOWN * 0.08)
	process.initial_velocity_min = wind * FLAKE_WIND_SHARE * 0.8
	process.initial_velocity_max = wind * FLAKE_WIND_SHARE * 1.1
	flakes.position = Vector3(0.0, -volume.size.y * 0.25, 0.0)


## One ground streamer on an active flow street near Henry, running downwind.
func _spawn_drift(along: Vector3, wind: float) -> void:
	var lit: Array[int] = []
	for i: int in range(POOL_SIZE):
		if _levels[i] > 0.3:
			lit.append(i)
	if lit.is_empty():
		return
	var volume: FogVolume = _volumes[lit[randi() % lit.size()]]
	var local := Vector3(randf_range(-0.5, 0.5) * volume.size.x, 0.0, randf_range(-0.4, 0.4) * volume.size.z)
	var at: Vector3 = volume.global_transform * local
	if Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z).length() > DRIFT_REACH_M:
		return
	var from := Vector3(at.x, _player.global_position.y + 9.0, at.z)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 14.0))
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.8:
		return
	var normal: Vector3 = hit["normal"]
	var surface_along: Vector3 = (along - normal * along.dot(normal)).normalized()
	var lift: SnowLift = _lifts[_lift_index]
	_lift_index = (_lift_index + 1) % _lifts.size()
	lift.global_transform = Transform3D(Basis(surface_along, normal, surface_along.cross(normal)).orthonormalized(),
		(hit["position"] as Vector3) + normal * 0.025)
	lift.lift(wind, _weather.get_snow_cover())


func _build_flakes() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = FLAKES_PER_VOLUME
	particles.amount_ratio = 0.0
	particles.emitting = false
	particles.lifetime = 1.6
	particles.randomness = 0.5
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-40.0, -6.0, -20.0), Vector3(80.0, 14.0, 40.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.spread = 9.0
	process.gravity = Vector3(0.0, -0.6, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 3.0
	process.turbulence_influence_min = 0.04
	process.turbulence_influence_max = 0.12
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	particles.collision_base_size = 0.02
	particles.process_material = process
	particles.draw_pass_1 = SnowfallVFX.build_snowflake_mesh(0.016, 0.0024, 0.0065, 0.0017, true)
	return particles


func _wind_along() -> Vector3:
	var along: Vector3 = _weather.get_wind_direction()
	along.y = 0.0
	return along.normalized() if along.length() > 0.01 else Vector3.RIGHT

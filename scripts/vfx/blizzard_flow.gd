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

var _weather: WeatherController
var _ground: KeyWestRealityGround
var _player: Node3D
var _volumes: Array[FogVolume] = []
var _materials: Array[ShaderMaterial] = []
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
	for i: int in range(POOL_SIZE):
		_levels[i] = move_toward(_levels[i], _targets[i], delta / FADE_S)
		_volumes[i].visible = _levels[i] > 0.001
		var material: ShaderMaterial = _materials[i]
		material.set_shader_parameter(&"density", _extinction * _levels[i])
		material.set_shader_parameter(&"wind", along * wind)


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


func _wind_along() -> Vector3:
	var along: Vector3 = _weather.get_wind_direction()
	along.y = 0.0
	return along.normalized() if along.length() > 0.01 else Vector3.RIGHT

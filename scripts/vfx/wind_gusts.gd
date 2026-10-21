class_name WindGusts
extends Node3D

## Wind streaks and ground drifting snow around Henry while wind is up outdoors.
## Decorative air streaks and transported surface snow share wind authority but
## have separate cadence: drifting snow must not read as one puff per streak.

## Wind below this shows no streaks or ground drift, m/s.
const MIN_WIND_MPS: float = 6.0
const MAX_WIND_MPS: float = 17.0
const POOL_SIZE: int = 8
const LIFT_POOL_SIZE: int = 6

## Seconds between decorative streaks at MIN and MAX wind.
const SLOW_INTERVAL: float = 2.6
const FAST_INTERVAL: float = 0.6
## Seconds between independent ground-drift streamers at MIN and MAX wind.
const DRIFT_SLOW_INTERVAL: float = 1.45
const DRIFT_FAST_INTERVAL: float = 0.28

const BURST_COUNT: int = 5
const BURST_SPACING: float = 0.3

## Spots tried per ground streamer; one is drawn by transport score, so drift smokes off
## crests, scoured ground and lee eaves, and only now and then off plain cover.
const DRIFT_CANDIDATES: int = 10
const COVER_WEIGHT: float = 0.06
const CREST_WEIGHT: float = 3.0
const SCOUR_WEIGHT: float = 1.5
const EAVE_WEIGHT: float = 3.0
## A crest lip drops this much over CREST_PROBE_M downwind, metres.
const CREST_PROBE_M: float = 1.2
const CREST_DROP_M: Vector2 = Vector2(0.02, 0.08)
## A roof's lee eave: the roof is gone or this far lower EAVE_PROBE_M downwind.
const EAVE_PROBE_M: float = 1.5
const EAVE_DROP_M: float = 1.2

var weather: WeatherController
var thermal: ThermalManager
var player: Node3D

var _pool: Array[WindStreak] = []
var _lifts: Array[SnowLift] = []
var _lift_index: int = 0
var _next: float = 0.0
var _drift_next: float = 0.0
var _burst_left: int = 0
var _search_left: float = 0.0


func _ready() -> void:
	top_level = true
	for i: int in range(POOL_SIZE):
		var streak := WindStreak.new()
		streak.autoplay = false
		streak.visible = false
		streak.width = 0.06
		streak.color = Color(0.95, 0.97, 1.0, 0.7)
		streak.finished.connect(streak.hide)
		add_child(streak)
		_pool.append(streak)
	for i: int in range(LIFT_POOL_SIZE):
		var lift := SnowLift.new()
		add_child(lift)
		_lifts.append(lift)


## Several streaks in quick succession: the moment the weather turns.
func burst() -> void:
	_burst_left = BURST_COUNT
	_next = 0.0
	_drift_next = 0.0


func _process(delta: float) -> void:
	if weather == null or player == null:
		_search_left -= delta
		if _search_left <= 0.0:
			_search_left = 1.0
			_find_systems()
		return

	var wind: float = weather.get_wind_speed_mps()
	if thermal != null and thermal.is_sheltered():
		_burst_left = 0
		return
	if _burst_left <= 0 and wind < MIN_WIND_MPS:
		return

	var wind_t: float = clampf(
		inverse_lerp(MIN_WIND_MPS, MAX_WIND_MPS, wind),
		0.0,
		1.0
	)

	_next -= delta
	if _next <= 0.0:
		_spawn_streak(wind)
		if _burst_left > 0:
			_burst_left -= 1
			_next = BURST_SPACING
		else:
			_next = lerpf(SLOW_INTERVAL, FAST_INTERVAL, wind_t) * randf_range(0.7, 1.3)

	# Ground transport has its own cadence. This is what prevents the snow from
	# reading as a smoke puff attached to each decorative wind line.
	_drift_next -= delta
	if _drift_next <= 0.0:
		_spawn_drift(wind)
		_drift_next = lerpf(
			DRIFT_SLOW_INTERVAL,
			DRIFT_FAST_INTERVAL,
			wind_t
		) * randf_range(0.72, 1.28)


## Places one decorative free streak in front of the camera.
func _spawn_streak(wind: float) -> void:
	var streak: WindStreak = null
	for candidate: WindStreak in _pool:
		if not candidate.visible:
			streak = candidate
			break
	var camera: Camera3D = get_viewport().get_camera_3d()
	if streak == null or camera == null:
		return

	var along: Vector3 = _horizontal_wind()
	var ahead: Vector3 = -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP)
	var centre: Vector3 = player.global_position + ahead * randf_range(4.0, 12.0) \
		+ right * randf_range(-5.0, 5.0) + Vector3.UP * randf_range(0.2, 2.2)

	streak.length = randf_range(4.0, 7.0)
	streak.loop_spread = streak.length * randf_range(0.06, 0.09)
	streak.loop_at = randf_range(0.35, 0.6)
	streak.loop_tilt_deg = randf_range(-35.0, 35.0)
	streak.duration = clampf(24.0 / maxf(wind, 1.0), 1.1, 2.4)
	streak.rebuild_path()

	var side: Vector3 = along.cross(Vector3.UP)
	streak.global_basis = Basis(along, Vector3.UP, side)
	streak.global_position = centre - along * streak.length * 0.5
	streak.play()


## Starts one elongated streamer where the wind would lift snow: crests, scour, lee eaves.
func _spawn_drift(wind: float) -> void:
	if weather.get_snow_cover() <= 0.04:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var ahead: Vector3 = -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP)
	var along: Vector3 = _horizontal_wind()
	var spots: Array[Dictionary] = []
	var total: float = 0.0
	for i: int in range(DRIFT_CANDIDATES):
		var spot: Dictionary = _drift_spot(player.global_position + ahead * randf_range(3.5, 11.0)
			+ right * randf_range(-6.0, 6.0), along)
		if spot.is_empty():
			continue
		spots.append(spot)
		total += float(spot["score"])
	if total <= 0.0:
		return
	var pick: float = randf() * total
	var chosen: Dictionary = spots[-1]
	for spot: Dictionary in spots:
		pick -= float(spot["score"])
		if pick <= 0.0:
			chosen = spot
			break

	var normal: Vector3 = chosen["normal"]
	var surface_along: Vector3 = (along - normal * along.dot(normal)).normalized()
	var surface_side: Vector3 = surface_along.cross(normal).normalized()
	var lift: SnowLift = _lifts[_lift_index]
	_lift_index = (_lift_index + 1) % _lifts.size()
	## Off a lip the plume starts at the edge and runs downwind of it.
	var lead: float = lift.streamer_length * 0.5 if bool(chosen["lip"]) else 0.0
	lift.global_transform = Transform3D(
		Basis(surface_along, normal, surface_side).orthonormalized(),
		(chosen["position"] as Vector3) + normal * 0.025 + surface_along * lead
	)
	lift.lift(wind, weather.get_snow_cover())


## Ground under `at` with its transport score, or empty where nothing could drift.
func _drift_spot(at: Vector3, along: Vector3) -> Dictionary:
	var hit: Dictionary = _ground_hit(at)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit["normal"]
	var position: Vector3 = hit["position"]
	if normal.dot(Vector3.UP) < 0.55:
		return {}
	var field: SnowField = SnowShell.active.field if is_instance_valid(SnowShell.active) else null
	var xz := Vector2(position.x, position.z)
	var wind_xz := Vector2(along.x, along.z)
	if field != null and field.is_building(xz):
		var below: Dictionary = _ground_hit(position + along * EAVE_PROBE_M)
		var eave: bool = below.is_empty() or (below["position"] as Vector3).y < position.y - EAVE_DROP_M
		return {"position": position, "normal": normal, "lip": eave,
			"score": COVER_WEIGHT + (EAVE_WEIGHT if eave else 0.0)}
	if field == null:
		return {"position": position, "normal": normal, "lip": false, "score": COVER_WEIGHT}
	## Fresh snow lifts; a wind crust holds (field softness 0.4 crust to 1.0 loose).
	var loose: float = clampf((field.get_softness(xz.x, xz.y) - 0.4) / 0.6, 0.0, 1.0)
	var top: float = field.get_snow_top(xz.x, xz.y)
	var lee: float = field.get_snow_top(xz.x + wind_xz.x * CREST_PROBE_M, xz.y + wind_xz.y * CREST_PROBE_M)
	var windward: float = field.get_snow_top(xz.x - wind_xz.x * CREST_PROBE_M, xz.y - wind_xz.y * CREST_PROBE_M)
	var crest: float = 0.0
	if is_finite(top) and is_finite(lee) and is_finite(windward) and windward <= top + 0.01:
		crest = smoothstep(CREST_DROP_M.x, CREST_DROP_M.y, top - lee)
	## The baked wind map scours (factor under 1) where flow speeds up: that snow is moving.
	var scour: float = clampf((1.0 - field.wind_factor(xz)) * 2.0, 0.0, 1.0)
	return {"position": position, "normal": normal, "lip": crest > 0.5,
		"score": loose * (COVER_WEIGHT + CREST_WEIGHT * crest + SCOUR_WEIGHT * scour)}


func _ground_hit(at: Vector3) -> Dictionary:
	var above: Vector3 = Vector3(at.x, player.global_position.y + 9.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(above, above + Vector3.DOWN * 14.0)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _horizontal_wind() -> Vector3:
	var along: Vector3 = weather.get_wind_direction()
	along.y = 0.0
	return along.normalized() if along.length() > 0.01 else Vector3.RIGHT


func _find_systems() -> void:
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if weather == null and node is WeatherController and not (node as WeatherController).profiles.is_empty():
			weather = node
		elif thermal == null and node is ThermalManager:
			thermal = node
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node3D

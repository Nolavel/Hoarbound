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

## 10 m wind that starts blowing snow, fresh to crusted (Li & Pomeroy 1997: ~4–11 m/s, dry snow).
const BLOWING_THRESHOLD_MPS: Vector2 = Vector2(5.0, 10.0)
var weather: WeatherController
var thermal: ThermalManager
var player: Node3D

var _pool: Array[WindStreak] = []
var _lifts: Array[SnowLift] = []
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


## Streaks and ground streamers on screen now (debug readout).
func get_active_counts() -> Vector2i:
	var streaks: int = 0
	for streak: WindStreak in _pool:
		streaks += 1 if streak.visible else 0
	var lifts: int = 0
	for lift: SnowLift in _lifts:
		lifts += 1 if lift.is_active() else 0
	return Vector2i(streaks, lifts)


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


## Starts one ground streamer whose sweep crosses the screen ahead of Henry.
func _spawn_drift(wind: float) -> void:
	if weather.get_snow_cover() <= 0.04:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var lift: SnowLift = _free_lift()
	if camera == null or lift == null:
		return
	var ahead: Vector3 = -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP)
	var spot: Vector3 = player.global_position + ahead * randf_range(5.0, 14.0) + right * randf_range(-6.0, 6.0)
	lift.launch_through(spot, _horizontal_wind(), wind, weather.get_snow_cover(), camera)


func _free_lift() -> SnowLift:
	for lift: SnowLift in _lifts:
		if not lift.is_active():
			return lift
	return null


## Wind that lifts snow: fresh snow goes first, a bonded crust holds to ~10 m/s (Li & Pomeroy 1997).
static func blowing_snow_threshold() -> float:
	var field: SnowField = SnowShell.active.field if is_instance_valid(SnowShell.active) else null
	var firmness: float = field.firmness if field != null else 0.5
	return lerpf(BLOWING_THRESHOLD_MPS.x, BLOWING_THRESHOLD_MPS.y, clampf(firmness, 0.0, 1.0))


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

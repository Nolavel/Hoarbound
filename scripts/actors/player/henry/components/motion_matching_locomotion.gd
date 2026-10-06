class_name MotionMatchingLocomotion
extends Node

## Feature-flagged Motion Matching for Henry's plain locomotion (#202). The body
## stays authoritative; actions, carry, sit, crouch, air and sprint keep the tree.

## Percentile of database root speeds treated as covered.
const COVERAGE_PERCENTILE := 0.99
## A body jump longer than this in one tick is a teleport: matching re-anchors.
const TELEPORT_DISTANCE := 1.0
## Airtime up to this (MovementController's start hop) keeps matching.
const AIR_GRACE_SECONDS := 0.2
## After real airtime the tree's landing plays before matching returns.
const LANDING_SECONDS := 0.4

## Off by default: production locomotion is untouched until the author opts in.
## The HOARBOUND_MOTION_MATCHING=1 environment variable also switches it on.
@export var enabled: bool = false
## Seconds to hand the pose between the AnimationTree and Motion Matching.
@export_range(0.05, 1.0, 0.05) var handover_seconds: float = 0.25
## Body speed share above the database's covered speed at which the tree returns.
@export_range(0.0, 0.5, 0.05) var coverage_margin: float = 0.1
## Standing still longer than this hands idle to the tree's loop (0 keeps it): the
## CMU idle is short ranges, the tree's Idle_Loop stays still for minutes.
@export_range(0.0, 5.0, 0.1) var idle_to_tree_seconds: float = 0.6

@export_group("Body dynamics")
## Opt-in, changes game feel: retunes the body's acceleration and turning toward
## the captured data (Holden, Code vs Data Driven Displacement). Author's call.
@export var data_matched_body: bool = false
## Data p95 is about 1.8 m/s^2 either way; production is 12 / 18 m/s^2.
@export var data_accel_m_s2: float = 3.0
@export var data_decel_m_s2: float = 3.5
## Player.turn_rate while matched; production 10 starts a 90-degree turn at 15 rad/s.
@export var data_turn_rate: float = 4.0

var debug_view: MotionMatchingDebugView

var _player: Player
var _visual: HenryUALAnimation
var _movement: MovementController
var _controller: MotionMatchingDatabasePlaybackController
var _tree_callback_mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _visual_rest := Transform3D.IDENTITY
var _coverage_speed := 0.0
var _weight := 0.0
var _active := false
var _ready_state := "disabled"
var _handovers := 0
var _active_seconds := 0.0
var _total_seconds := 0.0
var _last_body_position := Vector3.ZERO
var _air_time := 0.0
var _production_dynamics: Array[float] = []
var _landing_left := 0.0
var _still_time := 0.0


func _ready() -> void:
	set_physics_process(false)
	if OS.get_environment("HOARBOUND_MOTION_MATCHING") == "1":
		enabled = true
	if OS.get_environment("HOARBOUND_MM_DATA_BODY") == "1":
		data_matched_body = true
	if enabled:
		# After HenryUALAnimation has built its AnimationTree.
		_start.call_deferred()


## Why Motion Matching is or is not running, for logs and the debug overlay.
func get_state() -> String:
	return _ready_state


func get_weight() -> float:
	return _weight


func get_controller() -> MotionMatchingDatabasePlaybackController:
	return _controller


func get_report() -> Dictionary:
	var report := {
		"enabled": enabled,
		"state": _ready_state,
		"coverage_speed_m_s": _coverage_speed,
		"handovers": _handovers,
		"active_fraction": 0.0 if _total_seconds <= 0.0 else _active_seconds / _total_seconds,
	}
	if _controller != null:
		report["playback"] = _controller.get_report()
	return report


func _start() -> void:
	_player = get_parent() as Player
	_visual = _player.animation_component if _player != null else null
	_movement = _player.movement if _player != null else null
	if _visual == null or _visual.skeleton == null or _visual.animation_tree == null or _movement == null:
		_ready_state = "unavailable: Player wiring"
		push_warning("MotionMatchingLocomotion: %s." % _ready_state)
		return
	var build: Dictionary = MotionMatchingDatabaseBuilder.new().build(30.0)
	if not bool(build.get("ok", false)):
		_ready_state = "unavailable: %s" % String(build.get("error", "no database"))
		push_warning("MotionMatchingLocomotion: %s; the AnimationTree keeps locomotion." % _ready_state)
		return
	var database := build["database"] as MotionDatabase
	_coverage_speed = _covered_speed(database)
	_controller = MotionMatchingDatabasePlaybackController.new()
	_controller.drive_body = false
	_controller.write_gaze_rest = false
	_visual_rest = _visual.transform
	if not _controller.setup(database, _visual.skeleton, _player, _visual, debug_view, 0):
		_ready_state = "unavailable: playback setup"
		push_warning("MotionMatchingLocomotion: %s." % _ready_state)
		_controller = null
		return
	_visual.transform = _visual_rest
	# The tree is advanced here, every physics tick, right before the matched pose.
	_tree_callback_mode = _visual.animation_tree.callback_mode_process
	_visual.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if data_matched_body:
		_production_dynamics = [_movement.accel_rate, _movement.decel_rate, _player.turn_rate]
		# MovementController scales its rates by max(walk_speed, 1).
		var scale := maxf(_movement.walk_speed, 1.0)
		_movement.accel_rate = data_accel_m_s2 / scale
		_movement.decel_rate = data_decel_m_s2 / scale
		_player.turn_rate = data_turn_rate
	_ready_state = "ready (covers <= %.2f m/s%s)" % [_coverage_speed, ", data-matched body" if data_matched_body else ""]
	print("[MOTION_MATCHING_LOCOMOTION] %s, %d samples" % [_ready_state, database.get_sample_count()])
	set_physics_process(true)


func _exit_tree() -> void:
	if is_instance_valid(_visual) and _visual.animation_tree != null and _controller != null:
		_visual.animation_tree.callback_mode_process = _tree_callback_mode
	if _production_dynamics.size() == 3 and is_instance_valid(_movement) and is_instance_valid(_player):
		_movement.accel_rate = _production_dynamics[0]
		_movement.decel_rate = _production_dynamics[1]
		_player.turn_rate = _production_dynamics[2]


func _physics_process(delta: float) -> void:
	_visual.animation_tree.advance(delta)
	_total_seconds += delta
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var limit := _coverage_speed * (1.0 + (coverage_margin if _active else 0.0))
	if _player.is_on_floor():
		if _air_time > AIR_GRACE_SECONDS:
			_landing_left = LANDING_SECONDS
		_air_time = 0.0
	else:
		_air_time += delta
	_landing_left = maxf(0.0, _landing_left - delta)
	var grounded := _air_time <= AIR_GRACE_SECONDS and _landing_left <= 0.0
	var still := speed < 0.05 and _movement.get_target_velocity().length() < 0.01
	_still_time = _still_time + delta if still else 0.0
	var standing := idle_to_tree_seconds > 0.0 and _still_time > idle_to_tree_seconds
	var wanted := grounded and not standing and not _player.is_crouching() and speed <= limit \
		and _visual.is_plain_locomotion()
	_weight = move_toward(_weight, 1.0 if wanted else 0.0, delta / handover_seconds)
	var teleported := _player.global_position.distance_to(_last_body_position) > TELEPORT_DISTANCE
	_last_body_position = _player.global_position
	if _weight <= 0.0:
		if _active:
			_active = false
			_visual.transform = _visual_rest
			_visual.reset_physics_interpolation()
		_controller.observe()
		return
	if not _active or teleported:
		if not _active:
			_handovers += 1
		_active = true
		_visual.transform = _visual_rest
		_controller.restart()
	_active_seconds += delta
	_controller.weight = smoothstep(0.0, 1.0, _weight)
	_controller.follow(delta, _predict(), _movement.get_target_velocity())


## The body's own future at the matcher horizons: MovementController's
## constant-rate velocity approach and Player's exponential turn.
func _predict() -> Dictionary:
	var target := _movement.get_target_velocity()
	var rate := maxf(_movement.get_velocity_rate(), 0.001)  # INF while movement is locked
	var start := Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var forward := -_player.global_transform.basis.z
	var yaw := atan2(forward.x, forward.z)
	var goal_yaw := yaw if target.length() < 0.05 else atan2(target.x, target.z)
	var change := target - velocity
	var ramp := change.length() / rate
	var direction := change.normalized() if change.length() > 0.0001 else Vector3.ZERO
	var positions := PackedVector3Array()
	var forwards := PackedVector3Array()
	for horizon in MotionCharacterSimulation.FUTURE_HORIZONS:
		var t := float(horizon)
		var a := minf(t, ramp)
		var position := start + velocity * a + target * (t - a)
		if a > 0.0:
			position += direction * (0.5 * rate * a * a)
		positions.append(position)
		var turned := goal_yaw + wrapf(yaw - goal_yaw, -PI, PI) * exp(-_player.turn_rate * t)
		forwards.append(Vector3(sin(turned), 0.0, cos(turned)))
	return {"positions": positions, "forwards": forwards}


func _covered_speed(database: MotionDatabase) -> float:
	var speeds := PackedFloat32Array()
	for sample in range(database.get_sample_count()):
		var base := sample * database.feature_count
		speeds.append(Vector2(database.features[base], database.features[base + 1]).length())
	speeds.sort()
	return speeds[int(float(speeds.size() - 1) * COVERAGE_PERCENTILE)] if not speeds.is_empty() else 0.0

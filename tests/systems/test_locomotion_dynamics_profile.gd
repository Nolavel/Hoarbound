extends SceneTree

## MovementController owns its tuning: a requested dynamics profile governs only
## grounded walking, and Motion Matching asks for one without writing any rates.
## Run: godot --headless --script tests/systems/test_locomotion_dynamics_profile.gd

const PROFILE_ID: StringName = &"data_matched"
## Allowed relative error of a measured acceleration or braking rate.
const RATE_TOLERANCE: float = 0.05

var _failures: int = 0
var _player: Player


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)

	await _check_contract()
	await _check_motion_matching()
	if _failures > 0:
		push_error("dynamics profile: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dynamics profile: all checks passed")
	quit(0)


func _check_contract() -> void:
	await _spawn(false)
	var movement := _player.movement
	var production := Vector2(movement.accel_rate, movement.decel_rate) * maxf(movement.walk_speed, 1.0)
	var profile := _find_profile(movement)
	_check(profile != null, "movement has no '%s' profile" % PROFILE_ID)
	if profile == null:
		return
	var requester := Node.new()
	_check(not movement.request_dynamics_profile(&"missing", requester), "an unknown profile was accepted")

	var rates := await _walk_rates()
	print("dynamics profile: production accel %.2f, braking %.2f m/s^2" % [rates.x, rates.y])
	_check_rates(rates, production, "without a request")

	_check(movement.request_dynamics_profile(PROFILE_ID, requester), "the profile request was refused")
	rates = await _walk_rates()
	print("dynamics profile: requested accel %.2f, braking %.2f m/s^2" % [rates.x, rates.y])
	_check_rates(rates, Vector2(profile.walk_accel_m_s2, profile.walk_decel_m_s2), "with the profile")
	await _ticks(10, &"move_forward")
	_check(movement.get_applied_dynamics_profile() == PROFILE_ID, "the profile does not govern walking")
	_check(is_equal_approx(movement.get_turn_rate(_player.turn_rate), profile.turn_rate), "walking turns at the base rate")
	_check(is_equal_approx(movement.get_braking_rate(), profile.walk_decel_m_s2), "braking rate ignores the profile")

	_check(await _applied_while(&"sprint"), "the profile governs sprinting")
	_check(await _applied_while(&"crouch"), "the profile governs crouching")
	_player.global_position.y += 3.0
	await _ticks(2, &"")
	_check(not _player.is_on_floor() and movement.get_applied_dynamics_profile() == &"", "the profile governs the air")
	_check(is_equal_approx(movement.get_turn_rate(_player.turn_rate), _player.turn_rate), "the air turns at the profile rate")
	await _ticks(90, &"")

	var stranger := Node.new()
	movement.release_dynamics_profile(stranger)
	stranger.free()
	await _ticks(10, &"move_forward")
	_check(movement.get_applied_dynamics_profile() == PROFILE_ID, "another node released the request")
	requester.free()
	await _ticks(2, &"move_forward")
	_check(movement.get_applied_dynamics_profile() == &"", "a freed requester still holds the profile")
	rates = await _walk_rates()
	_check_rates(rates, production, "after the requester left")


func _check_motion_matching() -> void:
	await _spawn(true)
	var movement := _player.movement
	var locomotion := _player.get_node(^"MotionMatchingLocomotion") as MotionMatchingLocomotion
	if not locomotion.get_state().begins_with("ready"):
		print("dynamics profile: motion matching skipped (%s)" % locomotion.get_state())
		return
	var tuning := [movement.accel_rate, movement.decel_rate, _player.turn_rate]
	var walked := 0
	for _i: int in range(120):
		await _ticks(1, &"move_forward")
		walked += 1 if movement.get_applied_dynamics_profile() == PROFILE_ID else 0
	print("dynamics profile: matched walking ran %d of 120 ticks on the profile" % walked)
	_check(walked > 90, "matched walking does not request the profile")
	_check(await _applied_while(&"sprint"), "matched sprinting runs on the profile")
	_check([movement.accel_rate, movement.decel_rate, _player.turn_rate] == tuning, "motion matching wrote movement tuning")
	locomotion.queue_free()
	await _ticks(3, &"move_forward")
	_check(movement.get_applied_dynamics_profile() == &"", "removed motion matching still holds the profile")


func _spawn(motion_matching: bool) -> void:
	if is_instance_valid(_player):
		_player.queue_free()
		await physics_frame
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	(_player.get_node(^"MotionMatchingLocomotion") as MotionMatchingLocomotion).enabled = motion_matching
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.rotation = Vector3.ZERO
	await _ticks(30, &"")


## Walks off from a standstill, then stops; returns the peak planar acceleration
## and braking, m/s^2.
func _walk_rates() -> Vector2:
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(30, &"")
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var peaks := Vector2.ZERO
	var last: float = 0.0
	for tick: int in range(120):
		await _ticks(1, &"move_forward" if tick < 60 else &"")
		var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		var change: float = (speed - last) / delta
		peaks = Vector2(maxf(peaks.x, change), maxf(peaks.y, -change))
		last = speed
	return peaks


## Walks into `action` for 1.5 s; true if the walking profile stayed off once it
## took hold and the turn rate stayed the player's own.
func _applied_while(action: StringName) -> bool:
	var movement := _player.movement
	var clean := true
	Input.action_press(action)
	for tick: int in range(90):
		await _ticks(1, &"move_forward")
		var held: bool = movement.get_sprint_blend() >= 0.01 if action == &"sprint" else _player.is_crouching()
		if tick >= 30 and held:
			clean = clean and movement.get_applied_dynamics_profile() == &""
			clean = clean and is_equal_approx(movement.get_turn_rate(_player.turn_rate), _player.turn_rate)
	Input.action_release(action)
	await _ticks(120, &"")
	return clean


func _ticks(count: int, action: StringName) -> void:
	if action != &"":
		Input.action_press(action)
	for _i: int in range(count):
		await physics_frame
	if action != &"":
		Input.action_release(action)


func _find_profile(movement: MovementController) -> LocomotionDynamicsProfile:
	for profile: LocomotionDynamicsProfile in movement.dynamics_profiles:
		if profile != null and profile.id == PROFILE_ID:
			return profile
	return null


func _check_rates(measured: Vector2, expected: Vector2, label: String) -> void:
	_check(absf(measured.x - expected.x) <= expected.x * RATE_TOLERANCE,
		"%s: acceleration %.2f, expected %.2f m/s^2" % [label, measured.x, expected.x])
	_check(absf(measured.y - expected.y) <= expected.y * RATE_TOLERANCE,
		"%s: braking %.2f, expected %.2f m/s^2" % [label, measured.y, expected.y])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("dynamics profile: " + message)

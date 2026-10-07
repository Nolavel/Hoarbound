extends SceneTree

## Sprint build-up and top speed follow Henry's state: rested and fresh he
## sprints as before, exhausted he builds up slower, winded his top speed fades.
## Run: godot --headless --script tests/systems/test_sprint_fatigue.gd

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
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	var movement := _player.movement
	var fatigue := _player.get_node(^"FatigueComponent") as FatigueComponent

	var rested := await _sprint(1.0, 1.0)
	var exhausted := await _sprint(0.0, 1.0)
	var winded := await _sprint(1.0, 0.1)
	print("sprint fatigue: rested 90%% after %.2f s, top %.2f m/s" % [rested[0], rested[1]])
	print("sprint fatigue: exhausted 90%% after %.2f s, top %.2f m/s" % [exhausted[0], exhausted[1]])
	print("sprint fatigue: winded top %.2f m/s" % winded[1])
	var full: float = movement.sprint_speed
	_check(absf(rested[1] - full) < 0.1, "rested sprint does not reach %.2f m/s" % full)
	_check(exhausted[0] > rested[0] * 1.6, "exhaustion does not slow the build-up")
	_check(winded[1] < full * 0.75 and winded[1] > movement.walk_speed * 1.2, "a winded sprint is not a laboured jog")
	_check(is_equal_approx(movement.get_sprint_ramp_factor(), lerpf(movement.exhausted_sprint_ramp_factor, 1.0, fatigue.progress())),
		"ramp factor does not follow energy")
	if _failures > 0:
		push_error("sprint fatigue: %d check(s) failed" % _failures)
		quit(1)
		return
	print("sprint fatigue: all checks passed")
	quit(0)


## Sprints from a standstill for 8 s at the given energy and stamina shares;
## returns [seconds to 90% of the sprint speed, top speed].
func _sprint(energy: float, stamina_share: float) -> Array:
	var movement := _player.movement
	var fatigue := _player.get_node(^"FatigueComponent") as FatigueComponent
	var stamina := movement.stamina_manager
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	_player.global_position = Vector3(0.0, 1.0, 150.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	# Start each run from a standstill with the last sprint fully worn off.
	for _i: int in range(600):
		await physics_frame
		if movement.get_sprint_blend() < 0.001 and _player.velocity.length() < 0.05:
			break
	fatigue.current_energy = energy * fatigue.max_energy
	stamina.current_stamina = stamina_share * stamina.max_stamina
	# Hold the tank steady so only the shares under test vary.
	var deplete: float = stamina.stamina_deplete_rate
	stamina.stamina_deplete_rate = 0.000001
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var reached: float = -1.0
	var top: float = 0.0
	for tick: int in range(480):
		await physics_frame
		var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		top = maxf(top, speed)
		if reached < 0.0 and speed >= movement.sprint_speed * 0.9:
			reached = float(tick) / float(Engine.physics_ticks_per_second)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	stamina.stamina_deplete_rate = deplete
	return [reached if reached >= 0.0 else INF, top]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("sprint fatigue: " + message)

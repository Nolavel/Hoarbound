extends SceneTree

## Stamina recovery: once emptied, sprint waits for breath to reach the threshold (no stutter);
## breath returns after a short pause, eases in, and comes back faster standing than walking.
## Run: godot --headless --script tests/systems/test_stamina_recovery.gd

const DT: float = 1.0 / 60.0

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_empty_tank_waits_for_threshold()
	_test_recovery_eases_in_after_a_short_pause()
	_test_standing_recovers_faster_than_walking()
	_test_jump_resets_the_pause()
	if _failures > 0:
		push_error("stamina recovery: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("stamina recovery: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("stamina recovery: " + message)


func _manager() -> StaminaManager:
	var manager := StaminaManager.new()
	root.add_child(manager)
	manager.set_process(false)
	return manager


func _run(manager: StaminaManager, seconds: float) -> void:
	for _i: int in range(int(round(seconds / DT))):
		manager._update_stamina(DT)


func _test_empty_tank_waits_for_threshold() -> void:
	var m := _manager()
	m.start_consuming_stamina()
	_run(m, m.max_stamina / m.stamina_deplete_rate + 0.5)
	_check(m.current_stamina == 0.0 and m.is_exhausted(), "a full sprint did not run the tank dry")
	m.stop_consuming_stamina()
	var allowed_at: float = -1.0
	var stutter: int = 0
	var was_allowed: bool = false
	for i: int in range(60 * 30):
		m._update_stamina(DT)
		var allowed: bool = m.is_sprint_allowed()
		if allowed and allowed_at < 0.0:
			allowed_at = m.get_stamina_ratio()
		if allowed != was_allowed:
			stutter += 1
		was_allowed = allowed
	_check(allowed_at >= m.exhausted_until_ratio - 0.01, "sprint came back at %.3f, before the %.2f threshold" % [allowed_at, m.exhausted_until_ratio])
	_check(stutter == 1, "sprint permission flipped %d times while recovering" % stutter)
	m.free()


func _test_recovery_eases_in_after_a_short_pause() -> void:
	var m := _manager()
	m.current_stamina = 50.0
	_run(m, m.stamina_recover_delay * 0.9)
	_check(is_equal_approx(m.current_stamina, 50.0), "breath came back during the pause")
	_run(m, 0.2)
	var early: float = m.current_stamina - 50.0
	var before: float = m.current_stamina
	_run(m, 0.2)
	var later: float = m.current_stamina - before
	_check(early > 0.0 and later > early * 1.5, "recovery did not ease in (%.3f then %.3f)" % [early, later])
	_check(m.stamina_recover_delay <= 1.5, "the pause before recovery is %.1f s: too long to read" % m.stamina_recover_delay)
	m.free()


func _test_standing_recovers_faster_than_walking() -> void:
	var gained: Array[float] = []
	for share: float in [1.0, 0.55, 0.0]:
		var m := _manager()
		m.current_stamina = 0.0
		m.recovery_scale = share
		_run(m, 6.0)
		gained.append(m.current_stamina)
		m.free()
	_check(gained[0] > gained[1] * 1.5, "standing (%.1f) does not recover clearly faster than walking (%.1f)" % [gained[0], gained[1]])
	_check(gained[2] == 0.0, "breath came back in the air")
	var m := _manager()
	m.current_stamina = 0.0
	_run(m, 14.0)
	_check(m.get_stamina_ratio() > 0.99, "standing still does not refill an empty tank within 14 s (%.2f)" % m.get_stamina_ratio())
	m.free()


func _test_jump_resets_the_pause() -> void:
	var m := _manager()
	m.current_stamina = 50.0
	_run(m, m.stamina_recover_delay + 1.0)
	var resting: float = m.current_stamina
	_check(m.try_jump(), "a jump with stamina left was refused")
	var after_jump: float = m.current_stamina
	_run(m, m.stamina_recover_delay * 0.9)
	_check(is_equal_approx(m.current_stamina, after_jump) and after_jump < resting, "a jump did not restart the pause")
	m.free()

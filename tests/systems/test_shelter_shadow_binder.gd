extends SceneTree

## Runtime state contract, without an expensive render run.
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var binder := ShelterShadowBinder.new()
	root.add_child(binder)
	_check(is_zero_approx(binder.get_blend()), "outdoor is not the starting state")
	binder._on_sheltered_changed(true)
	binder._process(0.12)
	_check(binder.get_blend() > 0.0 and binder.get_blend() < 1.0, "interior state snapped at doorway")
	binder._process(0.12)
	_check(is_equal_approx(binder.get_blend(), 1.0), "interior mode did not reach full strength")
	binder._on_sheltered_changed(false)
	binder._process(0.24)
	_check(is_zero_approx(binder.get_blend()), "outdoor state was not restored")
	binder.free()
	if _failures > 0:
		push_error("shelter shadow binder: %d failure(s)" % _failures)
		quit(1)
	else:
		print("shelter shadow binder: state transitions passed")
		quit(0)


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	push_error(message)

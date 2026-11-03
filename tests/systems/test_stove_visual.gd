extends SceneTree

## Stove (#42): one log shows per fuel unit left, the door slots glow only while
## the fire burns, and a cold empty stove shows no logs.
## Run: godot --headless --script tests/systems/test_stove_visual.gd

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var stove := HeatSource.new()
		stove.starts_burning = false
		stove.burn_duration_h = 6.0
		stove.hours_per_fuel_unit = 2.0
		stove.warmup_seconds = 20.0
		var room_light := OmniLight3D.new()
		stove.add_child(room_light)
		stove.flame_light = room_light
		var visual := StoveVisual.new()
		stove.add_child(visual)
		root.add_child(stove)
		var ring_a := visual.get_node_or_null(^"CookRingA") as MeshInstance3D
		var ring_b := visual.get_node_or_null(^"CookRingB") as MeshInstance3D
		_check(ring_a != null and ring_b != null, "the cooktop has fewer than two plates")
		if ring_a != null and ring_b != null:
			_check(is_equal_approx(ring_a.position.z, -StoveVisual.COOK_RING_Z)
				and is_equal_approx(ring_b.position.z, StoveVisual.COOK_RING_Z),
				"the cooking plates are not spaced symmetrically")
		_check(visual.get_visible_log_count() == 0 and not visual.is_glowing(), "a cold empty stove shows logs or glow")

		_check(stove.add_logs(1), "cold stove would not accept a log")
		_check(stove.start_loaded_fire(), "loaded stove would not start its warm-up")
		visual._process(0.016)
		_check(stove.get_intensity() <= 0.1, "test no longer exercises the low thermal warm-up")
		_check(room_light.visible, "successful ignition did not reveal the room light")
		var catch_room: float = visual.get_room_light_energy()
		_check(catch_room > 0.4, "a caught fire leaves the room dark (%.2f)" % catch_room)
		_check(catch_room < StoveVisual.ROOM_LIGHT_ENERGY * 0.5, "the room is at full light at the catch (%.2f)" % catch_room)
		_check(visual.get_firebox_light_energy() > 0.5, "firebox glow is too weak at ignition")

		stove.ignite()
		for i: int in range(20):
			visual._process(0.1)
		var burn_room: float = visual.get_room_light_energy()
		_check(burn_room > StoveVisual.ROOM_LIGHT_ENERGY * 0.85, "the warmed fire never reaches its nominal burn (%.2f)" % burn_room)
		_check(visual.get_visible_log_count() == 3, "a full 6 h load does not show 3 logs (%d)" % visual.get_visible_log_count())
		_check(visual.is_glowing(), "a burning stove does not glow")
		stove.restore_fuel(1.5, true)
		_check(visual.get_visible_log_count() == 1, "1.5 h left does not show 1 log")
		# A committed new log must not reset an existing burning log's visual age.
		visual._process(1.0)
		var older_slot: int = visual._active_slots[0]
		var older_stage: float = float(visual._logs[older_slot].burn_progress)
		_check(stove.add_logs(1), "burning stove refused a real refuel")
		_check(visual.get_visible_log_count() == stove.get_loaded_log_count(), "refuel visual count disagrees with HeatSource")
		_check(visual._active_slots.has(older_slot), "refuel replaced the older log")
		_check(float(visual._logs[older_slot].burn_progress) >= older_stage, "refuel reset the older log")
		stove.advance_fuel(stove.get_remaining_hours())
		_check(visual.get_visible_log_count() == 0, "spent fuel leaves a log visible")
		visual._process(0.1)
		_check(visual._embers.emission_enabled, "flame extinction lost the residual coals immediately")
		visual._process(6.1)
		_check(visual._embers.emission_energy_multiplier <= 0.001, "residual coals never cool")
		stove.extinguish()
		_check(not visual.is_glowing(), "an extinguished stove still glows")
		print("test_stove_visual: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)

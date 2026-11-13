extends SceneTree

## Covers InputTape and its recorder: round trip through JSON, which actions are recorded,
## press/release at the right frame, echoes and developer keys ignored.
## Run: godot --headless --script tests/systems/test_input_tape.gd

const RECORDER: String = "res://scenes/ui/debug/input_tape_recorder.tscn"

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_round_trip()
	_test_recorder_filters_and_frames()
	_test_menus_and_dev_keys_are_not_tracked()
	if _failures > 0:
		push_error("input_tape: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("input_tape: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("input_tape: %s" % message)


func _test_round_trip() -> void:
	var tape := InputTape.new()
	tape.scene = "res://tests/scenes/TestScene.tscn"
	tape.start_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(1.0, 2.0, 3.0))
	tape.start_look = Vector2(0.7, -10.0)
	tape.events = [[5, "move_forward", true, 1.0], [40, "move_forward", false, 0.0]]
	tape.looks = [[0, 0.7, -10.0], [12, 0.9, -11.0]]
	var path: String = OS.get_temp_dir().path_join("hb_tape_test.json")
	_check(tape.save(path) == OK, "tape did not save")
	var back: InputTape = InputTape.load_file(path)
	_check(back != null, "tape did not load")
	if back == null:
		return
	_check(back.scene == tape.scene, "scene lost")
	_check(back.start_transform.origin.is_equal_approx(tape.start_transform.origin), "start origin lost")
	_check(is_equal_approx(back.start_transform.basis.get_euler().y, 0.7), "start yaw lost")
	_check(back.length_frames() == 40, "length %d, expected 40" % back.length_frames())
	_check(InputTape.from_dict({"version": 99}) == null, "a future version was accepted")


func _test_recorder_filters_and_frames() -> void:
	var player := Node3D.new()
	player.add_to_group(&"player")
	root.add_child(player)
	var recorder := (load(RECORDER) as PackedScene).instantiate() as InputTapeRecorder
	root.add_child(recorder)
	_check(recorder.start(), "recording did not start with a player present")
	recorder.record_event(_action(&"move_forward", true), 3)
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_W
	echo.pressed = true
	echo.echo = true
	recorder.record_event(echo, 4)
	recorder.record_event(_action(&"pause", true), 5)
	recorder.record_event(_action(&"dev_input_tape", true), 6)
	recorder.record_event(_action(&"move_forward", false), 9)
	var tape: InputTape = recorder.get(&"_tape")
	_check(tape.events.size() == 2, "expected press and release only, got %s" % str(tape.events))
	if tape.events.size() == 2:
		_check(int(tape.events[0][0]) == 3 and bool(tape.events[0][2]), "press not at frame 3")
		_check(int(tape.events[1][0]) == 9 and not bool(tape.events[1][2]), "release not at frame 9")
	var saved: String = recorder.stop()
	_check(saved != "" and FileAccess.file_exists(saved), "stop did not write the tape")
	_check(not recorder.is_recording(), "still recording after stop")
	root.remove_child(recorder)
	recorder.free()
	root.remove_child(player)
	player.free()


func _test_menus_and_dev_keys_are_not_tracked() -> void:
	var tracked: Array[StringName] = InputTape.tracked_actions()
	_check(tracked.has(&"move_forward") and tracked.has(&"interact"), "gameplay actions are not tracked")
	for action: StringName in tracked:
		_check(not String(action).begins_with("ui_") and not String(action).begins_with("dev_"), "%s is tracked" % action)
	_check(not tracked.has(&"pause"), "pause is tracked: a replay would stop in the menu")


func _action(name: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	return event

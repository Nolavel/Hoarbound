extends SceneTree

## The key hints panel leaves the tree before the world's other nodes (quit to title); a mode
## change sent then (the stove ritual restoring ON_FOOT) must not rebuild the detached panel.
## Run: godot --headless --script tests/systems/test_key_hints_teardown.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state == null:
		push_error("key hints teardown: PlayerState autoload missing")
		quit(1)
		return
	var on_foot: int = int(state.get_script().get_script_constant_map()["Mode"]["ON_FOOT"])
	var working: int = int(state.get_script().get_script_constant_map()["Mode"]["WORKING"])
	var panel: Control = (load("res://scenes/ui/hud/input_hints/key_hints_panel.tscn") as PackedScene).instantiate() as Control
	root.add_child(panel)
	await process_frame
	state.call(&"set_mode", working)
	await process_frame
	root.remove_child(panel)
	var before: Variant = panel.get(&"_shown_row_keys")
	state.call(&"set_mode", on_foot)
	_check(panel.get(&"_shown_row_keys") == before, "a mode change rebuilt the panel outside the tree")
	panel.free()
	if _failures > 0:
		push_error("key hints teardown: %d check(s) failed" % _failures)
		quit(1)
		return
	print("test_key_hints_teardown: PASS")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("key hints teardown: " + message)

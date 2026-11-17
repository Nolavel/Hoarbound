extends Node
## Run 2 of the Continue check: a fresh process opens the real title menu, presses Continue and compares the
## world with expected.json from run 1 (loop_key_west_727.gd --stop-after-sleep). Needs autoloads, so run it
## as a scene: godot --path . res://tools/runtime/continue_after_relaunch.tscn -- --expected=<expected.json>

const SNAPSHOT: GDScript = preload("res://tools/runtime/shelter_snapshot.gd")
const TITLE: String = "res://scenes/ui/menu/title_menu.tscn"

var _expected_path: String = ""
var _watcher: bool = false


func _ready() -> void:
	if not _watcher:
		## The scene itself is replaced by the menu; a copy hanging off the root watches the whole run.
		var watcher: Node = (get_script() as GDScript).new()
		watcher.set(&"_watcher", true)
		get_tree().root.add_child.call_deferred(watcher)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--expected="):
			_expected_path = arg.get_slice("=", 1)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(TITLE)
	var menu: TitleMenu = null
	for _i: int in range(300):
		await get_tree().process_frame
		menu = get_tree().current_scene as TitleMenu
		if menu != null:
			break
	if menu == null:
		_done(false, "title menu never opened")
		return
	await get_tree().process_frame
	var enabled: bool = not menu._continue_button.disabled
	print("CONTINUE title: continue_enabled=%s" % enabled)
	if not enabled:
		_done(false, "Continue disabled: no sleep save found after relaunch")
		return
	menu.continue_game()
	var ctx: Variant = null
	for _i: int in range(6000):
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.has_method(&"get_context"):
			ctx = scene.call(&"get_context")
			if ctx != null:
				break
	if ctx == null:
		_done(false, "the world never came up after Continue")
		return
	for _i: int in range(120):
		await get_tree().physics_frame
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(_expected_path))
	if not expected is Dictionary:
		_done(false, "cannot read %s" % _expected_path)
		return
	## Through JSON as run 1 wrote it, so 3 and 3.0 compare equal.
	var got: Dictionary = JSON.parse_string(JSON.stringify(SNAPSHOT.take(get_tree().current_scene, ctx.player as Node3D)))
	var diffs: Array[String] = SNAPSHOT.diff(expected, got)
	print("CONTINUE reloaded %s" % JSON.stringify(got))
	_done(diffs.is_empty(), "; ".join(diffs) if not diffs.is_empty() else "world matches the sleep save")


func _done(ok: bool, why: String) -> void:
	print("CONTINUE_AFTER_RELAUNCH: %s — %s" % ["PASS" if ok else "FAIL", why])
	get_tree().quit(0 if ok else 1)

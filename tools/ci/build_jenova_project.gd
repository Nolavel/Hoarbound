@tool
extends SceneTree

## CI entrypoint for the real Jenova editor build path. This does not invoke clang
## directly: it calls JenovaEditorPlugin.BuildProject(), the same method behind the
## editor's Build Solution action.

const MAX_WAIT_FRAMES := 600
var _frame := 0
var _started := false


func _initialize() -> void:
	print("[jenova-ci] waiting for Jenova editor plugin")


func _process(_delta: float) -> bool:
	_frame += 1
	if _started:
		return false
	if _frame > MAX_WAIT_FRAMES:
		push_error("[jenova-ci] JenovaEditorPlugin did not become available")
		quit(20)
		return true
	if not ClassDB.class_exists(&"JenovaEditorPlugin"):
		return false

	# Give EditorPlugin registration a few frames after ClassDB becomes visible.
	if _frame < 20:
		return false
	_started = true
	_call_deferred_build()
	return false


func _call_deferred_build() -> void:
	call_deferred("_build")


func _build() -> void:
	var settings := EditorInterface.get_editor_settings()
	# Linux enum: GNU=0, Clang=1. We explicitly exercise Jenova's Clang backend.
	settings.set_setting("jenova/compiler_model", 1)
	settings.set_setting("jenova/multi_threaded_compilation", true)
	settings.set_setting("jenova/generate_debug_information", false)

	var plugin: Object = ClassDB.class_call_static(&"JenovaEditorPlugin", &"GetInstance")
	if plugin == null:
		push_error("[jenova-ci] JenovaEditorPlugin singleton is null")
		quit(21)
		return

	print("[jenova-ci] invoking JenovaEditorPlugin.BuildProject() with Clang")
	var ok: bool = plugin.BuildProject()
	if not ok:
		push_error("[jenova-ci] Jenova BuildProject failed")
		quit(22)
		return

	print("[jenova-ci] JENOVA_BUILD_OK")
	quit(0)

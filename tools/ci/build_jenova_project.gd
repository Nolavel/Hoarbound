@tool
extends SceneTree

## CI entrypoint for the real Jenova editor build path. This does not invoke clang
## directly: it calls JenovaEditorPlugin.BuildProject(), the same method behind the
## editor's Build Solution action.

const MAX_WAIT_FRAMES := 600
## jenova/editor_verbose_output: 0 standard output, 1 Jenova terminal (default), 2 off.
const VERBOSE_STANDARD_OUTPUT := 0
## Frames for Jenova to apply the changed editor settings before the build starts.
const SETTINGS_SETTLE_FRAMES := 10
var _frame := 0
var _configured_frame := -1
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
	if _configured_frame < 0:
		_configure()
		_configured_frame = _frame
		return false
	if _frame - _configured_frame < SETTINGS_SETTLE_FRAMES:
		return false
	_started = true
	_call_deferred_build()
	return false


## Headless editors have no Jenova terminal; route its build log and compiler
## errors to standard output so CI logs show why a build failed.
func _configure() -> void:
	var settings := EditorInterface.get_editor_settings()
	var compiler_model: int = 1 if OS.get_name() == "Linux" else 0
	settings.set_setting("jenova/editor_verbose_output", VERBOSE_STANDARD_OUTPUT)
	settings.set_setting("jenova/compiler_model", compiler_model)
	settings.set_setting("jenova/multi_threaded_compilation", true)
	settings.set_setting("jenova/generate_debug_information", false)


func _call_deferred_build() -> void:
	call_deferred("_build")


func _build() -> void:
	var compiler_name: String = "Clang" if OS.get_name() == "Linux" else "MSVC"
	var plugin: Object = ClassDB.class_call_static(&"JenovaEditorPlugin", &"GetInstance")
	if plugin == null:
		push_error("[jenova-ci] JenovaEditorPlugin singleton is null")
		quit(21)
		return

	print("[jenova-ci] invoking JenovaEditorPlugin.BuildProject() with ", compiler_name)
	var ok: bool = plugin.BuildProject()
	if not ok:
		push_error("[jenova-ci] Jenova BuildProject failed")
		quit(22)
		return

	print("[jenova-ci] JENOVA_BUILD_OK")
	quit(0)

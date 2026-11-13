extends CanvasLayer

## F10 saves a ReportBundle; after a session that never exited cleanly, one is saved on its own.
## A short note on screen says where the zip went.

const ACTION_REPORT: StringName = &"report_bundle"
## Seconds the note stays on screen.
const NOTE_SECONDS: float = 6.0

@export var note: Label

var _note_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if note != null:
		note.visible = false
	var build_log: Node = get_node_or_null(^"/root/BuildLog")
	var unclean: String = String(build_log.get(&"previous_unclean_log")) if build_log != null else ""
	if unclean != "":
		_report_previous.call_deferred(unclean)


func _process(delta: float) -> void:
	if _note_left <= 0.0:
		return
	_note_left -= delta
	if _note_left <= 0.0 and note != null:
		note.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION_REPORT) and event.is_action_pressed(ACTION_REPORT, false, true):
		await RenderingServer.frame_post_draw
		_show(tr(&"REPORT_SAVED") % ReportBundle.make("tester pressed F10", get_tree()))


func _report_previous(log_path: String) -> void:
	var path: String = ReportBundle.make("previous session ended without a clean exit", null, log_path)
	if path != "":
		_show(tr(&"REPORT_CRASH_SAVED") % path)


func _show(text: String) -> void:
	if note == null:
		return
	note.text = text
	note.visible = true
	_note_left = NOTE_SECONDS

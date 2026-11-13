class_name InputTapeRecorder
extends CanvasLayer

## F9 starts and stops recording a tape of the player's input; exported builds save it beside
## the executable (tapes/), the editor under user://tapes. Replay: tools/runtime/replay_input_tape.tscn.

signal recording_changed(active: bool, path: String)

const ACTION_TOGGLE: StringName = &"dev_input_tape"
const FOLDER: String = "tapes"

@export var badge: Label

var _tape: InputTape
var _frame0: int = 0
var _actions: Array[StringName] = []
var _camera: TpsCamera
var _last_look: Vector2 = Vector2.INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if badge != null:
		badge.visible = false


func is_recording() -> bool:
	return _tape != null


## Starts a tape at the player's current place; false if no player is in the tree.
func start() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		push_warning("InputTapeRecorder: no player to record")
		return false
	_tape = InputTape.new()
	var current: Node = get_tree().current_scene
	_tape.scene = current.scene_file_path if current != null else ""
	_tape.physics_fps = Engine.physics_ticks_per_second
	_tape.build = str(ProjectSettings.get_setting("application/config/version", "?"))
	_tape.start_transform = player.global_transform
	_camera = get_viewport().get_camera_3d() as TpsCamera
	if _camera != null:
		_tape.start_look = Vector2(_camera.get_yaw(), _camera.get_view_pitch_deg())
	var saves: Array[Node] = get_tree().root.find_children("*", "SaveManager", true, false)
	if not saves.is_empty():
		_tape.world = (saves[0] as SaveManager).capture_payload()
	## Reseeding is harmless to play and makes every later random roll repeatable.
	_tape.rng_seed = randi()
	seed(_tape.rng_seed)
	_actions = InputTape.tracked_actions()
	_frame0 = Engine.get_physics_frames()
	_last_look = Vector2.INF
	_show(true)
	return true


## Ends the tape and writes it; returns the saved path or "" on failure.
func stop() -> String:
	if _tape == null:
		return ""
	var dir: String = tapes_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = dir.path_join("tape_%s.json" % stamp)
	var ok: bool = _tape.save(path) == OK
	print("InputTapeRecorder: %s %s (%d events, %d frames)" % ["saved" if ok else "FAILED", path, _tape.events.size(), _tape.length_frames()])
	_tape = null
	_show(false, path if ok else "")
	return path if ok else ""


## Beside the executable in exports, so a tester attaches it with the log.
static func tapes_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(FOLDER)
	return ProjectSettings.globalize_path("user://" + FOLDER)


## Records one input event at a frame; public so tests drive it without a running game.
func record_event(event: InputEvent, frame: int) -> void:
	if _tape == null or event.is_echo():
		return
	for action: StringName in _actions:
		if event.is_action(action, true):
			_tape.events.append([frame, String(action), event.is_action_pressed(action, false, true), event.get_action_strength(action, true)])


func _input(event: InputEvent) -> void:
	if _tape != null:
		record_event(event, Engine.get_physics_frames() - _frame0)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION_TOGGLE) and event.is_action_pressed(ACTION_TOGGLE, false, true):
		if is_recording():
			stop()
		else:
			start()


func _physics_process(_delta: float) -> void:
	if _tape == null or not is_instance_valid(_camera):
		return
	var look := Vector2(_camera.get_yaw(), _camera.get_view_pitch_deg())
	if look.distance_squared_to(_last_look) > 1e-10:
		_last_look = look
		_tape.looks.append([Engine.get_physics_frames() - _frame0, look.x, look.y])


func _show(active: bool, path: String = "") -> void:
	if badge != null:
		badge.visible = active
	recording_changed.emit(active, path)

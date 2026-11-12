extends Node
## Exported builds copy every engine message into logs/ beside the executable, so a tester can send it
## without digging in %APPDATA%. The editor keeps Godot's own log only.

const FOLDER: String = "logs"
const KEEP: int = 5


class FileLogger extends Logger:
	var _file: FileAccess
	var _lock: Mutex = Mutex.new()

	func _init(file: FileAccess) -> void:
		_file = file

	func _log_message(message: String, error: bool) -> void:
		_write(("ERROR: " if error else "") + message.trim_suffix("\n"))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		_write("%s: %s\n   at: %s (%s:%d)" % [kind, rationale if rationale != "" else code, function, file, line])

	func _write(text: String) -> void:
		_lock.lock()
		_file.store_line(text)
		_file.flush()
		_lock.unlock()


var _logger: FileLogger


func _init() -> void:
	if not OS.has_feature("template"):
		return
	var dir: String = OS.get_executable_path().get_base_dir().path_join(FOLDER)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return
	_prune(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var file: FileAccess = FileAccess.open(dir.path_join("hoarbound_%s.log" % stamp), FileAccess.WRITE)
	if file == null:
		return
	file.store_line("Hoarbound %s | %s | %s" % [ProjectSettings.get_setting("application/config/version", "?"),
		OS.get_name(), Time.get_datetime_string_from_system()])
	_logger = FileLogger.new(file)
	OS.add_logger(_logger)


func _ready() -> void:
	if _logger != null:
		print("GPU: %s | %s | driver %s | %s" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(),
			ProjectSettings.get_setting("rendering/rendering_device/driver", "")])


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)


## Keeps the newest KEEP logs.
func _prune(dir: String) -> void:
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	var logs: Array[String] = []
	for n: String in names:
		if n.begins_with("hoarbound_") and n.ends_with(".log"):
			logs.append(n)
	logs.sort()
	while logs.size() >= KEEP:
		DirAccess.remove_absolute(dir.path_join(logs.pop_front()))

class_name ReportBundle
extends RefCounted

## One zip a tester can attach: build and hardware, settings, the session log, the newest
## input tape, a world snapshot and a screenshot. Saved beside the executable in exports.

const FOLDER: String = "reports"
## Lines of a log kept in the bundle; the tail is where a failure is.
const LOG_TAIL_LINES: int = 4000


## Beside the executable in exports, user://reports in the editor.
static func reports_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(FOLDER)
	return ProjectSettings.globalize_path("user://" + FOLDER)


## Writes the bundle and returns its path, or "" on failure. `log_path` defaults to this session's log.
static func make(reason: String, tree: SceneTree, log_path: String = "", out_dir: String = "") -> String:
	var dir: String = out_dir if out_dir != "" else reports_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = dir.path_join("hoarbound_report_%s.zip" % stamp)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		push_error("ReportBundle: cannot write %s" % path)
		return ""
	_add(zip, "report.json", JSON.stringify(system_info(reason), "\t"))
	var build_info: String = OS.get_executable_path().get_base_dir().path_join("BUILD_INFO.txt")
	if FileAccess.file_exists(build_info):
		_add(zip, "BUILD_INFO.txt", FileAccess.get_file_as_string(build_info))
	if FileAccess.file_exists("user://settings.cfg"):
		_add(zip, "settings.cfg", FileAccess.get_file_as_string("user://settings.cfg"))
	var log_file: String = log_path if log_path != "" else _current_log()
	if log_file != "" and FileAccess.file_exists(log_file):
		_add(zip, "log_tail.txt", _tail(FileAccess.get_file_as_string(log_file), LOG_TAIL_LINES))
	var tape: String = _newest(InputTapeRecorder.tapes_dir(), "json")
	if tape != "":
		_add(zip, "tape/" + tape.get_file(), FileAccess.get_file_as_string(tape))
	if tree != null:
		_add(zip, "world.json", JSON.stringify(world_state(tree), "\t"))
		var viewport: Viewport = tree.root
		if viewport != null and DisplayServer.get_name() != "headless":
			var image: Image = viewport.get_texture().get_image()
			if image != null:
				zip.start_file("screenshot.png")
				zip.write_file(image.save_png_to_buffer())
				zip.close_file()
	zip.close()
	print("ReportBundle: saved %s (%s)" % [path, reason])
	return path


## Build, OS, CPU, memory, GPU and display: what a bug report always lacks.
static func system_info(reason: String) -> Dictionary:
	var memory: Dictionary = OS.get_memory_info()
	return {
		"reason": reason,
		"time": Time.get_datetime_string_from_system(),
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": "%s x%d" % [OS.get_processor_name(), OS.get_processor_count()],
		"ram_mb": int(memory.get("physical", 0)) / 1048576,
		"gpu": "%s | %s | %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_api_version()],
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"screen": str(DisplayServer.screen_get_size()) if DisplayServer.get_name() != "headless" else "headless",
		"locale": TranslationServer.get_locale(),
		"fps": Engine.get_frames_per_second(),
	}


## Where Henry is and what the world looks like, so a report can be revisited.
static func world_state(tree: SceneTree) -> Dictionary:
	var state: Dictionary = {"scene": tree.current_scene.scene_file_path if tree.current_scene != null else ""}
	var player := tree.get_first_node_in_group(&"player") as Node3D
	if player != null:
		var p: Vector3 = player.global_position
		state["player"] = {"position": [p.x, p.y, p.z], "yaw": player.global_rotation.y}
	var camera := tree.root.get_camera_3d() if tree.root != null else null
	if camera != null:
		var c: Vector3 = camera.global_position
		state["camera"] = [c.x, c.y, c.z]
	state["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	state["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	return state


static func _current_log() -> String:
	var dir: String = OS.get_executable_path().get_base_dir().path_join("logs")
	return _newest(dir, "log")


static func _newest(dir: String, extension: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var best: String = ""
	var best_time: int = -1
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != extension:
			continue
		var full: String = dir.path_join(file)
		var modified: int = FileAccess.get_modified_time(full)
		if modified > best_time:
			best_time = modified
			best = full
	return best


static func _tail(text: String, lines: int) -> String:
	var all: PackedStringArray = text.split("\n")
	return "\n".join(all.slice(maxi(0, all.size() - lines)))


static func _add(zip: ZIPPacker, name: String, text: String) -> void:
	zip.start_file(name)
	zip.write_file(text.to_utf8_buffer())
	zip.close_file()

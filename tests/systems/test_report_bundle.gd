extends SceneTree

## Covers ReportBundle and the unclean-exit check: the zip holds what a bug report needs, and
## only a v2 log without its clean-exit line counts as a crashed session.
## Run: godot --headless --script tests/systems/test_report_bundle.gd

const BUILD_LOG: GDScript = preload("res://core/diagnostics/build_log.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_bundle_contents()
	_test_unclean_detection()
	if _failures > 0:
		push_error("report_bundle: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("report_bundle: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("report_bundle: %s" % message)


func _scratch(name: String) -> String:
	var dir: String = OS.get_temp_dir().path_join("hb_report_test_%d" % Time.get_ticks_usec()).path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _test_bundle_contents() -> void:
	var dir: String = _scratch("out")
	var log_path: String = dir.path_join("fake.log")
	var lines: PackedStringArray = []
	for i: int in range(5000):
		lines.append("line %d" % i)
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	var player := Node3D.new()
	player.add_to_group(&"player")
	root.add_child(player)
	player.global_position = Vector3(1.0, 2.0, 3.0)
	var zip_path: String = ReportBundle.make("test", self, log_path, dir)
	_check(zip_path != "" and FileAccess.file_exists(zip_path), "no zip written")
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		_check(false, "zip does not open")
		return
	var names: PackedStringArray = zip.get_files()
	for want: String in ["report.json", "log_tail.txt", "world.json"]:
		_check(names.has(want), "bundle lacks %s (has %s)" % [want, str(names)])
	var info: Variant = JSON.parse_string(zip.read_file("report.json").get_string_from_utf8())
	for key: String in ["reason", "version", "os", "cpu", "ram_mb", "gpu"]:
		_check(info is Dictionary and (info as Dictionary).has(key), "report.json lacks %s" % key)
	var tail: String = zip.read_file("log_tail.txt").get_string_from_utf8()
	_check(tail.ends_with("line 4999") and not tail.contains("line 999\n"), "log tail is not the last %d lines" % ReportBundle.LOG_TAIL_LINES)
	var world: Variant = JSON.parse_string(zip.read_file("world.json").get_string_from_utf8())
	_check(world is Dictionary and (world as Dictionary).has("player"), "world.json lacks the player")
	zip.close()
	root.remove_child(player)
	player.free()


func _test_unclean_detection() -> void:
	var dir: String = _scratch("logs")
	_write(dir.path_join("hoarbound_a.log"), "Hoarbound 0.312c\nold session without header\n")
	_check(BUILD_LOG.find_unclean(dir) == "", "a pre-v2 log without the header counted as a crash")
	OS.delay_msec(1100)
	_write(dir.path_join("hoarbound_b.log"), "Hoarbound x\n%s\nplaying\n%s\n" % [BUILD_LOG.SESSION_HEADER, BUILD_LOG.SESSION_END])
	_check(BUILD_LOG.find_unclean(dir) == "", "a cleanly closed session counted as a crash")
	OS.delay_msec(1100)
	var crashed: String = dir.path_join("hoarbound_c.log")
	_write(crashed, "Hoarbound x\n%s\nplaying\nERROR: something\n" % BUILD_LOG.SESSION_HEADER)
	_check(BUILD_LOG.find_unclean(dir) == crashed, "a session without its clean-exit line was missed")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

extends SceneTree

## CI-only capture harness. The effect itself is not implemented here: this script
## advances the public Jenova C++ method deterministically and writes rendered frames.

const LAB_SCENE := "res://scenes/experimental/jenova_frost_lab.tscn"
const OUT_DIR := "res://docs/runtime_previews/jenova_frost"
const FRAME_DIR := OUT_DIR + "/frames"
const FPS := 30
const FREEZE_SECONDS := 6.5
const FRAME_COUNT := int(FREEZE_SECONDS * FPS) + 1
const FROST_STAGES: Array[Dictionary] = [
	{"name": "frost_00_clear", "amount": 0.0},
	{"name": "frost_25_percent", "amount": 0.25},
	{"name": "frost_50_percent", "amount": 0.5},
	{"name": "frost_75_percent", "amount": 0.75},
	{"name": "frost_95_percent", "amount": 0.95},
	{"name": "frost_100_percent", "amount": 1.0},
]

var _lab: Node


func _initialize() -> void:
	var frame_dir_path := ProjectSettings.globalize_path(FRAME_DIR)
	var dir_error := DirAccess.make_dir_recursive_absolute(frame_dir_path)
	if dir_error != OK and not DirAccess.dir_exists_absolute(frame_dir_path):
		push_error("[jenova-frost] failed to create frame directory: %s" % error_string(dir_error))
		quit(1)
		return
	var packed_scene := load(LAB_SCENE) as PackedScene
	if packed_scene == null:
		push_error("[jenova-frost] failed to load lab scene: %s" % LAB_SCENE)
		quit(1)
		return
	_lab = packed_scene.instantiate()
	root.add_child(_lab)
	call_deferred("_capture")


func _capture() -> void:
	await process_frame
	if _lab == null or not _lab.has_method("SetFrostAmount") or not _lab.has_method("GetFrostAmount"):
		push_error("[jenova-frost] Jenova C++ frost API is unavailable; module was not built/loaded")
		quit(2)
		return

	# Calling the method once disables the C++ autoplay path, so CI controls only the
	# timeline. Every material/shader update still goes through the Jenova C++ script.
	if not _set_frost_amount(0.0):
		quit(5)
		return
	for frame in range(FRAME_COUNT):
		var t := float(frame) / float(FPS)
		var amount := clampf(t / FREEZE_SECONDS, 0.0, 1.0)
		if not _set_frost_amount(amount):
			quit(5)
			return
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var output := ProjectSettings.globalize_path("%s/%04d.png" % [FRAME_DIR, frame])
		var err := image.save_png(output)
		if err != OK:
			push_error("[jenova-frost] failed to save %s: %s" % [output, error_string(err)])
			quit(3)
			return

	var stage_dir := OUT_DIR + "/stages"
	var stage_dir_path := ProjectSettings.globalize_path(stage_dir)
	var stage_dir_error := DirAccess.make_dir_recursive_absolute(stage_dir_path)
	if stage_dir_error != OK and not DirAccess.dir_exists_absolute(stage_dir_path):
		push_error("[jenova-frost] failed to create stage directory: %s" % error_string(stage_dir_error))
		quit(1)
		return
	for stage in FROST_STAGES:
		if not _set_frost_amount(stage.amount):
			quit(5)
			return
		await process_frame
		await RenderingServer.frame_post_draw
		var stage_path := "%s/%s.png" % [stage_dir, stage.name]
		var stage_image := root.get_texture().get_image()
		var stage_error := stage_image.save_png(ProjectSettings.globalize_path(stage_path))
		if stage_error != OK:
			push_error("[jenova-frost] failed to save %s: %s" % [stage_path, error_string(stage_error)])
			quit(3)
			return

	if not _write_report():
		quit(4)
		return
	print("[jenova-frost] captured %d frames / %.2f s at %d fps" % [FRAME_COUNT, FREEZE_SECONDS, FPS])
	print("[jenova-frost] captured %d exact frost stages" % FROST_STAGES.size())
	quit(0)


func _set_frost_amount(value: float) -> bool:
	_lab.call("SetFrostAmount", value)
	var actual := float(_lab.call("GetFrostAmount"))
	if not is_equal_approx(actual, value):
		push_error("[jenova-frost] C++ frost amount mismatch: expected %.3f, got %.3f" % [value, actual])
		return false
	return true


func _write_report() -> bool:
	var report := {
		"scene": LAB_SCENE,
		"controller": "res://scripts/experimental/jenova_frost/frost_window.cpp",
		"runtime": "Jenova C++",
		"shader_owner": "embedded in Jenova C++ source; no .gdshader",
		"fps": FPS,
		"freeze_seconds": FREEZE_SECONDS,
		"frames": FRAME_COUNT,
		"first_frame": "%s/0000.png" % FRAME_DIR,
		"last_frame": "%s/%04d.png" % [FRAME_DIR, FRAME_COUNT - 1],
		"stages": FROST_STAGES,
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file == null:
		push_error("[jenova-frost] failed to open capture report: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(report, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("[jenova-frost] failed to write capture report: %s" % error_string(write_error))
		return false
	return true

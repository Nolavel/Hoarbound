extends SceneTree

## CI-only capture harness. The effect itself is not implemented here: this script
## advances the public Jenova C++ method deterministically and writes rendered frames.

const LAB_SCENE := "res://scenes/experimental/jenova_frost_lab.tscn"
const OUT_DIR := "res://docs/runtime_previews/jenova_frost"
const FRAME_DIR := OUT_DIR + "/frames"
const FPS := 30
const FREEZE_SECONDS := 6.5
const FRAME_COUNT := int(FREEZE_SECONDS * FPS) + 1

var _lab: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_lab = (load(LAB_SCENE) as PackedScene).instantiate()
	root.add_child(_lab)
	call_deferred("_capture")


func _capture() -> void:
	await process_frame
	if _lab == null or not _lab.has_method("SetFrostAmount"):
		push_error("[jenova-frost] Jenova C++ method SetFrostAmount is unavailable; module was not built/loaded")
		quit(2)
		return

	# Calling the method once disables the C++ autoplay path, so CI controls only the
	# timeline. Every material/shader update still goes through the Jenova C++ script.
	_lab.call("SetFrostAmount", 0.0)
	for frame in range(FRAME_COUNT):
		var t := float(frame) / float(FPS)
		var amount := clampf(t / FREEZE_SECONDS, 0.0, 1.0)
		_lab.call("SetFrostAmount", amount)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var output := ProjectSettings.globalize_path("%s/%04d.png" % [FRAME_DIR, frame])
		var err := image.save_png(output)
		if err != OK:
			push_error("[jenova-frost] failed to save %s: %s" % [output, error_string(err)])
			quit(3)
			return

	_write_report()
	print("[jenova-frost] captured %d frames / %.2f s at %d fps" % [FRAME_COUNT, FREEZE_SECONDS, FPS])
	quit(0)


func _write_report() -> void:
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
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))

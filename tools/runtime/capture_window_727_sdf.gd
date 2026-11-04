extends SceneTree

## Issue #281: 6 sec, 12 fps, one real 727 FrontWindow1 / two sequential material tests.
const SCENE: PackedScene = preload("res://tests/scenes/window_727_sdf_probe.tscn")
const FRAMES: int = 72
const FPS: float = 12.0
const OUT_DIR: String = "res://docs/runtime_previews/window_727_sdf"
var _probe: Window727SDFProbe

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var frame_dir: String = ProjectSettings.globalize_path(OUT_DIR.path_join("frames"))
	if DirAccess.make_dir_recursive_absolute(frame_dir) != OK:
		push_error("WINDOW_727_TEST_FAIL: cannot make output folder")
		quit(1)
		return
	_probe = SCENE.instantiate() as Window727SDFProbe
	root.add_child(_probe)
	if not _probe.is_valid():
		push_error("WINDOW_727_TEST_FAIL: real window extraction did not succeed")
		quit(2)
		return
	for frame: int in range(FRAMES):
		_probe.set_test_time(float(frame) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var png: String = frame_dir.path_join("f_%03d.png" % frame)
		var screenshot: Image = root.get_texture().get_image()
		if screenshot == null or screenshot.is_empty() or screenshot.save_png(png) != OK:
			push_error("WINDOW_727_TEST_FAIL: failed capture at frame %d" % frame)
			quit(3)
			return
	print("WINDOW_727_SDF_CAPTURE_OK frames=%d fps=%d seconds=6 source_triangles=%d" % [
		FRAMES, int(FPS), _probe.verified_triangles()
	])
	_probe.queue_free()
	await process_frame
	quit(0)

extends SceneTree

## Real 727 scene, actual sun/grade/stove. Unshaded V3 vs lit V3, 6 seconds.
const SCENE: PackedScene = preload("res://tests/scenes/window_727_real_light.tscn")
const WARMUP: int = 125
const COUNT: int = 72
const FPS: int = 12
const OUTPUT: String = "res://docs/runtime_previews/window_727_real_light"

func _initialize() -> void:
	# SceneTree --resolution can be ignored on the software offscreen root.
	# A real 16:9 render target prevents wasting Lavapipe time at 1280x1024.
	root.size = Vector2i(640, 360)
	call_deferred(&"_capture")


func _capture() -> void:
	var frames: String = ProjectSettings.globalize_path(OUTPUT.path_join("frames"))
	if DirAccess.make_dir_recursive_absolute(frames) != OK:
		push_error("WINDOW_727_REAL_LIGHT_FAIL: output folder cannot be created")
		quit(2)
		return
	var demo: Window727RealLightProbe = SCENE.instantiate() as Window727RealLightProbe
	root.add_child(demo)
	for i: int in range(WARMUP):
		await process_frame
		if i == 5 or i == 55 or i == 115:
			demo.disable_nonessential_preview_viewports()
	if not demo.prepare():
		push_error("WINDOW_727_REAL_LIGHT_FAIL: real scene setup failed after warmup")
		quit(3)
		return
	# Stabilize the *real* day/night direct beam after switching blizzard to
	# the game's calm profile. Both A/B halves then share the same sunlight.
	for step: int in range(48):
		await process_frame
	for frame: int in range(COUNT):
		demo.set_capture_time(float(frame) / float(FPS))
		await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		var name: String = frames.path_join("f_%03d.png" % frame)
		if picture == null or picture.is_empty() or picture.save_png(name) != OK:
			push_error("WINDOW_727_REAL_LIGHT_FAIL: image save failed at frame %d" % frame)
			quit(4)
			return
	print("WINDOW_727_REAL_LIGHT_CAPTURE_OK frames=%d fps=%d seconds=6" % [COUNT, FPS])
	quit(0)

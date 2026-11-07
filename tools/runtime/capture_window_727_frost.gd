extends SceneTree

## Issue #281, new art iteration: one continuous 6 second capture of the real
## 727 FrontWindow1 with the new thaw material, on a neutral backdrop.
##
## Frames only. The video is assembled from them with ffmpeg outside Godot.
##
## Usage:
##   godot --path <project> --script res://tools/runtime/capture_window_727_frost.gd
##   godot --path <project> --script res://tools/runtime/capture_window_727_frost.gd -- --probe 0.5
##       --probe <warmth> captures a single frame at that heated_warmth value,
##       used for the pre-flight check before a full capture.

const COUNT: int = 72
const FPS: int = 12
# The frost shader is heavy on a software Vulkan device; a handful of frames is
# enough to compile the pipelines, the rest would only cost minutes.
const WARMUP: int = 6
const OUTPUT: String = "res://docs/runtime_previews/window_727_frost"


func _initialize() -> void:
	call_deferred(&"_capture")


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var probes: Array[float] = []
	for i: int in range(args.size() - 1):
		if args[i] == "--probe":
			probes.append(float(args[i + 1]))
	var frames: String = ProjectSettings.globalize_path(OUTPUT.path_join("frames"))
	if DirAccess.make_dir_recursive_absolute(frames) != OK:
		push_error("WINDOW_727_FROST_FAIL: output folder cannot be created")
		quit(2)
		return
	# A dedicated viewport, so the capture size is exactly 960x540 whatever the
	# window of the machine happens to be.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe: Window727FrostProbe = Window727FrostProbe.new()
	viewport.add_child(probe)
	for i: int in range(WARMUP):
		await process_frame
	if not probe.is_valid():
		push_error("WINDOW_727_FROST_FAIL: pane setup failed")
		quit(3)
		return
	if probes.size() > 0:
		for probe_warmth: float in probes:
			probe.set_warmth(probe_warmth)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var probe_image: Image = viewport.get_texture().get_image()
			var probe_path: String = frames.path_join("probe_%.2f.png" % probe_warmth)
			if probe_image == null or probe_image.is_empty() or probe_image.save_png(probe_path) != OK:
				push_error("WINDOW_727_FROST_FAIL: probe image save failed")
				quit(4)
				return
			print("WINDOW_727_FROST_PROBE_OK warmth=%.2f size=%dx%d file=%s renderer=%s method=%s" % [
				probe_warmth, probe_image.get_width(), probe_image.get_height(), probe_path,
				RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()
			])
		quit(0)
		return
	var last: Image = null
	for frame: int in range(COUNT):
		probe.set_capture_time(float(frame) / float(FPS))
		await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = viewport.get_texture().get_image()
		var name: String = frames.path_join("f_%03d.png" % frame)
		if picture == null or picture.is_empty() or picture.save_png(name) != OK:
			push_error("WINDOW_727_FROST_FAIL: image save failed at frame %d" % frame)
			quit(4)
			return
		last = picture
	print("WINDOW_727_FROST_CAPTURE_OK frames=%d fps=%d seconds=6 size=%dx%d renderer=%s method=%s" % [
		COUNT, FPS, last.get_width(), last.get_height(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()
	])
	quit(0)

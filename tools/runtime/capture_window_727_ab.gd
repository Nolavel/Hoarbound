extends SceneTree

## Issue #281, MCode/MiniMax: the same 727 real-light capture for two shaders.
##
## The scene, the window, the sun, the stove, the shelter grade, the camera
## move and the 0..1 heated_warmth ramp are identical for every run; only the
## shader on the extracted FrontWindow1 changes. That is what makes the two
## films comparable frame by frame.
##
## Run:
##   godot --path . --rendering-driver vulkan --rendering-method forward_plus \
##     --script res://tools/runtime/capture_window_727_ab.gd -- \
##     --shader res://tests/demos/window_727_real_light/<file>.gdshader \
##     --label <name> [--width 960] [--height 540]

const SCENE: PackedScene = preload("res://tests/scenes/window_727_real_light_ab.tscn")
const WARMUP: int = 125
const COUNT: int = 72
const FPS: int = 12
const OUTPUT_ROOT: String = "res://docs/runtime_previews/window_727_ab"


func _initialize() -> void:
	call_deferred(&"_capture")


## The process' resident memory, in MB: the software Vulkan device allocates
## every render target in system RAM.
func _rss_mb() -> float:
	var status: String = FileAccess.get_file_as_string("/proc/self/status")
	for line: String in status.split("\n"):
		if line.begins_with("VmRSS:"):
			return float(line.replace("VmRSS:", "").strip_edges().replace(" kB", "")) / 1024.0
	return 0.0


func _option(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return fallback


func _capture() -> void:
	var shader_path: String = _option("--shader", "")
	var label: String = _option("--label", "run")
	var width: int = int(_option("--width", "960"))
	var height: int = int(_option("--height", "540"))
	if shader_path == "":
		push_error("WINDOW_727_AB_FAIL: --shader is required")
		quit(2)
		return
	var shader: Shader = load(shader_path) as Shader
	if shader == null:
		push_error("WINDOW_727_AB_FAIL: shader %s did not load" % shader_path)
		quit(2)
		return
	root.size = Vector2i(width, height)
	var frames: String = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(label).path_join("frames"))
	if DirAccess.make_dir_recursive_absolute(frames) != OK:
		push_error("WINDOW_727_AB_FAIL: output folder cannot be created")
		quit(2)
		return
	var demo: Window727RealLightProbe = SCENE.instantiate() as Window727RealLightProbe
	root.add_child(demo)
	for i: int in range(WARMUP):
		await process_frame
		if i == 5 or i == 55 or i == 115:
			demo.disable_nonessential_preview_viewports()
		if i % 5 == 0:
			print("WINDOW_727_AB_MEM warmup=%d rss=%.0fMB static=%.0fMB objects=%d" % [i, _rss_mb(), OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT)])
	if not demo.prepare():
		push_error("WINDOW_727_AB_FAIL: real scene setup failed after warmup")
		quit(3)
		return
	# The material under test replaces the control on the very same pane.
	var lit: ShaderMaterial = demo.get("_lit") as ShaderMaterial
	if lit == null:
		push_error("WINDOW_727_AB_FAIL: the probe has no lit material")
		quit(3)
		return
	lit.shader = shader
	for step: int in range(48):
		await process_frame
	for frame: int in range(COUNT):
		demo.set_capture_time(float(frame) / float(FPS))
		await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		var name: String = frames.path_join("f_%03d.png" % frame)
		if picture == null or picture.is_empty() or picture.save_png(name) != OK:
			push_error("WINDOW_727_AB_FAIL: image save failed at frame %d" % frame)
			quit(4)
			return
	print("WINDOW_727_AB_OK label=%s shader=%s frames=%d fps=%d seconds=6 size=%dx%d" % [
		label, shader_path, COUNT, FPS, width, height
	])
	quit(0)

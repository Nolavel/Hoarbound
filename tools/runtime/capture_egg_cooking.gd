extends SceneTree

## Deterministic Forward+/Vulkan review using the production StoveVisual and pan GLB.
## Writes six runtime stills and a seven-second MP4; no gameplay state is changed.
const OUT: String = "res://docs/asset_previews/egg_cooking"
const FPS: int = 18
const STILLS: Dictionary = {
	5: "01_whole_egg.png",
	15: "02_cracked_shell.png",
	29: "03_albumen.png",
	34: "04_yolk_fall.png",
	42: "05_spread.png",
	96: "06_frying_edge.png",
}


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output: String = ProjectSettings.globalize_path(OUT)
	var frames: String = ProjectSettings.globalize_path("user://egg_cooking_capture/frames")
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute(frames)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.11, 0.14, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.74, 0.79, 0.87)
	environment.ambient_light_energy = 1.8
	world.environment = environment
	root.add_child(world)
	var stove := HeatSource.new()
	stove.starts_burning = false
	var visual := StoveVisual.new()
	visual.flue_length = 0.9
	stove.add_child(visual)
	root.add_child(stove)
	var ring := visual.get_node(^"CookRingA") as MeshInstance3D
	var pan := SurvivalItemVisual.make(&"frying_pan")
	pan.name = "ReviewFryingPan"
	ring.add_child(pan)
	pan.position.y = (ring.mesh as CylinderMesh).height * 0.5
	var egg := EggCookingVisual.new()
	egg.name = "EggCookingVisual"
	pan.add_child(egg)
	var bounce := OmniLight3D.new()
	bounce.light_color = Color(0.95, 0.84, 0.70)
	bounce.light_energy = 3.2
	bounce.omni_range = 2.2
	bounce.position = pan.to_global(Vector3(0.1, 0.34, 0.18))
	root.add_child(bounce)
	var review_sun := DirectionalLight3D.new()
	review_sun.rotation_degrees = Vector3(-58.0, 18.0, 0.0)
	review_sun.light_energy = 1.9
	review_sun.shadow_enabled = false
	root.add_child(review_sun)
	var camera := Camera3D.new()
	camera.fov = 37.0
	root.add_child(camera)
	var look: Vector3 = pan.to_global(Vector3(0.0, 0.105, 0.0))
	camera.look_at_from_position(pan.to_global(Vector3(0.18, 0.31, 0.51)), look)
	camera.make_current()
	for _i: int in range(12):
		await process_frame
	var stills_only: bool = OS.get_cmdline_user_args().has("--stills-only")
	var indices: Array[int] = []
	if stills_only:
		for index: int in STILLS.keys():
			indices.append(index)
		indices.sort()
	else:
		for index: int in range(int(EggCookingVisual.TOTAL_SECONDS * FPS) + 1):
			indices.append(index)
	for i: int in indices:
		egg.seek_seconds(float(i) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = output.path_join(STILLS[i]) if stills_only else frames.path_join("frame_%04d.png" % i)
		if image.save_png(path) != OK:
			push_error("Egg capture: failed to save %s" % path)
			quit(1)
			return
		if STILLS.has(i) and not stills_only:
			image.save_png(output.path_join(STILLS[i]))
	if stills_only:
		print("EGG_COOKING_CAPTURE stills=%d pan=%s" % [indices.size(), pan.name])
		quit()
		return
	var output_video: String = output.path_join("egg_crack_and_fry.mp4")
	var ffmpeg_output := []
	var result: int = OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y",
		"-framerate", str(FPS), "-i", frames.path_join("frame_%04d.png"),
		"-c:v", "libx264", "-crf", "21", "-pix_fmt", "yuv420p",
		"-movflags", "+faststart", output_video], ffmpeg_output, true)
	if result != 0:
		push_error("Egg capture: ffmpeg failed: %s" % str(ffmpeg_output))
		quit(1)
		return
	print("EGG_COOKING_CAPTURE frames=%d pan=%s video=%s" %
		[int(EggCookingVisual.TOTAL_SECONDS * FPS) + 1, pan.name, output_video])
	quit()

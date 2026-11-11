extends SceneTree

## Lightweight real CompassStrip capture: no Key West chunks, Vulkan, world 3D or ffmpeg.
## Executed only by an explicitly tagged push on codex, using the existing checks workflow.
## Writes six 960x180 PNGs with actual production Control._draw() output.
## Each capture shows exactly one status word (absolute or movement).

const OUT_SIZE := Vector2i(960, 180)
var _failed: bool = false

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if not args.is_empty() else "user://compass_light"
	if out_dir.begins_with("user://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var viewport := SubViewport.new()
	viewport.size = OUT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.size = Vector2(OUT_SIZE)
	viewport.add_child(backdrop)

	var strip := CompassStrip.new()
	strip.size = Vector2(OUT_SIZE)
	viewport.add_child(strip)

	var player := Node3D.new()
	root.add_child(player)
	var camera := Camera3D.new()
	root.add_child(camera)
	var bearings := FirstExitBearings.new()
	root.add_child(bearings)
	bearings.begin_play(true)
	if not bearings.has_active_target():
		push_error("COMPASS_QUICK: no active scenario 727 marker")
		quit(1)
		return

	strip._player = player
	strip._camera = camera
	strip._bearings = bearings
	strip._have_bearing = false

	var target: Vector2 = bearings.active_xz()
	## The warm view also checks the off-strip chevron. Snow and charcoal are
	## neutral contrast backdrops, not screenshots of the 3D game world.
	var cases: Array[Dictionary] = [
		{"file": "01_cold.png", "distance": 400.0, "yaw": 0.0, "background": Color("#e6ebef"),
		 "expected": FirstExitBearings.Proximity.COLD, "pulse": false},
		{"file": "02_warm_edge.png", "distance": 160.0, "yaw": 90.0, "background": Color("#26303a"),
		 "expected": FirstExitBearings.Proximity.WARM, "pulse": true},
		{"file": "03_hot.png", "distance": 40.0, "yaw": 0.0, "background": Color("#e6ebef"),
		 "expected": FirstExitBearings.Proximity.HOT, "pulse": false},
		{"file": "04_warmer.png", "distance": 220.0, "yaw": 0.0, "background": Color("#26303a"),
		 "expected": FirstExitBearings.Proximity.WARM, "pulse": true},
		{"file": "05_colder_ru.png", "distance": 220.0, "yaw": 0.0, "background": Color("#e6ebef"),
		 "expected": FirstExitBearings.Proximity.WARM, "pulse": true, "moving_away": true, "ru": true},
		{"file": "06_warmer_ru.png", "distance": 220.0, "yaw": 0.0, "background": Color("#26303a"),
		 "expected": FirstExitBearings.Proximity.WARM, "pulse": true, "ru": true},
	]
	for entry: Dictionary in cases:
		var d: float = float(entry["distance"])
		TranslationServer.set_locale("ru" if bool(entry.get("ru", false)) else "en")
		backdrop.color = entry["background"] as Color
		player.global_position = Vector3(target.x, 0.0, target.y + d)
		camera.rotation.y = deg_to_rad(float(entry["yaw"]))
		bearings._reset_proximity_feedback()
		var is_retreat: bool = bool(entry.get("moving_away", false))
		bearings._sample_distance(d + (-9.0 if is_retreat else 9.0) if bool(entry["pulse"]) else d, 0.25)
		strip._have_marker = false
		strip._have_bearing = false
		for i: int in 3:
			await process_frame
		if bool(entry["pulse"]):
			bearings._sample_distance(d, 0.25)
		for i: int in 5:
			await process_frame
		## Still-frame review: show the transient ring near its full expansion.
		## Runtime animation remains untouched; only capture clock is adjusted.
		if bool(entry["pulse"]):
			strip._pulse_elapsed = 0.42
			strip.queue_redraw()
			await process_frame
			await process_frame
		if int(bearings.proximity_state) != int(entry["expected"]):
			push_error("COMPASS_QUICK: wrong proximity for " + str(entry["file"]))
			_failed = true
			continue
		if bool(entry["pulse"]):
			var expected_trend: int = FirstExitBearings.Trend.MOVING_AWAY if is_retreat else FirstExitBearings.Trend.APPROACHING
			if bearings.trend_state != expected_trend:
				push_error("COMPASS_QUICK: expected movement event " + str(entry["file"]))
				_failed = true
			var expected_text: String = ("ХОЛОДНЕЕ" if is_retreat else "ТЕПЛЕЕ") if bool(entry.get("ru", false)) else ("COLDER" if is_retreat else "WARMER")
			if strip._display_word() != expected_text:
				push_error("COMPASS_QUICK: wrong sole trend word " + str(entry["file"]))
				_failed = true
		elif strip._display_word() != strip._proximity_text() or not strip._trend_text().is_empty():
			push_error("COMPASS_QUICK: stale trend text " + str(entry["file"]))
			_failed = true
		var picture: Image = viewport.get_texture().get_image()
		if picture.is_empty() or picture.get_width() != OUT_SIZE.x:
			push_error("COMPASS_QUICK: bad viewport image for " + str(entry["file"]))
			_failed = true
			continue
		var png: String = out_dir.path_join(str(entry["file"]))
		var err: Error = picture.save_png(png)
		if err != OK:
			push_error("COMPASS_QUICK: could not save " + png)
			_failed = true
		else:
			print("COMPASS_QUICK_PNG: ", png, " state=", int(bearings.proximity_state),
				" trend=", int(bearings.trend_state), " bytes=", FileAccess.get_file_as_bytes(png).size())

	if _failed:
		push_error("COMPASS_QUICK_CAPTURE: FAIL")
		quit(1)
	else:
		print("COMPASS_QUICK_CAPTURE: PASS")
		quit(0)

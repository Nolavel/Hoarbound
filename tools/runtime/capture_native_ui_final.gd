extends SceneTree

## Final candidate A/B: isolated process and actual GraphicsQuality native 3D budget.
## Compares legacy viewport against native UI and adaptive 3D scaling.
## A presented PNG is either the root viewport texture, when that texture is already
## the requested size, or the X11 framebuffer Godot presented. It is never resized.
##
## Run: xvfb-run -s "-screen 0 3840x2160x24" godot --path . --resolution 3840x2160
##   --position 0,0 --rendering-driver vulkan --rendering-method forward_plus
##   --audio-driver Dummy --fixed-fps 30 --script res://tools/runtime/capture_native_ui_final.gd
##   -- <out_dir> canvas_items hud 0.77 1920x1080 clarity
## Optional clarity mode captures production/native A/B in ONE frozen world.
## Only the capture harness overrides scaling; no production setting is saved.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const BEARINGS_SCRIPT: GDScript = preload("res://scripts/world/first_exit_bearings.gd")
const BASE := Vector2i(1920, 1080)
const HUD_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const EXTRA_SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]
const INTERIOR_UV := Vector2(2.6, 9.4)
const INTERIOR_FACE := Vector2(-1.2, 6.4)

var _out: String = ""
var _project_aspect: Window.ContentScaleAspect
var _project_3d_mode: Viewport.Scaling3DMode
var _project_3d_scale: float = 0.77
var _player: CharacterBody3D
var _camera: TpsCamera
var _view: Camera3D
var _pose_ready: bool = false
var _player_xf: Transform3D
var _camera_xf: Transform3D
var _shots: Array[Dictionary] = []
var _notes: PackedStringArray = PackedStringArray()
var _case_mode: String = "viewport"
var _case_group: String = "hud"
var _case_size: Vector2i = BASE
var _case_scale: float = 0.77
var _clarity: bool = false
var _variant: String = "production"
var _native_override: bool = false
var _project_stretch: String = ""
var _production_scale: float = 1.0



func _initialize() -> void:
	# A/B isolation: EVERY mode, resolution, and 3D scale gets a NEW Godot process.
	# No process begins at 4K and then shrinks its viewport for subsequent images.
	var args := OS.get_cmdline_user_args()
	if args.size() != 5 and args.size() != 6:
		push_error("Usage: -- <out_dir> <viewport|canvas_items> <hud|interior|inventory> <scale3d> <WIDTHxHEIGHT>")
		quit(2)
		return
	_out = args[0]
	if _out.begins_with("user://"):
		_out = ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(_out)
	_case_mode = args[1]
	_case_group = args[2]
	_case_scale = float(args[3])
	_clarity = args.size() == 6 and args[5] == "clarity"
	_project_stretch = String(ProjectSettings.get_setting("display/window/stretch/mode", "disabled"))
	var dimensions := args[4].split("x")
	if dimensions.size() != 2:
		push_error("Bad resolution: " + args[4])
		quit(2)
		return
	_case_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if not (_case_mode in ["viewport", "canvas_items"]) or not (_case_group in ["hud", "interior", "inventory"]):
		push_error("Bad case: %s / %s" % [_case_mode, _case_group])
		quit(2)
		return
	if _case_size.x < 640 or _case_size.y < 480 or _case_scale <= 0.0 or _case_scale > 1.0:
		push_error("Invalid size/scale")
		quit(2)
		return
	_project_aspect = root.content_scale_aspect
	_project_3d_mode = root.scaling_3d_mode
	_project_3d_scale = root.scaling_3d_scale
	if _clarity:
		seed(727)
		if _case_mode != "canvas_items" or RenderingServer.get_current_rendering_method() != "forward_plus":
			push_error("Clarity evidence requires native canvas_items and Forward+; no renderer fallback")
			quit(2)
			return
	# Set before world instantiation; subsequent shots NEVER toggle stretch mode.
	root.content_scale_size = BASE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if _case_mode == "viewport" else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if _case_mode == "viewport" else Window.CONTENT_SCALE_ASPECT_EXPAND
	root.scaling_3d_mode = _project_3d_mode
	ProjectSettings.set_setting("hfn/graphics/quality", "medium" if is_equal_approx(_case_scale, 0.77) else ("low" if is_equal_approx(_case_scale, 0.67) else "high"))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(_case_size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_log_renderer()
	print("STRETCH_CASE %s" % JSON.stringify({"mode": _case_mode, "group": _case_group, "resolution": [_case_size.x, _case_size.y], "scale3d": _case_scale}))
	_run()


func _run() -> void:
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	world.set(&"spawn_at_shelter", false)
	root.add_child(world)
	var ctx := await _wait_context(world, 360)
	if ctx == null or not (ctx.camera is TpsCamera) or not (ctx.player is CharacterBody3D):
		_notes.append("Missing actual Key West character or TPS camera")
		_finish(1)
		return
	_player = ctx.player as CharacterBody3D
	_camera = ctx.camera as TpsCamera
	_view = _camera
	_hide_debug(root)
	for _i: int in 90:
		await process_frame
	_remember_pose()
	if _case_group == "interior":
		await _interior(world)
	elif _case_group == "inventory":
		if not await _open_inventory():
			_finish(1)
			return
	_freeze_actors(true)
	# Let rendering settle on the requested root viewport after any camera/UI move.
	for _i: int in 8:
		await process_frame
	if _clarity:
		# Stop particles, animation and weather between variants, including delta-independent callbacks.
		_production_scale = root.scaling_3d_scale
		paused = true
		await _clarity_pair()
		var good: bool = _shots.size() == (4 if _case_group == "hud" and _case_size == BASE else 2)
		for shot: Dictionary in _shots:
			good = good and bool(shot["ok"])
		_finish(0 if good and _notes.is_empty() else 1)
		return
	await _shot(_case_group, _case_mode, _case_size, _case_scale)
	_finish(0 if _shots.size() == 1 and bool(_shots[0]["ok"]) else 1)


func _clarity_pair() -> void:
	var original_aa: Viewport.ScreenSpaceAA = root.screen_space_aa
	for name: String in ["A_production", "B_native"]:
		_variant = name
		_native_override = name == "B_native"
		await _shot(_case_group, _case_mode, _case_size, _case_scale)
	if _case_group == "hud" and _case_size == BASE:
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		for name: String in ["C_production_no_fxaa", "D_native_no_fxaa"]:
			_variant = name
			_native_override = name == "D_native_no_fxaa"
			await _shot(_case_group, _case_mode, _case_size, _case_scale)
	root.screen_space_aa = original_aa


func _interior(world: Node) -> void:
	_freeze_actors(false)
	var bearings := _bearings(world)
	if bearings == null:
		_notes.append("interior skipped: First Exit bearings missing")
		_freeze_actors(true)
		return
	var door := Vector3(bearings.shelter_xz().x, _player.global_position.y, bearings.shelter_xz().y)
	_player.global_position = door
	_player.velocity = Vector3.ZERO
	var shelter: KeyWest727Shelter = null
	for _i: int in 240:
		await process_frame
		shelter = world.find_child("Shelter727", true, false) as KeyWest727Shelter
		if shelter != null and not shelter.interior.is_empty() and shelter.get_node_or_null(^"House") != null:
			break
	if shelter == null or shelter.get_node_or_null(^"House") == null:
		_notes.append("interior skipped: Shelter727 did not stream in")
		_freeze_actors(true)
		return
	var house := shelter.get_node(^"House") as Node3D
	var floor_y := float(shelter.interior["floor_y"])
	var at := house.global_transform * Vector3(INTERIOR_UV.x, floor_y + _camera.origin_above_feet + 0.05, INTERIOR_UV.y)
	var face := house.global_transform * Vector3(INTERIOR_FACE.x, floor_y + _camera.origin_above_feet + 0.05, INTERIOR_FACE.y)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.look_at(Vector3(face.x, at.y, face.z), Vector3.UP)
	var to := face - at
	_camera.set_look(atan2(-to.x, -to.z), -8.0)
	_camera.snap_to_target()
	for _i: int in 40:
		await process_frame
	_remember_pose()
	_freeze_actors(true)


func _open_inventory() -> bool:
	var hub := _player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if hub == null:
		_notes.append("inventory skipped: PlayerHubComponent missing")
		return false
	var opened := hub.open()
	for _i: int in 90:
		await process_frame
	if not opened or not hub.is_open():
		_notes.append("inventory open refused (opened=%s is_open=%s)" % [opened, hub.is_open()])
		return false
	_remember_pose()
	return true


func _restore_exterior_pose() -> void:
	## Exterior pose was the first one remembered. Inventory replaced it, so the
	## scale shots go back to the recorded gameplay transform stored on the shot
	## list's first hud entry when present. Otherwise stay where we are.
	for shot: Dictionary in _shots:
		if String(shot["group"]) == "hud" and shot.has("player_xf"):
			_player.global_transform = shot["player_xf"]
			_camera.global_transform = shot["camera_xf"]
			_camera.make_current()
			_view = _camera
			_player.velocity = Vector3.ZERO
			_remember_pose()
			return


func _shot(group: String, mode_name: String, size: Vector2i, scale3d: float) -> void:
	# Preserve process-level settings; record actual window and viewport dimensions.
	var applied := await _apply_window(size, mode_name, scale3d)
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_lock_pose()
	await process_frame
	await process_frame
	_lock_pose()
	await RenderingServer.frame_post_draw
	var window_size := DisplayServer.window_get_size()
	var internal := root.get_viewport().get_texture().get_image()
	var internal_size := Vector2i(internal.get_width(), internal.get_height()) if internal != null else Vector2i.ZERO
	var path := _shot_path(group, mode_name, size, scale3d)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var source := ""
	var ok := applied and window_size == size
	if not ok:
		_notes.append("%s window %s != %s" % [path.get_file(), window_size, size])
	elif internal != null and Vector2i(internal.get_width(), internal.get_height()) == size:
		ok = internal.save_png(path) == OK
		source = "viewport"
	else:
		if internal != null:
			var internal_path := _out.path_join("internal").path_join(path.get_file().get_basename() + "__" + group + ".png")
			DirAccess.make_dir_recursive_absolute(internal_path.get_base_dir())
			internal.save_png(internal_path)
		ok = _grab_presented(path, size)
		source = "x11_present"
	var presented := Image.load_from_file(path) if ok else null
	if presented == null or Vector2i(presented.get_width(), presented.get_height()) != size:
		ok = false
		_notes.append("%s presented size %s" % [path.get_file(), Vector2i(presented.get_width(), presented.get_height()) if presented != null else Vector2i.ZERO])
	var ui: Array[String] = []
	for flag: String in _ui_flags():
		ui.append(flag)
	var row := {
		"variant": _variant,
		"quality": String(GraphicsQuality.current_quality()),
		"group": group,
		"mode": mode_name,
		"requested": [size.x, size.y],
		"window": [window_size.x, window_size.y],
		"internal": [internal_size.x, internal_size.y],
		"png": [presented.get_width(), presented.get_height()] if presented != null else [0, 0],
		"source": source,
		"aspect": int(root.content_scale_aspect),
		"scale_mode": int(root.content_scale_mode),
		"scale3d_mode": int(root.scaling_3d_mode),
		"scale3d": root.scaling_3d_scale,
		"estimated_3d_size": [int(floor(float(internal_size.x) * root.scaling_3d_scale)), int(floor(float(internal_size.y) * root.scaling_3d_scale))],
		"screen_space_aa": int(root.screen_space_aa),
		"msaa_3d": int(root.msaa_3d),
		"taa": root.use_taa,
		"fsr_sharpness": root.fsr_sharpness,
		"estimated_3d_pixels": float(internal_size.x * internal_size.y) * root.scaling_3d_scale * root.scaling_3d_scale,
		"budget_3d_pixels": float(BASE.x * BASE.y) * scale3d * scale3d,
		"fov": (_view if _view != null else _camera).fov,
		"camera_distance": (_view if _view != null else _camera).global_position.distance_to(_player.global_position),
		"player_xyz": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"camera_xyz": [_view.global_position.x, _view.global_position.y, _view.global_position.z],
		"camera_forward": [-_view.global_basis.z.x, -_view.global_basis.z.y, -_view.global_basis.z.z],
		"head_uv": _head_uv(),
		"feet_uv": _feet_uv(),
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"bars": _bars(presented) if presented != null else {},
		"ui": ui,
		"flat": presented == null or _is_flat(presented),
		"ok": ok and presented != null and not _is_flat(presented),
		"file": path,
		"player_xf": _player.global_transform,
		"camera_xf": _camera.global_transform,
	}
	_shots.append(row)
	print("STRETCH_SHOT %s" % JSON.stringify(_public_row(row)))


func _apply_window(size: Vector2i, mode_name: String, scale3d: float) -> bool:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(size)
	root.content_scale_size = BASE
	if mode_name == "viewport":
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.scaling_3d_mode = _project_3d_mode
	# Runtime graphics owner, not the capture harness, sets the 3D scale.
	await process_frame
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(Vector2i.ZERO)
		await process_frame
	if _clarity:
		# Resolve the production policy after resize, then override only 3D scale for B/D.
		root.scaling_3d_scale = 1.0 if _native_override else _production_scale
		for _i: int in 4:
			await process_frame
	return DisplayServer.window_get_size() == size


func _grab_presented(path: String, size: Vector2i) -> bool:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		_notes.append("no DISPLAY for the presented grab")
		return false
	var pos := DisplayServer.window_get_position()
	var output: Array = []
	var code := OS.execute("ffmpeg", PackedStringArray([
		"-y", "-loglevel", "error",
		"-f", "x11grab", "-draw_mouse", "0",
		"-video_size", "%dx%d" % [size.x, size.y],
		"-i", "%s+%d,%d" % [display, pos.x, pos.y],
		"-frames:v", "1", path,
	]), output, true)
	if code != 0:
		_notes.append("ffmpeg exit %d %s" % [code, " ".join(output)])
		return false
	return FileAccess.file_exists(path)


func _shot_path(group: String, mode_name: String, size: Vector2i, scale3d: float) -> String:
	var name := "%dx%d.png" % [size.x, size.y]
	if _clarity:
		return _out.path_join(_variant).path_join(name)
	if group == "scale3d":
		name = "%dx%d_s%03d.png" % [size.x, size.y, int(round(scale3d * 100.0))]
		return _out.path_join("scale3d").path_join(name)
	return _out.path_join(group).path_join(mode_name).path_join(name)


func _remember_pose() -> void:
	_player_xf = _player.global_transform
	var active := root.get_viewport().get_camera_3d()
	_view = active if active != null else _camera
	_camera_xf = _view.global_transform
	_pose_ready = true


func _lock_pose() -> void:
	if not _pose_ready:
		return
	_player.global_transform = _player_xf
	_player.velocity = Vector3.ZERO
	if _view != null:
		_view.global_transform = _camera_xf


func _freeze_actors(frozen: bool) -> void:
	_player.set_process(not frozen)
	_player.set_physics_process(not frozen)
	_camera.set_process(not frozen)
	_camera.set_physics_process(not frozen)
	if _view != null and _view != _camera:
		_view.set_process(not frozen)
		_view.set_physics_process(not frozen)
	Engine.time_scale = 0.0 if frozen else 1.0


func _wait_context(world: Node, limit: int) -> WorldContext:
	for _i: int in limit:
		await process_frame
		if world.has_method(&"get_context"):
			var ctx: Variant = world.call(&"get_context")
			if ctx is WorldContext and (ctx as WorldContext).player != null and (ctx as WorldContext).camera != null:
				return ctx as WorldContext
	return null


func _bearings(world: Node) -> FirstExitBearings:
	if not world.has_method(&"get_context"):
		return null
	var ctx: Variant = world.call(&"get_context")
	if not (ctx is WorldContext):
		return null
	return (ctx as WorldContext).get_system(BEARINGS_SCRIPT) as FirstExitBearings


func _hide_debug(node: Node) -> void:
	for node_name: String in ["DebugTime", "StatsDisplay", "DevDioramaMap", "TesterReport", "TapeRecorder"]:
		var found := node.find_child(node_name, true, false)
		if found != null and found.has_method(&"hide"):
			found.call(&"hide")


func _head_uv() -> String:
	return _project_uv(_player.global_position + Vector3(0.0, 1.65, 0.0))


func _feet_uv() -> String:
	return _project_uv(_player.global_position + Vector3(0.0, 0.05, 0.0))


func _project_uv(point: Vector3) -> String:
	var camera := _view if _view != null else _camera
	if camera.is_position_behind(point):
		return "behind"
	var p := camera.unproject_position(point)
	var s := camera.get_viewport().get_visible_rect().size
	if s.x <= 1.0 or s.y <= 1.0:
		return "no-viewport"
	return "%.3f,%.3f" % [p.x / s.x, p.y / s.y]


func _bars(image: Image) -> Dictionary:
	return {
		"left": _band_dark(image, true, true),
		"right": _band_dark(image, true, false),
		"top": _band_dark(image, false, true),
		"bottom": _band_dark(image, false, false),
	}


func _band_dark(image: Image, vertical: bool, at_start: bool) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	var band := maxi(2, int(float(width if vertical else height) * 0.015))
	var dark := 0
	var total := 0
	var steps := 24
	for i: int in steps:
		var x := band / 2
		var y := int(float(height) * (float(i) + 0.5) / float(steps))
		if not at_start:
			x = width - 1 - x
		if not vertical:
			x = int(float(width) * (float(i) + 0.5) / float(steps))
			y = band / 2 if at_start else height - 1 - band / 2
		if _luma(image.get_pixel(x, y)) < 0.035:
			dark += 1
		total += 1
	var cx := width / 2
	var cy := height / 2
	return total > 0 and float(dark) / float(total) > 0.85 and _luma(image.get_pixel(cx, cy)) > 0.06


func _is_flat(image: Image) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	var low := 1.0
	var high := 0.0
	for i: int in 16:
		for j: int in 16:
			var luma := _luma(image.get_pixel(int(float(width) * (float(i) + 0.5) / 16.0), int(float(height) * (float(j) + 0.5) / 16.0)))
			low = minf(low, luma)
			high = maxf(high, luma)
	return high - low < 0.04


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _ui_flags() -> PackedStringArray:
	var flags := PackedStringArray()
	var view := root.get_visible_rect()
	for layer: Variant in root.find_children("*", "CanvasLayer", true, false):
		if not (layer is CanvasLayer):
			continue
		for node: Variant in (layer as Node).find_children("*", "Control", true, false):
			if flags.size() >= 16 or not (node is Control):
				continue
			var control := node as Control
			if not control.is_visible_in_tree() or control.size.x < 8.0 or control.size.y < 8.0:
				continue
			var rect := control.get_global_rect()
			var outside := rect.position.x < -2.0 or rect.position.y < -2.0 or rect.end.x > view.size.x + 2.0 or rect.end.y > view.size.y + 2.0
			var fullscreen := absf(rect.size.x - view.size.x) < 4.0 and absf(rect.size.y - view.size.y) < 4.0
			if outside and not fullscreen:
				flags.append("outside %s" % control.get_path())
			if control is Label:
				var label := control as Label
				var need := label.get_minimum_size()
				if need.x > label.size.x + 3.0 or need.y > label.size.y + 3.0:
					flags.append("clipped %s" % label.get_path())
	return flags


func _required_ok() -> bool:
	var wanted := {"hud": 10, "interior": 6, "inventory": 6, "scale3d": 4}
	var got := {"hud": 0, "interior": 0, "inventory": 0, "scale3d": 0}
	for shot: Dictionary in _shots:
		if not bool(shot["ok"]):
			continue
		var size: Array = shot["requested"]
		if int(size[0]) >= 3840:
			continue
		var group := String(shot["group"])
		if got.has(group):
			got[group] = int(got[group]) + 1
	for group: String in wanted:
		if int(got[group]) < int(wanted[group]):
			_notes.append("%s ok %s/%s" % [group, got[group], wanted[group]])
			return false
	return true


func _public_row(row: Dictionary) -> Dictionary:
	var copy := row.duplicate()
	copy.erase("player_xf")
	copy.erase("camera_xf")
	return copy


func _note_list() -> Array[String]:
	var notes: Array[String] = []
	for note: String in _notes:
		notes.append(note)
	return notes


func _log_renderer() -> void:
	print("STRETCH_RENDERER driver=%s method=%s adapter=%s vendor=%s aspect=%s scale3d_mode=%s scale3d=%s" % [
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
		int(_project_aspect),
		int(_project_3d_mode),
		_project_3d_scale,
	])


func _finish(code: int) -> void:
	var public_shots: Array[Dictionary] = []
	for shot: Dictionary in _shots:
		public_shots.append(_public_row(shot))
	var report := {
		"base": [BASE.x, BASE.y],
		"project_stretch": _project_stretch,
		"clarity": _clarity,
		"frozen_scene": _clarity and paused,
		"case_mode": _case_mode,
		"case_group": _case_group,
		"case_size": [_case_size.x, _case_size.y],
		"case_scale3d": _case_scale,
		"project_aspect": int(_project_aspect),
		"project_scale3d_mode": int(_project_3d_mode),
		"project_scale3d": _project_3d_scale,
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"notes": _note_list(),
		"shots": public_shots,
		"passed": code == 0,
	}
	var path := _out.path_join("manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("STRETCH_DONE passed=%s notes=%s" % [code == 0, " | ".join(_notes)])
	quit(code)


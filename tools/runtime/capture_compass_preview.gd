extends SceneTree

## Real Key West viewport run for the First Exit compass. Not a drawn HUD stand-in.
## The production scene is instanced with spawn_at_shelter forced off for this process only.
## Run: xvfb-run -a godot --path . --resolution 960x540 --rendering-driver vulkan \
##   --rendering-method forward_plus --audio-driver Dummy --fixed-fps 15 \
##   --script res://tools/runtime/capture_compass_preview.gd -- <out_dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OTHER_SCENE: String = "res://archive/graciosa/scenes/Graciosa_Island_Terrain.tscn"
const BEARINGS_SCRIPT: GDScript = preload("res://scripts/world/first_exit_bearings.gd")
const PITCH_DEG: float = -6.0
const SWEEP_FRAMES: int = 60
const HOLD_FRAMES: int = 24
const SHORT_FRAMES: int = 18

var _out: String = ""
var _frames_dir: String = ""
var _stills_dir: String = ""
var _frame_i: int = 0
var _checks: Dictionary = {}
var _notes: Array[String] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://compass_preview"
	if _out.begins_with("user://"):
		_out = ProjectSettings.globalize_path(_out)
	_frames_dir = _out.path_join("frames")
	_stills_dir = _out.path_join("stills")
	DirAccess.make_dir_recursive_absolute(_frames_dir)
	DirAccess.make_dir_recursive_absolute(_stills_dir)
	_run()


func _run() -> void:
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	world.set(&"spawn_at_shelter", false)
	root.add_child(world)
	var ctx: WorldContext = await _wait_context(world, 240)
	if ctx == null:
		_fail("world_ready", "Key West context did not appear")
		_finish(1)
		return
	var bearings := ctx.get_system(BEARINGS_SCRIPT) as FirstExitBearings
	var player := ctx.player as CharacterBody3D
	var camera := ctx.camera as TpsCamera
	if bearings == null or player == null or camera == null:
		_fail("world_ready", "compass, Henry or the TPS camera is missing")
		_finish(1)
		return
	_set_render(false)
	for _i: int in 8:
		await physics_frame
	_check("scenario_start_arms_single_727",
		bearings.has_active_target() and bearings.active_label() == "727" and bearings.active_target_id == bearings.shelter_id(),
		"active=%s label=%s" % [bearings.active_target_id, bearings.active_label()])
	_set_render(true)
	await process_frame
	await _record(6, "01_start.png")
	await _sweep(player, camera, bearings)
	var shelter := world.find_child("Shelter727", true, false) as KeyWest727Shelter
	if shelter == null:
		_fail("interior_clears_marker", "Shelter727 is not in the scene")
		_finish(1)
		return
	var zone := _shelter_zone(shelter)
	await _approach(world, player, camera, bearings, zone)
	await _enter_and_leave(player, camera, bearings, zone)
	await _recall(bearings)
	await _save_inside(world, player, camera, bearings, zone)
	world.queue_free()
	for _i: int in 3:
		await process_frame
	await _other_profile()
	var code: int = 0 if _all_ok() else 1
	_finish(code)


func _sweep(player: CharacterBody3D, camera: TpsCamera, bearings: FirstExitBearings) -> void:
	var from := Vector2(player.global_position.x, player.global_position.z)
	var geographic: float = FirstExitBearings.bearing_of(from, bearings.active_xz())
	var sign_yaw: float = await _yaw_sign(camera)
	var offset: float = await _bearing_at_yaw(camera, 0.0)
	var relatives: Array[float] = []
	var saw_edge: bool = false
	var saw_ahead: bool = false
	var geo_drift: float = 0.0
	for i: int in SWEEP_FRAMES:
		var yaw: float = TAU * float(i) / float(SWEEP_FRAMES)
		camera.set_look(yaw, PITCH_DEG)
		camera.snap_to_target()
		await process_frame
		var cam_b: float = FirstExitBearings.camera_bearing(camera)
		var geo: float = FirstExitBearings.bearing_of(from, bearings.active_xz())
		geo_drift = maxf(geo_drift, absf(wrapf(geo - geographic, -PI, PI)))
		var rel: float = FirstExitBearings.relative_bearing(cam_b, geo)
		relatives.append(rel)
		var slot: Dictionary = FirstExitBearings.marker_slot(rel)
		if int(slot["edge"]) != 0:
			saw_edge = true
		if bool(slot["on_strip"]) and absf(float(slot["u"])) < 0.2:
			saw_ahead = true
		await _record(1, "02_edge.png" if int(slot["edge"]) != 0 and not FileAccess.file_exists(_stills_dir.path_join("02_edge.png")) else "")
	var wrap_yaw_a: float = _yaw_for_bearing(deg_to_rad(359.0), offset, sign_yaw)
	var wrap_yaw_b: float = _yaw_for_bearing(deg_to_rad(1.0), offset, sign_yaw)
	var before: float = await _bearing_at_yaw(camera, wrap_yaw_a)
	var after: float = await _bearing_at_yaw(camera, wrap_yaw_b)
	var step: float = wrapf(after - before, -PI, PI)
	await _record(8, "03_wrap.png")
	var span: float = _bearing_span(relatives)
	_check("marker_follows_camera", span > deg_to_rad(300.0) and geo_drift < deg_to_rad(2.0) and saw_ahead,
		"span_deg=%.1f geo_drift_deg=%.2f ahead=%s" % [rad_to_deg(span), rad_to_deg(geo_drift), saw_ahead])
	_check("edge_indicator", saw_edge, "the 727 mark never left the ±50° tape")
	_check("wrap_359_to_0", absf(rad_to_deg(step) - 2.0) < 20.0,
		"camera step across north was %.1f deg (before %.1f after %.1f)" % [rad_to_deg(step), rad_to_deg(before), rad_to_deg(after)])


func _approach(world: Node3D, player: CharacterBody3D, camera: TpsCamera, bearings: FirstExitBearings, zone: Area3D) -> void:
	var door := Vector3(bearings.shelter_xz().x, player.global_position.y, bearings.shelter_xz().y)
	var ground: Node = world.find_child("RealityGround", true, false)
	_set_render(false)
	_place(player, door)
	var waited: int = 0
	while waited < 600 and not (ground != null and ground.has_method(&"has_ground_at") and bool(ground.call(&"has_ground_at", door.x, door.z))):
		await process_frame
		waited += 1
	for _i: int in 6:
		await physics_frame
	if zone != null and _overlaps_727(bearings, zone):
		var away: Vector3 = door + (door - zone.global_position)
		away.y = door.y
		_place(player, away + Vector3.UP * 0.2)
		for _i: int in 4:
			await physics_frame
	await _aim_at(camera, player, zone.global_position if zone != null else door)
	await process_frame
	_set_render(true)
	await process_frame
	_check("chunk_at_727", waited < 600, "ground chunk was not live after %d frames" % waited)
	await _record(HOLD_FRAMES, "04_approach.png")


func _enter_and_leave(player: CharacterBody3D, camera: TpsCamera, bearings: FirstExitBearings, zone: Area3D) -> void:
	if zone == null:
		_fail("interior_clears_marker", "727 has no ShelterZone")
		return
	var outside: Vector3 = player.global_position
	var inside: Vector3 = zone.global_position + Vector3.UP * 0.4
	_set_render(false)
	for step: int in 8:
		_place(player, outside.lerp(inside, float(step + 1) / 8.0))
		await process_frame
		await physics_frame
		await physics_frame
	await _aim_at(camera, player, inside + Vector3(0, 1.2, 2.0))
	await process_frame
	_set_render(true)
	await process_frame
	var overlapped: bool = _overlaps_727(bearings, zone)
	_check("interior_real_overlap", overlapped, "the thermal probe is not inside a 727 zone")
	_check("interior_clears_marker", overlapped and bearings.active_target_id == "" and bearings.is_visited(bearings.shelter_id()),
		"active=%s visited=%s" % [bearings.active_target_id, bearings.is_visited(bearings.shelter_id())])
	await _record(HOLD_FRAMES, "05_interior_cleared.png")
	_set_render(false)
	for step: int in 8:
		_place(player, inside.lerp(outside, float(step + 1) / 8.0))
		await process_frame
		await physics_frame
	_set_render(true)
	_check("exit_does_not_restore", bearings.active_target_id == "" and not _overlaps_727(bearings, zone),
		"active=%s still_inside=%s" % [bearings.active_target_id, _overlaps_727(bearings, zone)])
	await _record(SHORT_FRAMES, "06_exit.png")


func _recall(bearings: FirstExitBearings) -> void:
	var before: String = bearings.active_target_id
	await _tap_recall()
	_check("recall_r", bearings.active_target_id == bearings.shelter_id() and before == "",
		"before=%s after=%s" % [before, bearings.active_target_id])
	await _record(SHORT_FRAMES, "07_recall.png")


func _save_inside(world: Node3D, player: CharacterBody3D, camera: TpsCamera, bearings: FirstExitBearings, zone: Area3D) -> void:
	if zone == null:
		_fail("save_load_keeps_manual_marker", "no zone")
		return
	var inside: Vector3 = zone.global_position + Vector3.UP * 0.4
	_set_render(false)
	_place(player, inside)
	for _i: int in 6:
		await process_frame
		await physics_frame
	if bearings.active_target_id != "":
		await _tap_recall()
	if bearings.active_target_id == "":
		await _tap_recall()
	var save := world.get_context().get_system(preload("res://scripts/systems/save/save_manager.gd")) as SaveManager
	var wrote: bool = save != null and save.save_to_slot(4, {"where": "compass_preview"})
	var loaded: bool = wrote and save.load_from_slot(4)
	for _i: int in 8:
		await process_frame
		await physics_frame
	await _aim_at(camera, player, inside + Vector3(0, 1.2, 2.0))
	_set_render(true)
	await process_frame
	var overlapped: bool = _overlaps_727(bearings, zone)
	_check("save_load_keeps_manual_marker",
		wrote and loaded and overlapped and bearings.active_target_id == bearings.shelter_id(),
		"wrote=%s loaded=%s overlap=%s active=%s" % [wrote, loaded, overlapped, bearings.active_target_id])
	await _record(HOLD_FRAMES, "08_loaded_inside.png")


func _other_profile() -> void:
	_set_render(false)
	var other := (load(OTHER_SCENE) as PackedScene).instantiate() as Node
	root.add_child(other)
	var world := other as World
	var ctx: WorldContext = await _wait_context(world if world != null else other, 180)
	var strip := _find_strip(other)
	var bearings: Node = ctx.get_system(BEARINGS_SCRIPT) if ctx != null else null
	var hidden: bool = bearings == null and (strip == null or not strip.visible)
	_set_render(true)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image != null:
		if image.get_width() != 960 or image.get_height() != 540:
			image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		image.save_png(_stills_dir.path_join("09_other_profile.png"))
	_check("other_profile_hides_compass", hidden,
		"bearings=%s strip_visible=%s" % [bearings != null, strip.visible if strip != null else "absent"])
	other.queue_free()


func _wait_context(world: Node, limit: int) -> WorldContext:
	for _i: int in limit:
		await process_frame
		if world != null and world.has_method(&"get_context"):
			var ctx: Variant = world.call(&"get_context")
			if ctx is WorldContext and (ctx as WorldContext).player != null:
				return ctx as WorldContext
	return null


func _yaw_sign(camera: TpsCamera) -> float:
	var origin: float = await _bearing_at_yaw(camera, 0.0)
	var turned: float = await _bearing_at_yaw(camera, deg_to_rad(20.0))
	var delta: float = wrapf(turned - origin, -PI, PI)
	return 0.0 if absf(delta) < 0.01 else signf(delta)


func _bearing_at_yaw(camera: TpsCamera, yaw: float) -> float:
	camera.set_look(yaw, PITCH_DEG)
	camera.snap_to_target()
	await process_frame
	return FirstExitBearings.camera_bearing(camera)


func _yaw_for_bearing(want: float, offset: float, sign_yaw: float) -> float:
	if sign_yaw == 0.0:
		return want
	return (want - offset) / sign_yaw


func _record(count: int, still: String) -> void:
	for i: int in count:
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		if image == null:
			_notes.append("missing viewport image at frame %d" % _frame_i)
			continue
		if image.get_width() != 960 or image.get_height() != 540:
			image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		var path := _frames_dir.path_join("frame_%04d.png" % _frame_i)
		image.save_png(path)
		if still != "" and i == count - 1:
			DirAccess.copy_absolute(path, _stills_dir.path_join(still))
		_frame_i += 1


func _place(player: CharacterBody3D, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _aim_at(camera: TpsCamera, player: CharacterBody3D, target: Vector3) -> void:
	var flat := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
	var bearing: float = atan2(flat.x, -flat.y)
	var offset: float = await _bearing_at_yaw(camera, 0.0)
	var sign_yaw: float = await _yaw_sign(camera)
	camera.set_look(_yaw_for_bearing(bearing, offset, sign_yaw), PITCH_DEG)
	camera.snap_to_target()
	await process_frame


func _tap_recall() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_R
	down.keycode = KEY_R
	down.unicode = 114
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _overlaps_727(bearings: FirstExitBearings, zone: Area3D) -> bool:
	var thermal := bearings.get_node_or_null(^"../ThermalManager") as ThermalManager
	if thermal == null or thermal.zone_probe == null:
		var world := bearings.get_parent()
		if world != null and world.has_method(&"get_context"):
			thermal = (world.call(&"get_context") as WorldContext).get_system(preload("res://scripts/systems/survival/thermal_manager.gd")) as ThermalManager
	if thermal == null or thermal.zone_probe == null:
		return false
	for area: Variant in thermal.zone_probe.get_overlapping_areas():
		if not area is Area3D:
			continue
		var hit := area as Area3D
		if hit == zone or _under_727(hit):
			return true
	return false


func _under_727(area: Node) -> bool:
	var node: Node = area
	while node != null:
		if node is KeyWest727Shelter:
			return true
		node = node.get_parent()
	return false


func _shelter_zone(shelter: Node) -> Area3D:
	var found := shelter.find_child("ShelterZone", true, false) as Area3D
	return found


func _find_strip(root_node: Node) -> CompassStrip:
	return root_node.find_child("CompassStrip", true, false) as CompassStrip


func _bearing_span(samples: Array[float]) -> float:
	if samples.size() < 2:
		return 0.0
	var total: float = 0.0
	var prev: float = samples[0]
	for i: int in range(1, samples.size()):
		total += absf(wrapf(samples[i] - prev, -PI, PI))
		prev = samples[i]
	return total


func _set_render(on: bool) -> void:
	RenderingServer.viewport_set_active(root.get_viewport_rid(), on)


func _check(key: String, ok: bool, detail: String) -> void:
	_checks[key] = ok
	print("COMPASS_CHECK %s %s %s" % [key, "pass" if ok else "fail", detail])
	if not ok:
		_notes.append("%s: %s" % [key, detail])


func _fail(key: String, detail: String) -> void:
	_check(key, false, detail)


func _all_ok() -> bool:
	if _checks.is_empty():
		return false
	for key: Variant in _checks.keys():
		if not bool(_checks[key]):
			return false
	return true


func _finish(code: int) -> void:
	var report: Dictionary = {
		"scene": SCENE,
		"spawn_at_shelter": false,
		"frames": _frame_i,
		"fps": 15,
		"checks": _checks,
		"notes": _notes,
		"passed": code == 0,
	}
	var path := _out.path_join("compass_preview.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("COMPASS_PREVIEW_JSON ", JSON.stringify(report))
	print("compass preview: %s -> %s" % ["passed" if code == 0 else "failed", _out])
	quit(code)

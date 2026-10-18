extends SceneTree

## Phase 3.1 proof for the production snow clipmap.
## Video: real third-person camera at production walk speed.
## Fixed-video: the same world-space patch throughout 5-10 recenter events.
## Numerical witness: stable world-space heightfield samples across live/retained ownership.
## Foot pair: side view of a REAL boot joint at early and deep sink; no debug-sole rendering.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET_NAME := "Duval Street"
const OUT := "res://docs/runtime_previews/key_west/snow_clipmap"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 60
const POST_RECENTER_SETTLE_FRAMES := 6
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const OUTER_HANDOFF_STEPS := 16
const GPU_CAPTURE_LAYER := 1 << 19 # layer 20; isolated diagnostic snow only
const GPU_HEIGHT_DELTA_LIMIT := 0.02 # encoded pixel delta; NOT metres
const GPU_CHANGED_FRACTION_LIMIT := 0.005
const OUTER_HANDOFF_FPS := 4
const FIXED_EVERY_N_FRAMES := 3 # 24 fixed-camera frames / 6 seconds = 4 FPS
const HEIGHT_WITNESS_SPACING_M := 0.5
const HEIGHT_WITNESS_RADIUS := 3
const REVIEW_HOUR := 14.0
const SEAM_SETTLED := 0.25
const MIN_WALK_DISTANCE_M := 8.0
const MIN_RECENTERS := 5
const MAX_RECENTERS := 10
const TPS_PITCH_DEG := -12.0
const FOOT_CONTACT_SINK_M := 0.035
const FOOT_PRESSED_SINK_M := 0.12

var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _fixed_camera: Camera3D
var _foot_camera: Camera3D
var _gpu_camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _day_night: DayNightManager
var _presentation: SnowPresentationSystem
var _shell: SnowShell
var _mover: MovementController
var _street_at := Vector2.ZERO
var _street_yaw := 0.0
var _frame_dir := ""
var _fixed_frame_dir := ""
var _outer_frame_dir := ""
var _gpu_frame_dir := ""
var _gpu_baseline: Image
var _gpu_max_delta := 0.0
var _gpu_max_changed_fraction := 0.0
var _gpu_min_covered := 2147483647
var _gpu_steps: Array[Dictionary] = []
var _gpu_pass := false
var _outer_frames_written := 0
var _outer_ownership: Array[Dictionary] = []
var _outer_was_retained := false
var _outer_was_chunk := false
var _fixed_patch := Vector2.ZERO
var _fixed_frames_written := 0
var _height_witnesses: Array[Dictionary] = []
var _edge_witnesses: Array[Dictionary] = []
var _edge_handoff_delta: float = 0.0
var _baseline_heights: Array[float] = []
var _height_delta_max_m := 0.0
var _height_samples_compared := 0
var _retained_points_after := 0
var _live_points_before := 0
var _start := Vector3.ZERO
var _last_origin := Vector2(INF, INF)
var _recenter_count := 0
var _foot_side := -1
var _foot_contact_saved := false
var _foot_pressed_saved := false
var _foot_sink_samples: Array[float] = []


func _initialize() -> void:
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	ProjectSettings.set_setting("hfn/snow/quality", "high")
	ProjectSettings.set_setting("hfn/snow/clipmap_geometry", true)
	if not _load_street():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_frame_dir = OUT.path_join("frames")
	_fixed_frame_dir = OUT.path_join("fixed_frames")
	_outer_frame_dir = OUT.path_join("outer_frames")
	_gpu_frame_dir = OUT.path_join("gpu_height_frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_frame_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_fixed_frame_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_outer_frame_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_gpu_frame_dir))
	_run()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("cannot load real Key West scene")
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	for _i in range(360):
		await process_frame
		if _world.has_method(&"get_context"):
			_ctx = _world.call(&"get_context")
			if _ctx != null:
				break
	if _ctx == null:
		_fail("WorldContext did not become ready")
		return

	_player = _ctx.player as CharacterBody3D
	_camera = _ctx.camera as Camera3D
	_ground = _world.find_child("RealityGround", true, false)
	_streaming = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	_weather = _ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd")) as WeatherController
	_presentation = _ctx.get_system(preload("res://scripts/systems/world/snow/snow_presentation_system.gd")) as SnowPresentationSystem
	_shell = SnowShell.active
	_mover = _player.get_node_or_null(^"MovementController") as MovementController if _player != null else null
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
		break
	if _player == null or _camera == null or _ground == null or _weather == null or _day_night == null or _presentation == null or _shell == null or _mover == null:
		_fail("missing player/camera/ground/weather/day-night/snow presentation/snow shell/movement")
		return

	var surface := _shell.get_node_or_null("SnowShellMesh") as MeshInstance3D
	if surface == null or String(surface.get_meta(&"snow_geometry", "")) != "clipmap_l0_l1_l2":
		_fail("production SnowShell did not install three radial LOD zones")
		return

	_hide_hud()
	_weather.set_weather(&"calm", true)
	_presentation.load_save_data({"settled": SEAM_SETTLED, "frost": 0.35, "storm": 0.4})
	_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + REVIEW_HOUR
	_day_night.force_update_lighting()
	_day_night.set_process(false)
	_place()
	await _wait_until_streamed()
	_shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(POST_RECENTER_SETTLE_FRAMES)

	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _street_yaw, TPS_PITCH_DEG)
	_camera.make_current()
	await _wait_frames(2)

	_start = _player.global_position
	_last_origin = _shell.get_origin()
	_build_fixed_camera(_start)
	_build_gpu_camera()
	_build_foot_camera()
	await _capture_radial_lod_debug()
	_record_height_witness("before")
	_record_edge_witness("before")
	await _capture_with_camera(_fixed_camera, OUT.path_join("handoff_fixed_before.png"))
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), OUT.path_join("start.png"))

	_press_walk_input()
	for i: int in range(VIDEO_FRAMES):
		await _capture_tps_frame(i)
		await _maybe_capture_foot_y()
		if i % FIXED_EVERY_N_FRAMES == 0:
			await _capture_fixed_frame()
	_release_motion_input()
	_player.velocity = Vector3.ZERO
	await _wait_frames(1)

	var finish := _player.global_position
	var walked := Vector2(_start.x, _start.z).distance_to(Vector2(finish.x, finish.z))
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), OUT.path_join("end.png"))
	await _capture_with_camera(_fixed_camera, OUT.path_join("handoff_fixed_after.png"))
	_record_height_witness("after")
	_record_edge_witness("after")
	_camera.make_current()
	# Stage 2: same fixed camera observes retained history turning into
	# SnowChunkCover, without changing the real-TPS first six seconds.
	await _probe_outer_owner_transition()
	_gpu_pass = _gpu_min_covered >= 5000 and _gpu_max_changed_fraction <= GPU_CHANGED_FRACTION_LIMIT
	_write_report(surface, walked)
	if walked < MIN_WALK_DISTANCE_M:
		_fail("Henry traversed %.2f m; need %.2f m for TPS seam proof" % [walked, MIN_WALK_DISTANCE_M])
		return
	if _recenter_count < MIN_RECENTERS or _recenter_count > MAX_RECENTERS:
		_fail("TPS proof observed %d recenter events; expected %d..%d" % [_recenter_count, MIN_RECENTERS, MAX_RECENTERS])
		return
	var retained_texture := _shell.get("_trail_packed_tex") as ImageTexture
	if retained_texture == null or retained_texture.get_width() != _shell.packed_res:
		_fail("retained GPU history lost source resolution during the window handoff")
		return
	if not _foot_contact_saved or not _foot_pressed_saved:
		_fail("foot-Y proof did not capture both sink stages")
		return
	if not _outer_was_retained or not _outer_was_chunk or _outer_frames_written != OUTER_HANDOFF_STEPS:
		_fail("outer probe did not observe retained->chunk with all expected frames")
		return
	if _edge_handoff_delta > 0.05:
		_fail("fixed-patch fade changed %.3f across owner switch" % _edge_handoff_delta)
		return
	if _fixed_frames_written != VIDEO_FRAMES / FIXED_EVERY_N_FRAMES:
		_fail("stationary camera: expected 24 frames, got %d" % _fixed_frames_written)
		return
	if _live_points_before <= 0 or _retained_points_after <= 0 or _height_samples_compared <= 0:
		_fail("heightfield witness did not cross live -> retained ownership")
		return
	print("SNOW_CLIPMAP_PHASE31 pass frames=%d settled=%.2f traverse=%.2fm recenter=%d step=%.2fm walk=%.2f foot=%s driver=%s" % [
		VIDEO_FRAMES, SEAM_SETTLED, walked, _recenter_count, _shell.recentre_step_m,
		_mover.walk_speed, str(_foot_sink_samples), RenderingServer.get_current_rendering_driver_name()])
	quit(0)



## Static overview of the actual three radial tessellation zones.
## Capture-only debug shader overlay; restored before TPS or deformation proof.
func _capture_radial_lod_debug() -> void:
	var surface := _shell.get_node_or_null("SnowShellMesh") as MeshInstance3D
	if surface == null:
		return
	var material := surface.material_override as ShaderMaterial
	if material == null:
		return
	var overview := Camera3D.new()
	overview.name = "SnowRadialLodCamera"
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = 31.0
	overview.far = 100.0
	_world.add_child(overview)
	overview.global_position = _player.global_position + Vector3(0.0, 40.0, 0.0)
	overview.look_at(_player.global_position, Vector3.FORWARD)
	material.set_shader_parameter("debug_lod_ownership", true)
	await _capture_with_camera(overview, OUT.path_join("radial_three_ring_debug.png"))
	material.set_shader_parameter("debug_lod_ownership", false)
	_camera.make_current()
	overview.queue_free()


func _capture_tps_frame(index: int) -> void:
	await process_frame
	var origin: Vector2 = _shell.get_origin()
	if _last_origin.x != INF and not origin.is_equal_approx(_last_origin):
		_recenter_count += 1
		_record_height_witness("recenter_%d" % _recenter_count)
		_record_edge_witness("recenter_%d" % _recenter_count)
	_last_origin = origin
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), _frame_dir.path_join("frame_%04d.png" % index))



## Controlled stress test: snapshot at the SAME world-space patch after each
## real recenter/owner change. The player is frozen: there is no animation,
## weather clock or new footstep to corrupt the static comparison. This stage
## is *not* presented as real walking and runs after the normal 6s TPS video.
func _probe_outer_owner_transition() -> void:
	var old_physics: bool = _shell.is_physics_processing()
	_shell.set_physics_process(false)
	var old_scale: float = Engine.time_scale
	Engine.time_scale = 0.0
	var start_origin: Vector2 = _shell.get_origin()
	var static_player := Vector2(_player.global_position.x, _player.global_position.z)
	await _capture_gpu_height_frame(0, static_player)
	for i: int in range(OUTER_HANDOFF_STEPS):
		var wanted: Vector2 = start_origin + Vector2(float(i + 1) * _shell.recentre_step_m, 0.0)
		_shell.recentre_to(wanted + Vector2.ONE * (_shell.window_m * 0.5))
		# Simulate the actor following the window. The real gameplay fade uses
		# the continuously moving Henry position, NOT snapped recenter.
		var virtual_player: Vector2 = wanted + Vector2.ONE * (_shell.window_m * 0.5)
		RenderingServer.global_shader_parameter_set(&"snow_player_xz", virtual_player)
		_fixed_camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		_save_image(_capture_image(), _outer_frame_dir.path_join("frame_%04d.png" % i))
		_outer_frames_written += 1
		var live: Vector2 = _shell.get_origin()
		var previous: Vector2 = _shell.get("_trail_origin")
		var owner: String = "live" if _in_window(_fixed_patch, live) else ("retained" if _in_window(_fixed_patch, previous) else "chunk")
		_outer_was_retained = _outer_was_retained or owner == "retained"
		_outer_was_chunk = _outer_was_chunk or owner == "chunk"
		var t: float = clampf((_fixed_patch.distance_to(virtual_player) - 18.0) / 7.0, 0.0, 1.0)
		var detail: float = 1.0 - t * t * (3.0 - 2.0 * t)
		if owner == "chunk" and not _outer_ownership.is_empty():
			var prior: Dictionary = _outer_ownership.back()
			if String(prior.get("owner", "")) == "retained" and float(prior.get("history_detail", 1.0)) > 0.05:
				_fail("history was evicted before the distance fade finished")
				return
		_outer_ownership.append({
			"step": i + 1,
			"owner": owner,
			"history_detail": detail,
			"virtual_player_xz": [virtual_player.x, virtual_player.y],
			"live_origin": [live.x, live.y],
			"retained_origin": [previous.x, previous.y],
			"fixed_patch_xz": [_fixed_patch.x, _fixed_patch.y],
		})
		await _capture_gpu_height_frame(i + 1, static_player)
		RenderingServer.global_shader_parameter_set(&"snow_player_xz", virtual_player)
	_camera.make_current()
	Engine.time_scale = old_scale
	_shell.set_physics_process(old_physics)


## Keep the same real-time traversal, but freeze exactly one render frame for
## each side-camera shot. Recording 24 frames rather than 72 stays inside the
## existing 420-second Lavapipe budget and avoids a second workflow.
func _capture_fixed_frame() -> void:
	var previous_scale: float = Engine.time_scale
	Engine.time_scale = 0.0
	_fixed_camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), _fixed_frame_dir.path_join("frame_%04d.png" % _fixed_frames_written))
	_fixed_frames_written += 1
	_camera.make_current()
	Engine.time_scale = previous_scale


## This is a HEIGHTFIELD witness, not a claim to sample the final tessellated
## GPU vertex. The numeric base height must not suddenly jump when the owner
## changes from live SnowField to the retained frozen field image.
func _record_height_witness(stage: String) -> void:
	var live_origin: Vector2 = _shell.get_origin()
	var trail_origin: Vector2 = _shell.get("_trail_origin")
	var trail_material := _shell.get("_trail_material") as ShaderMaterial
	var trail_image: Image
	if trail_material != null:
		var tex := trail_material.get_shader_parameter("field") as Texture2D
		if tex != null:
			trail_image = tex.get_image()
	var samples: Array[Dictionary] = []
	var max_error: float = 0.0
	var matched := 0
	var owners := {"live": 0, "retained": 0, "outer": 0}
	for z: int in range(-HEIGHT_WITNESS_RADIUS, HEIGHT_WITNESS_RADIUS + 1):
		for x: int in range(-HEIGHT_WITNESS_RADIUS, HEIGHT_WITNESS_RADIUS + 1):
			var at := _fixed_patch + Vector2(x, z) * HEIGHT_WITNESS_SPACING_M
			var owner := "outer"
			var height: float = -INF
			if _in_window(at, live_origin):
				height = _shell.field.get_snow_top(at.x, at.y)
				owner = "live"
			elif trail_image != null and _in_window(at, trail_origin):
				owner = "retained"
				height = _bilinear_red(trail_image, (at - trail_origin) / _shell.window_m)
			owners[owner] = int(owners[owner]) + 1
			var entry := {"xz": [at.x, at.y], "owner": owner, "heightfield_top_m": height if is_finite(height) else null}
			if stage == "before":
				_baseline_heights.append(height)
			else:
				var original: float = _baseline_heights[samples.size()]
				if is_finite(height) and is_finite(original):
					var delta: float = absf(height - original)
					entry["baseline_delta_m"] = delta
					max_error = maxf(max_error, delta)
					matched += 1
				samples.append(entry)
	_height_delta_max_m = maxf(_height_delta_max_m, max_error)
	_height_samples_compared += matched
	if stage == "before":
		_live_points_before = int(owners["live"])
	if stage == "after":
		_retained_points_after = int(owners["retained"])
	_height_witnesses.append({
		"stage": stage, "recenter_count": _recenter_count,
		"origin": [live_origin.x, live_origin.y],
		"owners": owners, "compared": matched,
		"max_heightfield_delta_m": max_error, "samples": samples,
	})


## Mirror snow_ground.gdshader's smoothstep-of-union at a fixed world point.
## This only gates discontinuities across an actual owner change; it does not
## mistake weather, Henry or newly produced footprints for geometry changes.
func _record_edge_witness(stage: String) -> void:
	var live: Vector2 = _shell.get_origin()
	var trail: Vector2 = _shell.get("_trail_origin")
	var own: float = _edge_at(_fixed_patch, live)
	var historical: float = _edge_at(_fixed_patch, trail)
	var combined: float = maxf(own, historical)
	var owner: String = "live" if _in_window(_fixed_patch, live) else ("retained" if _in_window(_fixed_patch, trail) else "outer")
	var previous: Dictionary = _edge_witnesses.back() if not _edge_witnesses.is_empty() else {}
	if not previous.is_empty() and owner != String(previous.get("owner", "")) and owner != "outer":
		_edge_handoff_delta = maxf(_edge_handoff_delta, absf(combined - float(previous.get("combined_fade", 0.0))))
	_edge_witnesses.append({
		"stage": stage, "owner": owner, "live_fade": own,
		"historical_fade": historical, "combined_fade": combined,
	})


func _edge_at(at: Vector2, origin: Vector2) -> float:
	if not is_finite(origin.x):
		return 0.0
	var rim: Vector2 = Vector2(
		minf(at.x - origin.x, origin.x + _shell.window_m - at.x),
		minf(at.y - origin.y, origin.y + _shell.window_m - at.y)
	)
	var t: float = clampf(minf(rim.x, rim.y) / 6.0, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _in_window(at: Vector2, origin: Vector2) -> bool:
	if not is_finite(origin.x):
		return false
	var margin := 0.25
	return at.x >= origin.x + margin and at.y >= origin.y + margin \
		and at.x < origin.x + _shell.window_m - margin \
		and at.y < origin.y + _shell.window_m - margin


func _bilinear_red(img: Image, uv: Vector2) -> float:
	var p := uv * Vector2(img.get_width(), img.get_height()) - Vector2(0.5, 0.5)
	var px := clampi(floori(p.x), 0, img.get_width() - 2)
	var py := clampi(floori(p.y), 0, img.get_height() - 2)
	var fx := clampf(p.x - float(px), 0.0, 1.0)
	var fy := clampf(p.y - float(py), 0.0, 1.0)
	var a: float = lerpf(img.get_pixel(px, py).r, img.get_pixel(px + 1, py).r, fx)
	var b: float = lerpf(img.get_pixel(px, py + 1).r, img.get_pixel(px + 1, py + 1).r, fx)
	return lerpf(a, b, fy)


func _maybe_capture_foot_y() -> void:
	if _foot_contact_saved and _foot_pressed_saved:
		return
	var left: float = _shell.get_foot_sink(0)
	var right: float = _shell.get_foot_sink(1)
	if _foot_side < 0:
		var side: int = 0 if left >= right else 1
		var sink: float = maxf(left, right)
		if sink >= FOOT_CONTACT_SINK_M:
			_foot_side = side
			await _capture_foot_stage(OUT.path_join("foot_y_contact.png"), sink)
			_foot_contact_saved = true
		return
	var same_sink: float = _shell.get_foot_sink(_foot_side)
	if not _foot_pressed_saved and same_sink >= FOOT_PRESSED_SINK_M:
		await _capture_foot_stage(OUT.path_join("foot_y_pressed.png"), same_sink)
		_foot_pressed_saved = true


## Freeze simulation for the extra render frame so the two stills really correspond
## to the measured sink stage instead of sinking further while the camera switches.
func _capture_foot_stage(path: String, sink_m: float) -> void:
	_update_foot_camera(_foot_side)
	var previous_scale: float = Engine.time_scale
	Engine.time_scale = 0.0
	_foot_camera.cull_mask = _camera.cull_mask & ~SnowShell.CONTACT_LAYER
	_foot_camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), path)
	Engine.time_scale = previous_scale
	_camera.make_current()
	_foot_sink_samples.append(sink_m)


func _build_fixed_camera(start: Vector3) -> void:
	_fixed_camera = Camera3D.new()
	_fixed_camera.name = "SnowHandoffFixedCamera"
	_fixed_camera.fov = 58.0
	_fixed_camera.near = 0.08
	_fixed_camera.far = 180.0
	_world.add_child(_fixed_camera)
	var forward: Vector3 = Basis(Vector3.UP, _street_yaw) * Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	## This patch starts behind Henry, exactly where the old capture visibly rewrote
	## from local snow to coarse chunk cover during the traversal.
	var patch := start - forward * 5.0 + right * 4.0
	_fixed_patch = Vector2(patch.x, patch.z)
	var ground_y := _ground_height(patch.x, patch.z)
	var target := Vector3(patch.x, ground_y + 0.08, patch.z)
	_fixed_camera.global_position = target - forward * 5.0 - right * 5.5 + Vector3.UP * 5.0
	_fixed_camera.look_at(target, Vector3.UP)



## Production spatial vertex displacement, read through diagnostic emission.
## The production vertex() calculation is not bypassed by this instrument.
func _build_gpu_camera() -> void:
	_gpu_camera = Camera3D.new()
	_gpu_camera.name = "SnowGpuVertexHeightCamera"
	_gpu_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_gpu_camera.size = 10.0
	_gpu_camera.near = 0.1
	_gpu_camera.far = 55.0
	_gpu_camera.cull_mask = GPU_CAPTURE_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_gpu_camera.environment = env
	_world.add_child(_gpu_camera)
	# Capture only snow; the terrain/debug/nav geometry in the normal world
	# previously occupied almost every pixel and made the 30px mask invalid.
	for node: Node in _world.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var mat := mesh_instance.get_active_material(0) as ShaderMaterial
		if mat != null and mat.shader != null and mat.shader.resource_path.ends_with("snow_chunk_cover.gdshader"):
			mesh_instance.layers |= GPU_CAPTURE_LAYER
	var ground_y: float = _ground_height(_fixed_patch.x, _fixed_patch.y)
	_gpu_camera.global_position = Vector3(_fixed_patch.x, ground_y + 35.0, _fixed_patch.y)
	_gpu_camera.look_at(Vector3(_fixed_patch.x, ground_y, _fixed_patch.y), Vector3.FORWARD)


func _set_gpu_height_mode(enabled: bool) -> void:
	var live := _shell.get("_surface") as ShaderMaterial
	var trail := _shell.get("_trail_material") as ShaderMaterial
	var chunk := _shell.get("_chunk_snow_material") as ShaderMaterial
	var live_mesh := _shell.get("_mesh") as MeshInstance3D
	var trail_mesh := _shell.get("_trail_mesh") as MeshInstance3D
	if live_mesh != null:
		live_mesh.layers |= GPU_CAPTURE_LAYER
	if trail_mesh != null:
		trail_mesh.layers |= GPU_CAPTURE_LAYER
	for value: Variant in [live, trail, chunk]:
		var mat := value as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("debug_gpu_height", enabled)
			mat.set_shader_parameter("debug_height_reference", _ground_height(_fixed_patch.x, _fixed_patch.y))


func _capture_gpu_height_frame(i: int, static_player: Vector2) -> void:
	RenderingServer.global_shader_parameter_set(&"snow_player_xz", static_player)
	_set_gpu_height_mode(true)
	_gpu_camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _capture_image()
	_save_image(img, _gpu_frame_dir.path_join("frame_%04d.png" % i))
	if _gpu_baseline == null:
		_gpu_baseline = img.duplicate()
	else:
		var witness: Dictionary = _compare_gpu_height_frames(_gpu_baseline, img)
		witness["recenter"] = i
		_gpu_steps.append(witness)
		_gpu_max_delta = maxf(_gpu_max_delta, float(witness["max_red_delta"]))
		_gpu_max_changed_fraction = maxf(_gpu_max_changed_fraction, float(witness["changed_fraction"]))
		_gpu_min_covered = mini(_gpu_min_covered, int(witness["covered_samples"]))
	_set_gpu_height_mode(false)
	_fixed_camera.make_current()


## Compare output from the FINAL GPU vertex shader, not SnowField CPU data.
## G/B mask identifies visible snow; R encodes Y at each interpolated pixel.
func _compare_gpu_height_frames(before: Image, after: Image) -> Dictionary:
	var covered: int = 0
	var changed: int = 0
	var max_delta: float = 0.0
	for y: int in range(6, mini(before.get_height(), after.get_height()) - 6, 5):
		for x: int in range(6, mini(before.get_width(), after.get_width()) - 6, 5):
			var a: Color = before.get_pixel(x, y)
			var b: Color = after.get_pixel(x, y)
			if a.b <= 0.35 or b.b <= 0.35 or a.g <= 0.16 or b.g <= 0.16:
				continue
			covered += 1
			var delta: float = absf(a.r - b.r)
			max_delta = maxf(max_delta, delta)
			if delta > GPU_HEIGHT_DELTA_LIMIT:
				changed += 1
	return {
		"covered_samples": covered,
		"changed_samples": changed,
		"changed_fraction": float(changed) / float(maxi(covered, 1)),
		"max_red_delta": max_delta,
	}


func _build_foot_camera() -> void:
	_foot_camera = Camera3D.new()
	_foot_camera.name = "SnowFootYCamera"
	_foot_camera.fov = 48.0
	_foot_camera.near = 0.08
	_foot_camera.far = 12.0
	_world.add_child(_foot_camera)


func _update_foot_camera(side: int) -> void:
	## An actual rendered foot bone, never a guessed offset from the pelvis.
	## Previous camera was under the snow/inside the contact geometry (red/black).
	var sensor := _player.find_child("FootContactSensor", true, false) as FootContactSensor
	var boot := Vector3.INF
	if sensor != null and sensor.visual != null and sensor.visual.skeleton != null:
		var skeleton: Skeleton3D = sensor.visual.skeleton
		var index: int = skeleton.find_bone("foot_l" if side == 0 else "foot_r")
		if index >= 0:
			boot = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	if not is_finite(boot.x):
		push_warning("snow Phase 3.1: foot bone missing; using contact plane fallback")
		var p: Vector3 = _player.global_position
		boot = Vector3(p.x, _ground_height(p.x, p.z) + 0.12, p.z)
	var forward: Vector3 = Basis(Vector3.UP, _street_yaw) * Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var ground_y: float = _ground_height(boot.x, boot.z)
	var target := Vector3(boot.x, maxf(ground_y + 0.14, boot.y - 0.03), boot.z)
	## 1.65m out, 0.56m up, steeply downward: safely outside both snow
	## and the red contact/collision helper meshes.
	_foot_camera.global_position = target + right * (1.65 if side == 0 else -1.65) - forward * 0.30 + Vector3.UP * 0.56
	_foot_camera.look_at(target, Vector3.UP)


func _capture_with_camera(camera: Camera3D, path: String) -> void:
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), path)


func _press_walk_input() -> void:
	Input.action_release(&"sprint")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"move_backward")
	Input.action_press(&"move_forward", 1.0)


func _load_street() -> bool:
	var file := FileAccess.open(STREET_DATA, FileAccess.READ)
	if file == null:
		_fail("cannot open %s" % STREET_DATA)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("invalid street data JSON")
		return false
	for row: Variant in (parsed as Dictionary).get("streets", []):
		if row is Dictionary and String((row as Dictionary).get("name", "")) == STREET_NAME:
			var at: Array = (row as Dictionary).get("at", [])
			if at.size() < 2:
				break
			_street_at = Vector2(float(at[0]), float(at[1]))
			_street_yaw = deg_to_rad(float((row as Dictionary).get("heading_deg", 0.0)))
			return true
	_fail("street '%s' missing from %s" % [STREET_NAME, STREET_DATA])
	return false


func _hide_hud() -> void:
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false


func _place() -> void:
	var ground_y := _ground_height(_street_at.x, _street_at.y)
	_player.global_position = Vector3(_street_at.x, ground_y + 1.0, _street_at.y)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = _street_yaw
	_player.reset_physics_interpolation()
	if _streaming != null:
		_streaming.scan(_player.global_position)


func _wait_until_streamed() -> void:
	if _streaming == null:
		await _wait_frames(SETTLE_FRAMES)
		return
	var active_at := -1
	for frame: int in range(MAX_WAIT_FRAMES + 1):
		var p := _player.global_position
		var own := StringName("kw_gen_%d_%d" % [floori(p.x / CHUNK_M), floori(p.z / CHUNK_M)])
		if active_at < 0 and _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE:
			active_at = frame
			_place()
		if active_at >= 0 and frame - active_at >= SETTLE_FRAMES:
			return
		await process_frame
	push_warning("snow Phase 3.1 preview: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


func _release_motion_input() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(action)


func _ground_height(x: float, z: float) -> float:
	if _ground != null and _ground.has_method(&"get_height"):
		return float(_ground.call(&"get_height", x, z))
	return 0.0


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _capture_image() -> Image:
	return root.get_texture().get_image()


func _save_image(image: Image, path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)


func _write_report(surface: MeshInstance3D, walked: float) -> void:
	var arrays: Array = surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var report := {
		"diagnostic": "snow Phase 3.1 TPS recenter, retained trail and Y-foot proof",
		"scene": SCENE,
		"street": STREET_NAME,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"geometry": String(surface.get_meta(&"snow_geometry", "")),
		"radial_lod": {
			"l0_radius_m": float(surface.get_meta(&"snow_l0_half_m", 0.0)),
			"l1_radius_m": float(surface.get_meta(&"snow_l1_radius_m", 0.0)),
			"l0_spacing_m": float(surface.get_meta(&"snow_l0_spacing_m", 0.0)),
			"l1_spacing_m": float(surface.get_meta(&"snow_l1_spacing_m", 0.0)),
			"l2_spacing_m": float(surface.get_meta(&"snow_l2_spacing_m", 0.0)),
			"anchoring": "3.2m recenter on 0.32m L2 world grid"
		},
		"l0_half_m": float(surface.get_meta(&"snow_l0_half_m", 0.0)),
		"l0_spacing_m": float(surface.get_meta(&"snow_l0_spacing_m", 0.0)),
		"l1_spacing_m": float(surface.get_meta(&"snow_l1_spacing_m", 0.0)),
		"recentre_step_m": _shell.recentre_step_m,
		"outer_step_m": SnowChunkCover.STEP_M,
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
		"traverse_distance_m": walked,
		"locomotion": "production_walk",
		"walk_speed_mps": _mover.walk_speed,
		"recenter_count": _recenter_count,
		"required_recenter_range": [MIN_RECENTERS, MAX_RECENTERS],
		"video_frames": VIDEO_FRAMES,
		"video_fps": VIDEO_FPS,
		"video_camera": "production_tps",
		"settled_snow": SEAM_SETTLED,
		"fixed_handoff_pair": ["handoff_fixed_before.png", "handoff_fixed_after.png"],
		"fixed_camera_frames": _fixed_frames_written,
		"fixed_camera_fps": VIDEO_FPS / FIXED_EVERY_N_FRAMES,
		"heightfield_witness": {
			"method": "world-space CPU SnowField heightfield versus retained frozen field R; NOT full GPU-displaced vertex",
			"location": [_fixed_patch.x, _fixed_patch.y],
			"max_delta_m": _height_delta_max_m,
			"recenter_edge_witness": _edge_witnesses,
			"max_edge_handoff_delta": _edge_handoff_delta,
			"compared_samples": _height_samples_compared,
			"live_before": _live_points_before,
			"retained_after": _retained_points_after,
			"stages": _height_witnesses,
		},
		"foot_y_captures": ["foot_y_contact.png", "foot_y_pressed.png"],
		"foot_sink_samples_m": _foot_sink_samples,
		"trail_shell": "retained_previous_window",
		"gpu_history": "frozen shaped GPU RGBA; world-tile copy on departure; save quantization only outside live/retained",
		"gpu_height_witness": {
			"method": "GPU vertex displacement encoded in emission, isolated snow-only layer 20, fixed top-down camera, frozen player/weather/light",
			"comparison": "baseline versus 16 forced recenters; pixel red difference, NOT metres",
			"frames": OUTER_HANDOFF_STEPS + 1,
			"min_covered_samples": _gpu_min_covered,
			"max_red_delta": _gpu_max_delta,
			"max_changed_fraction": _gpu_max_changed_fraction,
			"red_delta_threshold": GPU_HEIGHT_DELTA_LIMIT,
			"changed_fraction_threshold": GPU_CHANGED_FRACTION_LIMIT,
			"pass": _gpu_pass,
			"steps": _gpu_steps,
		},
		"outer_handoff_probe": {
			"kind": "frozen-weather forced recenter; TPS stage is real walking",
			"fixed_frames": _outer_frames_written,
			"fixed_fps": OUTER_HANDOFF_FPS,
			"retained_seen": _outer_was_retained,
			"chunk_seen": _outer_was_chunk,
			"steps": _outer_ownership,
		},
	}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _fail(message: String) -> void:
	_release_motion_input()
	push_error("SNOW_CLIPMAP_PHASE31 %s" % message)
	quit(1)

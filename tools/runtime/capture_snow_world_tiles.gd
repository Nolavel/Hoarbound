extends SceneTree

## Real Key West production world-tile renderer, backed by the live SnowShell
## and real FootContactSensor events. Includes movement/fixed/GPU recenter proofs.
const EXPERIMENT: GDScript = preload("res://scripts/systems/world/snow/world_snow_tile_surface.gd")
const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const OUT := "res://docs/runtime_previews/key_west/snow_world_tiles"
const FPS := 12
const FORWARD_FRAMES := 48
const RETURN_FRAMES := 48
const STRESS_STEPS := 16
const VIDEO_FRAMES := FORWARD_FRAMES + RETURN_FRAMES
const TILE_M := 3.2

var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _streaming: StreamingSystem
var _ground: Node
var _weather: WeatherController
var _day_night: DayNightManager
var _presentation: SnowPresentationSystem
var _shell: SnowShell
var _prototype: WorldSnowTileSurface
var _fixed: Camera3D
var _gpu: Camera3D
var _street_at := Vector2.ZERO
var _yaw := 0.0
var _start := Vector3.ZERO
var _forward := Vector2.ZERO
var _last_stamp := Vector2.ZERO
var _stamp_side := 0
var _distance_forward := 0.0
var _distance_return := 0.0
var _stress_max_diff := 0.0
var _stress_min_coverage := 2147483647
var _stress_stats: Array[Dictionary] = []
var _gpu_height_signal: Dictionary = {}
var _baseline: Image
var _frozen_fingerprint: int = 0
var _tile_history_snapshot: Dictionary = {}
var _before: Dictionary
var _after: Dictionary
var _errors: Array[String] = []


func _initialize() -> void:
    ProjectSettings.set_setting("hfn/graphics/quality", "high")
    ProjectSettings.set_setting("hfn/snow/quality", "high")
    ProjectSettings.set_setting("hfn/snow/world_tiles", true)
    if not _read_street():
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("walk_frames")))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("fixed_frames")))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("stress_frames")))
    _run()


func _run() -> void:
    var pack := load(SCENE) as PackedScene
    if pack == null:
        _fail("real Key West scene missing")
        return
    _world = pack.instantiate() as Node3D
    root.add_child(_world)
    for i: int in range(360):
        await process_frame
        if _world.has_method(&"get_context"):
            _ctx = _world.call(&"get_context")
            if _ctx != null:
                break
    if _ctx == null:
        _fail("WorldContext not ready")
        return
    _player = _ctx.player as CharacterBody3D
    _camera = _ctx.camera as Camera3D
    _streaming = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
    _weather = _ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd")) as WeatherController
    _presentation = _ctx.get_system(preload("res://scripts/systems/world/snow/snow_presentation_system.gd")) as SnowPresentationSystem
    _shell = SnowShell.active
    _ground = _world.find_child("RealityGround", true, false)
    for node: Node in _world.find_children("*", "DayNightManager", true, false):
        _day_night = node as DayNightManager
        break
    if _player == null or _camera == null or _ground == null or _shell == null or _weather == null or _day_night == null or _presentation == null:
        _fail("real scene missing required player/ground/weather/snow")
        return
    for node: Node in _world.find_children("*", "CanvasLayer", true, false):
        (node as CanvasLayer).visible = false
    _weather.set_weather(&"calm", true)
    _presentation.load_save_data({"settled": 0.25, "frost": 0.35, "storm": 0.4})
    _day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + 14.0
    _day_night.force_update_lighting()
    _day_night.set_process(false)

    _place()
    await _wait_streamed()
    _shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
    await _wait_frames(8)
    _start = _player.global_position
    var fwd3: Vector3 = Basis(Vector3.UP, _yaw) * Vector3.FORWARD
    _forward = Vector2(fwd3.x, fwd3.z).normalized()
    _last_stamp = Vector2(_start.x, _start.z)

    # Production mode is installed inside DeterministicSnowShell, not an isolated
    # replacement scene. The real simulation and foot events remain running.
    if not _shell is DeterministicSnowShell:
        _fail("not running production DeterministicSnowShell")
        return
    _prototype = (_shell as DeterministicSnowShell).get_world_tiles()
    if _prototype == null:
        _fail("production WorldSnowTiles was not installed")
        return

    _setup_cameras()
    if _camera.has_method(&"set_look"):
        _camera.call(&"set_look", _yaw, -22.0)
    _camera.make_current()
    await _wait_frames(2)
    _before = _prototype.coverage()
    _save_image(_screen(), OUT.path_join("before.png"))

    # Stage A: forward 8m, real player input; persistent world-space stamps.
    _set_input(&"move_forward")
    for i: int in range(FORWARD_FRAMES):
        await _travel_frame(i, true)
    _stop_input()
    _player.velocity = Vector3.ZERO
    var turn := Vector2(_player.global_position.x, _player.global_position.z)
    _distance_forward = turn.distance_to(Vector2(_start.x, _start.z))
    _save_image(_screen(), OUT.path_join("forward_end.png"))

    # Stage B: turn real Henry around and walk the same world tiles back.
    _player.rotation.y = _yaw + PI
    if _camera.has_method(&"set_look"):
        _camera.call(&"set_look", _yaw + PI, -22.0)
    _set_input(&"move_forward")
    for i: int in range(RETURN_FRAMES):
        await _travel_frame(FORWARD_FRAMES + i, false)
    _stop_input()
    _player.velocity = Vector3.ZERO
    _distance_return = turn.distance_to(Vector2(_player.global_position.x, _player.global_position.z))
    _after = _prototype.coverage()
    _save_image(_screen(), OUT.path_join("return_end.png"))
    await _snapshot(_fixed, OUT.path_join("return_fixed.png"))

    # Stage C: no stamps, no actor movement, constant world camera/weather/light.
    # Streaming mesh instances may disappear/recreate; data/mesh are world IDs.
    var old_scale := Engine.time_scale
    Engine.time_scale = 0.0
    var spot := Vector2(_start.x, _start.z)
    _prototype.focus(spot)
    _frozen_fingerprint = _prototype.deformation_fingerprint()
    _tile_history_snapshot = _history_snapshot()
    await _stress_frame(0)
    var shifts := [-1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0]
    for i: int in range(STRESS_STEPS):
        _prototype.focus(spot + Vector2(TILE_M * float(shifts[i]), 0.0))
        await _stress_frame(i + 1)
        # Restoring an unseen tile from SnowTrackStore expands the in-memory
        # history set but is NOT a mutation. Check each pre-existing world tile
        # by ID and exact bytes instead of hashing all newly loaded records.
        if not _history_unchanged():
            _errors.append("existing world tile data changed on recenter step %d" % (i + 1))
    _prototype.focus(spot)
    Engine.time_scale = old_scale
    _after = _prototype.coverage()

    if _distance_forward < 3.0 or _distance_return < 3.0:
        _errors.append("real Henry did not traverse and return at least 3m")
    if _prototype.stamp_count < 6:
        _errors.append("fewer than six actual-path prototype stamps")
    if _stress_min_coverage < 7000:
        _errors.append("GPU height probe had too few visible snow samples")
    if _stress_max_diff > 0.012:
        _errors.append("static GPU height changed by %.4f colour units" % _stress_max_diff)
    # A constant-purple image must not count as proof of unchanged geometry.
    # Require measurable height variation in the fixed GPU snapshot first.
    if float(_gpu_height_signal.get("p01_p99_span", 0.0)) < 0.015:
        _errors.append("GPU probe is nearly flat (red p01-p99 %.4f); no useful vertex-height witness" % float(_gpu_height_signal.get("p01_p99_span", 0.0)))
    if not _errors.is_empty():
        _save_report()
        _fail("; ".join(_errors))
        return
    # The existing CI video step consumes report.json for BOTH outcomes.
    # Previously only _fail() persisted it, so a passing GPU test failed CI.
    _save_report()
    print("SNOW_WORLD_TILES_EXP PASS forward=%.2fm return=%.2fm stamps=%d GPUmax=%.5f samples=%d tiles=%s renderer=%s" % [
        _distance_forward, _distance_return, _prototype.stamp_count, _stress_max_diff,
        _stress_min_coverage, str(_after), RenderingServer.get_current_rendering_driver_name()])
    quit(0)


func _travel_frame(index: int, forward_leg: bool) -> void:
    await process_frame
    var pos := Vector2(_player.global_position.x, _player.global_position.z)
    _prototype.focus(pos)
    # Real foot-contact stamps are written by DeterministicSnowShell.
    _camera.make_current()
    await RenderingServer.frame_post_draw
    _save_image(_screen(), OUT.path_join("walk_frames/frame_%04d.png" % index))
    if index % 2 == 0:
        _fixed.make_current()
        await process_frame
        await RenderingServer.frame_post_draw
        _save_image(_screen(), OUT.path_join("fixed_frames/frame_%04d.png" % int(index / 2)))
        _camera.make_current()


func _setup_cameras() -> void:
    var center := Vector3(_start.x, _baked_top(_start.x, _start.z), _start.z)
    _fixed = Camera3D.new()
    _fixed.name = "WorldSnowTilesFixedCamera"
    # Previous oblique camera landed inside roof/terrain: red-on-black invalid.
    # High orthographic survey of the same world trail; no moving camera.
    _fixed.projection = Camera3D.PROJECTION_ORTHOGONAL
    _fixed.size = 25.0
    # Exclude the main-camera SCREEN_PASS (layer 18). It corrupts the top-down
    # survey into red shapes on black in the real Vulkan CI capture.
    # Regular scene props stay visible on layer 1; fixed snow tiles also carry 21.
    _fixed.cull_mask = 1 | RenderLayers.SNOW_TILE_EXPERIMENT
    _fixed.near = 0.1
    _fixed.far = 120.0
    _world.add_child(_fixed)
    var dir := Vector3(_forward.x, 0.0, _forward.y)
    var fixed_center := center + dir * 4.5
    _fixed.global_position = fixed_center + Vector3.UP * 45.0
    _fixed.look_at(fixed_center, Vector3.FORWARD)

    _gpu = Camera3D.new()
    _gpu.name = "WorldSnowTileGpuHeightWitness"
    _gpu.projection = Camera3D.PROJECTION_ORTHOGONAL
    _gpu.size = 5.0
    _gpu.near = 0.1
    _gpu.far = 50.0
    _gpu.cull_mask = RenderLayers.SNOW_TILE_EXPERIMENT
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color.BLACK
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    _gpu.environment = env
    _world.add_child(_gpu)
    _gpu.global_position = center + Vector3.UP * 30.0
    _gpu.look_at(center, Vector3.FORWARD)


func _stress_frame(index: int) -> void:
    _prototype.set_height_debug(true, _baked_top(_start.x, _start.z))
    _gpu.make_current()
    await process_frame
    await RenderingServer.frame_post_draw
    var img: Image = _screen()
    _save_image(img, OUT.path_join("stress_frames/frame_%04d.png" % index))
    if _baseline == null:
        _baseline = img.duplicate()
        _gpu_height_signal = _height_signal(img)
    else:
        var metric: Dictionary = _difference(_baseline, img)
        metric["step"] = index
        _stress_stats.append(metric)
        _stress_max_diff = maxf(_stress_max_diff, float(metric["max_red_difference"]))
        _stress_min_coverage = mini(_stress_min_coverage, int(metric["snow_samples"]))
    _prototype.set_height_debug(false, 0.0)
    _fixed.make_current()


func _history_snapshot() -> Dictionary:
    var record: Dictionary = {}
    for key: Variant in _prototype._data.keys():
        record[key] = (_prototype._data[key] as Image).get_data()
    return record


func _history_unchanged() -> bool:
    for key: Variant in _tile_history_snapshot.keys():
        if not _prototype._data.has(key):
            return false
        if (_prototype._data[key] as Image).get_data() != (_tile_history_snapshot[key] as PackedByteArray):
            return false
    return true


# The old uniform-purple diagnostic could pass every recenter with zero delta
# without demonstrating that any actual displaced snow geometry was visible.
# Inspect robust red-channel percentiles to reject that false-green capture.
func _height_signal(img: Image) -> Dictionary:
    var bins := PackedInt32Array()
    bins.resize(256)
    var samples := 0
    for y: int in range(5, img.get_height() - 5, 4):
        for x: int in range(5, img.get_width() - 5, 4):
            var c: Color = img.get_pixel(x, y)
            if c.b < 0.35 or c.g < 0.16:
                continue
            bins[clampi(roundi(c.r * 255.0), 0, 255)] += 1
            samples += 1
    if samples == 0:
        return {"samples": 0, "p01": 0, "p99": 0, "p01_p99_span": 0.0}
    var p01 := 0
    var p99 := 255
    var accumulated := 0
    var low_cut := maxi(1, ceili(float(samples) * 0.01))
    var high_cut := maxi(1, ceili(float(samples) * 0.99))
    var found_low := false
    for i: int in range(256):
        accumulated += bins[i]
        if not found_low and accumulated >= low_cut:
            p01 = i
            found_low = true
        if accumulated >= high_cut:
            p99 = i
            break
    return {"samples": samples, "p01": p01, "p99": p99,
        "p01_p99_span": float(p99 - p01) / 255.0}


func _difference(a: Image, b: Image) -> Dictionary:
    var snow := 0
    var max_diff := 0.0
    var changed := 0
    for y: int in range(5, mini(a.get_height(), b.get_height()) - 5, 4):
        for x: int in range(5, mini(a.get_width(), b.get_width()) - 5, 4):
            var c: Color = a.get_pixel(x, y)
            var d: Color = b.get_pixel(x, y)
            if minf(c.b, d.b) < 0.35 or minf(c.g, d.g) < 0.16:
                continue
            snow += 1
            var diff := absf(c.r - d.r)
            max_diff = maxf(max_diff, diff)
            if diff > 0.012:
                changed += 1
    return {"snow_samples": snow, "changed_samples": changed, "max_red_difference": max_diff}


func _hide_production_snow() -> void:
    var old: Node = _shell.get_node_or_null("SnowShellMesh")
    if old != null:
        (old as VisualInstance3D).visible = false
    old = _shell.get_node_or_null("SnowTrailMesh")
    if old != null:
        (old as VisualInstance3D).visible = false
    for node: Node in _world.find_children("*", "MeshInstance3D", true, false):
        var m := node as MeshInstance3D
        if m.mesh == null or m.mesh.get_surface_count() == 0:
            continue
        var mat := m.get_active_material(0) as ShaderMaterial
        if mat != null and mat.shader != null and mat.shader.resource_path.ends_with("snow_chunk_cover.gdshader"):
            m.visible = false


func _baked_top(x: float, z: float) -> float:
    # Experimental settled reference is world-anchored and sampled ONCE at mesh
    # build time. The city-wind snow model is a later visual integration task.
    return _ground_height(x, z) + 0.29


func _ground_height(x: float, z: float) -> float:
    if _ground != null and _ground.has_method(&"get_height"):
        return float(_ground.call(&"get_height", x, z))
    return 0.0


func _place() -> void:
    var y := _ground_height(_street_at.x, _street_at.y)
    _player.global_position = Vector3(_street_at.x, y + 1.0, _street_at.y)
    _player.velocity = Vector3.ZERO
    _player.rotation.y = _yaw
    _player.reset_physics_interpolation()
    if _streaming != null:
        _streaming.scan(_player.global_position)


func _wait_streamed() -> void:
    if _streaming == null:
        await _wait_frames(60)
        return
    var activated := -1
    for i: int in range(600):
        var p := _player.global_position
        var name := StringName("kw_gen_%d_%d" % [floori(p.x / 512.0), floori(p.z / 512.0)])
        if activated < 0 and _streaming.get_state(name) == StreamingSystem.CellState.ACTIVE:
            activated = i
            _place()
        if activated >= 0 and i - activated >= 60:
            return
        await process_frame


func _read_street() -> bool:
    var f := FileAccess.open(STREET_DATA, FileAccess.READ)
    if f == null:
        _fail("street spawns JSON missing")
        return false
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    if not parsed is Dictionary:
        _fail("street spawns malformed")
        return false
    for item: Variant in (parsed as Dictionary).get("streets", []):
        if item is Dictionary and String((item as Dictionary).get("name", "")) == "Duval Street":
            var at: Array = (item as Dictionary).get("at", [])
            _street_at = Vector2(float(at[0]), float(at[1]))
            _yaw = deg_to_rad(float((item as Dictionary).get("heading_deg", 0.0)))
            return true
    _fail("Duval Street not found")
    return false


func _set_input(action: StringName) -> void:
    _stop_input()
    Input.action_press(action, 1.0)


func _stop_input() -> void:
    for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
        Input.action_release(action)


func _wait_frames(count: int) -> void:
    for i: int in range(count):
        await process_frame


func _screen() -> Image:
    return root.get_texture().get_image()


func _snapshot(cam: Camera3D, path: String) -> void:
    cam.make_current()
    await process_frame
    await RenderingServer.frame_post_draw
    _save_image(_screen(), path)
    _camera.make_current()


func _save_image(img: Image, path: String) -> void:
    var abs := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
    img.save_png(abs)


func _save_report() -> void:
    var out := {
        "kind": "PRODUCTION world-fixed L0/L1/L2 snow tiles + native streamed SnowChunkCover",
        "scene": SCENE, "production_snow_visible": true,
        "stamps": "real FootContactSensor events plus persistent native SnowTrackStore",
        "baseline": "native 2m SnowChunkCover terrain triangles + same shader snow_base_geom",
        "renderer": RenderingServer.get_current_rendering_driver_name(),
        "forward_m": _distance_forward, "return_m": _distance_return,
        "tiles_at_start": _before, "tiles_at_end": _after,
        "lod_tiers": _prototype.get_lod_summary(), "frozen_tiles_checked": _tile_history_snapshot.size(),
        "frozen_world_data_fingerprint": _frozen_fingerprint,
        "stress_recenter_steps": STRESS_STEPS,
        "gpu_height_witness": {"min_samples": _stress_min_coverage, "max_pixel_difference": _stress_max_diff, "steps": _stress_stats, "threshold": 0.012, "signal": _gpu_height_signal, "minimum_signal_span": 0.015},
        "passes": _errors.is_empty() and _stress_min_coverage >= 7000 and _stress_max_diff <= 0.012,
        "errors": _errors,
    }
    var f := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify(out, "\t"))
        f.close()


func _fail(message: String) -> void:
    _stop_input()
    push_error("SNOW_WORLD_TILES_EXP FAIL " + message)
    quit(1)

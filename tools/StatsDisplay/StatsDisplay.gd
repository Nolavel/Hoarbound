extends Control

@export_range(0.1, 2.0, 0.05) var update_interval: float = 0.25

const CONSOLE_INTERVAL_S: float = 1.0
const VIEWPORT_REFRESH_INTERVAL_S: float = 5.0
const BYTES_PER_MIB: float = 1024.0 * 1024.0

var _panel: PanelContainer
var _label: Label
var _elapsed: float = 0.0
var _frames: int = 0
var _console_elapsed: float = 0.0
var _console_simulation_elapsed: float = 0.0
var _console_frames: int = 0
var _console_frame_min_ms: float = INF
var _console_frame_max_ms: float = 0.0
var _console_sim_delta_min_ms: float = INF
var _console_sim_delta_max_ms: float = 0.0
var _viewport_refresh_elapsed: float = VIEWPORT_REFRESH_INTERVAL_S
var _last_wall_usec: int = 0
var _show_panel: bool = true
var _print_runtime_debug_stats: bool = false
var _measured_viewports: Array[Viewport] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_wall_usec = Time.get_ticks_usec()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -154.0
	_panel.offset_top = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = 116.0
	add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.025, 0.03, 0.78)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.94, 0.96))
	_label.text = "FPS      --\nFRAME    -- ms\nPROCESS  -- ms\nPHYSICS  -- ms\nSESSION  00:00:00"
	_panel.add_child(_label)


func on_world_ready(context: WorldContext) -> void:
	if context == null or context.world == null:
		return
	_show_panel = bool(context.world.get("enable_runtime_debug_panel"))
	_print_runtime_debug_stats = bool(context.world.get("print_runtime_debug_stats"))

	visible = _show_panel
	set_process(_show_panel or _print_runtime_debug_stats)
	if _print_runtime_debug_stats:
		call_deferred(&"_start_console_capture")


func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	if _last_wall_usec <= 0:
		_last_wall_usec = now_usec
	var wall_delta_s: float = maxf(float(now_usec - _last_wall_usec) / 1000000.0, 0.0)
	_last_wall_usec = now_usec

	if _show_panel:
		_elapsed += wall_delta_s
		_frames += 1
		if _elapsed >= update_interval:
			_update_visible_snapshot()
	if _print_runtime_debug_stats:
		_console_elapsed += wall_delta_s
		_console_simulation_elapsed += maxf(delta, 0.0)
		_console_frames += 1
		_console_frame_min_ms = minf(_console_frame_min_ms, wall_delta_s * 1000.0)
		_console_frame_max_ms = maxf(_console_frame_max_ms, wall_delta_s * 1000.0)
		_console_sim_delta_min_ms = minf(_console_sim_delta_min_ms, maxf(delta, 0.0) * 1000.0)
		_console_sim_delta_max_ms = maxf(_console_sim_delta_max_ms, maxf(delta, 0.0) * 1000.0)
		_viewport_refresh_elapsed += wall_delta_s
		if _console_elapsed >= CONSOLE_INTERVAL_S:
			_print_console_snapshot()


func _update_visible_snapshot() -> void:
	var fps: float = float(_frames) / maxf(_elapsed, 0.0001)
	var frame_ms: float = (_elapsed / maxf(float(_frames), 1.0)) * 1000.0
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var snapshot := (
		"FPS      %3d\n"
		+ "FRAME   %5.2f ms\n"
		+ "PROCESS %5.2f ms\n"
		+ "PHYSICS %5.2f ms\n"
		+ "SESSION %s"
	) % [int(round(fps)), frame_ms, process_ms, physics_ms, _format_session_uptime()]

	if _show_panel:
		_label.text = snapshot
	_elapsed = 0.0
	_frames = 0


func _start_console_capture() -> void:
	_refresh_measured_viewports()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var meta: Dictionary = {
		"schema": "hoarbound_perf_v3",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu_name": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"viewport_px": [int(viewport_size.x), int(viewport_size.y)],
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync_mode": int(DisplayServer.window_get_vsync_mode()),
		"engine_max_fps": Engine.max_fps,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)),
		"time_scale": Engine.time_scale,
		"snow_quality": str(ProjectSettings.get_setting("hfn/snow/quality", "high")),
		"measured_viewports": _measured_viewports.size(),
	}
	print("[PerfMeta] %s" % JSON.stringify(meta))


func _print_console_snapshot() -> void:
	if _viewport_refresh_elapsed >= VIEWPORT_REFRESH_INTERVAL_S:
		_refresh_measured_viewports()
	var render_cpu_total_ms: float = 0.0
	var render_gpu_total_ms: float = 0.0
	var viewport_samples: Array[Dictionary] = []
	for viewport: Viewport in _measured_viewports:
		if not is_instance_valid(viewport):
			continue
		var rid: RID = viewport.get_viewport_rid()
		var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		render_cpu_total_ms += cpu_ms
		render_gpu_total_ms += gpu_ms
		var sample: Dictionary = {
			"path": str(viewport.get_path()),
			"cpu_ms": _rounded(cpu_ms, 3),
			"gpu_ms": _rounded(gpu_ms, 3),
			"size_px": [viewport.size.x, viewport.size.y],
		}
		if viewport is SubViewport:
			sample["update_mode"] = int((viewport as SubViewport).render_target_update_mode)
		viewport_samples.append(sample)
	var frames: float = maxf(float(_console_frames), 1.0)
	var data: Dictionary = {
		"schema": "hoarbound_perf_v3",
		"ticks_msec": Time.get_ticks_msec(),
		"sample_s": _rounded(_console_elapsed, 4),
		"wall_sample_s": _rounded(_console_elapsed, 4),
		"simulation_sample_s": _rounded(_console_simulation_elapsed, 4),
		"frames": _console_frames,
		"fps_local": _rounded(frames / maxf(_console_elapsed, 0.0001), 3),
		"fps_engine": Engine.get_frames_per_second(),
		"fps_monitor": _rounded(Performance.get_monitor(Performance.TIME_FPS), 3),
		"frame_ms_avg": _rounded(_console_elapsed * 1000.0 / frames, 3),
		"frame_ms_min": _rounded(_console_frame_min_ms, 3),
		"frame_ms_max": _rounded(_console_frame_max_ms, 3),
		"simulation_delta_avg_ms": _rounded(_console_simulation_elapsed * 1000.0 / frames, 3),
		"simulation_delta_min_ms": _rounded(_console_sim_delta_min_ms, 3),
		"simulation_delta_max_ms": _rounded(_console_sim_delta_max_ms, 3),
		"process_ms": _rounded(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 3),
		"physics_ms": _rounded(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 3),
		"render_setup_cpu_ms": _rounded(RenderingServer.get_frame_setup_time_cpu(), 3),
		"render_cpu_all_viewports_ms": _rounded(render_cpu_total_ms, 3),
		"render_gpu_all_viewports_ms": _rounded(render_gpu_total_ms, 3),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"video_mem_mib": _mib(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_mem_mib": _mib(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_mem_mib": _mib(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"static_mem_mib": _mib(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"physics_active_objects": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"physics_collision_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"physics_islands": int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		"viewports": viewport_samples,
	}
	print("[PerfJSON] %s" % JSON.stringify(data))
	_console_elapsed = 0.0
	_console_simulation_elapsed = 0.0
	_console_frames = 0
	_console_frame_min_ms = INF
	_console_frame_max_ms = 0.0
	_console_sim_delta_min_ms = INF
	_console_sim_delta_max_ms = 0.0


func _refresh_measured_viewports() -> void:
	_measured_viewports.clear()
	_collect_viewports(get_tree().root)
	_viewport_refresh_elapsed = 0.0


func _collect_viewports(node: Node) -> void:
	if node is Viewport:
		var viewport: Viewport = node as Viewport
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_measured_viewports.append(viewport)
	for child: Node in node.get_children():
		_collect_viewports(child)


func _mib(bytes: float) -> float:
	return _rounded(bytes / BYTES_PER_MIB, 3)


func _rounded(value: float, decimals: int) -> float:
	var scale: float = pow(10.0, float(decimals))
	return round(value * scale) / scale


func _format_session_uptime() -> String:
	var total_seconds: int = int(Time.get_ticks_msec() / 1000)
	var hours: int = floori(float(total_seconds) / 3600.0)
	var minutes: int = floori(float(total_seconds % 3600) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

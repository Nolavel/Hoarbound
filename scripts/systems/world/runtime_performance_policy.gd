class_name RuntimePerformancePolicy
extends Node

## Small production performance policy for work that is safe to schedule at runtime.
## It deliberately keeps gameplay systems enabled: the Freeman/parallax sky still
## animates, camera collision still runs, and city detail still streams. The policy
## only reduces redundant work and island-wide residency.

const CAMERA_OPENNESS_PROBE_COUNT: int = 5
## Keep enough overlap for the full authored chunk footprint to have exact
## streamed geometry and collision before Henry reaches a neighbouring boundary.
const STREAM_LOAD_MARGIN_M: float = 140.0
const STREAM_UNLOAD_HYSTERESIS_M: float = 120.0
const LOCAL_MASSING_RADIUS_CHUNKS: float = 1.55
const MASSING_RESCAN_CHUNKS: float = 0.25

var _day_night: DayNightManager
var _camera: TpsCamera
var _city: ChunkedCityMassing
var _streaming: StreamingSystem
var _player: Node3D
var _has_massing_focus: bool = false
var _last_massing_focus := Vector2.ZERO
var _ring0_roads_retired: bool = false
var _streaming_policy_applied: bool = false


func _ready() -> void:
	## StreamingSystem uses the default priority. Run this policy afterwards so
	## broad radius scans can be narrowed to one exact city owner before render.
	process_priority = 100
	set_process(true)
	call_deferred(&"_refresh_bindings")


func _process(_delta: float) -> void:
	_refresh_bindings()
	_apply_sky_policy()
	_apply_camera_policy()
	_apply_streaming_policy()
	_update_local_city_massing()


func _refresh_bindings() -> void:
	if not is_instance_valid(_day_night):
		_day_night = get_parent().get_node_or_null(^"DayNightManager") as DayNightManager
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() as TpsCamera
		if _camera != null:
			_player = _camera.player
	if not is_instance_valid(_player) and _camera != null:
		_player = _camera.player
	## Residency must not depend on which Camera3D currently owns the viewport.
	## Player.tscn has a stable `player` group and StreamingSystem uses that same
	## gameplay node as its scan focus. This fallback keeps the performance policy
	## alive during camera hand-offs, editor/debug cameras and early scene startup.
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D

	var scene := get_tree().current_scene
	if scene == null:
		return
	if not is_instance_valid(_city):
		_city = scene.find_child("KeyWestCity", true, false) as ChunkedCityMassing
		if _city != null:
			_has_massing_focus = false
			_ring0_roads_retired = false
			_streaming_policy_applied = false
	if not is_instance_valid(_streaming):
		## World.gd creates systems with Script.new() as direct children; their
		## Node.name is not a stable class identifier.
		for child: Node in scene.get_children():
			_streaming = child as StreamingSystem
			if _streaming != null:
				break


func _apply_sky_policy() -> void:
	if _day_night == null or _day_night.sky_resource == null:
		return
	## Freeman/parallax changes cloud_time every rendered frame. Godot's automatic
	## mode already chooses incremental for custom uniforms, so explicitly choosing
	## incremental would be a no-op. For a genuinely dynamic sky the documented
	## fast path is realtime filtering at a 256 px radiance cubemap. This changes
	## only IBL/reflection filtering; the visible Freeman/parallax shader is intact.
	if _day_night.sky_resource.process_mode != Sky.PROCESS_MODE_REALTIME:
		_day_night.sky_resource.process_mode = Sky.PROCESS_MODE_REALTIME
	if _day_night.sky_resource.radiance_size != Sky.RADIANCE_SIZE_256:
		_day_night.sky_resource.radiance_size = Sky.RADIANCE_SIZE_256


func _apply_camera_policy() -> void:
	if _camera == null:
		return
	## Preserve the centre sweep, feelers, overlaps, doorway framing and thin-prop
	## fade logic. Only the adaptive room fan is reduced: five rays still sample
	## left / centre / right with intermediate coverage, down from seven.
	if _camera.probe_count > CAMERA_OPENNESS_PROBE_COUNT:
		_camera.probe_count = CAMERA_OPENNESS_PROBE_COUNT


func _apply_streaming_policy() -> void:
	if _city == null or _streaming == null or _player == null or _streaming_policy_applied:
		return
	## Runtime city chunks are exact geometry and collision, not merely visual cells.
	## Keep the full chunk diagonal covered so neighbours can be ready before Henry
	## reaches a cell boundary; overlap is expected and avoids exposing massing cubes
	## where the player can walk.
	_streaming.load_margin_m = maxf(_streaming.load_margin_m, STREAM_LOAD_MARGIN_M)
	_streaming.unload_hysteresis_m = maxf(
		_streaming.unload_hysteresis_m,
		STREAM_UNLOAD_HYSTERESIS_M
	)
	_streaming_policy_applied = true
	## Registration may already have scanned before the safety margin was applied.
	## Re-scan now so nearby chunks enter the normal StreamingSystem lifecycle.
	_streaming.scan(_player.global_position)


func _update_local_city_massing() -> void:
	if _city == null or _player == null or not _city._stream_ring0_ready:
		return

	## The island-wide road ribbon duplicates local streamed road geometry and is
	## almost never useful as a distant silhouette. Keep only per-chunk roads.
	if not _ring0_roads_retired:
		var ring0_roads := _city._ring0_roads as Node3D
		if is_instance_valid(ring0_roads):
			ring0_roads.queue_free()
		_city._ring0_roads = null
		_ring0_roads_retired = true

	var focus := Vector2(_player.global_position.x, _player.global_position.z)
	var rescan: float = maxf(_city.chunk_size_m * MASSING_RESCAN_CHUNKS, 32.0)
	if _has_massing_focus and focus.distance_to(_last_massing_focus) < rescan:
		return
	_last_massing_focus = focus
	_has_massing_focus = true

	## Exact geometry is owned by StreamingSystem. Ring0 building proxies are kept
	## only in the current local neighbourhood (roughly a 3x3 cell ring) instead
	## of all 148 chunks. Active detail chunks keep their proxy resource long
	## enough for OccluderInstance3D generation and clean HLOD hand-off.
	var keep_radius: float = _city.chunk_size_m * LOCAL_MASSING_RADIUS_CHUNKS
	for state_variant: Variant in _city._chunks.values():
		var state := state_variant as Dictionary
		var center: Vector2 = state.get("center", Vector2.ZERO)
		var detail := state.get("detail") as Node3D
		var detail_active: bool = is_instance_valid(detail) and detail.visible
		var keep: bool = detail_active or center.distance_to(focus) <= keep_radius
		var massing := state.get("massing") as Node3D
		if keep:
			if not is_instance_valid(massing):
				_city._ensure_massing(state)
				massing = state.get("massing") as Node3D
			if is_instance_valid(massing):
				massing.visible = not detail_active
			continue
		if is_instance_valid(massing):
			massing.queue_free()
		state["massing"] = null

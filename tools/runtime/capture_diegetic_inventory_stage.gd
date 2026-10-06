extends SceneTree

## Issue #203 focus-stability proof. Six seconds under the real Player + TPS camera:
## approach the production table, sweep the visible crosshair until a real pickup
## is acquired, micro-jitter around that measured aim, then make a decisive
## look-away. Camera values stay identical to proof #484.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 6.0
const FRAME_COUNT: int = int(DURATION_S * FPS)
const FOCUS_POSE: Vector3 = Vector3(0.72, 1.0, 1.62)
const RELEASE_START_S: float = 4.70
const RELEASE_CHECK_START_S: float = 5.35
const ACQUIRE_DEADLINE_S: float = 3.55

var _stage: DiegeticInventoryStage
var _peak_focus: float = 0.0
var _seen_ids: Array[String] = []
var _stable_drop_frames: int = 0
var _release_clear_frames: int = 0
var _stable_window_frames: int = 0
var _last_stable_id: StringName = &""
var _stable_transitions: int = 0
var _focus_locked: bool = false
var _locked_item_id: StringName = &""
var _locked_yaw_offset: float = 0.0
var _acquired_time_s: float = -1.0
var _commanded_yaw_offset: float = 0.0


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_stage = SCENE.instantiate() as DiegeticInventoryStage
	root.add_child(_stage)
	_run.call_deferred()


func _run() -> void:
	await _frames(90)
	if _stage.table == null or _stage.items.size() < 3:
		push_error("diegetic inventory focus capture: production table/items were not prepared")
		quit(1)
		return
	if not _stage.has_stage_crosshair():
		push_error("diegetic inventory focus capture: stage crosshair ring is missing")
		quit(1)
		return

	_stage.prepare_focus_demo()
	_stage.player.move_to_position(FOCUS_POSE)
	await _frames(15)

	for frame: int in range(FRAME_COUNT):
		var t: float = float(frame) / float(FPS)
		_drive_demo(t)
		await process_frame
		_record_probe(frame, t)
		var image := root.get_texture().get_image()
		image.save_png("%s/%04d.png" % [FRAME_DIR, frame])
		if frame == 24:
			image.save_png("%s/01_approach.png" % OUT_DIR)
		elif frame == 120:
			image.save_png("%s/02_item_focus.png" % OUT_DIR)
		elif frame == 174:
			image.save_png("%s/03_focus_release.png" % OUT_DIR)

	_stage.player.stop_moving()
	_write_report()

	if not _focus_locked or _acquired_time_s < 0.0 or _acquired_time_s > ACQUIRE_DEADLINE_S:
		push_error("diegetic inventory focus capture: no real pickup acquired before deadline (t=%.2f)" % _acquired_time_s)
		quit(1)
		return
	if _peak_focus < 0.55 or _seen_ids.is_empty():
		push_error("diegetic inventory focus capture: item framing never became visible enough (peak=%.3f ids=%s)" % [_peak_focus, _seen_ids])
		quit(1)
		return
	if _stable_window_frames < 15 or _stable_drop_frames > 0:
		push_error("diegetic inventory focus capture: acquired item flickered during micro-look window (drops=%d/%d)" % [_stable_drop_frames, _stable_window_frames])
		quit(1)
		return
	if _release_clear_frames < 10:
		push_error("diegetic inventory focus capture: decisive look-away did not release focus cleanly (clear_frames=%d)" % _release_clear_frames)
		quit(1)
		return

	print("[diegetic-inventory-focus] complete peak=", _peak_focus,
		" item=", _locked_item_id, " acquired_t=", _acquired_time_s,
		" yaw=", _locked_yaw_offset, " drops=", _stable_drop_frames,
		" release_clear_frames=", _release_clear_frames,
		" transitions=", _stable_transitions)
	quit(0)


func _drive_demo(t: float) -> void:
	## 0.0-1.25 s: production scripted walk to the exact previously verified pose.
	if t < 1.25:
		_set_look(0.0, -10.0)
		return

	## 1.25-1.85 s: lower the player's own look onto the tabletop. No auto-orbit.
	if t < 1.85:
		var a: float = inverse_lerp(1.25, 1.85, t)
		_set_look(0.0, lerpf(-10.0, -21.0, a))
		return

	## Once the real InteractComponent has acquired a pickup, keep that measured
	## centre composition and add controlled hand-like micro motion around it.
	if _focus_locked and t < RELEASE_START_S:
		var local_t: float = maxf(0.0, t - _acquired_time_s)
		var phase: float = local_t * TAU * 1.45
		var yaw_jitter: float = sin(phase) * 1.35
		var pitch_jitter: float = sin(phase * 1.7 + 0.4) * 0.55
		_set_look(_locked_yaw_offset + yaw_jitter, -21.0 + pitch_jitter)
		return

	## Before acquisition, sweep only the player's normal crosshair. This avoids
	## hard-coding a screen-space offset caused by the shoulder composition.
	if t < RELEASE_START_S:
		var a: float = clampf(inverse_lerp(1.85, 3.35, t), 0.0, 1.0)
		_set_look(lerpf(-4.0, 14.0, a), -21.0)
		return

	## 4.70-6.0 s: unmistakable look-away. Retention zone must break; only the
	## already-existing camera smoothing is allowed to remain.
	var out_a: float = inverse_lerp(RELEASE_START_S, DURATION_S, t)
	_set_look(lerpf(_locked_yaw_offset, _locked_yaw_offset + 34.0, out_a), lerpf(-21.0, -9.0, out_a))


func _set_look(yaw_offset_deg: float, pitch_deg: float) -> void:
	_commanded_yaw_offset = yaw_offset_deg
	_stage.set_demo_look(yaw_offset_deg, pitch_deg)


func _record_probe(frame: int, t: float) -> void:
	_peak_focus = maxf(_peak_focus, _stage.focus_weight)
	var id: StringName = _stage.get_focus_target_id()
	if id != &"" and not _seen_ids.has(String(id)):
		_seen_ids.append(String(id))

	var stable_id: StringName = _stage.get_stable_interact_target_id()
	if not _focus_locked and stable_id != &"":
		_focus_locked = true
		_locked_item_id = stable_id
		_locked_yaw_offset = _commanded_yaw_offset
		_acquired_time_s = t
		print("[diegetic-inventory-focus] ACQUIRED item=%s t=%.2f yaw=%.2f" % [
			String(_locked_item_id), _acquired_time_s, _locked_yaw_offset
		])

	if stable_id != _last_stable_id:
		_stable_transitions += 1
		_last_stable_id = stable_id

	## Give the first framing transition time to settle, then demand a completely
	## uninterrupted stable identity until the deliberate look-away begins.
	if _focus_locked and t >= _acquired_time_s + 0.35 and t <= RELEASE_START_S - 0.15:
		_stable_window_frames += 1
		if stable_id != _locked_item_id:
			_stable_drop_frames += 1
	if t >= RELEASE_CHECK_START_S and stable_id == &"":
		_release_clear_frames += 1

	if frame % 15 == 0:
		var interact := _stage.player.get_node_or_null(^"InteractComponent") as InteractComponent
		var live: InteractiveArea = interact.current_target if interact != null else null
		var live_name: String = String(live.name) if live != null else "none"
		print("[diegetic-inventory-focus] t=%.2f pos=%s live=%s stable=%s weight=%.2f boom=%.2f yaw=%.2f" % [
			t, _stage.player.global_position, live_name, String(stable_id),
			_stage.focus_weight, _stage.camera.get_boom_length(), _commanded_yaw_offset
		])


func _write_report() -> void:
	var report := {
		"issue": 203,
		"duration_s": DURATION_S,
		"fps": FPS,
		"production_camera_script_changed": false,
		"camera_values_changed_since_484": false,
		"scene_only_focus_framing": true,
		"focus_peak": _peak_focus,
		"focused_item_ids": _seen_ids,
		"locked_item_id": String(_locked_item_id),
		"acquired_time_s": _acquired_time_s,
		"acquired_yaw_offset_deg": _locked_yaw_offset,
		"small_item_retention_radius_px": DiegeticInventoryStage.SMALL_ITEM_RETENTION_RADIUS_PX,
		"stable_window_frames": _stable_window_frames,
		"stable_drop_frames": _stable_drop_frames,
		"stable_transitions": _stable_transitions,
		"release_clear_frames": _release_clear_frames,
		"crosshair_ring_visible": _stage.has_stage_crosshair(),
		"crosshair_source": "production enso_cursor_ring.svg",
		"focus_far_distance_m": DiegeticInventoryStage.FOCUS_FAR_DISTANCE,
		"focus_distance_m": DiegeticInventoryStage.FOCUS_DISTANCE_M,
		"aim_mode": false,
		"automatic_orbit": false,
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

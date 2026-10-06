extends SceneTree

## Issue #203 crosshair-true focus proof. Six seconds under the real Player + TPS
## camera: approach the production table, lock Henry's body facing the table, steer
## the visible production Enso ring onto one known production pickup, keep it there
## through hand-like micro motion while close-in framing runs, then look away.
## The experimental pass disables only InteractionFraming's lateral shoulder
## override; production camera scripts/defaults remain untouched.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 6.0
const FRAME_COUNT: int = int(DURATION_S * FPS)
const FOCUS_POSE: Vector3 = Vector3(0.72, 1.0, 1.62)
const DEMO_TARGET_ID: StringName = &"tinned_stew"
const BODY_LOCK_S: float = 0.95
const RELEASE_START_S: float = 4.70
const RELEASE_CHECK_START_S: float = 5.30
const ACQUIRE_DEADLINE_S: float = 2.80
const CROSSHAIR_MAX_ERROR_PX: float = 18.0
const BODY_MAX_YAW_DRIFT_DEG: float = 0.25

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
var _commanded_pitch_deg: float = -10.0
var _body_locked: bool = false
var _body_lock_yaw_deg: float = 0.0
var _body_yaw_drift_peak_deg: float = 0.0
var _crosshair_error_peak_px: float = 0.0
var _crosshair_error_sum_px: float = 0.0
var _crosshair_error_frames: int = 0
var _crosshair_off_item_frames: int = 0
var _wrong_target_frames: int = 0


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
	if _stage.get_item_by_id(DEMO_TARGET_ID) == null:
		push_error("diegetic inventory focus capture: requested demo target is missing: %s" % DEMO_TARGET_ID)
		quit(1)
		return
	if _stage.is_lateral_interaction_framing_enabled():
		push_error("diegetic inventory focus capture: lateral InteractionFraming must be disabled for this pass")
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
		elif frame == 78:
			image.save_png("%s/02_crosshair_on_item.png" % OUT_DIR)
		elif frame == 120:
			image.save_png("%s/03_close_in_focus.png" % OUT_DIR)
		elif frame == 174:
			image.save_png("%s/04_focus_release.png" % OUT_DIR)

	_stage.player.stop_moving()
	_write_report()

	if not _focus_locked or _acquired_time_s < 0.0 or _acquired_time_s > ACQUIRE_DEADLINE_S:
		push_error("diegetic inventory focus capture: requested pickup not acquired before deadline (t=%.2f)" % _acquired_time_s)
		quit(1)
		return
	if _locked_item_id != DEMO_TARGET_ID:
		push_error("diegetic inventory focus capture: wrong pickup locked (%s != %s)" % [_locked_item_id, DEMO_TARGET_ID])
		quit(1)
		return
	if _peak_focus < 0.55 or _seen_ids.is_empty():
		push_error("diegetic inventory focus capture: item close-in never became visible enough (peak=%.3f ids=%s)" % [_peak_focus, _seen_ids])
		quit(1)
		return
	if _stable_window_frames < 20 or _stable_drop_frames > 0:
		push_error("diegetic inventory focus capture: acquired item flickered during aimed micro-look window (drops=%d/%d)" % [_stable_drop_frames, _stable_window_frames])
		quit(1)
		return
	if _crosshair_error_frames < 20 or _crosshair_off_item_frames > 0:
		push_error("diegetic inventory focus capture: visible crosshair left item focus point (off=%d/%d peak=%.2fpx max=%.2fpx)" % [
			_crosshair_off_item_frames, _crosshair_error_frames, _crosshair_error_peak_px, CROSSHAIR_MAX_ERROR_PX
		])
		quit(1)
		return
	if _body_yaw_drift_peak_deg > BODY_MAX_YAW_DRIFT_DEG:
		push_error("diegetic inventory focus capture: Henry body followed camera look (yaw drift=%.3fdeg)" % _body_yaw_drift_peak_deg)
		quit(1)
		return
	if _release_clear_frames < 10:
		push_error("diegetic inventory focus capture: decisive look-away did not release focus cleanly (clear_frames=%d)" % _release_clear_frames)
		quit(1)
		return

	var mean_error: float = _crosshair_error_sum_px / maxf(float(_crosshair_error_frames), 1.0)
	print("[diegetic-inventory-focus] complete peak=", _peak_focus,
		" item=", _locked_item_id, " acquired_t=", _acquired_time_s,
		" crosshair_mean_px=", mean_error, " crosshair_peak_px=", _crosshair_error_peak_px,
		" body_yaw_drift_deg=", _body_yaw_drift_peak_deg,
		" drops=", _stable_drop_frames, " release_clear_frames=", _release_clear_frames,
		" transitions=", _stable_transitions)
	quit(0)


func _drive_demo(t: float) -> void:
	## 0.0-0.95 s: production scripted walk toward the previously verified pose.
	## The body is still free to face its locomotion direction during this approach.
	if t < BODY_LOCK_S:
		_set_look(0.0, -10.0)
		return

	if not _body_locked:
		_stage.player.stop_moving()
		_stage.lock_demo_body_to_table()
		_body_lock_yaw_deg = _stage.get_body_yaw_deg()
		_body_locked = true

	## 0.95-4.70 s: continuously solve the *real centre ray* toward the stew's
	## production focus point. The ring visibly travels onto the item, then follows
	## tiny hand-like input while the boom closes in. No body turn, no auto orbit.
	if t < RELEASE_START_S:
		var aim: Vector2 = _stage.get_demo_look_for_item(DEMO_TARGET_ID)
		var yaw_jitter: float = 0.0
		var pitch_jitter: float = 0.0
		if _focus_locked:
			var local_t: float = maxf(0.0, t - _acquired_time_s)
			var phase: float = local_t * TAU * 1.35
			yaw_jitter = sin(phase) * 0.22
			pitch_jitter = sin(phase * 1.7 + 0.4) * 0.10
		var yaw_goal: float = aim.x + yaw_jitter
		var pitch_goal: float = aim.y + pitch_jitter
		_commanded_yaw_offset = move_toward(_commanded_yaw_offset, yaw_goal, 0.72)
		_commanded_pitch_deg = move_toward(_commanded_pitch_deg, pitch_goal, 0.82)
		_stage.set_demo_look(_commanded_yaw_offset, _commanded_pitch_deg)
		return

	## 4.70-5.10 s: look vertically away from the table first so release cannot
	## legitimately acquire another neighbouring pickup on the way out.
	if t < 5.10:
		_commanded_yaw_offset = move_toward(_commanded_yaw_offset, _locked_yaw_offset + 5.0, 0.85)
		_commanded_pitch_deg = move_toward(_commanded_pitch_deg, 3.0, 1.45)
		_stage.set_demo_look(_commanded_yaw_offset, _commanded_pitch_deg)
		return

	## 5.10-6.0 s: continue into empty space beside/above the table.
	_commanded_yaw_offset = move_toward(_commanded_yaw_offset, _locked_yaw_offset + 34.0, 1.15)
	_commanded_pitch_deg = move_toward(_commanded_pitch_deg, 3.0, 1.0)
	_stage.set_demo_look(_commanded_yaw_offset, _commanded_pitch_deg)


func _set_look(yaw_offset_deg: float, pitch_deg: float) -> void:
	_commanded_yaw_offset = yaw_offset_deg
	_commanded_pitch_deg = pitch_deg
	_stage.set_demo_look(yaw_offset_deg, pitch_deg)


func _record_probe(frame: int, t: float) -> void:
	_peak_focus = maxf(_peak_focus, _stage.focus_weight)
	var id: StringName = _stage.get_focus_target_id()
	if id != &"" and not _seen_ids.has(String(id)):
		_seen_ids.append(String(id))

	var stable_id: StringName = _stage.get_stable_interact_target_id()
	if not _focus_locked and stable_id == DEMO_TARGET_ID:
		_focus_locked = true
		_locked_item_id = stable_id
		_locked_yaw_offset = _commanded_yaw_offset
		_acquired_time_s = t
		print("[diegetic-inventory-focus] ACQUIRED requested item=%s t=%.2f yaw=%.2f pitch=%.2f" % [
			String(_locked_item_id), _acquired_time_s, _locked_yaw_offset, _commanded_pitch_deg
		])
	elif not _focus_locked and stable_id != &"" and stable_id != DEMO_TARGET_ID:
		_wrong_target_frames += 1

	if stable_id != _last_stable_id:
		_stable_transitions += 1
		_last_stable_id = stable_id

	## Once close-in has started settling, require both logical stability and visual
	## truth: the actual item focus point must remain inside the centre Enso ring.
	if _focus_locked and t >= _acquired_time_s + 0.35 and t <= RELEASE_START_S - 0.15:
		_stable_window_frames += 1
		if stable_id != _locked_item_id:
			_stable_drop_frames += 1
		var error_px: float = _stage.get_item_crosshair_error_px(DEMO_TARGET_ID)
		_crosshair_error_frames += 1
		_crosshair_error_sum_px += error_px
		_crosshair_error_peak_px = maxf(_crosshair_error_peak_px, error_px)
		if error_px > CROSSHAIR_MAX_ERROR_PX:
			_crosshair_off_item_frames += 1
		if _body_locked:
			var yaw_now: float = _stage.get_body_yaw_deg()
			var yaw_drift: float = absf(wrapf(yaw_now - _body_lock_yaw_deg, -180.0, 180.0))
			_body_yaw_drift_peak_deg = maxf(_body_yaw_drift_peak_deg, yaw_drift)

	if t >= RELEASE_CHECK_START_S and stable_id == &"":
		_release_clear_frames += 1

	if frame % 15 == 0:
		var interact := _stage.player.get_node_or_null(^"InteractComponent") as InteractComponent
		var live: InteractiveArea = interact.current_target if interact != null else null
		var live_name: String = String(live.name) if live != null else "none"
		var error_text: String = "n/a"
		if _focus_locked and t < RELEASE_START_S:
			error_text = "%.1f" % _stage.get_item_crosshair_error_px(DEMO_TARGET_ID)
		print("[diegetic-inventory-focus] t=%.2f pos=%s live=%s stable=%s weight=%.2f boom=%.2f yaw=%.2f pitch=%.2f crosshair_err_px=%s body_yaw=%.2f" % [
			t, _stage.player.global_position, live_name, String(stable_id),
			_stage.focus_weight, _stage.camera.get_boom_length(), _commanded_yaw_offset,
			_commanded_pitch_deg, error_text, _stage.get_body_yaw_deg()
		])


func _write_report() -> void:
	var mean_error: float = _crosshair_error_sum_px / maxf(float(_crosshair_error_frames), 1.0)
	var report := {
		"issue": 203,
		"duration_s": DURATION_S,
		"fps": FPS,
		"production_camera_script_changed": false,
		"production_camera_defaults_changed": false,
		"scene_only_focus_framing": true,
		"scene_only_close_in": true,
		"lateral_interaction_recompose": false,
		"base_tps_shoulder_preserved": true,
		"henry_body_alignment_on_focus": false,
		"focus_peak": _peak_focus,
		"focused_item_ids": _seen_ids,
		"requested_item_id": String(DEMO_TARGET_ID),
		"locked_item_id": String(_locked_item_id),
		"acquired_time_s": _acquired_time_s,
		"acquired_yaw_offset_deg": _locked_yaw_offset,
		"small_item_retention_yaw_deg": DiegeticInventoryStage.SMALL_ITEM_RETENTION_YAW_DEG,
		"small_item_retention_pitch_deg": DiegeticInventoryStage.SMALL_ITEM_RETENTION_PITCH_DEG,
		"stable_window_frames": _stable_window_frames,
		"stable_drop_frames": _stable_drop_frames,
		"stable_transitions": _stable_transitions,
		"wrong_target_frames_before_requested_lock": _wrong_target_frames,
		"release_clear_frames": _release_clear_frames,
		"crosshair_ring_visible": _stage.has_stage_crosshair(),
		"crosshair_source": "production enso_cursor_ring.svg",
		"crosshair_error_mean_px": mean_error,
		"crosshair_error_peak_px": _crosshair_error_peak_px,
		"crosshair_error_limit_px": CROSSHAIR_MAX_ERROR_PX,
		"crosshair_off_item_frames": _crosshair_off_item_frames,
		"body_yaw_drift_peak_deg": _body_yaw_drift_peak_deg,
		"body_yaw_drift_limit_deg": BODY_MAX_YAW_DRIFT_DEG,
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
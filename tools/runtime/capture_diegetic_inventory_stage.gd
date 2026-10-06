extends SceneTree

## Issue #203 focus-stability proof. Six seconds under the real Player + TPS camera:
## approach the production table, acquire one nearby ItemPickup, add deliberate
## micro-look jitter, then make a decisive look-away. Camera values stay identical
## to proof #484; this pass evaluates only target retention + the visible ring.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 6.0
const FRAME_COUNT: int = int(DURATION_S * FPS)
const FOCUS_POSE: Vector3 = Vector3(0.72, 1.0, 1.62)
const STABILITY_WINDOW_START_S: float = 3.80
const STABILITY_WINDOW_END_S: float = 4.55
const RELEASE_CHECK_START_S: float = 5.35

var _stage: DiegeticInventoryStage
var _peak_focus: float = 0.0
var _seen_ids: Array[String] = []
var _stable_drop_frames: int = 0
var _release_clear_frames: int = 0
var _stable_window_frames: int = 0
var _last_stable_id: StringName = &""
var _stable_transitions: int = 0


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

	if _peak_focus < 0.55 or _seen_ids.is_empty():
		push_error("diegetic inventory focus capture: item focus never became visible enough (peak=%.3f ids=%s)" % [_peak_focus, _seen_ids])
		quit(1)
		return
	if _stable_window_frames <= 0 or _stable_drop_frames > 0:
		push_error("diegetic inventory focus capture: small-item focus flickered during micro-look window (drops=%d/%d)" % [_stable_drop_frames, _stable_window_frames])
		quit(1)
		return
	if _release_clear_frames < 10:
		push_error("diegetic inventory focus capture: decisive look-away did not release focus cleanly (clear_frames=%d)" % _release_clear_frames)
		quit(1)
		return

	print("[diegetic-inventory-focus] complete peak=", _peak_focus,
		" ids=", _seen_ids, " drops=", _stable_drop_frames,
		" release_clear_frames=", _release_clear_frames,
		" transitions=", _stable_transitions)
	quit(0)


func _drive_demo(t: float) -> void:
	## 0.0-1.25 s: production scripted walk to the exact previously verified pose.
	if t < 1.25:
		_stage.set_demo_look(0.0, -10.0)
		return

	## 1.25-1.85 s: lower the player's own look onto the tabletop. No auto-orbit.
	if t < 1.85:
		var a: float = inverse_lerp(1.25, 1.85, t)
		_stage.set_demo_look(0.0, lerpf(-10.0, -21.0, a))
		return

	## 1.85-3.35 s: hold the proven composition long enough for real acquisition.
	if t < 3.35:
		_stage.set_demo_look(0.0, -21.0)
		return

	## 3.35-4.70 s: intentional sub-item jitter. The centre ray may graze the can,
	## but the player is still clearly aiming at that same object.
	if t < 4.70:
		var phase: float = (t - 3.35) * TAU * 1.35
		var yaw_jitter: float = sin(phase) * 1.35
		var pitch_jitter: float = sin(phase * 1.7 + 0.4) * 0.55
		_stage.set_demo_look(yaw_jitter, -21.0 + pitch_jitter)
		return

	## 4.70-6.0 s: unmistakable look-away. Retention leash must break immediately;
	## only the camera's already-existing smooth return remains visible.
	var out_a: float = inverse_lerp(4.70, DURATION_S, t)
	_stage.set_demo_look(lerpf(0.0, 34.0, out_a), lerpf(-21.0, -9.0, out_a))


func _record_probe(frame: int, t: float) -> void:
	_peak_focus = maxf(_peak_focus, _stage.focus_weight)
	var id: StringName = _stage.get_focus_target_id()
	if id != &"" and not _seen_ids.has(String(id)):
		_seen_ids.append(String(id))

	var stable_id: StringName = _stage.get_stable_interact_target_id()
	if stable_id != _last_stable_id:
		_stable_transitions += 1
		_last_stable_id = stable_id

	if t >= STABILITY_WINDOW_START_S and t <= STABILITY_WINDOW_END_S:
		_stable_window_frames += 1
		if stable_id == &"":
			_stable_drop_frames += 1
	if t >= RELEASE_CHECK_START_S and stable_id == &"":
		_release_clear_frames += 1

	if frame % 15 == 0:
		var interact := _stage.player.get_node_or_null(^"InteractComponent") as InteractComponent
		var live: InteractiveArea = interact.current_target if interact != null else null
		var live_name: String = String(live.name) if live != null else "none"
		print("[diegetic-inventory-focus] t=%.2f pos=%s live=%s stable=%s weight=%.2f boom=%.2f" % [
			t, _stage.player.global_position, live_name, String(stable_id),
			_stage.focus_weight, _stage.camera.get_boom_length()
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
		"small_item_retention_s": DiegeticInventoryStage.SMALL_ITEM_RETENTION_S,
		"small_item_retention_full_angle_deg": DiegeticInventoryStage.SMALL_ITEM_RETENTION_FULL_ANGLE_DEG,
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

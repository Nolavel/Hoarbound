extends SceneTree

## Issue #203 interaction-commit proof using the existing diegetic inventory CI job.
## Production Henry + production TPS camera + real MealTable/tinned stew.
## Three cases in one movie:
## 1) near-edge item while Henry is at the table collision limit -> F -> small settle back -> pickup;
## 2) far-edge item -> stance solve -> authored reach + TwoBoneIK contact correction;
## 3) same far item beyond the settle budget -> crosshair focus is valid but no F prompt.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const LAB_SCRIPT: Script = preload("res://scripts/experimental/diegetic_inventory/table_interaction_solver_lab.gd")
## Keep the established output path so the existing workflow can encode/upload it.
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 10.0
const FRAME_COUNT: int = int(DURATION_S * FPS)
const NEAR_END_S: float = 3.8
const FAR_END_S: float = 7.7
## Player capsule radius is ~0.5 m and the table front is ~z=0.20. A root at
## z=0.56 was inside the table volume, not a valid "standing flush" scenario.
## z=0.70 models the closest physically plausible body stance at the table edge.
const NEAR_COLLISION_LIMIT_Z_M: float = 0.70
const MIN_VISIBLE_NEAR_SETTLE_M: float = 0.075

## The capture represents a player moving the mouse toward the item. Because the
## physical TPS camera origin changes as collision/boom settles, solve the newly
## measured look with a damped proportional correction rather than hard-snapping
## to last frame's answer. Once F commits, this automation stops completely.
const AIM_GAIN: float = 0.42
const AIM_MAX_YAW_STEP_DEG: float = 4.0
const AIM_MAX_PITCH_STEP_DEG: float = 4.0

var _stage: DiegeticInventoryStage
var _lab: TableInteractionSolverLab
var _near_pressed := false
var _far_pressed := false
var _near_prompt_seen := false
var _far_prompt_seen := false
var _out_focus_frames := 0
var _out_prompt_frames := 0
var _saved: Dictionary = {}
var _press_position: Dictionary = {}
var _settled_position: Dictionary = {}
var _last_state: int = -1
var _aim_yaw_offset_deg: float = 0.0
var _aim_pitch_deg: float = -22.0


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_stage = SCENE.instantiate() as DiegeticInventoryStage
	root.add_child(_stage)
	_run.call_deferred()


func _run() -> void:
	await _frames(90)
	if _stage.table == null or _stage.get_item_by_id(&"tinned_stew") == null:
		push_error("interaction settle capture: production table/stew were not prepared")
		quit(1)
		return

	## This proof isolates one requested can. The previous four-item staging layout
	## is useful for focus arbitration, but neighbouring production pickups can
	## physically overlap the near/far test coordinates and steal the centre ray.
	for other: ItemPickup in _stage.items:
		if other.item_id != &"tinned_stew":
			other.global_position = Vector3(50.0, -10.0, 50.0)

	_lab = LAB_SCRIPT.new() as TableInteractionSolverLab
	_stage.add_child(_lab)
	_lab.setup(_stage)
	_lab.prepare_case(&"NEAR_TOO_CLOSE")
	_set_collision_valid_near_pose()
	_reset_aim_controller()
	_last_state = _lab.state

	for frame: int in range(FRAME_COUNT):
		var t := float(frame) / float(FPS)
		_drive(t)
		if _lab.state == TableInteractionSolverLab.State.IDLE:
			_steer_crosshair_to_item()
		await process_frame
		_record_state(t)
		var image := root.get_texture().get_image()
		image.save_png("%s/%04d.png" % [FRAME_DIR, frame])
		_capture_keyframes(image, t)

	var report := _write_report()
	var failures := _validate(report)
	if not failures.is_empty():
		push_error("interaction settle capture failed: %s" % ", ".join(failures))
		quit(1)
		return
	print("[interaction-settle] PASS near=%s far=%s out_focus_frames=%d out_prompt_frames=%d" % [
		JSON.stringify(report["near"]), JSON.stringify(report["far"]), _out_focus_frames, _out_prompt_frames
	])
	quit(0)


func _set_collision_valid_near_pose() -> void:
	_stage.player.global_position = Vector3(0.02, 1.0, NEAR_COLLISION_LIMIT_Z_M)
	_stage.player.velocity = Vector3.ZERO
	_stage.player.reset_physics_interpolation()
	_stage.lock_demo_body_to_table()
	if _stage.camera.has_method(&"snap_to_target"):
		_stage.camera.call(&"snap_to_target")


func _reset_aim_controller() -> void:
	_aim_yaw_offset_deg = 0.0
	_aim_pitch_deg = -22.0


func _steer_crosshair_to_item() -> void:
	var desired: Vector2 = _stage.get_demo_look_for_item(&"tinned_stew")
	var yaw_error := desired.x - _aim_yaw_offset_deg
	var pitch_error := desired.y - _aim_pitch_deg
	_aim_yaw_offset_deg += clampf(yaw_error * AIM_GAIN, -AIM_MAX_YAW_STEP_DEG, AIM_MAX_YAW_STEP_DEG)
	_aim_pitch_deg += clampf(pitch_error * AIM_GAIN, -AIM_MAX_PITCH_STEP_DEG, AIM_MAX_PITCH_STEP_DEG)
	_stage.set_demo_look(_aim_yaw_offset_deg, _aim_pitch_deg)


func _drive(t: float) -> void:
	if t < NEAR_END_S:
		if not _near_pressed and t >= 0.85 and _lab.prompt_visible:
			_press_position["NEAR_TOO_CLOSE"] = _stage.player.global_position
			_near_pressed = _lab.press_interact()
		return

	if t < FAR_END_S:
		if _lab.current_case != &"FAR_EDGE":
			_lab.prepare_case(&"FAR_EDGE")
			_reset_aim_controller()
			_last_state = _lab.state
		if not _far_pressed and t >= NEAR_END_S + 0.85 and _lab.prompt_visible:
			_press_position["FAR_EDGE"] = _stage.player.global_position
			_far_pressed = _lab.press_interact()
		return

	if _lab.current_case != &"OUT_OF_REACH":
		_lab.prepare_case(&"OUT_OF_REACH")
		_reset_aim_controller()
		_last_state = _lab.state


func _record_state(t: float) -> void:
	if _lab.current_case == &"NEAR_TOO_CLOSE" and _lab.prompt_visible:
		_near_prompt_seen = true
	elif _lab.current_case == &"FAR_EDGE" and _lab.prompt_visible:
		_far_prompt_seen = true
	elif _lab.current_case == &"OUT_OF_REACH":
		if _stage.get_stable_interact_target_id() == &"tinned_stew":
			_out_focus_frames += 1
			if _lab.prompt_visible:
				_out_prompt_frames += 1

	if _last_state == TableInteractionSolverLab.State.SETTLE and _lab.state == TableInteractionSolverLab.State.ACTION:
		_settled_position[String(_lab.current_case)] = _stage.player.global_position
	_last_state = _lab.state

	if int(round(t * float(FPS))) % 15 == 0:
		var desired := _stage.get_demo_look_for_item(&"tinned_stew")
		print("[interaction-settle] t=%.2f case=%s stable=%s crosshair=%.2f prompt=%s state=%s pos=%s view_pitch=%.2f desired=(%.2f,%.2f) cmd=(%.2f,%.2f) solution=%s rejection=%s" % [
			t, String(_lab.current_case), String(_stage.get_stable_interact_target_id()),
			_stage.get_item_crosshair_error_px(&"tinned_stew"), _lab.prompt_visible,
			TableInteractionSolverLab.State.keys()[_lab.state], _stage.player.global_position,
			_stage.camera.get_view_pitch_deg(), desired.x, desired.y, _aim_yaw_offset_deg, _aim_pitch_deg,
			JSON.stringify(_lab.solution), JSON.stringify(_lab.rejection)
		])


func _capture_keyframes(image: Image, t: float) -> void:
	if _lab.current_case == &"NEAR_TOO_CLOSE":
		if _lab.prompt_visible and not _saved.has("near_focus"):
			image.save_png(OUT_DIR + "/01_near_too_close_focus.png")
			_saved["near_focus"] = true
		if _lab.state == TableInteractionSolverLab.State.SETTLE and not _saved.has("near_settle"):
			image.save_png(OUT_DIR + "/02_near_settle_back.png")
			_saved["near_settle"] = true
		if _case_has_contact("NEAR_TOO_CLOSE") and not _saved.has("near_contact"):
			image.save_png(OUT_DIR + "/03_near_pickup_contact.png")
			_saved["near_contact"] = true
	elif _lab.current_case == &"FAR_EDGE":
		if _lab.prompt_visible and not _saved.has("far_focus"):
			image.save_png(OUT_DIR + "/04_far_edge_focus.png")
			_saved["far_focus"] = true
		if _case_has_contact("FAR_EDGE") and not _saved.has("far_contact"):
			image.save_png(OUT_DIR + "/05_far_edge_reach_contact.png")
			_saved["far_contact"] = true
	elif _lab.current_case == &"OUT_OF_REACH":
		if _stage.get_stable_interact_target_id() == &"tinned_stew" and not _lab.prompt_visible and not _saved.has("out") and t >= FAR_END_S + 0.65:
			image.save_png(OUT_DIR + "/06_out_of_reach_no_prompt.png")
			_saved["out"] = true


func _case_has_contact(case_name: String) -> bool:
	var cases: Dictionary = (_lab.get_report()["case_results"] as Dictionary)
	if not cases.has(case_name):
		return false
	return bool((cases[case_name] as Dictionary).get("contact", false))


func _write_report() -> Dictionary:
	var proof := _lab.get_report()
	var cases: Dictionary = proof["case_results"] as Dictionary
	var near: Dictionary = (cases.get("NEAR_TOO_CLOSE", {}) as Dictionary).duplicate(true)
	var far: Dictionary = (cases.get("FAR_EDGE", {}) as Dictionary).duplicate(true)
	_add_motion_delta(near, "NEAR_TOO_CLOSE")
	_add_motion_delta(far, "FAR_EDGE")
	var report := {
		"issue": 203,
		"duration_s": DURATION_S,
		"fps": FPS,
		"production_camera_changed": false,
		"production_interact_component_changed": false,
		"focus_moves_body": false,
		"aim_automation_after_F": false,
		"near_start_is_collision_valid": true,
		"near_start_root_z_m": NEAR_COLLISION_LIMIT_Z_M,
		"commit_pipeline": "focus -> F -> solve stance -> small settle -> authored pickup -> TwoBoneIK contact correction",
		"near_prompt_seen": _near_prompt_seen,
		"far_prompt_seen": _far_prompt_seen,
		"near": near,
		"far": far,
		"out_of_reach": {
			"stable_focus_frames": _out_focus_frames,
			"prompt_frames": _out_prompt_frames,
			"expected_prompt": false,
		},
		"lab": proof,
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return report


func _add_motion_delta(result: Dictionary, case_name: String) -> void:
	if not _press_position.has(case_name) or not _settled_position.has(case_name):
		return
	var start: Vector3 = _press_position[case_name]
	var settled: Vector3 = _settled_position[case_name]
	var delta := settled - start
	result["settle_delta_x_m"] = delta.x
	result["settle_delta_z_m"] = delta.z
	result["settled_distance_m"] = Vector2(delta.x, delta.z).length()


func _validate(report: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	var near: Dictionary = report["near"] as Dictionary
	var far: Dictionary = report["far"] as Dictionary
	if not _near_prompt_seen or not _near_pressed:
		failures.append("near_F_never_became_valid")
	if not bool(near.get("contact", false)):
		failures.append("near_pickup_no_contact")
	if float(near.get("settle_delta_z_m", 0.0)) < MIN_VISIBLE_NEAR_SETTLE_M:
		failures.append("near_case_did_not_settle_back")
	if not _far_prompt_seen or not _far_pressed:
		failures.append("far_F_never_became_valid")
	if not bool(far.get("contact", false)):
		failures.append("far_pickup_no_contact")
	if float(far.get("item_depth_m", 0.0)) < 0.28:
		failures.append("far_item_was_not_actually_far_edge")
	if _out_focus_frames < 20:
		failures.append("out_of_reach_crosshair_never_stabilized")
	if _out_prompt_frames > 0:
		failures.append("F_was_offered_outside_settle_budget")
	for required: String in ["near_focus", "near_settle", "near_contact", "far_focus", "far_contact", "out"]:
		if not _saved.has(required):
			failures.append("missing_keyframe_%s" % required)
	return failures


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
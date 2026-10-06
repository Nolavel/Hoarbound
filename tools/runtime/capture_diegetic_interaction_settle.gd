extends SceneTree

## Issue #203 interaction-commit proof.
## Production Henry + production TPS camera + real MealTable/tinned stew.
## Three cases in one movie:
## 1) near-edge item while Henry is too close -> F -> small step/settle back -> pickup;
## 2) far-edge item -> stance solve -> authored reach + TwoBoneIK contact correction;
## 3) same far item beyond the settle budget -> crosshair focus is valid but no F prompt.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const LAB_SCRIPT: Script = preload("res://scripts/experimental/diegetic_inventory/table_interaction_solver_lab.gd")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_interaction_settle"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 10.0
const FRAME_COUNT: int = int(DURATION_S * FPS)
const NEAR_END_S: float = 3.8
const FAR_END_S: float = 7.7

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

	_lab = LAB_SCRIPT.new() as TableInteractionSolverLab
	_stage.add_child(_lab)
	_lab.setup(_stage)
	_lab.prepare_case(&"NEAR_TOO_CLOSE")
	_last_state = _lab.state

	for frame: int in range(FRAME_COUNT):
		var t := float(frame) / float(FPS)
		_drive(t)
		_lab.aim_at_item()
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


func _drive(t: float) -> void:
	if t < NEAR_END_S:
		if not _near_pressed and t >= 0.85 and _lab.prompt_visible:
			_press_position["NEAR_TOO_CLOSE"] = _stage.player.global_position
			_near_pressed = _lab.press_interact()
		return

	if t < FAR_END_S:
		if _lab.current_case != &"FAR_EDGE":
			_lab.prepare_case(&"FAR_EDGE")
			_last_state = _lab.state
		if not _far_pressed and t >= NEAR_END_S + 0.85 and _lab.prompt_visible:
			_press_position["FAR_EDGE"] = _stage.player.global_position
			_far_pressed = _lab.press_interact()
		return

	if _lab.current_case != &"OUT_OF_REACH":
		_lab.prepare_case(&"OUT_OF_REACH")
		_last_state = _lab.state


func _record_state(_t: float) -> void:
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
	if float(near.get("settle_delta_z_m", 0.0)) < 0.10:
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

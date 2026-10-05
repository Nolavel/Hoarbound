extends SceneTree

## Captures issue #198's production-path embodied-interaction lab through the
## production TPS camera. The renderer may run slower than the requested movie
## rate on CI, so frame output is time-quantized and ffmpeg preserves duration.
##
## Semantic proof is intentionally animation/gameplay oriented: a green run means
## all five cases chose a live feasible arm, played a complete authored action,
## stood to idle holding the can, returned it where required, and completed the
## final floor-pick-to-handoff sequence. Stock TwoBoneIK3D is contact correction.

const SCENE: String = "res://scenes/debug/embodied_interaction_lab.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/embodied_interaction"
const FRAME_DIR: String = OUT_DIR + "/frames"
const WARMUP_SECONDS: float = 1.0
const CAPTURE_SECONDS: float = 34.0
const CAPTURE_FPS: int = 10
const EXPECTED_CASES: PackedStringArray = ["HEAD", "CHEST", "WAIST", "KNEE", "FLOOR"]

var _scene: Node
var _actor: EmbodiedInteractionLabActor
var _time: float = 0.0
var _capture_time: float = 0.0
var _frame_index: int = 0
var _frame_credit: float = 0.0
var _capturing: bool = false
var _hero_saved: bool = false
var _saved_pickup_cases: Dictionary = {}
var _handoff_saved: bool = false
var _headless: bool = false


func _initialize() -> void:
	_headless = DisplayServer.get_name() == "headless"
	Engine.max_fps = 0 if _headless else CAPTURE_FPS
	Engine.time_scale = 8.0 if _headless else 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_actor = _scene.get_node("Henry") as EmbodiedInteractionLabActor
	_scene.process_mode = Node.PROCESS_MODE_DISABLED
	print("[EmbodiedCapture] warmup started")


func _process(delta: float) -> bool:
	_time += delta
	if not _capturing:
		if _time < WARMUP_SECONDS:
			return false
		_scene.process_mode = Node.PROCESS_MODE_INHERIT
		_capturing = true
		_capture_time = 0.0
		print("[EmbodiedCapture] capture started")
		return false

	_capture_time += delta
	_capture_time_quantized(delta)
	_capture_pickup_keyframe()
	_capture_handoff_keyframe()

	if _capture_time >= CAPTURE_SECONDS:
		var result: Dictionary = _write_report()
		print("[EmbodiedCapture] frames=%d seconds=%.2f movie_seconds=%.2f semantic_pass=%s" % [
			_frame_index, _capture_time, float(_frame_index) / float(CAPTURE_FPS), bool(result["pass"])])
		if not bool(result["pass"]):
			push_error("Embodied semantic proof failed: %s" % ", ".join(result["failures"] as PackedStringArray))
			quit(1)
		else:
			quit()
	return false


func _capture_time_quantized(delta: float) -> void:
	_frame_credit += delta * float(CAPTURE_FPS)
	var copies: int = int(floor(_frame_credit))
	if copies <= 0:
		return
	_frame_credit -= float(copies)
	var image := _viewport_image()
	for _copy: int in range(copies):
		if image != null:
			image.save_png("%s/frame_%04d.png" % [FRAME_DIR, _frame_index])
			_frame_index += 1


func _capture_pickup_keyframe() -> void:
	if _actor == null or _actor.get_pickup_phase() != "IDLE_PRESENT":
		return
	var case_index: int = _actor.get_pickup_case_index()
	if case_index < 0 or _saved_pickup_cases.has(case_index):
		return
	_saved_pickup_cases[case_index] = true
	var image := _viewport_image()
	if image != null:
		image.save_png("%s/pickup_case_%02d.png" % [OUT_DIR, case_index + 1])
	if not _hero_saved and image != null:
		image.save_png(OUT_DIR + "/alignment_action.png")
		_hero_saved = true


func _capture_handoff_keyframe() -> void:
	if _actor == null or _handoff_saved or _actor.get_handoff_phase() != "CONTACT":
		return
	_handoff_saved = true
	var image := _viewport_image()
	if image != null:
		image.save_png(OUT_DIR + "/handoff_contact.png")


func _viewport_image() -> Image:
	if _headless or root.get_texture() == null:
		return null
	return root.get_texture().get_image()


func _write_report() -> Dictionary:
	var proof: Dictionary = _actor.get_capture_report() if _actor != null else {}
	var failures := PackedStringArray()
	_validate_pickups(proof, failures)
	_validate_cycles(proof, failures)
	var handoff: Dictionary = proof.get("handoff", {}) as Dictionary
	if not bool(handoff.get("contact", false)):
		failures.append("handoff_contact")
	var receiver_arm: Dictionary = handoff.get("receiver_arm", {}) as Dictionary
	if bool(handoff.get("contact", false)) and not bool(receiver_arm.get("feasible", false)):
		failures.append("handoff_receiver_arm")
	if _saved_pickup_cases.size() != EXPECTED_CASES.size():
		failures.append("pickup_keyframes_%d_of_%d" % [_saved_pickup_cases.size(), EXPECTED_CASES.size()])
	if not _handoff_saved:
		failures.append("handoff_keyframe")
	if bool(proof.get("finger_ccd_required", true)):
		failures.append("finger_ccd_still_semantic")

	var semantic_pass: bool = failures.is_empty()
	var report: Dictionary = {
		"scene": SCENE,
		"frame_count": _frame_index,
		"capture_seconds": _capture_time,
		"movie_seconds": float(_frame_index) / float(CAPTURE_FPS),
		"requested_fps": CAPTURE_FPS,
		"pickup_keyframes": _saved_pickup_cases.size(),
		"handoff_keyframe": _handoff_saved,
		"semantic_pass": semantic_pass,
		"semantic_failures": Array(failures),
		"proof": proof,
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	return {"pass": semantic_pass, "failures": failures}


func _validate_pickups(proof: Dictionary, failures: PackedStringArray) -> void:
	var results: Array = proof.get("pickup_results", []) as Array
	if results.size() != EXPECTED_CASES.size():
		failures.append("pickup_results_%d_of_%d" % [results.size(), EXPECTED_CASES.size()])
		return
	var by_name: Dictionary = {}
	for value: Variant in results:
		if value is Dictionary:
			var result: Dictionary = value as Dictionary
			by_name[String(result.get("name", ""))] = result
	for case_name: String in EXPECTED_CASES:
		if not by_name.has(case_name):
			failures.append("%s_missing_result" % case_name)
			continue
		var result: Dictionary = by_name[case_name]
		if not bool(result.get("contact", false)):
			failures.append("%s_%s" % [case_name, String(result.get("reason", "no_contact"))])
		if String(result.get("chosen_hand", "")).is_empty():
			failures.append("%s_no_hand" % case_name)
		if not bool(result.get("body_aligned", false)):
			failures.append("%s_body" % case_name)
		var arm: Dictionary = result.get("arm", {}) as Dictionary
		if not bool(arm.get("feasible", false)):
			failures.append("%s_arm_%s" % [case_name, String(arm.get("reason", "invalid"))])


func _validate_cycles(proof: Dictionary, failures: PackedStringArray) -> void:
	var cycles: Dictionary = proof.get("cycle_results", {}) as Dictionary
	for case_name: String in EXPECTED_CASES:
		if not cycles.has(case_name):
			failures.append("%s_missing_cycle" % case_name)
			continue
		var cycle: Dictionary = cycles[case_name] as Dictionary
		if not bool(cycle.get("grasped", false)):
			failures.append("%s_cycle_grasp" % case_name)
		if not bool(cycle.get("stood_to_idle", false)):
			failures.append("%s_cycle_stand" % case_name)
		if not bool(cycle.get("idle_presented", false)):
			failures.append("%s_cycle_idle_present" % case_name)
		if case_name != "FLOOR":
			if not bool(cycle.get("returned", false)):
				failures.append("%s_cycle_return" % case_name)
			if not bool(cycle.get("released", false)):
				failures.append("%s_cycle_release" % case_name)

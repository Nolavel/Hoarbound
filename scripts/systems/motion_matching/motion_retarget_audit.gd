class_name MotionRetargetAudit
extends RefCounted

## Structural garbage detector for retargeted Henry poses (anatomical limits).
## Passing it does not replace looking at the rendered frames.

const HEAD_OVER_PELVIS_MIN := 0.35
const PELVIS_OVER_FEET_MIN := 0.40
const UPRIGHT_MAX_DEG := 35.0
const PELVIS_TILT_MAX_DEG := 45.0
const CHEST_YAW_MAX_DEG := 75.0
const FEET_MIN_SEPARATION := 0.06
const BONE_LENGTH_TOLERANCE := 0.001
const BASIS_DETERMINANT_TOLERANCE := 0.01
const ANGULAR_SPIKE_RAD_PER_S := 20.0
const KNEE_BENT_DEG := 15.0
const KNEE_BACKWARD_M := 0.02
const GROUND_MEDIAN_MAX := 0.06
const GROUND_PENETRATION_P5 := -0.08

var _target: UALSkeletonModel
var _rest_lengths := PackedFloat32Array()
var _indices: Dictionary = {}
var _ball_rest_height := 0.0
var _samples := 0
var _failures: Dictionary = {}
var _failed_samples := PackedInt32Array()
var _sample_failed := false
var _crossed_feet := 0
var _ground_errors: Array[float] = []
var _max_angular_speed := 0.0
var _max_angular_bone := ""
var _max_angular_sample := -1


func _init(target: UALSkeletonModel) -> void:
	_target = target
	for bone_name in ["pelvis", "spine_03", "Head", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]:
		_indices[bone_name] = target.find_bone(bone_name)
	_rest_lengths.resize(target.get_bone_count())
	for bone_index in range(target.get_bone_count()):
		var parent := target.parents[bone_index]
		_rest_lengths[bone_index] = 0.0 if parent < 0 else target.rest_local[bone_index].origin.length()
	_ball_rest_height = target.rest_global[_indices["ball_l"]].origin.y
	for check in ["non_finite", "quaternion_norm", "head_below_pelvis", "feet_above_pelvis", "not_upright",
			"pelvis_flipped", "chest_twisted", "feet_collapsed", "bone_length_changed", "bad_basis",
			"angular_spike", "knee_backward"]:
		_failures[check] = 0


func add_sample(globals: Array[Transform3D], rotations: Array[Quaternion], previous_rotations: Array[Quaternion], dt: float) -> void:
	if _sample_failed:
		_failed_samples.append(_samples - 1)
	_sample_failed = false
	_samples += 1
	var pelvis := globals[_indices["pelvis"]]
	var head := globals[_indices["Head"]].origin
	var foot_l := globals[_indices["foot_l"]].origin
	var foot_r := globals[_indices["foot_r"]].origin

	for bone_index in range(globals.size()):
		var transform := globals[bone_index]
		if not transform.origin.is_finite() or not transform.basis.is_finite():
			_fail("non_finite")
			return
		if absf(rotations[bone_index].length() - 1.0) > 0.001:
			_fail("quaternion_norm")
		if absf(transform.basis.determinant() - 1.0) > BASIS_DETERMINANT_TOLERANCE:
			_fail("bad_basis")
		var parent := _target.parents[bone_index]
		if parent >= 0 and bone_index != _target.pelvis_index:
			var length := transform.origin.distance_to(globals[parent].origin)
			if absf(length - _rest_lengths[bone_index]) > BONE_LENGTH_TOLERANCE:
				_fail("bone_length_changed")
		var angular := previous_rotations[bone_index].angle_to(rotations[bone_index]) / maxf(dt, 0.0001)
		if angular > _max_angular_speed:
			_max_angular_speed = angular
			_max_angular_bone = _target.bone_names[bone_index]
			_max_angular_sample = _samples - 1
		if angular > ANGULAR_SPIKE_RAD_PER_S:
			_fail("angular_spike")

	if head.y - pelvis.origin.y < HEAD_OVER_PELVIS_MIN:
		_fail("head_below_pelvis")
	# The supporting foot stays a leg below the hips; a running swing heel may kick
	# up behind (CMU runs), but no foot ever rises past the pelvis.
	if pelvis.origin.y - minf(foot_l.y, foot_r.y) < PELVIS_OVER_FEET_MIN or maxf(foot_l.y, foot_r.y) > pelvis.origin.y:
		_fail("feet_above_pelvis")
	if rad_to_deg((head - pelvis.origin).angle_to(Vector3.UP)) > UPRIGHT_MAX_DEG:
		_fail("not_upright")
	var pelvis_delta := pelvis.basis * _target.rest_global[_target.pelvis_index].basis.inverse()
	if rad_to_deg((pelvis_delta * Vector3.UP).angle_to(Vector3.UP)) > PELVIS_TILT_MAX_DEG:
		_fail("pelvis_flipped")
	var chest_index: int = _indices["spine_03"]
	var chest_delta := globals[chest_index].basis * _target.rest_global[chest_index].basis.inverse()
	var chest_forward := chest_delta * Vector3.BACK
	if rad_to_deg(Vector2(chest_forward.x, chest_forward.z).angle_to(Vector2(0.0, 1.0))) > CHEST_YAW_MAX_DEG:
		_fail("chest_twisted")
	if foot_l.distance_to(foot_r) < FEET_MIN_SEPARATION:
		_fail("feet_collapsed")
	if foot_l.x < foot_r.x - 0.05:
		_crossed_feet += 1
	var pelvis_forward := pelvis_delta * Vector3.BACK
	for side in ["l", "r"]:
		var thigh := globals[_indices["thigh_" + side]].origin
		var knee := globals[_indices["calf_" + side]].origin
		var ankle := globals[_indices["foot_" + side]].origin
		var bend := rad_to_deg((knee - thigh).angle_to(ankle - knee))
		var knee_forward := (knee - (thigh + ankle) * 0.5).dot(pelvis_forward)
		if bend > KNEE_BENT_DEG and knee_forward < -KNEE_BACKWARD_M:
			_fail("knee_backward")
	var lowest := minf(globals[_indices["ball_l"]].origin.y, globals[_indices["ball_r"]].origin.y)
	_ground_errors.append(lowest - _ball_rest_height)


## Sample indices (in add order) that broke at least one structural check.
func get_failed_samples() -> PackedInt32Array:
	var result := _failed_samples.duplicate()
	if _sample_failed:
		result.append(_samples - 1)
	return result


func get_report() -> Dictionary:
	var sorted := _ground_errors.duplicate()
	sorted.sort()
	var ground := {"p5": 0.0, "median": 0.0, "p95": 0.0}
	if not sorted.is_empty():
		ground = {
			"p5": sorted[int(sorted.size() * 0.05)],
			"median": sorted[int(sorted.size() * 0.5)],
			"p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))],
		}
	var hard_failures := 0
	for check in _failures.keys():
		hard_failures += int(_failures[check])
	var ground_ok := absf(float(ground["median"])) <= GROUND_MEDIAN_MAX and float(ground["p5"]) >= GROUND_PENETRATION_P5
	return {
		"samples": _samples,
		"failures": _failures.duplicate(),
		"hard_failure_count": hard_failures,
		"crossed_feet_fraction": 0.0 if _samples == 0 else float(_crossed_feet) / float(_samples),
		"ground_error_m": ground,
		"max_bone_angular_speed_rad_s": _max_angular_speed,
		"max_angular_bone": _max_angular_bone,
		"max_angular_sample": _max_angular_sample,
		"passed": hard_failures == 0 and ground_ok,
		"failed_sample_count": get_failed_samples().size(),
	}


func _fail(check: String) -> void:
	_failures[check] = int(_failures.get(check, 0)) + 1
	_sample_failed = true

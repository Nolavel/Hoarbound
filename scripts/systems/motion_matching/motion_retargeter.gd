class_name MotionRetargeter
extends RefCounted

## Source BVH -> canonical Henry UAL pose stream in character-root space.
## Pipeline and references: docs/motion_matching/retarget_audit.md.

const POSITION_SMOOTH_SECONDS := 0.5
const DIRECTION_SMOOTH_SECONDS := 1.0
const SAVGOL_ORDER := 3
const STANCE_TOE_SPEED := 0.20
const STANCE_HEIGHT_BAND := 0.03
const PROBE_BONES := [
	"pelvis", "spine_03", "Head", "foot_l", "foot_r", "ball_l", "ball_r",
	"calf_l", "calf_r", "thigh_l", "thigh_r", "hand_l", "hand_r",
]

var profile: SourceRetargetProfile
var clip: BVHClip
var target: UALSkeletonModel
var error_message: String = ""
var report: Dictionary = {}

## Henry-scale root track over the whole clip at track_rate_hz.
var track_rate_hz: float = 30.0
var root_positions: Array[Vector3] = []
var root_forwards: Array[Vector3] = []
var motion_scale: float = 1.0

var _alignment := Basis.IDENTITY
var _source_index_by_target: PackedInt32Array = PackedInt32Array()
var _source_reference_inverse: Array[Quaternion] = []
var _target_reference: Array[Quaternion] = []
var _target_rest_local: Array[Quaternion] = []
var _hips_index: int = -1
var _reference_leg_vertical: float = 0.0
var _ankle_stance_height: float = 0.0
var _pelvis_rest_model := Vector3.ZERO
var _pelvis_parent_rest_inverse := Transform3D.IDENTITY
## Constant vertical error the subject's proportions leave on Henry, metres.
var _ground_offset: float = 0.0


func setup(source_clip: BVHClip, source_profile: SourceRetargetProfile, target_model: UALSkeletonModel, rate_hz: float = 30.0) -> bool:
	clip = source_clip
	profile = source_profile
	target = target_model
	track_rate_hz = rate_hz
	if clip == null or profile == null or target == null:
		return _fail("missing clip/profile/target")
	_hips_index = clip.find_bone(String(profile.bone_map.get("pelvis", "")))
	if _hips_index < 0:
		return _fail("source has no pelvis joint %s" % profile.bone_map.get("pelvis", ""))
	if not _build_mapping():
		return false
	var reference := clip.global_transforms(profile.reference_frame)
	if not _measure_reference_heading(reference):
		return false
	_build_reference_rotations(reference)
	_build_root_track()
	_calibrate_feet_and_height(reference)
	_target_rest_local = target.rest_rotations()
	var pelvis := target.pelvis_index
	_pelvis_rest_model = target.rest_global[pelvis].origin
	var pelvis_parent := target.parents[pelvis]
	_pelvis_parent_rest_inverse = Transform3D.IDENTITY if pelvis_parent < 0 else target.rest_global[pelvis_parent].affine_inverse()
	_ground_offset = 0.0  # measured on the unaligned retarget
	_ground_offset = _measure_ground_offset()
	report["ground_offset_m"] = _ground_offset
	report["dataset"] = profile.dataset
	report["source_path"] = clip.source_path
	report["source_fps"] = 1.0 / clip.frame_time
	report["duration_seconds"] = get_duration()
	report["motion_scale_henry_over_source_leg"] = motion_scale
	report["mapped_bones"] = profile.bone_map.size()
	return true


func get_duration() -> float:
	return clip.get_duration(profile.first_motion_frame)


func track_index(seconds: float) -> int:
	return clampi(int(round(seconds * track_rate_hz)), 0, root_positions.size() - 1)


## Henry local rotations + pelvis local position for one source time.
func retarget_at(seconds: float) -> Dictionary:
	var frame := clip.frame_at_time(seconds, profile.first_motion_frame)
	var source := clip.global_transforms(frame)
	var index := track_index(seconds)
	var root := root_positions[index]
	var yaw_inverse := _yaw_basis(root_forwards[index]).inverse()
	var to_root := yaw_inverse * _alignment

	var bone_count := target.get_bone_count()
	var local_rotations: Array[Quaternion] = []
	local_rotations.resize(bone_count)
	var global_rotations: Array[Quaternion] = []
	global_rotations.resize(bone_count)
	for bone_index in range(bone_count):
		var parent := target.parents[bone_index]
		var parent_rotation := Quaternion.IDENTITY if parent < 0 else global_rotations[parent]
		var source_index := _source_index_by_target[bone_index]
		if source_index >= 0:
			var source_rotation := Quaternion(to_root * source[source_index].basis.orthonormalized())
			var target_global := (source_rotation * _source_reference_inverse[bone_index] * _target_reference[bone_index]).normalized()
			local_rotations[bone_index] = (parent_rotation.inverse() * target_global).normalized()
			global_rotations[bone_index] = target_global
		else:
			local_rotations[bone_index] = _target_rest_local[bone_index]
			global_rotations[bone_index] = (parent_rotation * _target_rest_local[bone_index]).normalized()

	var hips_world := _alignment * source[_hips_index].origin * motion_scale
	var hips_local := yaw_inverse * (hips_world - root)
	var height_delta := hips_local.y / motion_scale - _ankle_stance_height - _reference_leg_vertical
	var pelvis_model := Vector3(
		_pelvis_rest_model.x + hips_local.x,
		_pelvis_rest_model.y + height_delta * motion_scale - _ground_offset,
		_pelvis_rest_model.z + hips_local.z
	)
	return {
		"rotations": local_rotations,
		"pelvis_position": _pelvis_parent_rest_inverse * pelvis_model,
	}


## Source joints in Henry's root frame and scale, for side-by-side diagnostics.
func normalized_source_positions(seconds: float) -> PackedVector3Array:
	var frame := clip.frame_at_time(seconds, profile.first_motion_frame)
	var source := clip.global_transforms(frame)
	var index := track_index(seconds)
	var yaw_inverse := _yaw_basis(root_forwards[index]).inverse()
	var result := PackedVector3Array()
	for transform in source:
		var world := _alignment * transform.origin * motion_scale
		result.append(yaw_inverse * (world - root_positions[index]) - Vector3(0.0, (_ankle_stance_height) * motion_scale, 0.0))
	return result


## Raw source joints (aligned, meters) relative to the clip start root.
func raw_source_positions(seconds: float) -> PackedVector3Array:
	var frame := clip.frame_at_time(seconds, profile.first_motion_frame)
	var source := clip.global_transforms(frame)
	var start := root_positions[0] / motion_scale
	var result := PackedVector3Array()
	for transform in source:
		result.append(_alignment * transform.origin - start - Vector3(0.0, _ankle_stance_height, 0.0))
	return result


func _build_mapping() -> bool:
	_source_index_by_target.resize(target.get_bone_count())
	_source_index_by_target.fill(-1)
	var missing: Array[String] = []
	for target_name in profile.bone_map.keys():
		var target_index := target.find_bone(String(target_name))
		var source_index := clip.find_bone(String(profile.bone_map[target_name]))
		if target_index < 0 or source_index < 0:
			missing.append("%s<-%s" % [target_name, profile.bone_map[target_name]])
			continue
		_source_index_by_target[target_index] = source_index
	if not missing.is_empty():
		return _fail("profile %s mapping does not match the file: %s" % [profile.dataset, ", ".join(missing)])
	return true


func _measure_reference_heading(reference: Array[Transform3D]) -> bool:
	var forward := _heading_forward(reference)
	if forward == Vector3.ZERO:
		return _fail("reference heading joints are degenerate")
	var expected := profile.reference_forward.normalized()
	var agreement := forward.dot(expected)
	report["reference_forward_measured"] = [forward.x, forward.y, forward.z]
	report["reference_forward_agreement"] = agreement
	if agreement < 0.9:
		return _fail("reference forward %s disagrees with profile %s" % [forward, expected])
	# Align the measured source forward with UAL's model forward (+Z).
	_alignment = Basis(Vector3.UP, atan2(forward.x, forward.z)).inverse()
	return true


func _build_reference_rotations(reference: Array[Transform3D]) -> void:
	var bone_count := target.get_bone_count()
	_source_reference_inverse.resize(bone_count)
	_target_reference.resize(bone_count)
	var aligned_report: Dictionary = {}
	for bone_index in range(bone_count):
		_target_reference[bone_index] = target.rest_global[bone_index].basis.get_rotation_quaternion()
		var source_index := _source_index_by_target[bone_index]
		if source_index < 0:
			_source_reference_inverse[bone_index] = Quaternion.IDENTITY
			continue
		var source_reference := Quaternion(_alignment * reference[source_index].basis.orthonormalized())
		var bone_name := target.bone_names[bone_index]
		if profile.segment_aligned_bones.has(bone_name):
			var child_name := String(SourceRetargetProfile.UAL_SEGMENT_CHILD[bone_name])
			var source_child := clip.find_bone(String(profile.bone_map[child_name]))
			var target_child := target.find_bone(child_name)
			var source_dir := (_alignment * (reference[source_child].origin - reference[source_index].origin)).normalized()
			var target_dir := (target.rest_global[target_child].origin - target.rest_global[bone_index].origin).normalized()
			source_reference = Quaternion(source_dir, target_dir) * source_reference
			aligned_report[bone_name] = rad_to_deg(source_dir.angle_to(target_dir))
		_source_reference_inverse[bone_index] = source_reference.inverse()
	report["segment_alignment_degrees"] = aligned_report


func _build_root_track() -> void:
	var source_legs := 0.0
	var reference := clip.global_transforms(profile.reference_frame)
	for side in ["l", "r"]:
		var thigh := clip.find_bone(String(profile.bone_map["thigh_" + side]))
		var calf := clip.find_bone(String(profile.bone_map["calf_" + side]))
		var foot := clip.find_bone(String(profile.bone_map["foot_" + side]))
		source_legs += reference[thigh].origin.distance_to(reference[calf].origin)
		source_legs += reference[calf].origin.distance_to(reference[foot].origin)
	motion_scale = target.leg_length() / maxf(source_legs * 0.5, 0.01)

	var count := int(floor(get_duration() * track_rate_hz)) + 1
	var raw_positions: Array[Vector3] = []
	var raw_forwards: Array[Vector3] = []
	for sample in range(count):
		var frame := clip.frame_at_time(float(sample) / track_rate_hz, profile.first_motion_frame)
		var source := clip.global_transforms(frame)
		var hips := _alignment * source[_hips_index].origin * motion_scale
		raw_positions.append(Vector3(hips.x, 0.0, hips.z))
		var forward := _alignment * _heading_forward(source)
		raw_forwards.append(forward if forward != Vector3.ZERO else Vector3.BACK)
	root_positions = _savgol(raw_positions, int(round(POSITION_SMOOTH_SECONDS * track_rate_hz * 0.5)))
	var smoothed_forwards := _savgol(raw_forwards, int(round(DIRECTION_SMOOTH_SECONDS * track_rate_hz * 0.5)))
	root_forwards.clear()
	for forward in smoothed_forwards:
		var flat := Vector3(forward.x, 0.0, forward.z)
		root_forwards.append(flat.normalized() if flat.length_squared() > 0.000001 else Vector3.BACK)


func _calibrate_feet_and_height(reference: Array[Transform3D]) -> void:
	var foot_report: Dictionary = {}
	var stance_ankle_heights: Array[float] = []
	var reference_ankle_y := 0.0
	for side in ["l", "r"]:
		var ankle := clip.find_bone(profile.left_ankle if side == "l" else profile.right_ankle)
		var toe := clip.find_bone(profile.left_toe if side == "l" else profile.right_toe)
		reference_ankle_y += reference[ankle].origin.y * 0.5
		var toe_heights: Array[float] = []
		var samples: Array[Dictionary] = []
		var previous_toe := Vector3.INF
		for sample in range(root_positions.size()):
			var frame := clip.frame_at_time(float(sample) / track_rate_hz, profile.first_motion_frame)
			var source := clip.global_transforms(frame)
			var toe_position := _alignment * source[toe].origin
			var ankle_position := _alignment * source[ankle].origin
			var speed := 0.0 if previous_toe == Vector3.INF else toe_position.distance_to(previous_toe) * track_rate_hz
			previous_toe = toe_position
			toe_heights.append(toe_position.y)
			samples.append({"toe": toe_position, "ankle": ankle_position, "speed": speed})
		toe_heights.sort()
		var contact_level := toe_heights[int(toe_heights.size() * 0.05)]
		var pitches: Array[float] = []
		for entry in samples:
			var toe_position: Vector3 = entry["toe"]
			if float(entry["speed"]) > STANCE_TOE_SPEED or toe_position.y > contact_level + STANCE_HEIGHT_BAND:
				continue
			var ankle_position: Vector3 = entry["ankle"]
			var foot_dir := toe_position - ankle_position
			pitches.append(atan2(foot_dir.y, Vector2(foot_dir.x, foot_dir.z).length()))
			stance_ankle_heights.append(ankle_position.y)
		var target_index := target.find_bone("foot_" + side)
		var reference_dir := _alignment * (reference[toe].origin - reference[ankle].origin)
		var reference_pitch := atan2(reference_dir.y, Vector2(reference_dir.x, reference_dir.z).length())
		var flat_pitch := reference_pitch if pitches.is_empty() else _median(pitches)
		var horizontal := Vector3(reference_dir.x, 0.0, reference_dir.z).normalized()
		var flat_dir := horizontal * cos(flat_pitch) + Vector3.UP * sin(flat_pitch)
		# Pose match, not segment match: ankle placement differs per skeleton.
		var correction := Quaternion(reference_dir.normalized(), flat_dir.normalized())
		var reference_rotation := _source_reference_inverse[target_index].inverse()
		_source_reference_inverse[target_index] = (correction * reference_rotation).inverse()
		foot_report[side] = {
			"stance_samples": pitches.size(),
			"reference_pitch_deg": rad_to_deg(reference_pitch),
			"flat_pitch_deg": rad_to_deg(flat_pitch),
		}
	var reference_hips_y := reference[_hips_index].origin.y
	_ankle_stance_height = reference_ankle_y if stance_ankle_heights.is_empty() else _median(stance_ankle_heights)
	_reference_leg_vertical = reference_hips_y - reference_ankle_y
	report["foot_calibration"] = foot_report
	report["source_ankle_stance_height_m"] = _ankle_stance_height
	report["source_reference_hips_over_ankle_m"] = _reference_leg_vertical


func _heading_forward(transforms: Array[Transform3D]) -> Vector3:
	var across := Vector3.ZERO
	for pair_index in range(profile.left_heading_joints.size()):
		var left := clip.find_bone(profile.left_heading_joints[pair_index])
		var right := clip.find_bone(profile.right_heading_joints[pair_index])
		if left < 0 or right < 0:
			return Vector3.ZERO
		across += (transforms[left].origin - transforms[right].origin).normalized()
	var forward := across.cross(Vector3.UP)
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.000001 else Vector3.ZERO


func _yaw_basis(forward: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(forward.x, forward.z))


## Savitzky-Golay smoothing with shrinking windows at the clip ends.
func _savgol(values: Array[Vector3], half_window: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count := values.size()
	for center in range(count):
		var first := maxi(0, center - half_window)
		var last := mini(count - 1, center + half_window)
		var order := mini(SAVGOL_ORDER, last - first)
		result.append(_poly_fit_at(values, first, last, center, order))
	return result


func _poly_fit_at(values: Array[Vector3], first: int, last: int, center: int, order: int) -> Vector3:
	var size := order + 1
	var moments := PackedFloat64Array()
	moments.resize(2 * order + 1)
	var rhs: Array[Vector3] = []
	rhs.resize(size)
	rhs.fill(Vector3.ZERO)
	for index in range(first, last + 1):
		var x := float(index - center)
		var power := 1.0
		for degree in range(2 * order + 1):
			moments[degree] += power
			if degree < size:
				rhs[degree] += values[index] * power
			power *= x
	# Solve the normal equations; only the constant term is needed at x = 0.
	var matrix: Array[PackedFloat64Array] = []
	for row in range(size):
		var line := PackedFloat64Array()
		line.resize(size)
		for column in range(size):
			line[column] = moments[row + column]
		matrix.append(line)
	for pivot in range(size):
		var best := pivot
		for row in range(pivot + 1, size):
			if absf(matrix[row][pivot]) > absf(matrix[best][pivot]):
				best = row
		if best != pivot:
			var swap_line := matrix[pivot]
			matrix[pivot] = matrix[best]
			matrix[best] = swap_line
			var swap_rhs := rhs[pivot]
			rhs[pivot] = rhs[best]
			rhs[best] = swap_rhs
		var diagonal := matrix[pivot][pivot]
		if absf(diagonal) < 1e-12:
			return values[center]
		for row in range(size):
			if row == pivot:
				continue
			var factor := matrix[row][pivot] / diagonal
			if factor == 0.0:
				continue
			for column in range(pivot, size):
				matrix[row][column] -= factor * matrix[pivot][column]
			rhs[row] -= rhs[pivot] * factor
	return rhs[0] / matrix[0][0]


## Ground alignment: median over the clip of Henry's lower ball joint against its
## flat-foot rest height (the audit's ground error), removed from the pelvis.
func _measure_ground_offset() -> float:
	var ball_l := target.find_bone("ball_l")
	var ball_r := target.find_bone("ball_r")
	if ball_l < 0 or ball_r < 0 or root_positions.is_empty():
		return 0.0
	var rest_height := target.rest_global[ball_l].origin.y
	var errors: Array[float] = []
	for sample in range(0, root_positions.size(), 3):
		var pose := retarget_at(float(sample) / track_rate_hz)
		var globals := target.forward_kinematics(pose["rotations"], pose["pelvis_position"])
		errors.append(minf(globals[ball_l].origin.y, globals[ball_r].origin.y) - rest_height)
	return _median(errors)


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _fail(message: String) -> bool:
	error_message = message
	report["error"] = message
	push_error("MotionRetargeter: %s" % message)
	return false

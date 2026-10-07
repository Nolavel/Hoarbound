class_name MotionRetargeter
extends RefCounted

## Source BVH -> canonical Henry UAL pose stream in character-root space.
## Pipeline and references: docs/motion_matching/retarget_audit.md.

const POSITION_SMOOTH_SECONDS := 0.5
const DIRECTION_SMOOTH_SECONDS := 1.0
## Root velocity over this much of a clip's end carries on past it; slower than
## the minimum speed counts as standing still, so noise never drifts.
const EXTRAPOLATION_WINDOW_SECONDS := 0.25
const EXTRAPOLATION_MIN_SPEED := 0.1
const SAVGOL_ORDER := 3
const STANCE_TOE_SPEED := 0.20
const STANCE_HEIGHT_BAND := 0.03
## A foot is planted while it moves slower than this share of the body speed.
const STANCE_SPEED_SHARE := 0.25
## Ankle height gap over which body weight shifts from one foot to the other, m.
const WEIGHT_SHIFT_HEIGHT := 0.02
## Retarget stages on top of the S·R⁻¹·G core; the diagnostics switch them off one by one.
const STAGE_SEGMENT_SWING := 1
const STAGE_FOOT_PITCH := 2
const STAGE_GROUND := 4
const STAGE_STANCE := 8
const STAGE_ALL := 15
## Arms and trunk retargeted from a relaxed standing pair (source idle, Henry idle)
## instead of the T-pose: UE IK Retargeter's retarget pose. Needs both neutral inputs.
const STAGE_NEUTRAL_POSE := 16
## Forearm roll moved from the hand onto the lowerarm, as Henry's own clips carry it.
const STAGE_TWIST_SPLIT := 32
## Spine bones sample the source trunk by length share (UE chain "Interpolated").
const STAGE_SPINE_CHAIN := 64
const NEUTRAL_POSE_BONES := [
	"spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]
const TWIST_PAIRS := [["lowerarm_l", "hand_l"], ["lowerarm_r", "hand_r"]]
## Anatomical elbow flexion limit: Henry's standing elbow bend fades out towards it.
const ELBOW_FLEX_LIMIT_DEGREES := 145.0
const SPINE_CHAIN_TARGETS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
const PROBE_BONES := [
	"pelvis", "spine_03", "Head", "foot_l", "foot_r", "ball_l", "ball_r",
	"calf_l", "calf_r", "thigh_l", "thigh_r", "hand_l", "hand_r",
]

var profile: SourceRetargetProfile
var clip: BVHClip
var target: UALSkeletonModel
var error_message: String = ""
var report: Dictionary = {}
## Enabled STAGE_* bits; set before setup(). Baking always uses STAGE_ALL.
var stages: int = STAGE_ALL
## Henry's relaxed standing pose (local rotation per bone) for STAGE_NEUTRAL_POSE.
var target_neutral_local: Array[Quaternion] = []
## The source family's relaxed standing clip; frames come from the profile.
var source_neutral_clip: BVHClip

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
## Local rotation of bones without a source joint (rest, or Henry's neutral fingers).
var _unmapped_local: Array[Quaternion] = []
## Source trunk joints (hips to neck) and their reference inverses, for STAGE_SPINE_CHAIN.
var _chain_joints: PackedInt32Array = PackedInt32Array()
var _chain_reference_inverse: Array[Quaternion] = []
## Target bone -> [chain segment, share along it].
var _chain_samples: Dictionary = {}
var _twist_indices: Array[Vector2i] = []
## Source joints' mean standing rotation (body frame); empty unless STAGE_NEUTRAL_POSE ran.
var _source_neutral: Array[Quaternion] = []
## Forearm and hand references with a straight elbow on Henry's standing shoulder: the
## standing pose's elbow bend is blended out as the source elbow flexes.
var _straight_source_inverse: Dictionary = {}
var _straight_target: Dictionary = {}
var _soft_elbow_side: Dictionary = {}
var _elbow_joints: Array[Vector3i] = []
var _hips_index: int = -1
var _reference_leg_vertical: float = 0.0
var _ankle_stance_height: float = 0.0
var _pelvis_rest_model := Vector3.ZERO
var _pelvis_parent_rest_inverse := Transform3D.IDENTITY
## Constant vertical error the subject's proportions leave on Henry, metres.
var _ground_offset: float = 0.0
## Per side, how far Henry's planted ball sits from the mean of both, m: the
## source's unequal legs on Henry's equal ones. Removed from the pelvis in stance.
var _stance_offsets: Array[float] = [0.0, 0.0]
var _ankle_indices: Array[int] = [-1, -1]
## Root velocity over the clip's last moments, carried on past its end.
var _end_velocity := Vector3.ZERO


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
	_unmapped_local = _target_rest_local.duplicate()
	if stages & STAGE_NEUTRAL_POSE:
		_apply_neutral_pose(reference)
	if stages & STAGE_SPINE_CHAIN:
		_build_spine_chain(reference)
	_twist_indices.clear()
	if stages & STAGE_TWIST_SPLIT:
		for pair in TWIST_PAIRS:
			_twist_indices.append(Vector2i(target.find_bone(pair[0]), target.find_bone(pair[1])))
	var pelvis := target.pelvis_index
	_pelvis_rest_model = target.rest_global[pelvis].origin
	var pelvis_parent := target.parents[pelvis]
	_pelvis_parent_rest_inverse = Transform3D.IDENTITY if pelvis_parent < 0 else target.rest_global[pelvis_parent].affine_inverse()
	_ankle_indices = [clip.find_bone(profile.left_ankle), clip.find_bone(profile.right_ankle)]
	_ground_offset = 0.0  # both measured on the unaligned retarget
	_stance_offsets = [0.0, 0.0]
	if stages & STAGE_STANCE:
		_stance_offsets = _measure_stance_offsets()
	report["stance_offsets_m"] = _stance_offsets.duplicate()
	if stages & STAGE_GROUND:
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


## Root position, continued at the end velocity past the clip (UE5 Pose Search
## root-motion extrapolation): a capture leaving the volume is not a stop.
func root_position_at(seconds: float) -> Vector3:
	var last := root_positions.size() - 1
	var index := maxi(int(round(seconds * track_rate_hz)), 0)
	if index <= last:
		return root_positions[index]
	return root_positions[last] + _end_velocity * (float(index - last) / track_rate_hz)


## Henry local rotations + pelvis local position for one source time.
func retarget_at(seconds: float) -> Dictionary:
	var frame := clip.frame_at_time(seconds, profile.first_motion_frame)
	var source := clip.global_transforms(frame)
	var index := track_index(seconds)
	var root := root_positions[index]
	var yaw_inverse := _yaw_basis(root_forwards[index]).inverse()
	var to_root := yaw_inverse * _alignment

	var chain_deltas: Array[Quaternion] = []
	for chain_index in range(_chain_joints.size()):
		var joint_rotation := Quaternion(to_root * source[_chain_joints[chain_index]].basis.orthonormalized())
		chain_deltas.append((joint_rotation * _chain_reference_inverse[chain_index]).normalized())
	var elbow_weights: Array[float] = []
	for joints in _elbow_joints:
		var upper := source[joints.y].origin - source[joints.x].origin
		var fore := source[joints.z].origin - source[joints.y].origin
		var flex := rad_to_deg(upper.angle_to(fore)) if upper.length_squared() > 0.0 and fore.length_squared() > 0.0 else 0.0
		elbow_weights.append(clampf(1.0 - flex / ELBOW_FLEX_LIMIT_DEGREES, 0.0, 1.0))
	var bone_count := target.get_bone_count()
	var local_rotations: Array[Quaternion] = []
	local_rotations.resize(bone_count)
	var global_rotations: Array[Quaternion] = []
	global_rotations.resize(bone_count)
	for bone_index in range(bone_count):
		var parent := target.parents[bone_index]
		var parent_rotation := Quaternion.IDENTITY if parent < 0 else global_rotations[parent]
		var source_index := _source_index_by_target[bone_index]
		if _chain_samples.has(bone_index):
			var sample: Vector2 = _chain_samples[bone_index]
			var delta := chain_deltas[int(sample.x)].slerp(chain_deltas[int(sample.x) + 1], sample.y)
			var target_global := (delta * _target_reference[bone_index]).normalized()
			local_rotations[bone_index] = (parent_rotation.inverse() * target_global).normalized()
			global_rotations[bone_index] = target_global
		elif source_index >= 0:
			var source_rotation := Quaternion(to_root * source[source_index].basis.orthonormalized())
			var target_global := (source_rotation * _source_reference_inverse[bone_index] * _target_reference[bone_index]).normalized()
			if _soft_elbow_side.has(bone_index):
				var straight_inverse: Quaternion = _straight_source_inverse[bone_index]
				var straight_target: Quaternion = _straight_target[bone_index]
				var straight := (source_rotation * straight_inverse * straight_target).normalized()
				target_global = straight.slerp(target_global, elbow_weights[int(_soft_elbow_side[bone_index])])
			local_rotations[bone_index] = (parent_rotation.inverse() * target_global).normalized()
			global_rotations[bone_index] = target_global
		else:
			local_rotations[bone_index] = _unmapped_local[bone_index]
			global_rotations[bone_index] = (parent_rotation * _unmapped_local[bone_index]).normalized()
	for pair in _twist_indices:
		_split_twist(local_rotations, pair.x, pair.y)

	var hips_world := _alignment * source[_hips_index].origin * motion_scale
	var hips_local := yaw_inverse * (hips_world - root)
	var height_delta := hips_local.y / motion_scale - _ankle_stance_height - _reference_leg_vertical
	var pelvis_model := Vector3(
		_pelvis_rest_model.x + hips_local.x,
		_pelvis_rest_model.y + height_delta * motion_scale - _ground_offset - _stance_correction(source),
		_pelvis_rest_model.z + hips_local.z
	)
	return {
		"rotations": local_rotations,
		"pelvis_position": _pelvis_parent_rest_inverse * pelvis_model,
	}


## Source model space -> Henry root space (alignment, then the root yaw) at one time.
func root_space_basis(seconds: float) -> Basis:
	return _yaw_basis(root_forwards[track_index(seconds)]).inverse() * _alignment


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


## Moves the hand's roll about the forearm axis (+Y of the lowerarm) onto the lowerarm;
## the hand keeps its global rotation and position (it sits on that axis).
func _split_twist(local_rotations: Array[Quaternion], lowerarm: int, hand: int) -> void:
	var delta := (local_rotations[hand] * _target_rest_local[hand].inverse()).normalized()
	var twist := Quaternion(0.0, delta.y, 0.0, delta.w)
	if twist.length_squared() < 0.000001:
		return
	twist = twist.normalized()
	local_rotations[lowerarm] = (local_rotations[lowerarm] * twist).normalized()
	local_rotations[hand] = (twist.inverse() * local_rotations[hand]).normalized()


## Arms and trunk take their reference from the relaxed standing pair; fingers keep
## Henry's own neutral hand pose. Heading is taken out of both standing poses.
func _apply_neutral_pose(reference: Array[Transform3D]) -> void:
	if target_neutral_local.size() != target.get_bone_count() or source_neutral_clip == null \
			or source_neutral_clip.bone_names != clip.bone_names or profile.neutral_frames.y <= profile.neutral_frames.x:
		report["neutral_pose"] = "skipped: missing or mismatched neutral inputs"
		return
	var source_neutral := _average_source_neutral()
	_source_neutral = source_neutral
	var target_neutral := _target_neutral_globals()
	for bone_name in NEUTRAL_POSE_BONES:
		var bone_index := target.find_bone(bone_name)
		var source_index := _source_index_by_target[bone_index] if bone_index >= 0 else -1
		if source_index < 0:
			continue
		_source_reference_inverse[bone_index] = source_neutral[source_index].inverse()
		_target_reference[bone_index] = target_neutral[bone_index]
	for side in ["l", "r"]:
		var hand := target.find_bone("hand_" + side)
		for bone_index in range(target.get_bone_count()):
			if _is_descendant(bone_index, hand):
				_unmapped_local[bone_index] = target_neutral_local[bone_index]
	_build_straight_elbow_references(reference, source_neutral, target_neutral)
	report["neutral_pose"] = "%s frames %d-%d" % [profile.neutral_clip, profile.neutral_frames.x, profile.neutral_frames.y]


## Same standing shoulder, elbow and wrist straight as in the reference pose, on both sides.
func _build_straight_elbow_references(reference: Array[Transform3D], source_neutral: Array[Quaternion], target_neutral: Array[Quaternion]) -> void:
	_straight_source_inverse.clear()
	_straight_target.clear()
	_soft_elbow_side.clear()
	_elbow_joints.clear()
	for side in ["l", "r"]:
		var bones := [target.find_bone("upperarm_" + side), target.find_bone("lowerarm_" + side), target.find_bone("hand_" + side)]
		var joints := Vector3i(_source_index_by_target[bones[0]], _source_index_by_target[bones[1]], _source_index_by_target[bones[2]])
		if joints.x < 0 or joints.y < 0 or joints.z < 0:
			continue
		var rest: Array[Quaternion] = []
		var source_reference: Array[Quaternion] = []
		for index in range(3):
			rest.append(target.rest_global[bones[index]].basis.get_rotation_quaternion())
			source_reference.append(Quaternion(_alignment * reference[joints[index]].basis.orthonormalized()))
		var target_lower := target_neutral[bones[0]] * rest[0].inverse() * rest[1]
		var target_hand := target_lower * rest[1].inverse() * rest[2]
		var source_lower := source_neutral[joints.x] * source_reference[0].inverse() * source_reference[1]
		var source_hand := source_lower * source_reference[1].inverse() * source_reference[2]
		_straight_target[bones[1]] = target_lower.normalized()
		_straight_target[bones[2]] = target_hand.normalized()
		_straight_source_inverse[bones[1]] = source_lower.normalized().inverse()
		_straight_source_inverse[bones[2]] = source_hand.normalized().inverse()
		_soft_elbow_side[bones[1]] = _elbow_joints.size()
		_soft_elbow_side[bones[2]] = _elbow_joints.size()
		_elbow_joints.append(joints)


func _average_source_neutral() -> Array[Quaternion]:
	var sums: Array[Quaternion] = []
	for frame in range(profile.neutral_frames.x, mini(profile.neutral_frames.y, source_neutral_clip.frame_count)):
		var transforms := source_neutral_clip.global_transforms(frame)
		var forward := _alignment * _heading_forward(transforms)
		var to_body := _yaw_basis(forward if forward != Vector3.ZERO else Vector3.BACK).inverse() * _alignment
		for joint in range(transforms.size()):
			var rotation := Quaternion(to_body * transforms[joint].basis.orthonormalized())
			if sums.size() <= joint:
				sums.append(rotation)
			else:
				sums[joint] = _accumulate(sums[joint], rotation)
	var result: Array[Quaternion] = []
	for total in sums:
		result.append(total.normalized())
	return result


func _target_neutral_globals() -> Array[Quaternion]:
	var globals := target.forward_kinematics(target_neutral_local, target.rest_local[target.pelvis_index].origin)
	var across := Vector3.ZERO
	for pair in [["thigh_l", "thigh_r"], ["upperarm_l", "upperarm_r"]]:
		across += (globals[target.find_bone(pair[0])].origin - globals[target.find_bone(pair[1])].origin).normalized()
	var forward := across.cross(Vector3.UP)
	forward.y = 0.0
	var to_body := _yaw_basis(forward.normalized() if forward.length_squared() > 0.000001 else Vector3.BACK).inverse()
	var result: Array[Quaternion] = []
	for transform in globals:
		result.append(Quaternion(to_body * transform.basis.orthonormalized()).normalized())
	return result


## Sign-aligned running sum, normalised by the caller: a mean of nearby rotations.
func _accumulate(total: Quaternion, rotation: Quaternion) -> Quaternion:
	var aligned := rotation if total.dot(rotation) >= 0.0 else -rotation
	return Quaternion(total.x + aligned.x, total.y + aligned.y, total.z + aligned.z, total.w + aligned.w)


func _is_descendant(bone_index: int, ancestor: int) -> bool:
	var parent := target.parents[bone_index]
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = target.parents[parent]
	return false


## Source trunk from hips to the joint on Henry's neck; each Henry spine bone samples
## the trunk at its own share of the chain length (both in their reference poses).
func _build_spine_chain(reference: Array[Transform3D]) -> void:
	_chain_samples.clear()
	_chain_joints = PackedInt32Array()
	_chain_reference_inverse.clear()
	var neck := clip.find_bone(String(profile.bone_map.get("neck_01", "")))
	if neck < 0 or _hips_index < 0:
		report["spine_chain"] = "skipped: no neck joint"
		return
	var joint := neck
	while joint >= 0:
		_chain_joints.insert(0, joint)
		if joint == _hips_index:
			break
		joint = clip.parents[joint]
	if _chain_joints[0] != _hips_index or _chain_joints.size() < 3:
		report["spine_chain"] = "skipped: neck is not under the hips"
		return
	var source_shares := _chain_shares(_chain_joints, func(index: int) -> Vector3: return reference[index].origin)
	var target_chain := PackedInt32Array()
	for bone_name in SPINE_CHAIN_TARGETS:
		target_chain.append(target.find_bone(bone_name))
	var target_shares := _chain_shares(target_chain, func(index: int) -> Vector3: return target.rest_global[index].origin)
	# One reference for the whole trunk: the standing pose when it ran, else the T-pose.
	for chain_joint in _chain_joints:
		var reference_rotation := _source_neutral[chain_joint] if not _source_neutral.is_empty() \
			else Quaternion(_alignment * reference[chain_joint].basis.orthonormalized())
		_chain_reference_inverse.append(reference_rotation.inverse())
	for target_index in range(1, target_chain.size() - 1):
		var share := target_shares[target_index]
		var segment := 0
		while segment < source_shares.size() - 2 and source_shares[segment + 1] <= share:
			segment += 1
		var span := maxf(source_shares[segment + 1] - source_shares[segment], 0.000001)
		_chain_samples[target_chain[target_index]] = Vector2(segment, clampf((share - source_shares[segment]) / span, 0.0, 1.0))
	report["spine_chain"] = {"source_shares": source_shares, "target_shares": target_shares}


func _chain_shares(chain: PackedInt32Array, position_of: Callable) -> PackedFloat32Array:
	var lengths := PackedFloat32Array([0.0])
	for index in range(1, chain.size()):
		var step: float = (position_of.call(chain[index]) as Vector3).distance_to(position_of.call(chain[index - 1]))
		lengths.append(lengths[-1] + step)
	var total := maxf(lengths[-1], 0.000001)
	var shares := PackedFloat32Array()
	for length in lengths:
		shares.append(length / total)
	return shares


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
		if stages & STAGE_SEGMENT_SWING and profile.segment_aligned_bones.has(bone_name):
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
	var window := mini(int(round(EXTRAPOLATION_WINDOW_SECONDS * track_rate_hz)), root_positions.size() - 1)
	_end_velocity = Vector3.ZERO
	if window > 0:
		var velocity := (root_positions[-1] - root_positions[-1 - window]) * (track_rate_hz / float(window))
		_end_velocity = velocity if velocity.length() >= EXTRAPOLATION_MIN_SPEED else Vector3.ZERO


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
		var correction := Quaternion(reference_dir.normalized(), flat_dir.normalized()) if stages & STAGE_FOOT_PITCH else Quaternion.IDENTITY
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


## Pelvis shift that sets the weight-bearing foot on the same ground as the other:
## its stance offset, blended by which ankle is lower (equal in double support).
func _stance_correction(source: Array[Transform3D]) -> float:
	if _ankle_indices[0] < 0 or _ankle_indices[1] < 0:
		return 0.0
	var left := (_alignment * source[_ankle_indices[0]].origin).y * motion_scale
	var right := (_alignment * source[_ankle_indices[1]].origin).y * motion_scale
	var left_weight := 1.0 / (1.0 + exp((left - right) / WEIGHT_SHIFT_HEIGHT))
	return left_weight * _stance_offsets[0] + (1.0 - left_weight) * _stance_offsets[1]


## Median height of each planted ball (slower than STANCE_SPEED_SHARE of the root),
## minus the mean of both sides; zero when a side never plants.
func _measure_stance_offsets() -> Array[float]:
	var balls := [target.find_bone("ball_l"), target.find_bone("ball_r")]
	if balls[0] < 0 or balls[1] < 0 or root_positions.size() < 3:
		return [0.0, 0.0]
	var heights: Array = [[], []]
	var previous: Array[Vector3] = []
	for sample in range(root_positions.size()):
		var pose := retarget_at(float(sample) / track_rate_hz)
		var globals := target.forward_kinematics(pose["rotations"], pose["pelvis_position"])
		var basis := _yaw_basis(root_forwards[sample])
		var current: Array[Vector3] = []
		for side in range(2):
			current.append(root_positions[sample] + basis * globals[balls[side]].origin)
		if not previous.is_empty():
			var body_speed := Vector2(root_positions[sample].x - root_positions[sample - 1].x, root_positions[sample].z - root_positions[sample - 1].z).length() * track_rate_hz
			for side in range(2):
				var speed := Vector2(current[side].x - previous[side].x, current[side].z - previous[side].z).length() * track_rate_hz
				if body_speed > 0.3 and speed < STANCE_SPEED_SHARE * body_speed:
					(heights[side] as Array).append(globals[balls[side]].origin.y)
		previous = current
	if (heights[0] as Array).size() < 3 or (heights[1] as Array).size() < 3:
		return [0.0, 0.0]
	var left := _median_of(heights[0])
	var right := _median_of(heights[1])
	var mean := (left + right) * 0.5
	return [left - mean, right - mean]


func _median_of(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


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

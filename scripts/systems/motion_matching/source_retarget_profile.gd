class_name SourceRetargetProfile
extends Resource

## Import conventions of one mocap source family, measured rather than guessed.
## One profile per family; see docs/motion_matching/retarget_audit.md.

## Source family id written to database provenance, e.g. "CMU".
@export var dataset: String = ""
## Source length unit to meters.
@export var units_to_meters: float = 1.0
## Reference (bind) pose frame: 0 = first frame, -1 = zero-rotation BVH offsets.
@export var reference_frame: int = 0
## First frame that is real motion (CMU frame 0 is a synthetic T-pose).
@export var first_motion_frame: int = 1
## Model-space forward of the reference pose; checked against the across vector.
@export var reference_forward: Vector3 = Vector3.BACK
## Height of the capture floor in source space, meters.
@export var floor_height: float = 0.0
## UAL target bone -> source joint. Unmapped source joints still contribute via
## model-space retarget, because each target bone reads its source global pose.
@export var bone_map: Dictionary = {}
## Joints whose left-right differences define the body heading (Holden PFNN).
@export var left_heading_joints: PackedStringArray = PackedStringArray()
@export var right_heading_joints: PackedStringArray = PackedStringArray()
## Source ankle and toe joints, used for floor contact and flat-foot calibration.
@export var left_ankle: String = ""
@export var right_ankle: String = ""
@export var left_toe: String = ""
@export var right_toe: String = ""
## UAL bones whose anatomical segment is aligned to the source reference pose.
@export var segment_aligned_bones: PackedStringArray = PackedStringArray()
## True only after the family passed the retarget audit on real data.
@export var verified: bool = false
## Human-readable conventions, mirrored in docs/motion_matching/retarget_audit.md.
@export_multiline var conventions: String = ""

const UAL_SEGMENT_CHILD := {
	"upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l",
	"thigh_r": "calf_r", "calf_r": "foot_r",
}


static func cmu_bvh() -> SourceRetargetProfile:
	var profile := SourceRetargetProfile.new()
	profile.dataset = "CMU"
	# ASF "units length 0.45": one BVH unit is 1/0.45 inch.
	profile.units_to_meters = 0.0254 / 0.45
	profile.reference_frame = 0
	profile.first_motion_frame = 1
	profile.reference_forward = Vector3.BACK
	profile.floor_height = 0.0
	profile.bone_map = {
		"pelvis": "Hips", "spine_01": "LowerBack", "spine_02": "Spine", "spine_03": "Spine1",
		"neck_01": "Neck1", "Head": "Head",
		"clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
		"clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
		"thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
		"thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase",
	}
	profile.left_heading_joints = PackedStringArray(["LeftUpLeg", "LeftArm"])
	profile.right_heading_joints = PackedStringArray(["RightUpLeg", "RightArm"])
	profile.left_ankle = "LeftFoot"
	profile.right_ankle = "RightFoot"
	profile.left_toe = "LeftToeBase"
	profile.right_toe = "RightToeBase"
	profile.segment_aligned_bones = PackedStringArray(UAL_SEGMENT_CHILD.keys())
	profile.verified = true
	profile.conventions = "Y-up, right-handed; frame 0 synthetic T-pose facing +Z, left +X; ZYX Euler (Zrotation Yrotation Xrotation); root 6 channels; units 1/0.45 inch."
	return profile


static func style100_bvh() -> SourceRetargetProfile:
	var profile := SourceRetargetProfile.new()
	profile.dataset = "100STYLE"
	profile.units_to_meters = 0.01
	profile.reference_frame = -1
	profile.first_motion_frame = 0
	profile.reference_forward = Vector3.BACK
	profile.floor_height = 0.0
	profile.bone_map = {
		"pelvis": "Hips", "spine_01": "Chest", "spine_02": "Chest2", "spine_03": "Chest4",
		"neck_01": "Neck", "Head": "Head",
		"clavicle_l": "LeftCollar", "upperarm_l": "LeftShoulder", "lowerarm_l": "LeftElbow", "hand_l": "LeftWrist",
		"clavicle_r": "RightCollar", "upperarm_r": "RightShoulder", "lowerarm_r": "RightElbow", "hand_r": "RightWrist",
		"thigh_l": "LeftHip", "calf_l": "LeftKnee", "foot_l": "LeftAnkle", "ball_l": "LeftToe",
		"thigh_r": "RightHip", "calf_r": "RightKnee", "foot_r": "RightAnkle", "ball_r": "RightToe",
	}
	profile.left_heading_joints = PackedStringArray(["LeftHip", "LeftShoulder"])
	profile.right_heading_joints = PackedStringArray(["RightHip", "RightShoulder"])
	profile.left_ankle = "LeftAnkle"
	profile.right_ankle = "RightAnkle"
	profile.left_toe = "LeftToe"
	profile.right_toe = "RightToe"
	profile.segment_aligned_bones = PackedStringArray(UAL_SEGMENT_CHILD.keys())
	profile.verified = false # Unmeasured here: see docs/motion_matching/retarget_audit.md.
	profile.conventions = "Assumed: Y-up, centimetres, zero-rotation offsets as reference, frame 0 is motion. Unverified."
	return profile


static func for_dataset(dataset_id: String) -> SourceRetargetProfile:
	match dataset_id:
		"CMU":
			return cmu_bvh()
		"100STYLE":
			return style100_bvh()
	return null

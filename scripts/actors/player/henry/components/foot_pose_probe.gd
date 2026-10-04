class_name FootPoseProbe
extends SkeletonModifier3D

## Read-only first SkeletonModifier3D in Henry's modifier chain. Godot runs
## SkeletonModifier3D after AnimationMixer playback; this probe snapshots the raw
## locomotion pose before Wade/SnowFeet/DoorHand alter it. FootContactSensor then
## consumes that snapshot instead of trying to subtract IK after the fact.
##
## Samples are Skeleton3D-local global bone positions. FootContactSensor applies
## the skeleton's current world transform on its physics tick, so body translation
## between animation and physics updates cannot drag a footprint behind Henry.

signal pose_sampled(side: int, heel: Vector3, ball: Vector3, toe: Vector3)

enum Side { LEFT, RIGHT }

const BONES: Dictionary = {
	Side.LEFT: {"heel": &"foot_l", "ball": &"ball_l", "toe": &"ball_leaf_l"},
	Side.RIGHT: {"heel": &"foot_r", "ball": &"ball_r", "toe": &"ball_leaf_r"},
}

var _index: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	for side: int in Side.values():
		var names: Dictionary = BONES[side]
		var points: Dictionary = {}
		for key: String in names:
			var bone: int = _bone(skeleton, names[key])
			if bone < 0:
				points.clear()
				break
			points[key] = skeleton.get_bone_global_pose(bone).origin
		if not points.is_empty():
			pose_sampled.emit(side, points["heel"], points["ball"], points["toe"])


func _bone(skeleton: Skeleton3D, name: StringName) -> int:
	if not _index.has(name):
		_index[name] = skeleton.find_bone(name)
	return int(_index[name])

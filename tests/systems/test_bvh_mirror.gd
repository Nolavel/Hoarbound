extends SceneTree

## BVHClip.mirrored() reflects a capture across the sagittal plane: each joint lands
## where its other-side partner was, with x negated; mirroring twice restores it.

const BVH := """HIERARCHY
ROOT Hips
{
	OFFSET 0 0 0
	CHANNELS 6 Xposition Yposition Zposition Zrotation Yrotation Xrotation
	JOINT LHipJoint
	{
		OFFSET 0 0 0
		CHANNELS 3 Zrotation Yrotation Xrotation
		JOINT LeftUpLeg
		{
			OFFSET 1.4 -1.7 0.8
			CHANNELS 3 Zrotation Yrotation Xrotation
			JOINT LeftLeg
			{
				OFFSET 2.3 -6.4 0
				CHANNELS 3 Zrotation Yrotation Xrotation
				End Site
				{
					OFFSET 0 -7 0
				}
			}
		}
	}
	JOINT RHipJoint
	{
		OFFSET 0 0 0
		CHANNELS 3 Zrotation Yrotation Xrotation
		JOINT RightUpLeg
		{
			OFFSET -1.5 -1.7 0.8
			CHANNELS 3 Zrotation Yrotation Xrotation
			JOINT RightLeg
			{
				OFFSET -2.4 -6.5 0
				CHANNELS 3 Zrotation Yrotation Xrotation
				End Site
				{
					OFFSET 0 -7 0
				}
			}
		}
	}
}
MOTION
Frames: 2
Frame Time: 0.0333333
1.0 17.0 2.0 5.0 -20.0 3.0 0 0 0 10.0 4.0 -30.0 6.0 -8.0 25.0 0 0 0 -12.0 7.0 15.0 2.0 3.0 9.0
-0.5 16.5 3.0 -4.0 35.0 -6.0 0 0 0 -7.0 11.0 40.0 3.0 2.0 -10.0 0 0 0 9.0 -5.0 -20.0 -1.0 6.0 30.0
"""

var _failures: int = 0


func _initialize() -> void:
	var path := "user://test_bvh_mirror.bvh"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(BVH)
	file.close()
	var clip := BVHClip.new()
	_check(clip.load_file(path, 0.05), "the test BVH does not load")
	var mirrored := clip.mirrored()
	var twice := mirrored.mirrored()
	var largest_mirror := 0.0
	var largest_twice := 0.0
	for frame in range(clip.frame_count):
		var original := clip.global_transforms(frame)
		var reflected := mirrored.global_transforms(frame)
		var restored := twice.global_transforms(frame)
		for bone in range(clip.get_bone_count()):
			var partner := clip.find_bone(BVHClip.mirror_name(clip.bone_names[bone]))
			var expected := original[partner].origin * Vector3(-1.0, 1.0, 1.0)
			largest_mirror = maxf(largest_mirror, reflected[bone].origin.distance_to(expected))
			largest_twice = maxf(largest_twice, restored[bone].origin.distance_to(original[bone].origin))
	print("bvh mirror: mirrored joints off by %.6f m, mirrored twice off by %.6f m" % [largest_mirror, largest_twice])
	_check(BVHClip.mirror_name("LHipJoint") == "RHipJoint" and BVHClip.mirror_name("RightLeg") == "LeftLeg"
		and BVHClip.mirror_name("LowerBack") == "LowerBack", "joint names do not pair up")
	_check(largest_mirror < 0.00001, "a mirrored joint is not where its partner's reflection is")
	_check(largest_twice < 0.00001, "mirroring twice does not restore the capture")
	if _failures > 0:
		push_error("bvh mirror: %d check(s) failed" % _failures)
		quit(1)
		return
	print("bvh mirror: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("bvh mirror: " + message)

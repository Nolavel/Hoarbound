extends SceneTree

## Every bone a body part names (data/body/*.tres) exists on Henry's real skeleton, and each
## pair is mirrored left/right (#236: the feet bones were named by scheme, never checked).

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	var skeletons: Array[Node] = player.find_children("*", "Skeleton3D", true, false)
	_check(not skeletons.is_empty(), "Henry has no Skeleton3D")
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var library: BodyPartLibrary = BodyPartLibrary.shared()
		for id: StringName in library.get_ids():
			var part: BodyPartDefinition = library.find(id)
			_check(not part.bones.is_empty(), "%s names no bones" % id)
			for bone: String in part.bones:
				var index: int = skeleton.find_bone(bone)
				_check(index >= 0, "%s bone '%s' is not on Henry's skeleton" % [id, bone])
				if index >= 0:
					print("body bones: %s %s -> #%d, parent %s" % [id, bone, index, skeleton.get_bone_name(skeleton.get_bone_parent(index))])
		_check_mirrored(skeleton, &"foot_l", &"foot_r")
		_check_mirrored(skeleton, &"hand_l", &"hand_r")
	player.queue_free()
	print("test_body_part_bones: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## The pair sits on opposite sides of Henry in rest pose, at the same height.
func _check_mirrored(skeleton: Skeleton3D, left: StringName, right: StringName) -> void:
	var l: int = skeleton.find_bone(left)
	var r: int = skeleton.find_bone(right)
	if l < 0 or r < 0:
		return
	var lp: Vector3 = skeleton.get_bone_global_rest(l).origin
	var rp: Vector3 = skeleton.get_bone_global_rest(r).origin
	_check(signf(lp.x) != signf(rp.x) and absf(lp.y - rp.y) < 0.02,
		"%s %s and %s %s are not a mirrored pair" % [left, lp, right, rp])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_body_part_bones: " + message)

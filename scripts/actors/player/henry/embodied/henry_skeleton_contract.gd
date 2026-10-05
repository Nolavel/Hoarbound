class_name HenrySkeletonContract
extends RefCounted

## Semantic bone roles used by future embodied-interaction features.
## The validator is read-only: it never renames/reparents/reimports the rig.

const ROLE_ALIASES: Dictionary = {
	&"root": [&"root", &"Root"],
	&"pelvis": [&"pelvis", &"Pelvis"],
	&"head": [&"Head", &"head"],
	&"left_hand": [&"hand_l", &"Hand_L", &"hand_L"],
	&"right_hand": [&"hand_r", &"Hand_R", &"hand_R"],
	&"left_foot": [&"foot_l", &"Foot_L", &"foot_L"],
	&"right_foot": [&"foot_r", &"Foot_R", &"foot_R"],
}


static func resolve_bone(skeleton: Skeleton3D, role: StringName) -> int:
	if skeleton == null or not ROLE_ALIASES.has(role):
		return -1
	for alias: StringName in ROLE_ALIASES[role]:
		var index: int = skeleton.find_bone(alias)
		if index >= 0:
			return index
	return -1


static func validate(skeleton: Skeleton3D) -> PackedStringArray:
	var missing := PackedStringArray()
	if skeleton == null:
		missing.append("skeleton")
		return missing
	for role: StringName in ROLE_ALIASES:
		if resolve_bone(skeleton, role) < 0:
			missing.append(String(role))
	return missing


static func describe(skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in ROLE_ALIASES:
		var index: int = resolve_bone(skeleton, role)
		result[String(role)] = skeleton.get_bone_name(index) if skeleton != null and index >= 0 else "MISSING"
	return result

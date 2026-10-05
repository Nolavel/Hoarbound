@tool
class_name EmbodiedTarget3D
extends Marker3D

## Small authoring primitive shared by future embodied interactions.
## It deliberately owns no detection, registry, animation or gameplay state.

enum Role {
	BODY,
	LEFT_HAND,
	RIGHT_HAND,
	LEFT_FOOT,
	RIGHT_FOOT,
	EXIT,
	ITEM_PLACEMENT,
}

@export var role: Role = Role.BODY
@export var target_id: StringName = &""
@export_multiline var authoring_note: String = ""


func get_target_transform() -> Transform3D:
	return global_transform


func matches_role(wanted_role: Role) -> bool:
	return role == wanted_role

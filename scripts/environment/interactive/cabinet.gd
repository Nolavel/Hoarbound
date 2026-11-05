class_name Cabinet
extends InteractiveArea

## A cabinet whose door swings on its hinge. The cabinet owns the door state;
## Henry's clip is requested through player_animation_action.

## Emitted when the door starts to swing, true when it opens.
signal door_toggled(open: bool)

const OPEN_KEY: String = "CABINET_OPEN"
const CLOSE_KEY: String = "CABINET_CLOSE"

@export_group("Door")
## Pivot on the hinge side; the door panel is its child.
@export var door_hinge: Node3D
## Yaw of the hinge when fully open.
@export var open_angle_deg: float = -105.0
## Wait before the door moves, so it swings as Henry's hand reaches it.
@export_range(0.0, 1.5, 0.05) var hand_delay: float = 0.45
@export_range(0.1, 2.0, 0.05) var swing_time: float = 0.55

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"chest_open"
	super()
	_update_prompt()


func is_open() -> bool:
	return _open


## Open, it is aimed at on its swung-open leaf, so aiming into the shelves offers what is inside instead
## (ContainerSearch: F searches, F on the leaf shuts it).
func get_focus_point(observer: Vector3) -> Vector3:
	if _open and door_hinge != null:
		var leaf := door_hinge.find_children("*", "MeshInstance3D", true, false)
		if not leaf.is_empty():
			var mesh := leaf[0] as MeshInstance3D
			return mesh.global_transform * mesh.get_aabb().get_center()
	return super(observer)


## Refuses while the door is still swinging, so repeated presses stay sane.
func can_interact() -> bool:
	return super() and door_hinge != null and not is_swinging()


func is_swinging() -> bool:
	return _tween != null and _tween.is_running()


func _on_interaction_performed() -> void:
	_open = not _open
	var target: float = deg_to_rad(open_angle_deg) if _open else 0.0
	_tween = create_tween()
	_tween.tween_interval(hand_delay)
	_tween.tween_property(door_hinge, ^"rotation:y", target, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN_OUT)
	_tween.finished.connect(_update_prompt)
	door_toggled.emit(_open)


func _update_prompt() -> void:
	set_item_name(tr(CLOSE_KEY if _open else OPEN_KEY))
	set_description("")

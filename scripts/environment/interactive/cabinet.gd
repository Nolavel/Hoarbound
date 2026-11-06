class_name Cabinet
extends InteractiveArea

## A cabinet whose door (or a chest's lid) swings on its hinge. The cabinet owns the door state;
## Henry's clip is requested through player_animation_action.

## Emitted when the door starts to swing, true when it opens.
signal door_toggled(open: bool)

const OPEN_KEY: String = "CABINET_OPEN"
const CLOSE_KEY: String = "CABINET_CLOSE"

@export_group("Door")
## Pivot on the hinge side; the door panel is its child.
@export var door_hinge: Node3D
## Angle of the hinge when fully open, about swing_axis (the hinge's own space).
@export var open_angle_deg: float = -105.0
## The hinge's axis: up for a door, right (X) for a chest's lid.
@export var swing_axis: Vector3 = Vector3.UP
## A side-hinged door swings this far (same way as open_angle_deg) to make room for the pack set down beside it.
@export var wide_angle_deg: float = 165.0
## Prompt keys while shut and while open (a chest says so).
@export var open_key: String = OPEN_KEY
@export var close_key: String = CLOSE_KEY
## Wait before the door moves, so it swings as Henry's hand reaches it.
@export_range(0.0, 1.5, 0.05) var hand_delay: float = 0.45
@export_range(0.1, 2.0, 0.05) var swing_time: float = 0.55

var _open: bool = false
var _wide: bool = false
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


## Open, it is put at wide_angle_deg at once (at a hard cut of the view, so no swing shows).
func open_wide() -> void:
	if not _open or door_hinge == null:
		return
	if _tween != null:
		_tween.kill()
	_wide = true
	door_hinge.rotation = swing_axis.normalized() * deg_to_rad(signf(open_angle_deg) * absf(wide_angle_deg))


## From wide, it swings back to its usual open angle.
func end_wide() -> void:
	if not _wide or door_hinge == null:
		return
	_wide = false
	if not _open:
		return
	_tween = create_tween()
	_tween.tween_property(door_hinge, ^"rotation", swing_axis.normalized() * deg_to_rad(open_angle_deg), swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_interaction_performed() -> void:
	_open = not _open
	_wide = false
	if _tween != null:
		_tween.kill()
	var target: Vector3 = swing_axis.normalized() * deg_to_rad(open_angle_deg) if _open else Vector3.ZERO
	_tween = create_tween()
	_tween.tween_interval(hand_delay)
	_tween.tween_property(door_hinge, ^"rotation", target, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN_OUT)
	_tween.finished.connect(_update_prompt)
	door_toggled.emit(_open)


func _update_prompt() -> void:
	set_item_name(tr(close_key if _open else open_key))
	set_description("")

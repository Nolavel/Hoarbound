class_name ContainerSearch
extends InteractiveArea

## "Search" on an open container that holds something (owner's design): the pickup marker with an eye in its
## ring, at the middle of the open face, within reach. F searches where Henry stands (visit_container).

const EYE: Texture2D = preload("res://assets/ui/hud/pickup_marker/eye.svg")
## The marker stands this far out of the shelves' open face, so the view to it never clips the furniture; it is
## offered only with Henry within REACH_M of it (flat): he walks up himself, F searches where he stands, metres.
const OUT_M: float = 0.06
const REACH_M: float = 1.4

var container: ItemContainer


func _init() -> void:
	name = "Search"
	marker_icon = EYE
	interaction_type = InteractionType.OTHER
	auto_detect_ground = false
	monitoring = false
	monitorable = false


func get_interaction_channel() -> InteractionChannel:
	return InteractionChannel.PICKUP


## Offered while the door is open, something is inside and Henry is not already at it.
func can_interact() -> bool:
	if container == null or not container.is_reachable() or container.items.is_empty():
		return false
	var hub: PlayerHubComponent = _hub()
	if hub != null and hub.is_open():
		return false
	var body := hub.get_parent() as Node3D if hub != null else null
	if body == null:
		return true
	var to: Vector3 = get_focus_point(body.global_position) - body.global_position
	return Vector2(to.x, to.z).length() <= REACH_M


## The middle of the open face: the front for a cupboard, the top for a drawer or a chest.
func get_focus_point(_observer: Vector3) -> Vector3:
	if container.opens_up:
		var box: AABB = container.shelves_box()
		return container.global_transform * Vector3(box.get_center().x, box.end.y + OUT_M, box.get_center().z)
	var face: Array = container.front()
	return (face[0] as Vector3) + (face[1] as Vector3) * OUT_M


func _on_interaction_performed() -> void:
	var hub: PlayerHubComponent = _hub()
	if hub != null:
		hub.visit_container(container)


func _hub() -> PlayerHubComponent:
	var player := get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	return player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null

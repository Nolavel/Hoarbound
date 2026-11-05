class_name ContainerSearch
extends InteractiveArea

## "Search" on an open container that holds something (owner's design): the pickup marker with an eye over
## its F, at the middle of the shelves' open face. F starts the visit (PlayerHubComponent.visit_container).

const EYE: Texture2D = preload("res://assets/ui/hud/pickup_marker/eye.svg")
## The marker stands this far out of the shelves' face, so the view to it never clips the furniture, metres.
const OUT_M: float = 0.06

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
	return hub == null or not (hub.is_open() or hub.is_visiting())


func get_focus_point(_observer: Vector3) -> Vector3:
	var face: Array = container.front()
	return (face[0] as Vector3) + (face[1] as Vector3) * OUT_M


func _on_interaction_performed() -> void:
	var hub: PlayerHubComponent = _hub()
	if hub != null:
		hub.visit_container(container)


func _hub() -> PlayerHubComponent:
	var player := get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	return player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null

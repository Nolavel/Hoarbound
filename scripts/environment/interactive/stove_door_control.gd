class_name StoveDoorControl
extends InteractiveArea

## The stove door as an aim target: F on it starts the same stove ritual as the firebox.
var feed: HeatSourceFeed


func can_interact() -> bool:
	return is_instance_valid(feed) and feed.can_interact()


func _on_interaction_performed() -> void:
	if feed != null:
		feed._on_interaction_performed()


func _get_interaction_text() -> String:
	if feed == null:
		return ""
	set_description(feed.get_status_text())
	return feed._get_interaction_text()


func accepts_focus(from: Vector3, direction: Vector3) -> bool:
	return is_aim_on_door(from, direction)


## While Henry works the stove the firebox keeps F, so the door hands focus back.
func resolve_focus(_from: Vector3, _direction: Vector3) -> InteractiveArea:
	if is_instance_valid(feed) and (feed.session_active or feed.is_acting()):
		return feed
	return self


func is_aim_on_door(from: Vector3, direction: Vector3) -> bool:
	return is_finite(get_aim_distance(from, direction))


func get_aim_distance(from: Vector3, direction: Vector3) -> float:
	var local_from: Vector3 = to_local(from)
	var local_direction: Vector3 = global_basis.inverse() * direction
	if absf(local_direction.x) < 0.0001:
		return INF
	var distance: float = -local_from.x / local_direction.x
	var hit: Vector3 = local_from + local_direction * distance
	if distance < 0.0 or absf(hit.y) > StoveVisual.DOOR_H * 0.5 or absf(hit.z) > StoveVisual.DOOR_W * 0.5:
		return INF
	return distance


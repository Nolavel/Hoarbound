class_name ThrownItem
extends RigidBody3D

## An item in flight after a throw. At first contact it strikes the target through
## ThrowImpactCapability; snow bursts and is gone, anything else comes to rest as a pickup.

signal impacted(item_id: StringName, point: Vector3, normal: Vector3, collider: Object, impulse: float)

const SNOW_ITEMS: Array[StringName] = [&"snow_handful"]
const RADIUS_M: float = 0.04
## Below this speed a resting item stops being physics and becomes a pickup again, m/s.
const REST_SPEED: float = 0.15
const REST_SECONDS: float = 0.6
## Gives up waiting for rest after this long in flight or rolling.
const MAX_FLIGHT_SECONDS: float = 12.0
## Linear damping once down: snow and grit stop a rolling stone that free flight must not slow.
const GROUND_DAMP: float = 2.5

var item_id: StringName = &""
var _struck: bool = false
## Fastest of the last few steps: contacts report a step late, after the bounce has slowed it.
var _recent_speeds: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _rest_s: float = 0.0
var _age_s: float = 0.0


## Spawns item_id at from with velocity under parent, ignoring the thrower's own body.
static func launch(id: StringName, from: Vector3, velocity: Vector3, thrower: PhysicsBody3D, parent: Node) -> ThrownItem:
	var body := ThrownItem.new()
	body.item_id = id
	var item: ItemResource = ItemCatalog.get_item(id)
	body.mass = maxf(item.weight if item != null else 0.2, 0.05)
	parent.add_child(body)
	body.global_position = from
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	if thrower != null:
		body.add_collision_exception_with(thrower)
	return body


func _init() -> void:
	name = "ThrownItem"
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0  # the aim arc is a plain parabola; the flight must match it
	angular_damp = 1.0
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS_M
	collision.shape = sphere
	add_child(collision)


func _ready() -> void:
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	visual.position = Vector3.DOWN * RADIUS_M
	add_child(visual)


func is_snow() -> bool:
	return item_id in SNOW_ITEMS


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _struck and state.get_contact_count() > 0:
		_strike(state)
	_recent_speeds.remove_at(0)
	_recent_speeds.append(state.linear_velocity.length())


func _physics_process(delta: float) -> void:
	_age_s += delta
	if not _struck and _age_s < MAX_FLIGHT_SECONDS:
		return
	_rest_s = _rest_s + delta if linear_velocity.length() < REST_SPEED else 0.0
	if _rest_s >= REST_SECONDS or _age_s >= MAX_FLIGHT_SECONDS:
		_settle()


func _strike(state: PhysicsDirectBodyState3D) -> void:
	_struck = true
	var point: Vector3 = state.get_contact_collider_position(0)
	var normal: Vector3 = state.get_contact_local_normal(0)
	var collider: Object = state.get_contact_collider_object(0)
	var impulse: float = mass * maxf(_recent_speeds[0], maxf(_recent_speeds[1], _recent_speeds[2]))
	var target: Object = _impact_target(collider)
	if not ThrowImpactCapability.hit(target, item_id, point, normal, impulse, collider) and is_inside_tree():
		for sink: Node in get_tree().get_nodes_in_group(ThrowImpactCapability.WORLD_GROUP):
			if ThrowImpactCapability.hit(sink, item_id, point, normal, impulse, collider):
				break
	impacted.emit(item_id, point, normal, collider, impulse)
	linear_damp = GROUND_DAMP
	if is_snow():
		call_deferred(&"queue_free")


## The collider or the nearest ancestor that takes throw hits (a pane's body sits under the window).
func _impact_target(collider: Object) -> Object:
	var node := collider as Node
	for _i: int in range(3):
		if node == null:
			break
		if CapabilityContract.has(node, ThrowImpactCapability.ID):
			return node
		node = node.get_parent()
	return collider


## At rest: hand the item back to the world as a pickup where it lies.
func _settle() -> void:
	set_physics_process(false)
	if not is_snow():
		var pickup := ItemPickup.new()
		pickup.item_id = item_id
		pickup.count = 1
		pickup.world_id = StringName("thrown:%s:%d:%d" % [item_id, Time.get_ticks_msec(), get_instance_id()])
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3
		collision.shape = shape
		pickup.add_child(collision)
		get_parent().add_child(pickup)
		pickup.global_position = global_position + Vector3.DOWN * RADIUS_M
	queue_free()

class_name ThrowComponent
extends Node

## Hold RMB with a throwable in hand (snow, a stone) to aim: a dotted arc shows the flight with
## a slight hand sway. LMB while aiming throws it on the overhand clip's release.

signal aim_changed(aiming: bool)
signal thrown(item_id: StringName, body: ThrownItem)

const AIM_ACTION: StringName = &"present_held"
const THROW_ACTION: StringName = &"fire"
const THROW_CLIP: StringName = &"throw"
## The hand lets go this far into the throw action (traced on Henry: the whip forward starts at 0.28 s).
const RELEASE_SECONDS: float = 0.29
const GRAVITY: float = 9.8
## The camera's aim ray reaches this far for a target point, metres.
const MAX_AIM_M: float = 40.0
## Slow hand sway on the aim while held, degrees and Hz; a little more at the release.
const SWAY_DEG: float = 1.2
const SWAY_HZ: float = 0.5
const RELEASE_JITTER_DEG: float = 0.8
const ARC_DOTS: int = 36
const ARC_STEP_S: float = 0.035
const ARC_DOT_M: float = 0.035

@export var held: HeldItemComponent
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent

var _aiming: bool = false
var _throwing: bool = false
var _sway_s: float = 0.0
var _noise: FastNoiseLite
var _velocity: Vector3 = Vector3.ZERO
## Where the drawn arc lands now; the throw is solved to it again from the hand at the release.
var _aim_point: Vector3 = Vector3.ZERO
var _arc: MultiMeshInstance3D
var _marker: MeshInstance3D


func _ready() -> void:
	var body: Node = get_parent()
	if held == null:
		held = body.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	_noise = FastNoiseLite.new()
	_noise.frequency = 1.0
	_noise.seed = 4217
	_build_arc()


## Launch speed of the item now in hand, 0 when it cannot be thrown.
func held_throw_speed() -> float:
	if held == null or not held.is_holding():
		return 0.0
	var item: ItemResource = ItemCatalog.get_item(held.get_item_id())
	return item.throw_speed_mps if item != null else 0.0


func is_aiming() -> bool:
	return _aiming


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _throwing:
		return
	if event.is_action_pressed(AIM_ACTION) and held_throw_speed() > 0.0:
		_set_aiming(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(AIM_ACTION) and _aiming:
		_set_aiming(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(THROW_ACTION) and _aiming:
		get_viewport().set_input_as_handled()
		throw_now()


func _process(delta: float) -> void:
	if not _aiming:
		return
	if held_throw_speed() <= 0.0:
		_set_aiming(false)
		return
	_sway_s += delta
	_velocity = aim_velocity()
	var body := get_parent() as Node3D
	if body != null and body.has_method(&"face_work_target"):
		body.call(&"face_work_target", body.global_position + Vector3(_velocity.x, 0.0, _velocity.z))
	_draw_arc(_release_point(), _velocity)


## Velocity the item would leave the hand with now: aimed at the camera's target, swayed.
func aim_velocity() -> Vector3:
	var speed: float = held_throw_speed()
	var from: Vector3 = _release_point()
	var direction: Vector3 = launch_direction(from, _aim_target(from), speed, GRAVITY)
	return _sway(direction, SWAY_DEG) * speed


## Starts the overhand throw; the item leaves the hand at the clip's release.
func throw_now() -> bool:
	var speed: float = held_throw_speed()
	if speed <= 0.0 or _throwing:
		return false
	_throwing = true
	var velocity: Vector3 = aim_velocity()
	var aim_point: Vector3 = _aim_point if _aiming else _release_point() + velocity
	_set_aiming(false)
	var body: Node = get_parent()
	if body.has_method(&"play_action_animation"):
		body.call(&"play_action_animation", THROW_CLIP)
	if is_inside_tree():
		await get_tree().create_timer(RELEASE_SECONDS).timeout
	## The hand is elsewhere at the release than while aiming: solve again from it to the same point.
	var from: Vector3 = _release_point()
	velocity = launch_direction(from, aim_point, speed, GRAVITY) * speed
	var thrown_body: ThrownItem = release(velocity)
	_throwing = false
	return thrown_body != null


## The hand lets go: the item leaves storage and flies with velocity (plus a little jitter).
func release(velocity: Vector3) -> ThrownItem:
	if held == null or not held.is_holding():
		return null
	var item_id: StringName = held.get_item_id()
	var zone: StringName = held.get_source_zone()
	var from: Vector3 = _release_point()
	held.put_away()
	if HeldOwnership.take(inventory, equipment, item_id, zone).is_empty():
		return null
	var thrower := get_parent() as PhysicsBody3D
	var carried: Vector3 = (thrower.get(&"velocity") as Vector3) * 0.5 if thrower != null else Vector3.ZERO
	var direction: Vector3 = _sway(velocity.normalized(), RELEASE_JITTER_DEG, randf() * 100.0)
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var flying: ThrownItem = ThrownItem.launch(item_id, from, direction * velocity.length() + carried, thrower, world)
	if inventory != null:
		inventory.notify_weight_changed()
	thrown.emit(item_id, flying)
	return flying


## Unit launch direction from from to target at speed: the low arc, or 45 degrees when out of reach.
static func launch_direction(from: Vector3, target: Vector3, speed: float, gravity: float) -> Vector3:
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var dx: float = flat.length()
	var dy: float = target.y - from.y
	if dx < 0.01:
		return Vector3.UP if dy > 0.0 else Vector3.DOWN
	var across: Vector3 = flat / dx
	var v2: float = speed * speed
	var root_term: float = v2 * v2 - gravity * (gravity * dx * dx + 2.0 * dy * v2)
	var angle: float = PI * 0.25 if root_term < 0.0 else atan((v2 - sqrt(root_term)) / (gravity * dx))
	return (across * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _set_aiming(on: bool) -> void:
	if _aiming == on:
		return
	_aiming = on
	_arc.visible = on
	_marker.visible = on
	aim_changed.emit(on)


func _release_point() -> Vector3:
	var prop: Node3D = held.get_held_prop() if held != null else null
	if prop != null:
		return prop.global_position
	var body := get_parent() as Node3D
	return body.global_position + Vector3.UP * 1.5 if body != null else Vector3.ZERO


## Where the camera's centre ray lands within MAX_AIM_M (its far end over open sky).
func _aim_target(from: Vector3) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var body := get_parent() as Node3D
	if camera == null:
		var ahead: Vector3 = -body.global_basis.z if body != null else Vector3.FORWARD
		return from + ahead * 15.0
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * MAX_AIM_M)
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else origin + forward * MAX_AIM_M


## direction turned by up to max_deg of slow noise sway (yaw and pitch apart).
func _sway(direction: Vector3, max_deg: float, offset: float = 0.0) -> Vector3:
	var t: float = _sway_s * SWAY_HZ + offset
	var yaw: float = deg_to_rad(max_deg) * _noise.get_noise_1d(t)
	var pitch: float = deg_to_rad(max_deg) * _noise.get_noise_1d(t + 57.0)
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	return direction.rotated(Vector3.UP, yaw).rotated(side, pitch).normalized()


func _build_arc() -> void:
	var dot := SphereMesh.new()
	dot.radius = ARC_DOT_M * 0.5
	dot.height = ARC_DOT_M
	dot.radial_segments = 6
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	dot.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = dot
	multimesh.instance_count = ARC_DOTS
	_arc = MultiMeshInstance3D.new()
	_arc.name = "ThrowArc"
	_arc.multimesh = multimesh
	_arc.top_level = true
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc.visible = false
	add_child(_arc)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.2
	var ring_material := material.duplicate() as StandardMaterial3D
	ring_material.vertex_color_use_as_albedo = false
	ring_material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	ring.material = ring_material
	_marker = MeshInstance3D.new()
	_marker.name = "ThrowLanding"
	_marker.mesh = ring
	_marker.top_level = true
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


## Steps the parabola from from with velocity until it meets the world; dots fade along it.
func _draw_arc(from: Vector3, velocity: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = (get_parent() as Node3D).get_world_3d().direct_space_state
	var body := get_parent() as CollisionObject3D
	var position: Vector3 = from
	var v: Vector3 = velocity
	var shown: int = 0
	var landed: bool = false
	_aim_point = from + velocity * ARC_STEP_S * ARC_DOTS
	for i: int in range(ARC_DOTS):
		var next: Vector3 = position + v * ARC_STEP_S
		v.y -= GRAVITY * ARC_STEP_S
		var query := PhysicsRayQueryParameters3D.create(position, next)
		if body != null:
			query.exclude = [body.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit["normal"]
			var reference: Vector3 = Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
			var x_axis: Vector3 = normal.cross(reference).normalized()
			## The ring lies flat on whatever it lands on: its Y axis along the surface normal.
			_marker.global_transform = Transform3D(Basis(x_axis, normal, x_axis.cross(normal)), hit["position"] + normal * 0.02)
			_aim_point = hit["position"]
			landed = true
			break
		position = next
		var fade: float = 1.0 - float(i) / float(ARC_DOTS)
		_arc.multimesh.set_instance_transform(i, Transform3D(Basis(), position))
		_arc.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.25 + 0.6 * fade))
		shown = i + 1
	_arc.multimesh.visible_instance_count = shown
	_marker.visible = landed

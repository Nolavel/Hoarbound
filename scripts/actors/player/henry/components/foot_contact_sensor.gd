class_name FootContactSensor
extends Node

## Watches Henry's animated feet and reports each moment a foot is planted on
## the ground. The honest source for footprints, footstep audio and ice load.

signal foot_planted(
	side: Side, position: Vector3, normal: Vector3, forward: Vector3, speed_mps: float
)

enum Side { LEFT, RIGHT }

const POSE_PROBE_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_pose_probe.gd")
const BONES: Dictionary = {
	Side.LEFT: {"heel": &"foot_l", "ball": &"ball_l", "toe": &"ball_leaf_l"},
	Side.RIGHT: {"heel": &"foot_r", "ball": &"ball_r", "toe": &"ball_leaf_r"},
}

@export_group("Wiring")
@export var body: CharacterBody3D
@export var visual: HenryUALAnimation

@export_group("Contact")
@export var contact_height_m: float = 0.06
@export var lift_height_m: float = 0.09
@export var animated_rearm_rise_m: float = 0.045
@export var min_speed_mps: float = 0.35
@export var probe_depth_m: float = 1.2
## With a contact source, a foot keeps its print until it is this far from it:
## a contact flickering within one stance is the same print, not a new step.
@export var same_print_radius_m: float = 0.1

## Animation that knows its own foot contacts (Motion Matching's database labels)
## replaces the height guess while it drives the pose; it registers itself here.
var contact_source: Object
var _lifted: Dictionary = {Side.LEFT: true, Side.RIGHT: true}
var _print_at: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _bone_index: Dictionary = {}
var _sampled_local_y: Dictionary = {}
var _last_planted_local_y: Dictionary = {}
var _raw_pose_local: Array[Dictionary] = [{}, {}]
var _pose_probe: FootPoseProbe


func _physics_process(_delta: float) -> void:
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null or body == null:
		return
	_ensure_pose_probe(skeleton)
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length()
	var driven: bool = contact_source != null and bool(contact_source.call(&"drives_foot_contacts"))
	for side: int in Side.values():
		var feet: Dictionary = _sample_pre_modifier_pose(skeleton, side)
		if feet.is_empty():
			continue
		var ball: Vector3 = feet["ball"]
		if driven:
			_sampled_local_y[side] = body.to_local(ball).y
		else:
			observe_foot_motion(side, body.to_local(ball).y)
		var contact: Dictionary = _contact_below(feet)
		if contact.is_empty():
			continue
		var normal: Vector3 = contact["normal"]
		var forward: Vector3 = (feet["toe"] as Vector3) - (feet["heel"] as Vector3)
		if driven:
			update_driven_foot(side, bool(contact_source.call(&"is_foot_planted", side)),
				contact["position"], forward, body.is_on_floor(), speed, normal)
			continue
		var height: float = surface_clearance(ball, contact["ball_ground"], normal)
		update_foot(
			side,
			height,
			contact["position"],
			forward,
			body.is_on_floor(),
			speed,
			normal
		)


## Inserts a read-only modifier before Wade/SnowFeet. Godot invokes modifiers
## after AnimationMixer playback, in Skeleton3D child order, so this is the exact
## locomotion pose before snow IK can feed back into the sensor.
func _ensure_pose_probe(skeleton: Skeleton3D) -> void:
	if is_instance_valid(_pose_probe):
		return
	_pose_probe = skeleton.get_node_or_null(^"FootPoseProbe") as FootPoseProbe
	if _pose_probe == null:
		_pose_probe = POSE_PROBE_SCRIPT.new() as FootPoseProbe
		_pose_probe.name = "FootPoseProbe"
		skeleton.add_child(_pose_probe)
		skeleton.move_child(_pose_probe, 0)
	if not _pose_probe.pose_sampled.is_connected(_on_pre_modifier_pose):
		_pose_probe.pose_sampled.connect(_on_pre_modifier_pose)


func _on_pre_modifier_pose(side: int, heel: Vector3, ball: Vector3, toe: Vector3) -> void:
	if side < 0 or side >= _raw_pose_local.size():
		return
	_raw_pose_local[side] = {"heel": heel, "ball": ball, "toe": toe}


func observe_foot_motion(side: int, animated_local_y: float) -> void:
	_sampled_local_y[side] = animated_local_y
	if _lifted[side] or not _last_planted_local_y.has(side):
		return
	if animated_local_y - float(_last_planted_local_y[side]) >= animated_rearm_rise_m:
		_lifted[side] = true


func surface_clearance(point: Vector3, ground_point: Vector3, ground_normal: Vector3) -> float:
	var normal: Vector3 = (
		ground_normal.normalized()
		if ground_normal.length_squared() > 0.0001
		else Vector3.UP
	)
	return maxf((point - ground_point).dot(normal), 0.0)


## Resolve heel/ball/toe probes into one contact plane. Averaging the valid probe
## normals makes the footprint follow sloped/crowned streets instead of global UP.
static func resolve_contact_from_hits(feet: Dictionary, hits: Dictionary) -> Dictionary:
	if feet.is_empty() or hits.is_empty():
		return {}
	var normal_sum := Vector3.ZERO
	var point_sum := Vector3.ZERO
	var valid: int = 0
	for key: String in ["heel", "ball", "toe"]:
		if not hits.has(key):
			continue
		var hit: Dictionary = hits[key]
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.length_squared() <= 0.0001:
			normal = Vector3.UP
		normal_sum += normal.normalized()
		point_sum += hit["position"] as Vector3
		valid += 1
	if valid == 0:
		return {}
	var normal: Vector3 = normal_sum.normalized()
	if normal.length_squared() <= 0.0001:
		normal = Vector3.UP
	var anchor: Vector3 = point_sum / float(valid)
	if hits.has("ball") and not (hits["ball"] as Dictionary).is_empty():
		anchor = hits["ball"]["position"] as Vector3
	var centre: Vector3 = ((feet["heel"] as Vector3) + (feet["toe"] as Vector3)) * 0.5
	centre -= normal * (centre - anchor).dot(normal)
	var ball: Vector3 = feet["ball"]
	var ball_ground: Vector3
	if hits.has("ball") and not (hits["ball"] as Dictionary).is_empty():
		ball_ground = hits["ball"]["position"] as Vector3
	else:
		ball_ground = ball - normal * (ball - anchor).dot(normal)
	return {"position": centre, "normal": normal, "ball_ground": ball_ground}


func update_foot(
	side: int, height_m: float, ground_point: Vector3, forward: Vector3,
	on_floor: bool, speed_mps: float, ground_normal: Vector3 = Vector3.UP
) -> bool:
	if height_m > lift_height_m:
		_lifted[side] = true
		return false
	if height_m > contact_height_m or not _lifted[side]:
		return false
	if not on_floor or speed_mps < min_speed_mps:
		return false
	_plant(side, ground_point, forward, ground_normal, speed_mps)
	return true


## A contact reported by the animation itself: one plant per contact, the same
## gates and event as update_foot.
func update_driven_foot(
	side: int, planted: bool, ground_point: Vector3, forward: Vector3,
	on_floor: bool, speed_mps: float, ground_normal: Vector3 = Vector3.UP
) -> bool:
	var on_print: bool = _print_at[side] != Vector3.INF \
		and Vector2(ground_point.x - _print_at[side].x, ground_point.z - _print_at[side].z).length() <= same_print_radius_m
	if not planted:
		if not on_print:
			_lifted[side] = true
		return false
	if not _lifted[side]:
		return false
	if on_print:
		_lifted[side] = false
		return false
	if not on_floor or speed_mps < min_speed_mps:
		return false
	_plant(side, ground_point, forward, ground_normal, speed_mps)
	return true


func _plant(side: int, ground_point: Vector3, forward: Vector3, ground_normal: Vector3, speed_mps: float) -> void:
	_lifted[side] = false
	_print_at[side] = ground_point
	if _sampled_local_y.has(side):
		_last_planted_local_y[side] = float(_sampled_local_y[side])
	var normal: Vector3 = ground_normal.normalized() if ground_normal.length_squared() > 0.0001 else Vector3.UP
	var along: Vector3 = forward - normal * forward.dot(normal)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD - normal * Vector3.FORWARD.dot(normal)
	foot_planted.emit(side, ground_point, normal, along.normalized(), speed_mps)


func is_planted(side: int) -> bool:
	return not bool(_lifted[side])


func get_foot(side: int) -> Dictionary:
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null:
		return {}
	return _sample_pre_modifier_pose(skeleton, side)


func _skeleton() -> Skeleton3D:
	if visual == null:
		return null
	return visual.skeleton


## Cached probe samples are Skeleton3D-local; applying the current skeleton world
## transform here removes body-translation latency between animation and physics.
func _sample_pre_modifier_pose(skeleton: Skeleton3D, side: int) -> Dictionary:
	if side < 0 or side >= _raw_pose_local.size() or _raw_pose_local[side].is_empty():
		return {}
	var raw: Dictionary = _raw_pose_local[side]
	return {
		"heel": skeleton.global_transform * (raw["heel"] as Vector3),
		"ball": skeleton.global_transform * (raw["ball"] as Vector3),
		"toe": skeleton.global_transform * (raw["toe"] as Vector3),
	}


func _index_of(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _bone_index.has(bone):
		_bone_index[bone] = skeleton.find_bone(bone)
	return _bone_index[bone]


func _contact_below(feet: Dictionary) -> Dictionary:
	var hits: Dictionary = {}
	for key: String in ["heel", "ball", "toe"]:
		var hit: Dictionary = _ground_below(feet[key])
		if not hit.is_empty():
			hits[key] = hit
	return resolve_contact_from_hits(feet, hits)


func _ground_below(point: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.3, point + Vector3.DOWN * probe_depth_m
	)
	query.exclude = [body.get_rid()]
	return space.intersect_ray(query)

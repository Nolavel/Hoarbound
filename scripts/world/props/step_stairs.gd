@tool
class_name StepStairs
extends StaticBody3D

## A flight of stairs Henry can walk: visible steps over one wedge collider. CharacterBody3D has no step-up,
## so the steps never collide; he walks the wedge. Origin: foot of the first riser, climbing along -Z.

## Slope the player's controller still walks as floor, degrees (MovementController.max_floor_angle).
const WALKABLE_DEG: float = 45.0

@export_range(1, 64) var step_count: int = 10:
	set(value):
		step_count = value
		_rebuild()
## Height of one step, metres.
@export_range(0.05, 0.4, 0.005) var riser: float = 0.17:
	set(value):
		riser = value
		_rebuild()
## Depth of one step, metres.
@export_range(0.1, 1.0, 0.005) var tread: float = 0.28:
	set(value):
		tread = value
		_rebuild()
@export_range(0.3, 10.0, 0.05) var width: float = 1.2:
	set(value):
		width = value
		_rebuild()
## Where the walked slope lies on the steps: 0 through their inner corners (feet sink at the nosings),
## 1 through the nosings (feet float over the treads). It starts this share of a tread before the first riser.
@export_range(0.0, 1.0, 0.05) var ramp_lead: float = 0.5:
	set(value):
		ramp_lead = value
		_rebuild()
## Off when the steps are an authored mesh and only the collider is wanted.
@export var build_steps: bool = true:
	set(value):
		build_steps = value
		_rebuild()
@export var step_material: Material:
	set(value):
		step_material = value
		_rebuild()

var _shape_node: CollisionShape3D
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _get_configuration_warnings() -> PackedStringArray:
	if get_slope_deg() > WALKABLE_DEG:
		return ["These steps climb at %.0f degrees; Henry walks up to %.0f." % [get_slope_deg(), WALKABLE_DEG]]
	return []


func get_rise() -> float:
	return riser * float(step_count)


func get_run() -> float:
	return tread * float(step_count)


func get_slope_deg() -> float:
	return rad_to_deg(atan2(riser, tread))


## Local point at the head of the flight, on the top landing's edge.
func get_top() -> Vector3:
	return Vector3(0.0, get_rise(), -get_run())


## The six corners of the walked wedge, local: solid down to the ground so nothing passes under the flight.
func wedge_points() -> PackedVector3Array:
	var half: float = width * 0.5
	var foot_z: float = ramp_lead * tread
	var head_z: float = -(float(step_count) - ramp_lead) * tread
	var rise: float = get_rise()
	var points := PackedVector3Array()
	for x: float in [-half, half]:
		points.append(Vector3(x, 0.0, foot_z))
		points.append(Vector3(x, 0.0, -get_run()))
		points.append(Vector3(x, rise, head_z))
		points.append(Vector3(x, rise, -get_run()))
	return points


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = "Wedge"
		add_child(_shape_node, false, Node.INTERNAL_MODE_BACK)
	var shape := ConvexPolygonShape3D.new()
	shape.points = wedge_points()
	_shape_node.shape = shape
	if _mesh_node == null:
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "Steps"
		add_child(_mesh_node, false, Node.INTERNAL_MODE_BACK)
	_mesh_node.mesh = _steps_mesh() if build_steps else null
	update_configuration_warnings()


## One mesh of step blocks, each standing from the ground to its tread.
func _steps_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for i: int in range(step_count):
		var height: float = riser * float(i + 1)
		box.size = Vector3(width, height, tread)
		tool.append_from(box, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, -tread * (float(i) + 0.5))))
	tool.set_material(step_material)
	return tool.commit()

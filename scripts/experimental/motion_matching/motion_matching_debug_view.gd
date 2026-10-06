class_name MotionMatchingDebugView
extends Node3D

## World-space and HUD readout for the Motion Matching lab. Pure presentation:
## it reads the controller snapshot and never writes back into matching.

const DESIRED_COLOR := Color(0.2, 1.0, 0.35)
const CURRENT_COLOR := Color(0.2, 0.55, 1.0)
const BEST_COLOR := Color(1.0, 0.85, 0.2)
const FACING_COLOR := Color(1.0, 0.5, 0.1)
const SIMULATION_COLOR := Color(0.85, 1.0, 0.85)
const CONTACT_COLOR := Color(1.0, 0.25, 0.6)
const GROUND_LIFT := 0.02
const RIBBON_HALF_WIDTH := 0.035

@export var hud_label: Label

var _mesh: ImmediateMesh
var _material: StandardMaterial3D


func _ready() -> void:
	var instance := MeshInstance3D.new()
	instance.name = "Lines"
	_mesh = ImmediateMesh.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true


func update_view(controller: MotionMatchingDatabasePlaybackController) -> void:
	var database := controller.get_database()
	var skeleton := controller.get_skeleton()
	var model := skeleton.global_transform.orthonormalized()
	var snapshot := controller.get_snapshot()
	var prediction := controller.get_prediction()
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	var root := Vector3(model.origin.x, GROUND_LIFT, model.origin.z)
	var simulation := controller.get_simulation()
	var simulation_root := Vector3(simulation.position.x, GROUND_LIFT, simulation.position.z)
	_disc(simulation_root, 0.05, SIMULATION_COLOR)
	_arrow(simulation_root, simulation.basis() * Vector3.BACK, 0.35, DESIRED_COLOR)
	if not prediction.is_empty():
		var points: Array[Vector3] = [simulation_root]
		for position in prediction["positions"]:
			points.append(Vector3(position.x, GROUND_LIFT, position.z))
		_ribbon(points, DESIRED_COLOR)
		var forwards: PackedVector3Array = prediction["forwards"]
		for index in range(forwards.size()):
			_arrow(points[index + 1], forwards[index], 0.22, DESIRED_COLOR)
	_row_trajectory(database, int(snapshot["current_sample"]), model, CURRENT_COLOR, 0.005)
	var best: Dictionary = snapshot["best"]
	if not best.is_empty() and int(best["sample_index"]) != int(snapshot["current_sample"]):
		_row_trajectory(database, int(best["sample_index"]), model, BEST_COLOR, 0.01)
	_arrow(root, model.basis * Vector3.BACK, 0.5, FACING_COLOR)
	var contacts := int(snapshot["contacts"])
	for side in [["foot_l", 1], ["foot_r", 2]]:
		if contacts & int(side[1]):
			var foot := model * skeleton.get_bone_global_pose(skeleton.find_bone(side[0])).origin
			_disc(Vector3(foot.x, GROUND_LIFT, foot.z), 0.07, CONTACT_COLOR)
	_mesh.surface_end()
	if hud_label != null:
		hud_label.text = _hud_text(database, snapshot)


func _hud_text(database: MotionDatabase, snapshot: Dictionary) -> String:
	var best: Dictionary = snapshot["best"]
	var current_cost: Dictionary = snapshot["current_cost"]
	var lines := PackedStringArray()
	lines.append("MOTION MATCHING  live root-space  |  search %d of %d samples, no role gate" % [int(snapshot["candidate_count"]), database.get_sample_count()])
	lines.append("ROOT  speed %.2f m/s   yaw rate %+.2f rad/s   blend %.2f   anim-sim %.2f m %+.0f deg" % [float(snapshot["root_speed"]), float(snapshot["angular_velocity"]), float(snapshot["blend_alpha"]), float(snapshot["anim_to_simulation_m"]), rad_to_deg(float(snapshot["anim_to_simulation_yaw"]))])
	lines.append("CURRENT  %s @ %.2fs  #%d  [%s]" % [snapshot["current_clip"], float(snapshot["current_time"]), int(snapshot["current_sample"]), snapshot["current_role_metadata"]])
	if not current_cost.is_empty():
		lines.append("         cost %.2f = pose %.2f  vel %.2f  traj %.2f  face %.2f" % [float(current_cost["total_cost"]), float(current_cost["pose_cost"]), float(current_cost["velocity_cost"]), float(current_cost["trajectory_cost"]), float(current_cost["facing_cost"])])
	if not best.is_empty():
		lines.append("BEST     %s @ %.2fs  #%d  [%s]" % [best["clip"], float(best["time"]), int(best["sample_index"]), best["role"]])
		lines.append("         cost %.2f = pose %.2f  vel %.2f  traj %.2f  face %.2f" % [float(best["total_cost"]), float(best["pose_cost"]), float(best["velocity_cost"]), float(best["trajectory_cost"]), float(best["facing_cost"])])
	lines.append("DECISION %s   contacts L%d R%d" % [snapshot["decision"], int(snapshot["contacts"]) & 1, (int(snapshot["contacts"]) >> 1) & 1])
	lines.append("green: simulation path+facing  blue: current frame  yellow: best frame  orange: animated facing  [role] = metadata only")
	return "\n".join(lines)


func _row_trajectory(database: MotionDatabase, sample: int, model: Transform3D, color: Color, lift: float) -> void:
	var row := database.get_feature_row(sample)
	var points: Array[Vector3] = [Vector3(model.origin.x, GROUND_LIFT + lift, model.origin.z)]
	for feature in [21, 23, 25]:
		var world := model * Vector3(row[feature], 0.0, row[feature + 1])
		points.append(Vector3(world.x, GROUND_LIFT + lift, world.z))
	_ribbon(points, color)
	for index in range(3):
		var forward := model.basis * Vector3(row[27 + index * 2], 0.0, row[28 + index * 2])
		_arrow(points[index + 1], forward, 0.16, color)


func _ribbon(points: Array[Vector3], color: Color) -> void:
	for index in range(points.size() - 1):
		var direction := points[index + 1] - points[index]
		if direction.length_squared() < 0.000001:
			continue
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * RIBBON_HALF_WIDTH
		_quad(points[index] - side, points[index] + side, points[index + 1] + side, points[index + 1] - side, color)


func _arrow(origin: Vector3, direction: Vector3, length: float, color: Color) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return
	flat = flat.normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	var tip := origin + flat * length
	_quad(origin - side * 0.015, origin + side * 0.015, tip + side * 0.015, tip - side * 0.015, color)
	_triangle(tip + flat * 0.08, tip + side * 0.05, tip - side * 0.05, color)


func _disc(center: Vector3, radius: float, color: Color) -> void:
	for segment in range(12):
		var a := TAU * float(segment) / 12.0
		var b := TAU * float(segment + 1) / 12.0
		_triangle(center, center + Vector3(cos(a), 0.0, sin(a)) * radius, center + Vector3(cos(b), 0.0, sin(b)) * radius, color)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(a, b, c, color)
	_triangle(a, c, d, color)


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(vertex)

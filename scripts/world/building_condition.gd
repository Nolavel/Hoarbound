class_name BuildingCondition
extends RefCounted

## Shelter readability (#235): what a house's exterior says from the street, derived from its
## condition in data/world/key_west/building_conditions.json, never hand-dressed per house.
## Signs describe the physical state; they never promise a night's shelter.

const TABLE_PATH: String = "res://data/world/key_west/building_conditions.json"
const BURNT_SHADER: Shader = preload("res://shaders/environment/buildings/burnt_wall.gdshader")
const SNOW_SHADER: Shader = preload("res://shaders/environment/snow/snow_prop.gdshader")
const APPLIED_META: StringName = &"building_condition"
## Snowed-in drift: height up the walls (over the door, to the sills) and how far it spreads.
const DRIFT_HEIGHT: float = 1.5
const DRIFT_SPREAD: float = 2.4
## Empty house: a doorless opening on the front and its door torn half open beside it.
const DOOR_SIZE := Vector2(1.0, 2.1)

static var _table: Dictionary = {}
static var _loaded: bool = false


## Applies the conditions of every listed building under `root` (a streamed cluster), once.
static func decorate(root: Node) -> void:
	if root == null:
		return
	var table: Dictionary = _buildings()
	if table.is_empty():
		return
	for node: Node in root.find_children("KW_BUILDING_*", "MeshInstance3D", true, false):
		var entry: Variant = table.get(String(node.name))
		if entry is Dictionary and not node.has_meta(APPLIED_META):
			apply(node as MeshInstance3D, entry)


## The condition named in `entry` ({condition, front: [x, z]}) on one generated building.
static func apply(building: MeshInstance3D, entry: Dictionary) -> void:
	var condition: String = String(entry.get("condition", ""))
	var front_raw: Array = entry.get("front", [0.0, 1.0])
	var front := Vector3(float(front_raw[0]), 0.0, float(front_raw[1])).normalized()
	var hull: PackedVector2Array = footprint(building.mesh)
	var base: float = _base_y(building.mesh)
	match condition:
		"burnt":
			_burnt(building, base)
		"empty":
			_set_surface(building, "windows", _flat(Color(0.025, 0.025, 0.03)))
			_doorway(building, hull, base, front)
		"snowed":
			_drift(building, hull, base)
		_:
			push_warning("BuildingCondition: unknown condition '%s' on %s" % [condition, building.name])
			return
	building.set_meta(APPLIED_META, condition)


## Convex outline of the walls' base, in the building's local plan (x, z), counter-clockwise.
static func footprint(mesh: Mesh) -> PackedVector2Array:
	var base: float = _base_y(mesh)
	var points := PackedVector2Array()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in vertices:
		if v.y < base + 0.3:
			points.append(Vector2(v.x, v.z))
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	if _signed_area(hull) < 0.0:
		hull.reverse()
	return hull


static func _buildings() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		_table = (parsed as Dictionary).get("buildings", {}) if parsed is Dictionary else {}
	return _table


static func _base_y(mesh: Mesh) -> float:
	return mesh.get_aabb().position.y


static func _signed_area(hull: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in range(hull.size()):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## Outward normal of hull edge a -> b in the plan; the hull is counter-clockwise in (x, z).
static func _outward(a: Vector2, b: Vector2) -> Vector2:
	var d: Vector2 = (b - a).normalized()
	return Vector2(d.y, -d.x)


## Fire-gutted: charcoal walls sooted towards the top, black roof, black empty windows.
static func _burnt(building: MeshInstance3D, base: float) -> void:
	var walls := ShaderMaterial.new()
	walls.shader = BURNT_SHADER
	walls.set_shader_parameter(&"base_y", building.global_position.y + base)
	walls.set_shader_parameter(&"wall_height", building.mesh.get_aabb().size.y)
	_set_surface(building, "walls", walls)
	_set_surface(building, "roof", _flat(Color(0.05, 0.045, 0.04)))
	_set_surface(building, "windows", _flat(Color(0.01, 0.01, 0.01)))


## Empty: the front's middle carries a dark doorless opening and the torn door hangs open.
static func _doorway(building: MeshInstance3D, hull: PackedVector2Array, base: float, front: Vector3) -> void:
	var best: int = -1
	var best_dot: float = -2.0
	for i: int in range(hull.size()):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		if a.distance_to(b) < DOOR_SIZE.x * 2.5:
			continue
		var facing: float = _outward(a, b).dot(Vector2(front.x, front.z))
		if facing > best_dot:
			best_dot = facing
			best = i
	if best < 0:
		return
	var a: Vector2 = hull[best]
	var b: Vector2 = hull[(best + 1) % hull.size()]
	var n: Vector2 = _outward(a, b)
	var mid: Vector2 = (a + b) * 0.5 + n * 0.04
	var yaw: float = atan2(n.x, n.y)
	var hole := MeshInstance3D.new()
	hole.name = "Condition_Doorway"
	var quad := QuadMesh.new()
	quad.size = DOOR_SIZE
	hole.mesh = quad
	hole.material_override = _flat(Color(0.015, 0.015, 0.018))
	hole.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, base + DOOR_SIZE.y * 0.5, mid.y))
	building.add_child(hole)
	## The door, torn off its top hinge, leans open against the wall beside the opening.
	var along: Vector2 = (b - a).normalized()
	var door := MeshInstance3D.new()
	door.name = "Condition_TornDoor"
	var slab := BoxMesh.new()
	slab.size = Vector3(DOOR_SIZE.x * 0.9, DOOR_SIZE.y * 0.95, 0.05)
	door.mesh = slab
	door.material_override = _flat(Color(0.30, 0.22, 0.15))
	var hinge: Vector2 = mid + along * DOOR_SIZE.x * 0.5
	var open_yaw: float = yaw - deg_to_rad(110.0)
	var basis := Basis(Vector3.UP, open_yaw) * Basis(Vector3.FORWARD, deg_to_rad(6.0))
	var centre: Vector3 = Vector3(hinge.x, base + slab.size.y * 0.5, hinge.y) + basis * Vector3(slab.size.x * 0.5, 0.0, 0.0)
	door.transform = Transform3D(basis, centre)
	building.add_child(door)


## Snowed in: a drift wraps the walls up to DRIFT_HEIGHT and spreads DRIFT_SPREAD out.
static func _drift(building: MeshInstance3D, hull: PackedVector2Array, base: float) -> void:
	if hull.size() < 3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = hull.size()
	for i: int in range(count):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % count]
		var n: Vector2 = _outward(a, b)
		var top_a := Vector3(a.x + n.x * 0.03, base + DRIFT_HEIGHT, a.y + n.y * 0.03)
		var top_b := Vector3(b.x + n.x * 0.03, base + DRIFT_HEIGHT, b.y + n.y * 0.03)
		var low_a := Vector3(a.x + n.x * DRIFT_SPREAD, base - 0.1, a.y + n.y * DRIFT_SPREAD)
		var low_b := Vector3(b.x + n.x * DRIFT_SPREAD, base - 0.1, b.y + n.y * DRIFT_SPREAD)
		_quad(st, top_a, top_b, low_b, low_a)
		## Round the corner to the next edge's foot.
		var c: Vector2 = hull[(i + 2) % count]
		var n2: Vector2 = _outward(b, c)
		var low_next := Vector3(b.x + n2.x * DRIFT_SPREAD, base - 0.1, b.y + n2.y * DRIFT_SPREAD)
		_tri(st, top_b, low_next, low_b)
	st.generate_normals()
	var drift := MeshInstance3D.new()
	drift.name = "Condition_SnowDrift"
	drift.mesh = st.commit()
	var snow := ShaderMaterial.new()
	snow.shader = SNOW_SHADER
	snow.set_shader_parameter(&"base_color", Color(0.90, 0.92, 0.95))
	drift.material_override = snow
	building.add_child(drift)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## One triangle, wound so its normal faces outward and up.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y < 0.0:
		var t: Vector3 = b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _set_surface(building: MeshInstance3D, surface_name: String, material: Material) -> void:
	var slots: Array = building.get_meta("material_slots", [])
	var index: int = slots.find(surface_name)
	if index >= 0 and index < building.mesh.get_surface_count():
		building.set_surface_override_material(index, material)


static func _flat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	return mat

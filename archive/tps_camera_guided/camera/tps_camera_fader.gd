class_name TpsCameraFader
extends RefCounted

## Presentation only: thin occluders between camera and Henry turn see-through,
## and Henry dithers out while the camera is inside his reach. Never moves the camera.

## How see-through a thin occluder gets, 0..1.
var occluder_transparency: float = 0.7
## Meshes wider than this in their middle axis are never faded: a building
## must not vanish because a pipe on it crossed the view.
var max_visual_extent: float = 1.5
var fade_in_time: float = 0.12
var fade_out_time: float = 0.35
## Meshes without the stylized shader blend as a whole, so they never go further.
var body_fallback_max: float = 0.7

## Faded occluder visuals by instance id: [GeometryInstance3D, amount, own transparency].
var _faded: Dictionary = {}
var _body_root: Node
var _body_layers: int = 0
var _body: Array[GeometryInstance3D] = []
var _body_amount: float = 0.0
var _body_refresh: float = 0.0


## Eases the visuals of these colliders toward see-through and the rest back.
func update_occluders(colliders: Array, delta: float) -> void:
	var wanted: Dictionary = {}
	for collider: Variant in colliders:
		if collider is Node:
			for geo: GeometryInstance3D in _visuals_of(collider as Node):
				if _middle_extent(geo) <= max_visual_extent:
					wanted[geo.get_instance_id()] = geo
	for id: int in wanted:
		if not _faded.has(id):
			var geo: GeometryInstance3D = wanted[id]
			_faded[id] = [geo, 0.0, geo.transparency]
	for id: int in _faded.keys():
		var entry: Array = _faded[id]
		var geo: GeometryInstance3D = entry[0]
		if not is_instance_valid(geo):
			_faded.erase(id)
			continue
		var target: float = occluder_transparency if wanted.has(id) else 0.0
		var time: float = fade_in_time if target > float(entry[1]) else fade_out_time
		entry[1] = move_toward(float(entry[1]), target, occluder_transparency * delta / time)
		geo.transparency = maxf(float(entry[2]), float(entry[1]))
		if float(entry[1]) <= 0.0 and target <= 0.0:
			geo.transparency = float(entry[2])
			_faded.erase(id)


## How many occluder visuals are faded at all right now.
func get_faded_count() -> int:
	return _faded.size()


## Henry's visuals are the geometry under `root` drawn on `layers`.
func set_body(root: Node, layers: int) -> void:
	_body_root = root
	_body_layers = layers
	_body.clear()


## 0 shows Henry, 1 removes him; stylized materials dither, others blend.
func update_body(amount: float, delta: float) -> void:
	_body_refresh -= delta
	if is_equal_approx(amount, _body_amount) and _body_refresh > 0.0:
		return
	if _body.is_empty() or _body_refresh <= 0.0:
		_collect_body()
		_body_refresh = 1.0
	for geo: GeometryInstance3D in _body:
		if is_instance_valid(geo):
			_apply_body(geo, amount)
	_body_amount = amount


func get_body_fade() -> float:
	return _body_amount


func _collect_body() -> void:
	_body.clear()
	if not is_instance_valid(_body_root):
		return
	for node: Node in _body_root.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if geo.layers & _body_layers:
			_body.append(geo)


func _apply_body(geo: GeometryInstance3D, amount: float) -> void:
	if _is_stylized(geo):
		geo.set_instance_shader_parameter(&"camera_fade", amount)
	else:
		geo.transparency = minf(amount, body_fallback_max)


static func _is_stylized(geo: GeometryInstance3D) -> bool:
	var material: Material = geo.material_override
	var mesh_instance := geo as MeshInstance3D
	if material == null and mesh_instance != null and mesh_instance.get_surface_override_material_count() > 0:
		material = mesh_instance.get_active_material(0)
	var shader_material := material as ShaderMaterial
	return shader_material != null and (shader_material.shader == StylizedEnvironmentMaterial.OPAQUE_SHADER
		or shader_material.shader == StylizedEnvironmentMaterial.DOUBLE_SIDED_SHADER)


static func _middle_extent(geo: GeometryInstance3D) -> float:
	var size: Vector3 = geo.get_aabb().size * geo.global_basis.get_scale().abs()
	var sorted: Array[float] = [size.x, size.y, size.z]
	sorted.sort()
	return sorted[1]


## The collider's own meshes, and the mesh it hangs under when it is one.
static func _visuals_of(collider: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	for node: Node in collider.find_children("*", "GeometryInstance3D", true, false):
		found.append(node as GeometryInstance3D)
	var parent := collider.get_parent() as GeometryInstance3D
	if parent != null:
		found.append(parent)
	return found

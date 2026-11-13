class_name SceneParity
extends RefCounted

## Snapshot of what a node tree draws, independent of node names, for moving code-built
## trees into authored scenes: snapshot the old build, then diff the new scene against it.

const POSITION_EPS: float = 0.0005
const VALUE_EPS: float = 0.001


## One entry per visual descendant: type, transform relative to root, mesh, material, text.
static func snapshot(root: Node3D) -> Array:
	var entries: Array = []
	for node: Node in root.find_children("*", "", true, false):
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var entry: Dictionary = {"type": visual.get_class(), "xform": _xform(root.global_transform.affine_inverse() * visual.global_transform)}
		if visual is GeometryInstance3D:
			entry["cast_shadow"] = int((visual as GeometryInstance3D).cast_shadow)
		if visual is MeshInstance3D:
			var mesh: Mesh = (visual as MeshInstance3D).mesh
			entry["mesh"] = _resource(mesh)
			if mesh is PrimitiveMesh:
				entry["material"] = _resource((mesh as PrimitiveMesh).material)
		if visual is Label3D:
			var label := visual as Label3D
			entry["text"] = label.text
			entry["label"] = [label.font_size, label.pixel_size, label.outline_size, _color(label.modulate), int(label.horizontal_alignment),
				label.font.resource_path if label.font != null else ""]
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _key(a) < _key(b))
	return entries


## Human-readable differences; empty means the two trees draw the same thing.
static func diff(expected: Array, actual: Array) -> Array[String]:
	actual = JSON.parse_string(JSON.stringify(actual))
	var problems: Array[String] = []
	if expected.size() != actual.size():
		problems.append("visual count %d, expected %d" % [actual.size(), expected.size()])
	var unmatched: Array = actual.duplicate()
	for want: Dictionary in expected:
		var found: int = -1
		for i: int in range(unmatched.size()):
			if _same(want, unmatched[i]):
				found = i
				break
		if found < 0:
			problems.append("missing: %s" % JSON.stringify(want))
		else:
			unmatched.remove_at(found)
	for extra: Dictionary in unmatched:
		problems.append("extra: %s" % JSON.stringify(extra))
	return problems


static func save(entries: Array, path: String) -> void:
	var lines: PackedStringArray = []
	for entry: Variant in entries:
		lines.append("\t" + JSON.stringify(entry))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[\n" + ",\n".join(lines) + "\n]\n")


static func load_file(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key: Variant in a:
			if not (b as Dictionary).has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i: int in range((a as Array).size()):
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= VALUE_EPS
	return a == b


static func _key(entry: Dictionary) -> String:
	var x: Array = entry["xform"]
	return "%s|%.3f|%.3f|%.3f|%s" % [entry["type"], x[9], x[10], x[11], entry.get("text", "")]


static func _xform(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _color(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


## Class plus the stored properties that change what is drawn, scripts and paths excluded.
static func _resource(resource: Resource) -> Variant:
	if resource == null:
		return null
	var out: Dictionary = {"class": resource.get_class()}
	if resource is Mesh and not resource is PrimitiveMesh:
		return _mesh_digest(resource as Mesh)
	if resource is ShaderMaterial:
		var shader_material := resource as ShaderMaterial
		out["shader"] = shader_material.shader.resource_path if shader_material.shader != null else ""
		var params: Dictionary = {}
		for uniform: Dictionary in shader_material.shader.get_shader_uniform_list() if shader_material.shader != null else []:
			params[uniform["name"]] = _plain(shader_material.get_shader_parameter(uniform["name"]))
		out["params"] = params
		return out
	## Only what differs from a fresh instance, so a fixture lists what was actually set.
	var fresh: Object = ClassDB.instantiate(resource.get_class()) if ClassDB.can_instantiate(resource.get_class()) else null
	for property: Dictionary in resource.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = property["name"]
		if name.begins_with("resource_") or name == "script":
			continue
		var value: Variant = resource.get(name)
		if fresh != null and not (value is Object) and typeof(value) == typeof(fresh.get(name)) and value == fresh.get(name):
			continue
		out[name] = _plain(value)
	return out


## Generated meshes compare by shape, not bytes: surfaces, vertex count, bounds and rounded vertices.
static func _mesh_digest(mesh: Mesh) -> Dictionary:
	var out: Dictionary = {"class": mesh.get_class(), "surfaces": mesh.get_surface_count()}
	var aabb: AABB = mesh.get_aabb()
	out["aabb"] = [aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z]
	var count: int = 0
	var digest: PackedStringArray = []
	for surface: int in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		count += vertices.size()
		for v: Vector3 in vertices:
			digest.append("%.3f,%.3f,%.3f" % [v.x, v.y, v.z])
		out["material_%d" % surface] = _resource(mesh.surface_get_material(surface))
	out["vertices"] = count
	out["hash"] = ";".join(digest).md5_text()
	return out


## JSON-safe form: colours and vectors as arrays, other engine types as their text form.
static func _plain(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is StringName:
		return String(value)
	if value is Color:
		return _color(value)
	if value is Vector2 or value is Vector3:
		var list: Array = []
		for i: int in range(3 if value is Vector3 else 2):
			list.append(value[i])
		return list
	if value is Resource:
		return _resource(value)
	if value is Object:
		return null
	if value is PackedColorArray or value is PackedFloat32Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_plain(item))
		return items
	return var_to_str(value)

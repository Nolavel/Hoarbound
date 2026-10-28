class_name WindowBreakage
extends Node3D

## Glass that throws can crack and break (#257). Panes are the 727 window breaches and every
## pane quad in a generated facade's "windows" surface, found from the hit point. Damage adds up:
## a stone breaks a pane at once, snow cracks it first. A broken 727 pane opens its breach.

signal pane_changed(key: StringName, state: int)

enum PaneState {INTACT, CRACKED, BROKEN}

const BREACH_GROUP: StringName = &"glazed_window"
const DAMAGE_SHADER: Shader = preload("res://shaders/environment/windows/window_damage.gdshader")
## Impulse (N*s) a pane takes before it cracks and before it breaks, added over hits.
const CRACK_AT: float = 2.0
const BREAK_AT: float = 5.0
## A hit counts for a pane this close to its plane and this far past its edge, metres.
const PLANE_REACH_M: float = 0.25
const EDGE_SLACK_M: float = 0.05
const WINDOWS_SURFACE: String = "windows"

## key -> {damage, state, impact (pane UV), seed}
var _panes: Dictionary = {}
var _overlays: Dictionary = {}
## Mesh instance id -> its facade panes in world space, read once per streamed-in mesh.
var _facade_cache: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	add_to_group(ThrowImpactCapability.WORLD_GROUP)
	ThrowImpactCapability.publish(self, self, &"take_hit")


## A throw met the world: crack or break the pane at point, if there is one.
func take_hit(item_id: StringName, point: Vector3, _normal: Vector3, impulse: float, collider: Object) -> bool:
	var pane: Dictionary = find_pane(point, collider)
	if pane.is_empty():
		return false
	var key: StringName = pane["key"]
	var record: Dictionary = _panes.get(key, {"damage": 0.0, "state": PaneState.INTACT, "seed": randf() * 100.0})
	if record["state"] == PaneState.BROKEN:
		return true
	record["damage"] = float(record["damage"]) + impulse
	record["impact"] = pane["uv"]
	record["frame"] = [pane["centre"], pane["right"], pane["up"], pane["normal"], pane["size"]]
	var state: int = PaneState.BROKEN if record["damage"] >= BREAK_AT else (PaneState.CRACKED if record["damage"] >= CRACK_AT else PaneState.INTACT)
	var changed: bool = state != record["state"]
	record["state"] = state
	_panes[key] = record
	if changed:
		_show(key, record)
		if state == PaneState.BROKEN:
			_shatter(pane)
			if pane.has("breach"):
				(pane["breach"] as ShelterBreach).set_glazed(false)
		pane_changed.emit(key, state)
	return true


func get_pane_state(key: StringName) -> int:
	return int(_panes.get(key, {}).get("state", PaneState.INTACT))


## The pane under point: {key, centre, right, up, size, normal, uv[, breach]}, or {} on bare wall.
func find_pane(point: Vector3, collider: Object) -> Dictionary:
	for node: Node in get_tree().get_nodes_in_group(BREACH_GROUP):
		var breach := node as ShelterBreach
		var local: Vector3 = breach.global_transform.affine_inverse() * point
		var half := Vector2(breach.opening_width_m, breach.opening_height_m) * 0.5
		if absf(local.z) <= PLANE_REACH_M + 0.2 and absf(local.x) <= half.x + EDGE_SLACK_M and absf(local.y) <= half.y + EDGE_SLACK_M:
			var basis: Basis = breach.global_basis.orthonormalized()
			return {"key": StringName("breach:" + str(breach.get_path())), "centre": breach.global_position, "right": basis.x,
				"up": basis.y, "normal": basis.z, "size": half * 2.0, "uv": Vector2(0.5 + local.x / (half.x * 2.0), 0.5 - local.y / (half.y * 2.0)),
				"breach": breach}
	var body := collider as Node
	if body == null or body.get_parent() == null:
		return {}
	for mesh_node: Node in body.get_parent().find_children("*", "MeshInstance3D", true, false):
		for pane: Dictionary in _facade_panes(mesh_node as MeshInstance3D):
			var offset: Vector3 = point - (pane["centre"] as Vector3)
			var u: float = offset.dot(pane["right"])
			var v: float = offset.dot(pane["up"])
			var half: Vector2 = (pane["size"] as Vector2) * 0.5
			if absf(offset.dot(pane["normal"])) <= PLANE_REACH_M and absf(u) <= half.x + EDGE_SLACK_M and absf(v) <= half.y + EDGE_SLACK_M:
				var hit: Dictionary = pane.duplicate()
				hit["uv"] = Vector2(0.5 + u / (half.x * 2.0), 0.5 - v / (half.y * 2.0))
				return hit
	return {}


## Every pane quad of a mesh's "windows" surface in world space (two triangles per pane).
func _facade_panes(mesh_instance: MeshInstance3D) -> Array:
	var id: int = mesh_instance.get_instance_id()
	if _facade_cache.has(id):
		return _facade_cache[id]
	var panes: Array = []
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh != null:
		for s: int in range(mesh.get_surface_count()):
			if mesh.surface_get_name(s) != WINDOWS_SURFACE:
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i: int in range(verts.size()):
					indices.append(i)
			var xf: Transform3D = mesh_instance.global_transform
			for t: int in range(0, indices.size() - 5, 6):
				var corners: Array[Vector3] = []
				for k: int in range(6):
					var p: Vector3 = xf * verts[indices[t + k]]
					if not corners.any(func(c: Vector3) -> bool: return c.is_equal_approx(p)):
						corners.append(p)
				var pane: Dictionary = _pane_from(corners)
				if not pane.is_empty():
					panes.append(pane)
	_facade_cache[id] = panes
	return panes


## A pane frame from its four world corners: centre, axes along and up the wall, size and a stable key.
static func _pane_from(corners: Array[Vector3]) -> Dictionary:
	if corners.size() != 4:
		return {}
	var centre := Vector3.ZERO
	var low := INF
	var high := -INF
	for c: Vector3 in corners:
		centre += c * 0.25
		low = minf(low, c.y)
		high = maxf(high, c.y)
	var bottom: Array[Vector3] = corners.filter(func(c: Vector3) -> bool: return c.y < (low + high) * 0.5)
	if bottom.size() != 2:
		return {}
	var right: Vector3 = (bottom[1] - bottom[0])
	var width: float = right.length()
	if width < 0.01:
		return {}
	right /= width
	var normal: Vector3 = right.cross(Vector3.UP).normalized()
	return {"key": StringName("pane:%d:%d:%d" % [roundi(centre.x * 100.0), roundi(centre.y * 100.0), roundi(centre.z * 100.0)]),
		"centre": centre, "right": right, "up": Vector3.UP, "normal": normal, "size": Vector2(width, high - low)}


func _show(key: StringName, record: Dictionary) -> void:
	var frame: Array = record["frame"]
	var pane: Dictionary = {"centre": frame[0], "right": frame[1], "up": frame[2], "normal": frame[3], "size": frame[4]}
	var overlay: MeshInstance3D = _overlays.get(key)
	if overlay == null:
		overlay = MeshInstance3D.new()
		overlay.name = "PaneDamage"
		var quad := QuadMesh.new()
		quad.size = pane["size"]
		var material := ShaderMaterial.new()
		material.shader = DAMAGE_SHADER
		quad.material = material
		overlay.mesh = quad
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(overlay)
		## Both faces, a hair proud of the glass on the street side so it never flickers with it.
		var normal: Vector3 = pane["normal"]
		overlay.global_transform = Transform3D(Basis(pane["right"], pane["up"], normal), (pane["centre"] as Vector3) + normal * 0.012)
		_overlays[key] = overlay
	var shader_material := (overlay.mesh as QuadMesh).material as ShaderMaterial
	shader_material.set_shader_parameter(&"state", float(record["state"]))
	shader_material.set_shader_parameter(&"impact", record.get("impact", Vector2(0.5, 0.5)))
	shader_material.set_shader_parameter(&"seed", float(record["seed"]))
	shader_material.set_shader_parameter(&"pane_size", pane["size"])


## Glass shards falling from a broken pane, to both sides of it.
func _shatter(pane: Dictionary) -> void:
	var shards := GPUParticles3D.new()
	shards.name = "Shards"
	shards.one_shot = true
	shards.amount = 28
	shards.lifetime = 1.6
	shards.explosiveness = 0.9
	shards.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var size: Vector2 = pane["size"]
	process.emission_box_extents = Vector3(size.x * 0.4, size.y * 0.4, 0.02)
	process.direction = Vector3(0.0, 0.2, 1.0)
	process.spread = 70.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 2.2
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.angular_velocity_min = -540.0
	process.angular_velocity_max = 540.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	shards.process_material = process
	var shard := QuadMesh.new()
	shard.size = Vector2(0.06, 0.09)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.92, 0.96, 0.7)
	glass.metallic_specular = 1.0
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	shard.material = glass
	shards.draw_pass_1 = shard
	add_child(shards)
	var normal: Vector3 = pane["normal"]
	shards.global_transform = Transform3D(Basis(pane["right"], pane["up"], normal), pane["centre"])
	shards.emitting = true
	get_tree().create_timer(shards.lifetime + 0.5).timeout.connect(shards.queue_free)


func get_save_key() -> StringName:
	return &"window_breakage"


func get_save_data() -> Dictionary:
	var saved: Dictionary = {}
	for key: StringName in _panes:
		var record: Dictionary = _panes[key]
		var frame: Array = record["frame"]
		var flat: Array = []
		for part: Variant in frame:
			if part is Vector3:
				flat.append_array([part.x, part.y, part.z])
			else:
				flat.append_array([(part as Vector2).x, (part as Vector2).y])
		saved[String(key)] = {"damage": record["damage"], "state": record["state"], "seed": record["seed"],
			"impact": [record["impact"].x, record["impact"].y], "frame": flat}
	return {"panes": saved}


## Restores pane damage: the struck panes show again and 727's broken panes reopen their breaches.
func load_save_data(data: Dictionary) -> void:
	_panes.clear()
	for overlay: Node in _overlays.values():
		overlay.queue_free()
	_overlays.clear()
	var saved: Dictionary = data.get("panes", {})
	for raw: Variant in saved:
		var record: Dictionary = saved[raw]
		var impact: Array = record.get("impact", [0.5, 0.5])
		var f: Array = record.get("frame", [])
		if f.size() != 14:
			continue
		var key := StringName(str(raw))
		_panes[key] = {"damage": float(record.get("damage", 0.0)), "state": int(record.get("state", 0)),
			"seed": float(record.get("seed", 0.0)), "impact": Vector2(float(impact[0]), float(impact[1])),
			"frame": [Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8]),
				Vector3(f[9], f[10], f[11]), Vector2(f[12], f[13])]}
		if int(_panes[key]["state"]) != PaneState.INTACT:
			_show(key, _panes[key])
	for node: Node in get_tree().get_nodes_in_group(BREACH_GROUP):
		var key := StringName("breach:" + str(node.get_path()))
		if get_pane_state(key) == PaneState.BROKEN:
			(node as ShelterBreach).set_glazed(false)

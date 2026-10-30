class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260). Worn, each runs through authored anchors over Henry's
## body (pack_strap_anchors.tscn, bound to his bones): tight along the body, with slack where it
## hangs free between the pack and the body. Off his back, each is a limp loop on the pack.

const ANCHORS_SCENE: PackedScene = preload("res://scenes/actors/player/henry/pack_strap_anchors.tscn")
## Strap width, the wider pad over the shoulder, and its thickness, metres.
const WIDTH_M: float = 0.042
const PAD_WIDTH_M: float = 0.058
const THICK_M: float = 0.008
## Samples between two anchors along the body.
const SAMPLES_PER_SPAN: int = 6
## Free runs (pack to upper back, armpit to pack) are cinched straight: samples along each.
const FREE_POINTS: int = 7
## Off the back: chain points of the whole loop.
const LIMP_POINTS: int = 26
## Verlet: constraint passes, share of velocity kept per step, gravity (m/s^2).
const ITERATIONS: int = 10
const DAMPING: float = 0.96
const GRAVITY: float = 9.8
## Where each strap is sewn to the pack's back, in BackpackModel space (x for the +X side; the
## back face is z = 0 and faces -Z): sewn a little below the top so the strap rises onto the shoulder,
## and the bottom corner.
const PACK_TOP: Vector3 = Vector3(0.11, 0.36, -0.016)
const PACK_BOTTOM: Vector3 = Vector3(0.14, 0.05, -0.016)

@export var colour: Color = Color(0.22, 0.23, 0.25)

var _skeleton: Skeleton3D
var _pack: PackRig
## Rebuilt each frame from packed arrays in one upload (per-vertex ImmediateMesh calls cost ~1 ms).
var _mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _count: int = 0
## Points per strip this frame, and index lists already built for those counts.
var _strips := PackedInt32Array()
var _index_cache: Dictionary = {}
var _material := StandardMaterial3D.new()
## Per side ([+X, -X]): the anchor markers on the bones, in order along the strap.
var _anchors: Array = [[], []]
## Per side: the limp loop's verlet chain [points, previous points, segment length].
var _limp: Array = [[], []]
var _worn_last: bool = false


func _init() -> void:
	top_level = true
	process_priority = 100  # after the animation has posed the bones
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material.albedo_color = colour
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _mesh


## Ties the straps to Henry's skeleton and the pack, and puts the anchors on his bones: the
## authored +X side as is, the other side mirrored onto the matching _r bones.
func setup(skeleton: Skeleton3D, pack: PackRig) -> void:
	_skeleton = skeleton
	_pack = pack
	_material.albedo_color = colour
	var authored: Node = ANCHORS_SCENE.instantiate()
	var attachments: Dictionary = {}
	var mirror := Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3.BACK)
	for side: int in range(2):
		for marker: Node in authored.get_children():
			var rest_xf: Transform3D = (marker as Node3D).transform
			var bone_name := String(marker.get_meta(&"bone", &"spine_03"))
			if side == 1:
				rest_xf = Transform3D(mirror * rest_xf.basis * mirror, mirror * rest_xf.origin)
				bone_name = bone_name.replace("_l", "_r")
			var bone: int = skeleton.find_bone(bone_name)
			if bone < 0:
				push_warning("PackShoulderStraps: no bone %s for strap anchor %s." % [bone_name, marker.name])
				continue
			if not attachments.has(bone_name):
				var attachment := BoneAttachment3D.new()
				attachment.name = "StrapBone_" + bone_name
				attachment.bone_name = bone_name
				skeleton.add_child(attachment)
				attachments[bone_name] = attachment
			var anchor := Marker3D.new()
			anchor.name = "Strap%s_%s" % ["L" if side == 0 else "R", marker.name]
			anchor.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * rest_xf
			(attachments[bone_name] as Node3D).add_child(anchor)
			(_anchors[side] as Array).append(anchor)
	authored.free()


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	if _pack == null or _pack.get_canvas() == null or not _pack.is_visible_in_tree():
		return
	var worn: bool = _pack.get_parent() is BoneAttachment3D
	var step: float = clampf(delta, 0.0, 0.05)
	var changed: bool = worn != _worn_last
	_worn_last = worn
	_count = 0
	_strips.clear()
	for side: int in range(2):
		if worn:
			_draw_worn(side)
		else:
			_draw_limp(side, step, changed)
	if _count == 0:
		return
	_vertices.resize(_count)
	_normals.resize(_count)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_INDEX] = _strip_indices()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(0, _material)


## Worn: free run from the pack onto the upper back, tight run along the anchors, free run from
## under the arm back to the pack's bottom corner.
func _draw_worn(side: int) -> void:
	var anchors: Array = _anchors[side]
	if anchors.size() < 2:
		return
	var points: Array[Vector3] = []
	var ups: Array[Vector3] = []
	for anchor: Node3D in anchors:
		points.append(anchor.global_position)
		ups.append(anchor.global_basis.y.normalized())
	var last: int = points.size() - 1
	var top: Vector3 = _pack_end(PACK_TOP, points[0])
	var bottom: Vector3 = _pack_end(PACK_BOTTOM, points[last])
	var pack_out: Vector3 = (_pack.get_canvas().global_basis * Vector3.FORWARD).normalized()
	## Worn, the free runs are cinched straight between the pack and the body.
	var top_run: Array = _straight(top, points[0])
	var bottom_run: Array = _straight(points[last], bottom)
	var path: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var widths: Array[float] = []
	for k: int in range(top_run.size() - 1):
		path.append(top_run[k])
		normals.append(pack_out.slerp(ups[0], float(k) / (top_run.size() - 1)))
		widths.append(WIDTH_M)
	for i: int in range(last):
		for k: int in range(SAMPLES_PER_SPAN):
			var t: float = float(k) / SAMPLES_PER_SPAN
			path.append(_catmull(points, i, t))
			normals.append(ups[i].slerp(ups[i + 1], t))
			## Padded from the upper back over the shoulder to the chest (anchors 0 to 4).
			var u: float = float(i) + t
			widths.append(lerpf(WIDTH_M, PAD_WIDTH_M, smoothstep(0.0, 0.8, u) * (1.0 - smoothstep(3.6, 4.6, u))))
	for k: int in range(bottom_run.size()):
		path.append(bottom_run[k])
		normals.append(ups[last].slerp(pack_out, float(k) / (bottom_run.size() - 1)))
		widths.append(WIDTH_M)
	_band(path, normals, widths)


## Off his back: one limp loop from the pack's top to its bottom corner, lying on the floor.
func _draw_limp(side: int, step: float, reset: bool) -> void:
	var flip := Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0)
	var top: Vector3 = _pack.get_canvas_point(PACK_TOP * flip, Vector3.FORWARD)
	var bottom: Vector3 = _pack.get_canvas_point(PACK_BOTTOM * flip, Vector3.FORWARD)
	var pack_out: Vector3 = (_pack.get_canvas().global_basis * Vector3.FORWARD).normalized()
	## As long as the worn strap: along the body anchors plus a third again for the free runs.
	var length: float = 0.0
	var anchors: Array = _anchors[side]
	for i: int in range(anchors.size() - 1):
		length += (anchors[i] as Node3D).global_position.distance_to((anchors[i + 1] as Node3D).global_position)
	length = maxf(length * 1.35, 0.5)
	var straight: float = maxf(top.distance_to(bottom), 0.01)
	var run: Array = _chain(_limp, side, top, bottom, LIMP_POINTS, length / straight - 1.0, step, reset, pack_out * 0.12)
	var floor_y: float = _pack.get_canvas().global_position.y + 0.005
	var path: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var widths: Array[float] = []
	for k: int in range(run.size()):
		var p: Vector3 = run[k]
		## It lies on the floor; the chain is kept there so it settles rather than sinks.
		if p.y < floor_y:
			p.y = floor_y
			run[k] = p
		path.append(p)
		normals.append(pack_out)
		widths.append(WIDTH_M)
	_band(path, normals, widths)


static func _straight(from: Vector3, to: Vector3) -> Array:
	var run: Array = []
	for k: int in range(FREE_POINTS):
		run.append(from.lerp(to, float(k) / (FREE_POINTS - 1)))
	return run


## The pack-side end of a strap: the authored point on the side of the pack nearer `toward`.
func _pack_end(p: Vector3, toward: Vector3) -> Vector3:
	var a: Vector3 = _pack.get_canvas_point(p, Vector3.FORWARD)
	var b: Vector3 = _pack.get_canvas_point(p * Vector3(-1.0, 1.0, 1.0), Vector3.FORWARD)
	return a if a.distance_squared_to(toward) < b.distance_squared_to(toward) else b


## Steps one side's verlet chain pinned between `from` and `to`, `slack` longer than straight.
## `reset` lays it out afresh along the line (pushed by `bulge` at its middle). Returns its points.
func _chain(store: Array, side: int, from: Vector3, to: Vector3, count: int, slack: float, step: float, reset: bool, bulge: Vector3 = Vector3.ZERO) -> Array:
	var chain: Array = store[side]
	if reset or chain.is_empty() or (chain[0] as Array).size() != count:
		var fresh: Array = []
		for k: int in range(count):
			var t: float = float(k) / (count - 1)
			fresh.append(from.lerp(to, t) + bulge * sin(t * PI))
		chain = [fresh, fresh.duplicate(), from.distance_to(to) * (1.0 + slack) / (count - 1)]
		store[side] = chain
	var points: Array = chain[0]
	var previous: Array = chain[1]
	var segment: float = chain[2]
	for k: int in range(1, count - 1):
		var p: Vector3 = points[k]
		var carried: Vector3 = (p - (previous[k] as Vector3)) * DAMPING
		previous[k] = p
		points[k] = p + carried + Vector3.DOWN * GRAVITY * step * step
	points[0] = from
	points[count - 1] = to
	for _pass: int in range(ITERATIONS):
		for k: int in range(count - 1):
			var a: Vector3 = points[k]
			var b: Vector3 = points[k + 1]
			var gap: Vector3 = b - a
			var length: float = gap.length()
			if length < 0.00001:
				continue
			var fix: Vector3 = gap * (1.0 - segment / length)
			if k == 0:
				points[k + 1] = b - fix
			elif k + 1 == count - 1:
				points[k] = a + fix
			else:
				points[k] = a + fix * 0.5
				points[k + 1] = b - fix * 0.5
	return points


static func _catmull(points: Array[Vector3], i: int, t: float) -> Vector3:
	var last: int = points.size() - 1
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, last)]
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)


## A flat band along the path, lying on the given normals, `widths` wide: eight vertices per point
## (both faces and both edges, each with its own normal), joined by the cached index list.
func _band(path: Array[Vector3], ups: Array[Vector3], widths: Array[float]) -> void:
	var count: int = path.size()
	if count < 2:
		return
	if _vertices.size() < _count + count * 8:
		_vertices.resize(_count + count * 8)
		_normals.resize(_count + count * 8)
	var half: float = THICK_M * 0.5
	var last_out := Vector3.ZERO
	var k: int = _count
	for i: int in range(count):
		var along: Vector3 = (path[mini(i + 1, count - 1)] - path[maxi(i - 1, 0)]).normalized()
		var out: Vector3 = (ups[i] - along * ups[i].dot(along)).normalized()
		## A band has two faces: keep each normal on the same side as the last, so it never flips.
		if out.dot(last_out) < 0.0:
			out = -out
		last_out = out
		var side: Vector3 = along.cross(out).normalized()
		var across: Vector3 = side * widths[i] * 0.5
		var mid: Vector3 = path[i] + out * half
		var top: Vector3 = mid + out * half
		var bottom: Vector3 = mid - out * half
		_vertices[k] = top - across
		_vertices[k + 1] = top + across
		_vertices[k + 2] = bottom - across
		_vertices[k + 3] = bottom + across
		_vertices[k + 4] = top + across
		_vertices[k + 5] = bottom + across
		_vertices[k + 6] = top - across
		_vertices[k + 7] = bottom - across
		_normals[k] = out
		_normals[k + 1] = out
		_normals[k + 2] = -out
		_normals[k + 3] = -out
		_normals[k + 4] = side
		_normals[k + 5] = side
		_normals[k + 6] = -side
		_normals[k + 7] = -side
		k += 8
	_strips.append(count)
	_count = k


## Triangles joining each strip's points: top, bottom and the two edges between neighbours.
func _strip_indices() -> PackedInt32Array:
	var key: String = str(_strips)
	if _index_cache.has(key):
		return _index_cache[key]
	var indices := PackedInt32Array()
	var base: int = 0
	for count: int in _strips:
		for i: int in range(count - 1):
			var a: int = base + i * 8
			var b: int = a + 8
			for pair: Array in [[0, 1], [2, 3], [5, 4], [7, 6]]:
				indices.append_array([a + pair[0], a + pair[1], b + pair[1], a + pair[0], b + pair[1], b + pair[0]])
		base += count * 8
	_index_cache[key] = indices
	return indices

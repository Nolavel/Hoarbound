class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260): from the pack onto the upper back, over each shoulder, down
## the chest, under the arm and back to the pack, laid on the coat as posed; only the ends follow it.

## Strap width, the wider pad over the shoulder, and its thickness, metres.
const WIDTH_M: float = 0.042
const PAD_WIDTH_M: float = 0.058
const THICK_M: float = 0.008
## Gap kept between the strap's underside and the coat's flat facets, metres.
const CLEARANCE_M: float = 0.004
## The coat is re-skinned and the strap re-laid this often (frames), easing toward the new lay.
const RELAY_EVERY: int = 10
const RELAY_EASE: float = 0.6
## Samples along each stretch between two coat points, and along each free run to the pack.
const SAMPLES_PER_SPAN: int = 6
const SAMPLES_FREE: int = 4
## Where each strap is sewn to the pack's back, in BackpackModel space (x for the +X side; the
## back face is z = 0 and faces -Z): the top of the back pad, and the bottom corner.
const PACK_TOP: Vector3 = Vector3(0.11, 0.44, -0.016)
const PACK_BOTTOM: Vector3 = Vector3(0.14, 0.05, -0.016)
## Coat parts the straps lie over.
const COAT_PARTS: Array[String] = ["Outfit_Jacket", "Outfit_Hood", "Outfit_Trim"]
## A ray only takes a coat layer this close to the expected surface, so it skips the lining and
## a sleeve beside the torso.
const MAX_DRIFT_M: float = 0.08
## Coat points the strap passes, in the model's rest space round spine_03 (+X side; y up, z forward):
## start of a ray inside the torso, its direction, the surface expected (jacket at rest), and the
## coat's outward normal there. Upper back, over the shoulder, down the chest, under the arm. The
## collar and hood ring reach 0.18 m out from the spine, the shoulder joint 0.2 m: the strap rides
## the shoulder outside the collar and comes down the chest towards the armpit.
const COAT_POINTS: Array = [
	[Vector3(0.15, 0.17, 0.0), Vector3.FORWARD, Vector3(0.15, 0.17, -0.15), Vector3(0.1, 0.3, -1.0)],
	[Vector3(0.185, 0.0, -0.02), Vector3.UP, Vector3(0.185, 0.18, -0.02), Vector3(0.35, 1.0, 0.0)],
	[Vector3(0.17, 0.12, -0.02), Vector3.BACK, Vector3(0.17, 0.12, 0.065), Vector3(0.3, 0.6, 1.0)],
	[Vector3(0.16, 0.06, -0.02), Vector3.BACK, Vector3(0.16, 0.06, 0.088), Vector3(0.35, 0.2, 1.0)],
	[Vector3(0.155, 0.0, -0.02), Vector3.BACK, Vector3(0.155, 0.0, 0.09), Vector3(0.45, -0.1, 1.0)],
	[Vector3(0.0, -0.06, 0.04), Vector3.RIGHT, Vector3(0.172, -0.06, 0.04), Vector3(1.0, -0.1, 0.3)],
]
## Outward normals where the strap meets the pack, rest space (+X side): top, bottom.
const PACK_TOP_NORMAL: Vector3 = Vector3(0.0, 0.5, -1.0)
const PACK_BOTTOM_NORMAL: Vector3 = Vector3(0.6, -0.3, -1.0)

@export var colour: Color = Color(0.28, 0.19, 0.12)

var _skeleton: Skeleton3D
var _pack: PackRig
var _spine: int = -1
var _spine_rest: Transform3D
var _immediate := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
## Coat triangles round the torso, rest space relative to spine_03 as last posed: corners and
## centroids. Their vertices are skinned from `_skin_*`: rest position, four bones and weights.
var _tris: PackedVector3Array = PackedVector3Array()
var _centroids: PackedVector3Array = PackedVector3Array()
var _tri_verts: PackedInt32Array = PackedInt32Array()
var _skin_rest: PackedVector3Array = PackedVector3Array()
var _skin_bones: PackedInt32Array = PackedInt32Array()
var _skin_binds: Array[Transform3D] = []
var _skin_weights: PackedFloat32Array = PackedFloat32Array()
var _frame: int = 0
## The strap's run on the coat per side ([-X, +X]): points and normals, rest space round spine_03.
var _coat_path: Array = [[], []]
var _coat_normals: Array = [[], []]


func _init() -> void:
	top_level = true
	process_priority = 100  # after the animation has posed the bones
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material.albedo_color = colour
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _immediate


## Ties the straps to Henry's skeleton and the pack he wears, and lays them on his coat.
func setup(skeleton: Skeleton3D, pack: PackRig) -> void:
	_skeleton = skeleton
	_pack = pack
	_material.albedo_color = colour
	_spine = skeleton.find_bone(&"spine_03")
	if _spine < 0:
		push_warning("PackShoulderStraps: Henry's skeleton has no spine_03.")
		return
	_spine_rest = skeleton.get_bone_global_rest(_spine)
	for part: String in COAT_PARTS:
		var coat := skeleton.find_child(part, true, false) as MeshInstance3D
		if coat != null and coat.mesh != null and coat.skin != null:
			_add_coat_part(coat)
	_relay(1.0)


## Keeps a coat part's triangles round the torso (chosen at rest) and its skin data.
func _add_coat_part(coat: MeshInstance3D) -> void:
	var skin: Skin = coat.skin
	var bind_bones: Array[int] = []
	for i: int in range(skin.get_bind_count()):
		var bone: int = skin.get_bind_bone(i)
		bind_bones.append(bone if bone >= 0 else _skeleton.find_bone(skin.get_bind_name(i)))
	var to_rest: Transform3D = _skeleton.global_transform.affine_inverse() * coat.global_transform
	for surface: int in range(coat.mesh.get_surface_count()):
		var arrays: Array = coat.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bones.size() / maxi(verts.size(), 1)
		## Flat-shaded corners repeat a position per face: weld them so each is skinned once.
		var kept: Dictionary = {}
		var welded: Dictionary = {}
		for i: int in range(0, index.size(), 3):
			var centre: Vector3 = (to_rest * verts[index[i]] + to_rest * verts[index[i + 1]] + to_rest * verts[index[i + 2]]) / 3.0 - _spine_rest.origin
			## Only the corridor the straps run in: off the breastbone, short of the arms.
			if absf(centre.x) < 0.05 or absf(centre.x) > 0.25 or centre.y < -0.12 or centre.y > 0.34 or absf(centre.z) > 0.24:
				continue
			for k: int in range(3):
				var v: int = index[i + k]
				var key: Vector3i = Vector3i((verts[v] * 2000.0).round())
				if welded.has(key):
					kept[v] = welded[key]
				if not kept.has(v):
					kept[v] = _skin_rest.size()
					welded[key] = kept[v]
					_skin_rest.append(verts[v])
					for w: int in range(4):
						var bind: int = bones[v * stride + w] if w < stride else 0
						_skin_bones.append(bind_bones[bind])
						_skin_binds.append(skin.get_bind_pose(bind))
						_skin_weights.append(weights[v * stride + w] if w < stride else 0.0)
				_tri_verts.append(kept[v])


## Skins the kept coat vertices to the current pose, in rest space round spine_03, and lays both
## straps on them; `ease` blends from the last lay (1 takes the new one outright).
func _relay(ease: float) -> void:
	if _tri_verts.is_empty():
		return
	var to_rest: Transform3D = _spine_rest * _skeleton.get_bone_global_pose(_spine).affine_inverse()
	var poses: Dictionary = {}
	var posed := PackedVector3Array()
	posed.resize(_skin_rest.size())
	for v: int in range(_skin_rest.size()):
		var p := Vector3.ZERO
		for w: int in range(4):
			var j: int = v * 4 + w
			var weight: float = _skin_weights[j]
			if weight > 0.0:
				var bone: int = _skin_bones[j]
				if not poses.has(bone):
					poses[bone] = _skeleton.get_bone_global_pose(bone)
				p += ((poses[bone] as Transform3D) * _skin_binds[j] * _skin_rest[v]) * weight
		posed[v] = to_rest * p - _spine_rest.origin
	_tris.resize(_tri_verts.size())
	_centroids.resize(_tri_verts.size() / 3)
	for t: int in range(_centroids.size()):
		var a: Vector3 = posed[_tri_verts[t * 3]]
		var b: Vector3 = posed[_tri_verts[t * 3 + 1]]
		var c: Vector3 = posed[_tri_verts[t * 3 + 2]]
		_tris[t * 3] = a
		_tris[t * 3 + 1] = b
		_tris[t * 3 + 2] = c
		_centroids[t] = (a + b + c) / 3.0
	for side: int in range(2):
		var old_path: Array = (_coat_path[side] as Array).duplicate()
		var old_ups: Array = (_coat_normals[side] as Array).duplicate()
		_lay_on_coat(side)
		if ease < 1.0 and old_path.size() == (_coat_path[side] as Array).size():
			for i: int in range(old_path.size()):
				_coat_path[side][i] = (old_path[i] as Vector3).lerp(_coat_path[side][i], ease)
				_coat_normals[side][i] = (old_ups[i] as Vector3).slerp(_coat_normals[side][i], ease).normalized()


## Finds the coat points on one side, runs a curve through them and projects every sample onto
## the coat along its normal, keeping the facet's normal so the band lies flat.
func _lay_on_coat(side: int) -> void:
	var flip := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for entry: Array in COAT_POINTS:
		var from: Vector3 = (entry[0] as Vector3) * flip
		var dir: Vector3 = (entry[1] as Vector3) * flip
		var expected: Vector3 = (entry[2] as Vector3) * flip
		var hit: Array = _outer_hit(from, dir, (expected - from).dot(dir), expected)
		points.append(hit[0] if not hit.is_empty() else expected)
		normals.append(((entry[3] as Vector3) * flip).normalized())
	var path: Array = _coat_path[side]
	var ups: Array = _coat_normals[side]
	path.clear()
	ups.clear()
	var spans: int = points.size() - 1
	for i: int in range(spans):
		for k: int in range(SAMPLES_PER_SPAN + (1 if i == spans - 1 else 0)):
			var t: float = float(k) / SAMPLES_PER_SPAN
			var sample: Vector3 = _catmull(points, i, t)
			var normal: Vector3 = normals[i].slerp(normals[i + 1], t).normalized()
			var hit: Array = _outer_hit(sample - normal * MAX_DRIFT_M, normal, MAX_DRIFT_M, sample)
			path.append((hit[0] if not hit.is_empty() else sample) + normal * CLEARANCE_M)
			ups.append(hit[1] if not hit.is_empty() else normal)
	## Facets turn sharply; neighbouring normals are averaged so the band bends, not snaps.
	for _pass: int in range(2):
		var smooth: Array = ups.duplicate()
		for i: int in range(1, ups.size() - 1):
			smooth[i] = ((ups[i - 1] as Vector3) + (ups[i] as Vector3) * 2.0 + (ups[i + 1] as Vector3)).normalized()
		ups.assign(smooth)


## The outermost coat hit along a ray within MAX_DRIFT_M of `expected` metres: [point, facet normal
## facing along the ray], or empty. Only facets near `near` are tested.
func _outer_hit(from: Vector3, dir: Vector3, expected: float, near: Vector3) -> Array:
	var best: float = -1.0
	var best_normal := Vector3.ZERO
	for t: int in range(_centroids.size()):
		if _centroids[t].distance_squared_to(near) > 0.01:
			continue
		var a: Vector3 = _tris[t * 3]
		var b: Vector3 = _tris[t * 3 + 1]
		var c: Vector3 = _tris[t * 3 + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
		if hit == null:
			continue
		var d: float = ((hit as Vector3) - from).dot(dir)
		if absf(d - expected) < MAX_DRIFT_M and d > best:
			best = d
			best_normal = (b - a).cross(c - a).normalized()
	if best < 0.0:
		return []
	return [from + dir * best, best_normal if best_normal.dot(dir) > 0.0 else -best_normal]


static func _catmull(points: Array[Vector3], i: int, t: float) -> Vector3:
	var last: int = points.size() - 1
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, last)]
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_immediate.clear_surfaces()
	## Only while the pack is on his back: set down, it is no longer strapped to him.
	if _pack == null or _spine < 0 or _pack.get_canvas() == null or not _pack.is_visible_in_tree() \
			or not (_pack.get_parent() is BoneAttachment3D):
		return
	## The run on the coat rides the chest bone, so it follows the torso, never the pack.
	var carry: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_spine) * _spine_rest.affine_inverse()
	var chest: Vector3 = carry * _spine_rest.origin
	if _frame % RELAY_EVERY == 0:
		_relay(RELAY_EASE if _frame > 0 else 1.0)
	_frame += 1
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for side: int in range(2):
		var flip := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
		var coat: Array[Vector3] = []
		var coat_up: Array[Vector3] = []
		for i: int in range((_coat_path[side] as Array).size()):
			coat.append(carry * (_spine_rest.origin + (_coat_path[side][i] as Vector3)))
			coat_up.append((carry.basis * (_coat_normals[side][i] as Vector3)).normalized())
		if coat.is_empty():
			continue
		var top: Vector3 = _pack_point(PACK_TOP, coat[0], chest)
		var bottom: Vector3 = _pack_point(PACK_BOTTOM, coat[coat.size() - 1], chest)
		var top_up: Vector3 = (carry.basis * (PACK_TOP_NORMAL * flip)).normalized()
		var bottom_up: Vector3 = (carry.basis * (PACK_BOTTOM_NORMAL * flip)).normalized()
		## Straight free runs from the pack onto the coat and back; the coat run between them.
		var path: Array[Vector3] = []
		var ups: Array[Vector3] = []
		for k: int in range(SAMPLES_FREE):
			var t: float = float(k) / SAMPLES_FREE
			path.append(top.lerp(coat[0], t))
			ups.append(top_up.slerp(coat_up[0], t))
		path.append_array(coat)
		ups.append_array(coat_up)
		for k: int in range(1, SAMPLES_FREE + 1):
			var t: float = float(k) / SAMPLES_FREE
			path.append(coat[coat.size() - 1].lerp(bottom, t))
			ups.append(coat_up[coat_up.size() - 1].slerp(bottom_up, t))
		_band(path, ups)
	_immediate.surface_end()


## The pack-side end of a strap on whichever side of the pack faces the same way as `toward`.
func _pack_point(p: Vector3, toward: Vector3, chest: Vector3) -> Vector3:
	var a: Vector3 = _pack.get_canvas_point_unswayed(p, Vector3.FORWARD)
	var b: Vector3 = _pack.get_canvas_point_unswayed(p * Vector3(-1.0, 1.0, 1.0), Vector3.FORWARD)
	var side: Vector3 = toward - chest
	return a if (a - chest).dot(side) > (b - chest).dot(side) else b


## A flat band along the path, lying on the given normals.
func _band(path: Array[Vector3], ups: Array[Vector3]) -> void:
	var rails: Array = []
	for i: int in range(path.size()):
		var along: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var out: Vector3 = (ups[i] - along * ups[i].dot(along)).normalized()
		var across: Vector3 = along.cross(out).normalized()
		## Padded from the upper back over the shoulder to the chest, plain webbing elsewhere.
		var u: float = float(i - SAMPLES_FREE) / SAMPLES_PER_SPAN
		var width: float = lerpf(WIDTH_M, PAD_WIDTH_M, smoothstep(-0.2, 0.5, u) * (1.0 - smoothstep(2.0, 2.8, u)))
		## Lifted by half its thickness so it lies on the coat, not in it.
		rails.append([path[i] + out * THICK_M * 0.5, out, across * width * 0.5])
	for i: int in range(rails.size() - 1):
		var a: Array = rails[i]
		var b: Array = rails[i + 1]
		for face: float in [1.0, -1.0]:
			var lift: float = THICK_M * 0.5 * face
			_quad(a[0] + a[1] * lift - a[2], a[0] + a[1] * lift + a[2], b[0] + b[1] * lift + b[2], b[0] + b[1] * lift - b[2], a[1] * face)
		for edge: float in [1.0, -1.0]:
			var ea: Vector3 = a[0] + a[2] * edge
			var eb: Vector3 = b[0] + b[2] * edge
			_quad(ea - a[1] * THICK_M * 0.5, ea + a[1] * THICK_M * 0.5, eb + b[1] * THICK_M * 0.5, eb - b[1] * THICK_M * 0.5, (a[2] as Vector3).normalized() * edge)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		_immediate.surface_set_normal(normal)
		_immediate.surface_add_vertex(v)

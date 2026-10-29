class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260): from the top of the pack over each shoulder, down the chest
## and under the arm to the pack's bottom corner. Rebuilt each frame from the chest bone and the pack.

## Strap width, the wider pad over the shoulder, and its thickness, metres.
const WIDTH_M: float = 0.042
const PAD_WIDTH_M: float = 0.058
const THICK_M: float = 0.008
const SAMPLES_PER_SPAN: int = 6
## Where each strap is sewn to the pack's back, in BackpackModel space (x for the +X side; the
## back face is z = 0 and faces -Z): the top of the back pad, and the bottom corner.
const PACK_TOP: Vector3 = Vector3(0.085, 0.44, -0.016)
const PACK_BOTTOM: Vector3 = Vector3(0.14, 0.05, -0.016)

## Points on the coat, measured on the jacket mesh round spine_03 in the model's rest space (x out
## to the strap's side, y up, z forward), each with the coat's outward normal there: over the
## shoulder, high and low on the chest, and under the arm.
@export var over_shoulder: Vector3 = Vector3(0.12, 0.285, -0.01)
@export var chest_high: Vector3 = Vector3(0.12, 0.2, 0.115)
@export var chest_low: Vector3 = Vector3(0.15, 0.02, 0.175)
@export var under_arm: Vector3 = Vector3(0.2, -0.04, 0.06)
@export var colour: Color = Color(0.28, 0.19, 0.12)

## Outward normals at those points, same space; the band lies flat on the coat along them.
const NORMALS: Array[Vector3] = [
	Vector3(0.0, 0.5, -1.0),
	Vector3(0.15, 1.0, 0.0),
	Vector3(0.1, 0.6, 1.0),
	Vector3(0.2, 0.0, 1.0),
	Vector3(1.0, -0.2, 0.4),
	Vector3(0.6, -0.3, -1.0),
]

var _skeleton: Skeleton3D
var _pack: PackRig
var _spine: int = -1
var _spine_rest: Transform3D
var _immediate := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _init() -> void:
	top_level = true
	process_priority = 100  # after the animation has posed the bones
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material.albedo_color = colour
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _immediate


## Ties the straps to Henry's skeleton and the pack he wears.
func setup(skeleton: Skeleton3D, pack: PackRig) -> void:
	_skeleton = skeleton
	_pack = pack
	_material.albedo_color = colour
	_spine = skeleton.find_bone(&"spine_03")
	if _spine < 0:
		push_warning("PackShoulderStraps: Henry's skeleton has no spine_03.")
		return
	_spine_rest = skeleton.get_bone_global_rest(_spine)


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_immediate.clear_surfaces()
	## Only while the pack is on his back: set down, it is no longer strapped to him.
	if _pack == null or _spine < 0 or _pack.get_canvas() == null or not _pack.is_visible_in_tree() \
			or not (_pack.get_parent() is BoneAttachment3D):
		return
	## Rest-space coat points ride on the chest bone, so they follow the torso, never the pack.
	var carry: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_spine) * _spine_rest.affine_inverse()
	var chest: Vector3 = carry * _spine_rest.origin
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for side: float in [-1.0, 1.0]:
		var flip := Vector3(side, 1.0, 1.0)
		var coat: Array[Vector3] = []
		for offset: Vector3 in [over_shoulder, chest_high, chest_low, under_arm]:
			coat.append(carry * (_spine_rest.origin + offset * flip))
		var top: Vector3 = _pack_point(PACK_TOP, coat[0], chest)
		var bottom: Vector3 = _pack_point(PACK_BOTTOM, coat[3], chest)
		var points: Array[Vector3] = [top, coat[0], coat[1], coat[2], coat[3], bottom]
		var normals: Array[Vector3] = []
		for i: int in range(NORMALS.size()):
			normals.append((carry.basis * (NORMALS[i] * flip)).normalized())
		_strap(points, normals)
	_immediate.surface_end()


## The pack-side end of a strap on whichever side of the pack faces the same way as `toward`.
func _pack_point(p: Vector3, toward: Vector3, chest: Vector3) -> Vector3:
	var a: Vector3 = _pack.get_canvas_point_unswayed(p, Vector3.FORWARD)
	var b: Vector3 = _pack.get_canvas_point_unswayed(p * Vector3(-1.0, 1.0, 1.0), Vector3.FORWARD)
	var side: Vector3 = toward - chest
	return a if (a - chest).dot(side) > (b - chest).dot(side) else b


## A flat band through the points (Catmull-Rom) lying on the given surface normals.
func _strap(points: Array[Vector3], normals: Array[Vector3]) -> void:
	var path: Array[Vector3] = []
	var ups: Array[Vector3] = []
	var spans: int = points.size() - 1
	for i: int in range(spans):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, spans)]
		for k: int in range(SAMPLES_PER_SPAN):
			var t: float = float(k) / SAMPLES_PER_SPAN
			path.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
			ups.append(normals[i].slerp(normals[i + 1], t))
	path.append(points[spans])
	ups.append(normals[spans])
	var rails: Array = []
	for i: int in range(path.size()):
		var along: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var out: Vector3 = (ups[i] - along * ups[i].dot(along)).normalized()
		var across: Vector3 = along.cross(out).normalized()
		## Padded over the shoulder (between the first and third points), plain webbing elsewhere.
		var u: float = float(i) / SAMPLES_PER_SPAN
		var width: float = lerpf(WIDTH_M, PAD_WIDTH_M, smoothstep(0.6, 1.2, u) * (1.0 - smoothstep(2.0, 2.8, u)))
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

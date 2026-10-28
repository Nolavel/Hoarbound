class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260): from the top of the pack over each shoulder, down the chest
## and under the arm to the pack's bottom corner. Rebuilt each frame from the bones and the pack.

## Strap width, the wider pad over the shoulder, and its thickness, metres.
const WIDTH_M: float = 0.042
const PAD_WIDTH_M: float = 0.058
const THICK_M: float = 0.008
const SAMPLES_PER_SPAN: int = 6
## Where each strap meets the pack, in BackpackModel space (x for the +X side).
const PACK_TOP: Vector3 = Vector3(0.075, 0.47, -0.004)
const PACK_BOTTOM: Vector3 = Vector3(0.15, 0.06, -0.004)

## Points on the coat from the chest bone (spine_03) in Henry's frame, x out to the strap's side,
## y up his spine, z forward: over the shoulder, high and low on the chest, under the arm.
@export var over_shoulder: Vector3 = Vector3(0.12, 0.32, -0.04)
@export var chest_high: Vector3 = Vector3(0.12, 0.22, 0.17)
@export var chest_low: Vector3 = Vector3(0.16, 0.03, 0.17)
@export var under_arm: Vector3 = Vector3(0.23, -0.02, 0.05)
@export var colour: Color = Color(0.28, 0.19, 0.12)

var _skeleton: Skeleton3D
var _pack: PackRig
var _spine: int = -1
var _neck: int = -1
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
	_neck = skeleton.find_bone(&"neck_01")
	if _spine < 0 or _neck < 0:
		push_warning("PackShoulderStraps: Henry's skeleton has no spine_03 or neck_01.")


func _process(_delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	_immediate.clear_surfaces()
	var canvas: BackpackModel = _pack.get_canvas() if _pack != null else null
	## Only while the pack is on his back: set down, it is no longer strapped to him.
	if canvas == null or _spine < 0 or _neck < 0 or not _pack.is_visible_in_tree() or not (_pack.get_parent() is BoneAttachment3D):
		return
	var chest: Vector3 = _bone(_spine)
	var up: Vector3 = (_bone(_neck) - chest).normalized()
	var forward: Vector3 = chest - _pack.global_position
	forward = (forward - up * forward.dot(up)).normalized()
	var right: Vector3 = forward.cross(up).normalized()
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	var pack_x: float = signf((canvas.global_basis * Vector3.RIGHT).dot(right))
	for side: float in [-1.0, 1.0]:
		var frame := Basis(right * side, up, forward)
		var mirror := Vector3(side * pack_x, 1.0, 1.0)
		var points: Array[Vector3] = [
			canvas.global_transform * (PACK_TOP * mirror),
			chest + frame * over_shoulder,
			chest + frame * chest_high,
			chest + frame * chest_low,
			chest + frame * under_arm,
			canvas.global_transform * (PACK_BOTTOM * mirror),
		]
		_strap(points, chest, up)
	_immediate.surface_end()


func _bone(index: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin


## A flat band through the points (Catmull-Rom), facing away from the spine's axis.
func _strap(points: Array[Vector3], chest: Vector3, up: Vector3) -> void:
	var path: Array[Vector3] = []
	var spans: int = points.size() - 1
	for i: int in range(spans):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, spans)]
		for k: int in range(SAMPLES_PER_SPAN):
			var t: float = float(k) / SAMPLES_PER_SPAN
			path.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	path.append(points[spans])
	var rails: Array = []
	for i: int in range(path.size()):
		var along: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var off_axis: Vector3 = path[i] - chest
		var out: Vector3 = off_axis - up * off_axis.dot(up)
		out = (out - along * out.dot(along)).normalized()
		var across: Vector3 = along.cross(out).normalized()
		## Padded over the shoulder (between the first and third points), plain webbing elsewhere.
		var u: float = float(i) / SAMPLES_PER_SPAN
		var width: float = lerpf(WIDTH_M, PAD_WIDTH_M, smoothstep(0.6, 1.2, u) * (1.0 - smoothstep(2.0, 2.8, u)))
		rails.append([path[i], out, across * width * 0.5])
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

class_name ArmStrapClearance
extends SkeletonModifier3D

## Keeps each upper arm off the pack straps under it: the sleeve, as a capsule round the upper arm bone (its
## radius measured from the jacket), is pushed off the strap's points by turning the arm at the shoulder
## (capsule-to-point collision resolved by rotation, as spring-bone colliders do).

## Strap points further than this from the arm are not tested, metres.
const NEAR_M: float = 0.2
## The upper arm's first share (the shoulder joint, under the pad) is not tested.
const SHOULDER_SHARE: float = 0.3
## How fast the arm eases back in once the strap no longer pushes it, radians per second.
const EASE_BACK: float = 1.0
const EASE_OUT: float = 3.0
## Never turned further than this, degrees.
const MAX_TURN_DEG: float = 8.0

var straps: PackShoulderStraps
## Per arm [right, left]: sleeve radius round the bone, and the turn now applied (radians).
var _radius: Array[float] = [0.06, 0.06]
var _turn: Array[float] = [0.0, 0.0]
var _axis: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Deepest overlap found this frame per arm, before the turn (for measuring), metres.
var overlap: Array[float] = [0.0, 0.0]


## Measures each sleeve's radius from the jacket's rest mesh: the median distance of its upper-arm vertices from the bone.
func measure_sleeves(jacket: MeshInstance3D) -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or jacket == null or jacket.skin == null:
		return
	var skin: Skin = jacket.skin
	for side: int in 2:
		var s: String = "l" if side == 1 else "r"
		var upper: int = rig.find_bone("upperarm_" + s)
		var lower: int = rig.find_bone("lowerarm_" + s)
		var a: Vector3 = rig.get_bone_global_rest(upper).origin
		var b: Vector3 = rig.get_bone_global_rest(lower).origin
		var distances: Array[float] = []
		for surface: int in jacket.mesh.get_surface_count():
			var arrays: Array = jacket.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for v: int in verts.size():
				for w: int in 4:
					var bind: int = bones[v * 4 + w]
					var bone: int = skin.get_bind_bone(bind)
					if bone < 0:
						bone = rig.find_bone(skin.get_bind_name(bind))
					if bone == upper and weights[v * 4 + w] > 0.6:
						## The rest mesh is in skin space: the bind pose takes it to the bone, the rest back to the rig.
						var p: Vector3 = rig.get_bone_global_rest(bone) * (skin.get_bind_pose(bind) * verts[v])
						distances.append(_segment_distance(p, a, b)[0])
		if distances.size() > 10:
			distances.sort()
			## The inner sleeve (the side that meets the strap) is the thin side: its lower quartile.
			_radius[side] = distances[distances.size() / 4]


func _process_modification() -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or straps == null or not straps.is_worn():
		_turn = [0.0, 0.0]
		return
	var points: PackedVector3Array = straps.strap_points()
	var to_rig: Transform3D = rig.global_transform.affine_inverse()
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	for side: int in 2:
		var s: String = "l" if side == 1 else "r"
		var upper: int = rig.find_bone("upperarm_" + s)
		var lower: int = rig.find_bone("lowerarm_" + s)
		if upper < 0 or lower < 0:
			continue
		## An arm holding something (HandGrip) is placed by its grip, not pushed here as well.
		var grip := rig.get_node_or_null(NodePath("HandGrip_" + s)) as HandGrip
		if grip != null and grip.get_weight() > 0.01:
			_turn[side] = 0.0
			continue
		var pose: Transform3D = rig.get_bone_global_pose(upper)
		var a: Vector3 = pose.origin
		var b: Vector3 = rig.get_bone_global_pose(lower).origin
		var length: float = a.distance_to(b)
		var deepest: float = 0.0
		var push := Vector3.ZERO
		var lever: float = length
		for world: Vector3 in points:
			var p: Vector3 = to_rig * world
			if p.distance_to(a) > length + NEAR_M:
				continue
			var hit: Array = _segment_distance(p, a, b)
			## The shoulder's top carries the pad by design: only the arm below the joint is kept off the strap.
			if float(hit[2]) < SHOULDER_SHARE:
				continue
			var depth: float = _radius[side] + PackShoulderStraps.THICK_M - float(hit[0])
			if depth > deepest:
				deepest = depth
				push = (hit[1] as Vector3) - p
				lever = maxf(float(hit[2]) * length, 0.05)
		overlap[side] = deepest
		## The turn that carries the arm's touching point `deepest` further off along the push.
		var want: float = 0.0
		if deepest > 0.0 and push.length_squared() > 1e-10:
			var along: Vector3 = (b - a) / length
			var axis: Vector3 = along.cross(push.normalized())
			if axis.length_squared() > 1e-8:
				_axis[side] = axis.normalized()
				want = minf(asin(clampf(deepest / lever, 0.0, 1.0)), deg_to_rad(MAX_TURN_DEG))
		## In at once (never through the strap), back out slowly (no flicker as the arm swings).
		## Eased both ways (no snap that reads as a twitch); out faster than back in.
		_turn[side] = move_toward(_turn[side], want, (EASE_OUT if want > _turn[side] else EASE_BACK) * delta)
		if _turn[side] > 0.0001 and _axis[side] != Vector3.ZERO:
			pose.basis = Basis(_axis[side], _turn[side]) * pose.basis
			rig.set_bone_global_pose(upper, pose)


## Distance from p to segment a-b, the closest point on it, and how far along it (0..1).
static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> Array:
	var ab: Vector3 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-10), 0.0, 1.0)
	var c: Vector3 = a + ab * t
	return [p.distance_to(c), c, t]

class_name BootSole
extends RefCounted
## Outline of Henry's army boot outsole, heel block to rounded toe, for the meshes that
## press snow. boot_sole.gdshaderinc mirrors half_width() and press() for the persistent stamp.

## Outsole length heel to toe, metres (a size 44 boot); the width is SnowShell.sole_width_m.
const LENGTH_M: float = 0.305
## Sole-local u runs -1 (heel back) to 1 (toe); widths are shares of the ball's half width.
## The heel block ends at a straight breast here; the shank behind the ball is the waist.
const BREAST_U: float = -0.44
const HEEL_HALF: float = 0.74
const WAIST_HALF: float = 0.62
const OUTLINE_STEPS: int = 40


## Half width of the outsole at `u`, 0 outside it.
static func half_width(u: float) -> float:
	if u <= -1.0 or u >= 1.0:
		return 0.0
	if u < -0.72:
		## Rounded heel back: a superellipse, square-shouldered like a real heel block.
		var t: float = (u + 0.72) / 0.28
		return HEEL_HALF * pow(maxf(1.0 - t * t * t * t, 0.0), 0.25)
	if u < BREAST_U:
		return HEEL_HALF
	if u < 0.42:
		## Shank narrows to the waist under the arch, then widens to the ball.
		var waist: float = lerpf(0.7, WAIST_HALF, smoothstep(BREAST_U, -0.2, u))
		return lerpf(waist, 1.0, smoothstep(-0.2, 0.42, u))
	if u < 0.55:
		return 1.0
	var toe: float = (u - 0.55) / 0.45
	return sqrt(maxf(1.0 - toe * toe, 0.0))


## Share of the boot's press at `u`: heel block and ball full, the arched shank light.
static func press(u: float) -> float:
	var shank: float = smoothstep(BREAST_U - 0.02, BREAST_U + 0.02, u) * (1.0 - smoothstep(-0.05, 0.2, u))
	return lerpf(1.0, 0.45, shank) * lerpf(1.0, 0.85, smoothstep(0.6, 1.0, u))


## Prism of the outsole between `u0` and `u1` in a unit box, toe towards -Z, to scale to
## sole width, height and length; the shank's underside sits `arch` above the rest.
static func build_mesh(u0: float, u1: float, arch: float = 0.06) -> ArrayMesh:
	var ring := PackedVector2Array()
	var lift := PackedFloat32Array()
	for i: int in range(OUTLINE_STEPS * 2 + 2):
		var k: int = i if i <= OUTLINE_STEPS else OUTLINE_STEPS * 2 + 1 - i
		var u: float = clampf(lerpf(u0, u1, float(k) / OUTLINE_STEPS), -0.999, 0.999)
		var side: float = 0.5 if i <= OUTLINE_STEPS else -0.5
		ring.append(Vector2(half_width(u) * side, -u * 0.5))
		lift.append((1.0 - press(u)) * arch)
	var verts := PackedVector3Array()
	var count: int = ring.size()
	for i: int in range(count):
		verts.append(Vector3(ring[i].x, -0.5 + lift[i], ring[i].y))
	for p: Vector2 in ring:
		verts.append(Vector3(p.x, 0.5, p.y))
	var indices := PackedInt32Array()
	var cap: PackedInt32Array = Geometry2D.triangulate_polygon(ring)
	for t: int in range(0, cap.size(), 3):
		indices.append_array([cap[t], cap[t + 2], cap[t + 1]])
		indices.append_array([cap[t] + count, cap[t + 1] + count, cap[t + 2] + count])
	for i: int in range(count):
		var j: int = (i + 1) % count
		indices.append_array([i, j, i + count, j, j + count, i + count])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

class_name PackClothCheck
extends RefCounted

## The pack canvas as backpack_canvas.gdshader draws it (rest rounded box, bulge over the outlines it was
## handed, slack sagging onto them), for stands that check nothing in the pack comes through the cloth.

## backpack_canvas.gdshader soft_m: the bulge feathers over this distance.
const SOFT_M: float = 0.03


## Deepest any drawn item's point lies past the canvas's inner face, metres (negative: clear of it).
static func worst_past(interior: PackInterior) -> float:
	var proxies: Array[AABB] = interior.drawn_boxes()
	if proxies.size() != interior.items.size():
		return -1.0
	var worst: float = -1.0
	for i: int in interior.items.size():
		for q: Vector3 in interior.support_points(i, true):
			worst = maxf(worst, past(q, proxies, interior.model.get_fill()))
	return worst


static func past(q: Vector3, proxies: Array[AABB], fill: float) -> float:
	## The canvas's rest vertex nearest q, on the rounded box the shell and panel are built on.
	var c := Vector3(0.0, BackpackModel.BODY.y * 0.5, BackpackModel.BODY.z * 0.5)
	var r: float = BackpackModel.ROUND_M
	var core: Vector3 = BackpackModel.BODY * 0.5 - Vector3.ONE * r
	var d: Vector3 = q - c
	var clamped: Vector3 = d.clamp(-core, core)
	var n: Vector3 = d - clamped
	if n.length() < 0.00001:
		var axis: int = (d.abs() - core).max_axis_index()
		n = Vector3.ZERO
		n[axis] = signf(d[axis])
	n = n.normalized()
	var p: Vector3 = c + clamped + n * r
	var push: float = 0.0
	var clear: float = 1.0
	for box: AABB in proxies:
		var dd: float = box_distance(p, box) - BackpackModel.CANVAS_LINING_M
		push = maxf(push, smoothstep(SOFT_M, -SOFT_M, dd) * maxf(SOFT_M - dd, 0.0))
		clear = minf(clear, dd)
	push = minf(push, BackpackModel.CANVAS_STRETCH_M)
	var height: float = BackpackModel.BODY.y
	var high: float = smoothstep(height * 0.45, height, p.y)
	var slump: Vector3 = (Vector3(0.0, -BackpackModel.SLUMP_TOP_M * high, 0.0) - n * BackpackModel.SLUMP_WALL_M * smoothstep(0.1, 0.4, p.y / height)) * (1.0 - clampf(fill, 0.0, 1.0))
	var sag: float = slump.length()
	if sag > 0.0:
		slump *= minf(sag, maxf(clear, 0.0)) / sag
	var cloth: Vector3 = p + n * push + slump
	return (q - (cloth - n * BackpackModel.CANVAS_LINING_M)).dot(n)


static func box_distance(p: Vector3, box: AABB) -> float:
	var q: Vector3 = (p - box.get_center()).abs() - box.size * 0.5
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

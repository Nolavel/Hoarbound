extends SceneTree

## Finds where the shoulder straps lie on Henry's jacket: a ray outward per sample along the guide anchors
## hits the outer cloth; each row is three hits across (triangle, barycentric, lift over folds) the outward guide normal and how padded it is (0 webbing, 1 shoulder pad), and its centre at rest.
## Run: godot --headless --path . --script res://tools/runtime/measure_strap_points.gd

const OUTFIT: String = "res://assets/characters/henry/henry_outfit.glb"
const GUIDES: String = "res://scenes/actors/player/henry/pack_strap_anchors.tscn"
const OUT: String = "res://scenes/actors/player/henry/strap_points.json"
const JACKET: String = "Outfit_Jacket"
## Sample spacing along the strap, metres, and its width (padded from UpperBack, guide 2, to ChestLow, guide 7).
const STEP_M: float = 0.015
const WIDTH_M: float = 0.042
const PAD_WIDTH_M: float = 0.052
## Rays start this far inside the guide and reach this far out.
const RAY_BACK: float = 0.12
const RAY_REACH: float = 0.3
## Cloth within this distance of a hit (across the surface) lifts the strap over its folds.
const LIFT_REACH: float = 0.02

## The strap's underside air (as PackShoulderStraps.GAP_M), the extra a pressed point goes under it, and
## the deepest press (the vertex colour holds depth / PRESS_MAX_M), metres; cloth points this near a row.
const GAP_M: float = 0.001
const PRESS_MARGIN_M: float = 0.0015
const PRESS_MAX_M: float = 0.03
const NEAR_M: float = 0.05
## Poses the strap rests on (its lift) besides the rest mesh: [clip, seconds]; the press covers the rest.
const LIFT_POSES: Array = []
## Poses the press covers: [clip, seconds], standing, walking, running, crouching and working.
const POSES: Array = [["Idle", 0.0], ["Idle", 1.0], ["Idle", 2.0], ["Walk", 0.0], ["Walk", 0.3], ["Walk", 0.6],
	["Jog_Fwd", 0.0], ["Jog_Fwd", 0.25], ["Sprint", 0.0], ["Sprint", 0.2], ["Crouch_Idle", 0.5], ["Crouch_Fwd", 0.0],
	["Crouch_Fwd", 0.4], ["Idle_Torch", 0.5], ["Interact", 0.5]]

var _tris: Array = []
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _binds: Array = []
var _mats: Array = []
var _verts := PackedVector3Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _offsets: Array[int] = []


func _initialize() -> void:
	var model: Node = (load(OUTFIT) as PackedScene).instantiate()
	var jacket := model.find_child(JACKET, true, false) as MeshInstance3D
	var counts: Array = []
	for s: int in jacket.mesh.get_surface_count():
		var arrays: Array = jacket.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		counts.append(verts.size())
		for t: int in range(0, index.size(), 3):
			_tris.append([s, index[t], index[t + 1], index[t + 2], verts[index[t]], verts[index[t + 1]], verts[index[t + 2]]])
	var guides: Node = (load(GUIDES) as PackedScene).instantiate()
	var sides: Array = []
	var misses: int = 0
	for side: int in 2:
		var flip := Vector3(-1.0 if side == 1 else 1.0, 1.0, 1.0)
		var points: Array[Vector3] = []
		var ups: Array[Vector3] = []
		for marker: Node3D in guides.get_children():
			points.append(marker.transform.origin * flip)
			ups.append((marker.transform.basis.y * flip).normalized())
		var samples: Array = []
		var span_total: int = points.size() - 1
		for i: int in span_total:
			var steps: int = maxi(2, ceili(points[i].distance_to(points[i + 1]) / STEP_M))
			for k: int in steps:
				var t: float = float(k) / steps
				samples.append([_catmull(points, i, t), ups[i].slerp(ups[i + 1], t).normalized(), float(i) + t])
		samples.append([points[span_total], ups[span_total], float(span_total)])
		var rows: Array = []
		for j: int in samples.size():
			var p: Vector3 = samples[j][0]
			var n: Vector3 = samples[j][1]
			var u: float = samples[j][2]
			var along: Vector3 = ((samples[mini(j + 1, samples.size() - 1)][0] as Vector3) - (samples[maxi(j - 1, 0)][0] as Vector3)).normalized()
			var across: Vector3 = along.cross(n).normalized()
			var pad: float = smoothstep(2.0, 2.8, u) * (1.0 - smoothstep(6.6, 7.6, u))
			var width: float = lerpf(WIDTH_M, PAD_WIDTH_M, pad)
			var row: Array = []
			for a: float in [-0.5, 0.0, 0.5]:
				var hit: Array = _outermost(p + across * width * a - n * RAY_BACK, n)
				if hit.is_empty():
					misses += 1
					continue
				hit.append(_lift(hit, n))
				row.append(hit)
			if row.size() == 3:
				row.append([n.x, n.y, n.z])
				row.append(pad)
				var rest: Vector3 = _point(row[1])
				row.append([rest.x, rest.y, rest.z])
				rows.append(row)
		sides.append(rows)
	var press: Array = _pose_fit(model, jacket, sides)
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"surface_vertices": counts, "sides": sides, "press": press}, "\t"))
	file.close()
	var deepest: float = 0.0
	for p: Array in press:
		deepest = maxf(deepest, p[2])
	print("strap points: %d + %d rows, %d ray misses, %d cloth points pressed (deepest %.1f mm) -> %s" % [sides[0].size(), sides[1].size(), misses, press.size(), deepest * 1000.0, OUT])
	guides.free()
	quit(0)


## Lifts each hit over the cloth round it as Henry stands (LIFT_POSES), then finds how far each cloth
## point under a strap must be pressed in so that in no pose of POSES it comes up into the strap: a strap
## presses the folds under it flat. Returns [[surface, vertex, depth, normal faces out], ...].
func _pose_fit(model: Node, jacket: MeshInstance3D, sides: Array) -> Array:
	root.add_child(model)
	_skeleton = jacket.get_parent() as Skeleton3D
	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skin: Skin = jacket.skin
	for b: int in skin.get_bind_count():
		var bone: int = skin.get_bind_bone(b)
		_binds.append([bone if bone >= 0 else _skeleton.find_bone(skin.get_bind_name(b)), skin.get_bind_pose(b)])
	var normals := PackedVector3Array()
	for s: int in jacket.mesh.get_surface_count():
		var arrays: Array = jacket.mesh.surface_get_arrays(s)
		_offsets.append(_verts.size())
		_verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		_bones.append_array(arrays[Mesh.ARRAY_BONES])
		_weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
	## Per row, the cloth points near its centre at rest (a pose moves them only a little relative to it).
	var near: Dictionary = {}
	for side: int in 2:
		for r: int in (sides[side] as Array).size():
			var p: Vector3 = _point(sides[side][r][1])
			var list := PackedInt32Array()
			for v: int in _verts.size():
				if _verts[v].distance_to(p) < NEAR_M and not _arm(v):
					list.append(v)
			near["%d:%d" % [side, r]] = list
	for pose: Array in [["", 0.0]] + LIFT_POSES:
		for side: int in 2:
			var rows: Array = _posed_rows(sides[side], pose)
			for r: int in rows.size():
				var row: Array = rows[r]
				for c: int in 3:
					var hit: Array = sides[side][r][c]
					for v: int in near["%d:%d" % [side, r]]:
						var d: Vector3 = _skinned(v) - (row[c] as Vector3)
						var h: float = d.dot(row[3])
						if (d - (row[3] as Vector3) * h).length() < LIFT_REACH and h > float(hit[7]) and h < 0.03:
							hit[7] = h
	var press: Dictionary = {}
	for pose: Array in POSES:
		for side: int in 2:
			var rows: Array = _posed_rows(sides[side], pose)
			for r: int in range(1, rows.size() - 1):
				var row: Array = rows[r]
				var n: Vector3 = row[3]
				var lifted: Array = []
				for c: int in 3:
					lifted.append((row[c] as Vector3) + n * float(sides[side][r][c][7]))
				var c0: Vector3 = lifted[1]
				var along: Vector3 = (rows[r + 1][1] as Vector3) - (rows[r - 1][1] as Vector3)
				var reach: float = along.length() * 0.5
				along = along.normalized()
				var across: Vector3 = (lifted[2] as Vector3) - (lifted[0] as Vector3)
				var half: float = across.length() * 0.5
				across = across.normalized()
				var lh: float = ((lifted[0] as Vector3) - c0).dot(n)
				var rh: float = ((lifted[2] as Vector3) - c0).dot(n)
				for v: int in near["%d:%d" % [side, r]]:
					var d: Vector3 = _skinned(v) - c0
					var a: float = d.dot(across)
					if absf(d.dot(along)) > reach or absf(a) > half:
						continue
					var excess: float = d.dot(n) - (rh if a > 0.0 else lh) * absf(a) / half - GAP_M + PRESS_MARGIN_M
					if excess > float(press.get(v, 0.0)):
						press[v] = minf(excess, PRESS_MAX_M)
	var out: Array = []
	for v: int in press:
		var s: int = 0
		while s + 1 < _offsets.size() and v >= _offsets[s + 1]:
			s += 1
		## Which way the vertex's own normal faces against the strap's outward normal at rest.
		var facing: bool = normals[v].dot(_rest_out(v, sides)) > 0.0
		out.append([s, v - _offsets[s], snappedf(float(press[v]), 0.0001), facing])
	return out


## The strap's outward guide normal at the row nearest a rest vertex.
func _rest_out(v: int, sides: Array) -> Vector3:
	var best: float = 1e9
	var out := Vector3.UP
	for rows: Array in sides:
		for row: Array in rows:
			var d: float = _point(row[1]).distance_squared_to(_verts[v])
			if d < best:
				best = d
				out = Vector3(row[3][0], row[3][1], row[3][2])
	return out


## The rows of one side in a pose ("" is the rest pose): [left, centre, right, outward normal].
func _posed_rows(rows: Array, pose: Array) -> Array:
	if pose[0] != "":
		_player.play(pose[0])
		_player.seek(pose[1], true)
	else:
		_player.stop()
		_skeleton.reset_bone_poses()
	_mats.clear()
	for b: Array in _binds:
		_mats.append(_skeleton.get_bone_global_pose(int(b[0])) * (b[1] as Transform3D))
	var centres: Array[Vector3] = []
	for row: Array in rows:
		centres.append(_skinned_hit(row[1]))
	var spine: int = _skeleton.find_bone(&"spine_03")
	var turn: Basis = (_skeleton.get_bone_global_pose(spine) * _skeleton.get_bone_global_rest(spine).affine_inverse()).basis
	var posed: Array = []
	for r: int in rows.size():
		var left: Vector3 = _skinned_hit(rows[r][0])
		var right: Vector3 = _skinned_hit(rows[r][2])
		var n: Vector3 = (right - left).cross(centres[mini(r + 1, rows.size() - 1)] - centres[maxi(r - 1, 0)]).normalized()
		if n.dot(turn * Vector3(rows[r][3][0], rows[r][3][1], rows[r][3][2])) < 0.0:
			n = -n
		posed.append([left, centres[r], right, n])
	return posed


func _skinned(v: int) -> Vector3:
	var q := Vector3.ZERO
	for w: int in 4:
		var wt: float = _weights[v * 4 + w]
		if wt > 0.0:
			q += ((_mats[_bones[v * 4 + w]] as Transform3D) * _verts[v]) * wt
	return q


## A sleeve point (mostly on the arm bones): the arm presses on the strap, it never lifts it.
func _arm(v: int) -> bool:
	var arm: float = 0.0
	for w: int in 4:
		var bone: String = _skeleton.get_bone_name(int(_binds[_bones[v * 4 + w]][0]))
		if bone.begins_with("upperarm") or bone.begins_with("lowerarm") or bone.begins_with("hand"):
			arm += _weights[v * 4 + w]
	return arm > 0.5


## A hit skinned with the pose's matrices: its triangle's vertices, blended barycentrically.
func _skinned_hit(hit: Array) -> Vector3:
	var base: int = _offsets[int(hit[0])]
	return _skinned(base + int(hit[1])) * float(hit[4]) + _skinned(base + int(hit[2])) * float(hit[5]) + _skinned(base + int(hit[3])) * float(hit[6])


## A hit's rest position on the jacket.
func _point(hit: Array) -> Vector3:
	for t: Array in _tris:
		if t[0] == hit[0] and t[1] == hit[1] and t[2] == hit[2] and t[3] == hit[3]:
			return (t[4] as Vector3) * float(hit[4]) + (t[5] as Vector3) * float(hit[5]) + (t[6] as Vector3) * float(hit[6])
	return Vector3.ZERO


## How far the cloth round a hit rises above it along `n` (folds the strap rests on), from the rest mesh.
func _lift(hit: Array, n: Vector3) -> float:
	var tri: Array = _tris[0]
	var p := Vector3.ZERO
	for t: Array in _tris:
		if t[0] == hit[0] and t[1] == hit[1] and t[2] == hit[2] and t[3] == hit[3]:
			tri = t
			break
	p = (tri[4] as Vector3) * float(hit[4]) + (tri[5] as Vector3) * float(hit[5]) + (tri[6] as Vector3) * float(hit[6])
	var rise: float = 0.0
	for t: Array in _tris:
		for c: int in 3:
			var d: Vector3 = (t[4 + c] as Vector3) - p
			var h: float = d.dot(n)
			if (d - n * h).length() < LIFT_REACH and h > rise and h < 0.03:
				rise = h
	return rise


## The last cloth the ray crosses within reach: [surface, i0, i1, i2, b0, b1, b2].
func _outermost(origin: Vector3, dir: Vector3) -> Array:
	var best: float = -1.0
	var found: Array = []
	for tri: Array in _tris:
		var a: Vector3 = tri[4]
		var e1: Vector3 = (tri[5] as Vector3) - a
		var e2: Vector3 = (tri[6] as Vector3) - a
		var pv: Vector3 = dir.cross(e2)
		var det: float = e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var tv: Vector3 = origin - a
		var u: float = tv.dot(pv) / det
		if u < 0.0 or u > 1.0:
			continue
		var qv: Vector3 = tv.cross(e1)
		var v: float = dir.dot(qv) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var t: float = e2.dot(qv) / det
		if t > 0.0 and t < RAY_REACH and t > best:
			best = t
			found = [tri[0], tri[1], tri[2], tri[3], 1.0 - u - v, u, v]
	return found


static func _catmull(points: Array[Vector3], i: int, t: float) -> Vector3:
	var last: int = points.size() - 1
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, last)]
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)

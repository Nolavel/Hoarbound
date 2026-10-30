class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260). Worn, each lies on Henry's jacket: its points are triangles of
## the jacket (strap_points.json, measured by tools/runtime/measure_strap_points.gd), skinned each frame
## exactly as the GPU skins the jacket, so the strap never sinks in or lifts off; straight runs join the
## pack's back face. Off his back, each is a limp loop on the pack.

const POINTS_FILE: String = "res://scenes/actors/player/henry/strap_points.json"
const JACKET: String = "Outfit_Jacket"
## Thickness of the shoulder pad and of the webbing it narrows to under the arm, and the air kept
## between the strap's underside and the cloth, metres.
const THICK_M: float = 0.008
const WEBBING_M: float = 0.003
const GAP_M: float = 0.001
## The deepest press the vertex colour encodes (as measure_strap_points.gd PRESS_MAX_M), metres.
const PRESS_MAX_M: float = 0.03
## Free runs (pack to upper back, under the arm to pack) are cinched straight: samples along each.
const FREE_POINTS: int = 7
## Off the back: chain points of the whole loop, and its strap width.
const LIMP_POINTS: int = 26
const WIDTH_M: float = 0.042
## Verlet: constraint passes, share of velocity kept per step, gravity (m/s^2).
const ITERATIONS: int = 10
const DAMPING: float = 0.96
const GRAVITY: float = 9.8
## Where each strap is sewn to the pack's back face, in BackpackModel space (x for the +X side; the
## back face is z = 0 and faces -Z): a little below the top so it rises onto the shoulder, and the bottom corner.
const PACK_TOP: Vector3 = Vector3(0.11, 0.36, 0.0)
const PACK_BOTTOM: Vector3 = Vector3(0.14, 0.05, 0.0)

@export var colour: Color = Color(0.22, 0.23, 0.25)

var _skeleton: Skeleton3D
var _pack: PackRig
var _jacket: MeshInstance3D
## Rebuilt each frame from packed arrays in one upload (per-vertex ImmediateMesh calls cost ~1 ms).
var _mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _count: int = 0
## Points per strip this frame, and index lists already built for those counts.
var _strips := PackedInt32Array()
var _index_cache: Dictionary = {}
var _material := StandardMaterial3D.new()
## Per side ([+X, -X]): rows across the strap, each [left, centre, right, rest outward normal]; a point is
## [rest positions of its triangle's 3 vertices, their skeleton bones (4 each), weights (4 each), barycentric].
var _rows: Array = [[], []]
## Skin bind index to [skeleton bone, bind pose]; per-frame bone matrices for the binds in use.
var _binds: Array = []
var _bind_xf: Dictionary = {}
## Per side: the limp loop's verlet chain [points, previous points, segment length].
var _limp: Array = [[], []]
var _worn_last: bool = false
var _pressed: bool = false
var _delta: float = 0.0


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material.albedo_color = colour
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _mesh


## Ties the straps to Henry's skeleton, jacket and pack. Drawn when the skeleton's final pose is
## ready (after every modifier), the same pose the jacket is skinned with.
func setup(skeleton: Skeleton3D, pack: PackRig) -> void:
	_skeleton = skeleton
	_pack = pack
	_material.albedo_color = colour
	_jacket = skeleton.find_child(JACKET, true, false) as MeshInstance3D
	if _jacket == null or _jacket.skin == null:
		push_warning("PackShoulderStraps: no skinned %s to lay the straps on." % JACKET)
		return
	var skin: Skin = _jacket.skin
	for b: int in skin.get_bind_count():
		var bone: int = skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		_binds.append([bone, skin.get_bind_pose(b)])
	var surfaces: Array = []
	for s: int in _jacket.mesh.get_surface_count():
		surfaces.append(_jacket.mesh.surface_get_arrays(s))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POINTS_FILE))
	for s: int in surfaces.size():
		if int(data["surface_vertices"][s]) != (surfaces[s][Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			push_warning("PackShoulderStraps: the jacket changed; re-run tools/runtime/measure_strap_points.gd.")
			return
	for side: int in 2:
		for row: Array in data["sides"][side]:
			var out: Array = []
			for k: int in 3:
				var hit: Array = row[k]
				var arrays: Array = surfaces[int(hit[0])]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var rest: Array[Vector3] = []
				var hit_bones := PackedInt32Array()
				var hit_weights := PackedFloat32Array()
				for c: int in 3:
					var v: int = int(hit[1 + c])
					rest.append(verts[v])
					for w: int in 4:
						hit_bones.append(bones[v * 4 + w])
						hit_weights.append(weights[v * 4 + w])
				out.append([rest, hit_bones, hit_weights, Vector3(hit[4], hit[5], hit[6]), float(hit[7])])
			var n: Array = row[3]
			out.append(Vector3(n[0], n[1], n[2]))
			out.append(float(row[4]))
			(_rows[side] as Array).append(out)
	_press_cloth(data["press"], surfaces)
	skeleton.skeleton_updated.connect(_redraw)


## Writes how far each cloth point under a strap is pressed in (measured over Henry's poses) into a copy
## of the jacket mesh's vertex colours; the jacket's shader presses them in while the pack is worn.
func _press_cloth(press: Array, surfaces: Array) -> void:
	var colours: Array = []
	for arrays: Array in surfaces:
		var blank := PackedColorArray()
		blank.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		blank.fill(Color(0.0, 0.0, 0.0, 1.0))
		colours.append(blank)
	for p: Array in press:
		## Packed arrays are values: change a copy and put it back.
		var surface: PackedColorArray = colours[int(p[0])]
		surface[int(p[1])] = Color(float(p[2]) / PRESS_MAX_M, 1.0 if p[3] else 0.0, 0.0, 1.0)
		colours[int(p[0])] = surface
	var source: Mesh = _jacket.mesh
	var pressed := ArrayMesh.new()
	for s: int in surfaces.size():
		var arrays: Array = surfaces[s]
		arrays[Mesh.ARRAY_COLOR] = colours[s]
		pressed.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays)
		pressed.surface_set_material(s, source.surface_get_material(s))
		pressed.surface_set_name(s, source.surface_get_name(s))
	_jacket.mesh = pressed


## Turns the jacket's press on or off with the pack worn.
func _set_press(worn: bool) -> void:
	_pressed = worn
	if _jacket == null:
		return
	for s: int in _jacket.mesh.get_surface_count():
		var material := _jacket.get_surface_override_material(s) as ShaderMaterial
		if material != null:
			material.set_shader_parameter(&"garment_press", 1.0 if worn else 0.0)
			material.set_shader_parameter(&"garment_press_max", PRESS_MAX_M)


func _process(delta: float) -> void:
	_delta = delta
	## Off his back the skeleton still poses every frame; worn, only the final pose may draw.
	if _jacket == null:
		_redraw()


func _redraw() -> void:
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	var shown: bool = _pack != null and _pack.get_canvas() != null and _pack.is_visible_in_tree()
	var worn: bool = shown and _pack.get_parent() is BoneAttachment3D
	if worn != _pressed:
		_set_press(worn)
	if not shown:
		return
	var step: float = clampf(_delta, 0.0, 0.05)
	var changed: bool = worn != _worn_last
	_worn_last = worn
	_count = 0
	_strips.clear()
	_bind_xf.clear()
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


## A jacket point this frame, skinned like the GPU: each triangle vertex blended over its bones, then barycentric.
func skin_point(point: Array) -> Vector3:
	var rest: Array = point[0]
	var bones: PackedInt32Array = point[1]
	var weights: PackedFloat32Array = point[2]
	var bary: Vector3 = point[3]
	var p := Vector3.ZERO
	for c: int in 3:
		var v: Vector3 = rest[c]
		var skinned := Vector3.ZERO
		for w: int in 4:
			var weight: float = weights[c * 4 + w]
			if weight > 0.0:
				skinned += (_bind(bones[c * 4 + w]) * v) * weight
		p += skinned * bary[c]
	return _skeleton.global_transform * p


## Skeleton-space matrix of one skin bind this frame (cached per draw).
func _bind(index: int) -> Transform3D:
	if not _bind_xf.has(index):
		var bind: Array = _binds[index]
		_bind_xf[index] = _skeleton.get_bone_global_pose(int(bind[0])) * (bind[1] as Transform3D)
	return _bind_xf[index]


## Worn rows this frame: [left, centre, right, outward normal, thickness] in world space.
func worn_rows(side: int) -> Array:
	var rows: Array = []
	var basis: Basis = _skeleton.global_basis
	for row: Array in _rows[side]:
		var left: Vector3 = skin_point(row[0])
		var centre: Vector3 = skin_point(row[1])
		var right: Vector3 = skin_point(row[2])
		## Outward: the skinned spread of the row crossed with the strap's run, on the rest normal's side.
		rows.append([left, centre, right, basis * (row[3] as Vector3), Vector3(row[0][4], row[1][4], row[2][4]), row[4]])
	for i: int in rows.size():
		var along: Vector3 = (rows[mini(i + 1, rows.size() - 1)][1] as Vector3) - (rows[maxi(i - 1, 0)][1] as Vector3)
		var across: Vector3 = (rows[i][2] as Vector3) - (rows[i][0] as Vector3)
		var n: Vector3 = across.cross(along).normalized()
		if n.dot(rows[i][3]) < 0.0:
			n = -n
		## Lifted over the folds round each point, so no fold pokes into the strap.
		var lift: Vector3 = rows[i][4]
		for c: int in 3:
			rows[i][c] = (rows[i][c] as Vector3) + n * lift[c]
		rows[i][3] = n
		rows[i][4] = lerpf(WEBBING_M, THICK_M, rows[i][5])
		rows[i].resize(5)
	return rows


## Worn: a straight run from the pack's back face onto the back, the rows on the jacket, and a straight run
## from the back of the side to the pack's bottom corner; returns the band and its rows on the jacket.
func worn_band(side: int) -> Dictionary:
	var rows: Array = worn_rows(side)
	if rows.size() < 2:
		return {}
	var pack_out: Vector3 = (_pack.get_canvas().global_basis * Vector3.FORWARD).normalized()
	var band: Array = []
	_free_run(band, _pack_end(PACK_TOP, rows[0][1]), pack_out, rows[0], true)
	band.append_array(rows.slice(1, rows.size() - 1))
	_free_run(band, _pack_end(PACK_BOTTOM, rows[rows.size() - 1][1]), pack_out, rows[rows.size() - 1], false)
	return {"band": band, "rows": rows}


func _draw_worn(side: int) -> void:
	var worn: Dictionary = worn_band(side)
	if not worn.is_empty():
		_band(worn["band"])


## A straight run between the pack (`at`, its face normal `face_out`) and a row on the jacket, as wide
## as that row; `into` runs pack to body, else body to pack.
func _free_run(band: Array, at: Vector3, face_out: Vector3, row: Array, into: bool) -> void:
	var half: Vector3 = ((row[2] as Vector3) - (row[0] as Vector3)) * 0.5
	## At the pack the strap's width lies flat in its face, so neither edge sinks into the canvas.
	var flat: Vector3 = (half - face_out * half.dot(face_out)).normalized() * half.length()
	for k: int in FREE_POINTS:
		var t: float = float(k) / (FREE_POINTS - 1)
		if not into:
			t = 1.0 - t
		var centre: Vector3 = at.lerp(row[1], t)
		var n: Vector3 = face_out.slerp(row[3], t).normalized()
		var across: Vector3 = flat.lerp(half, t)
		band.append(row if t >= 1.0 else [centre - across, centre, centre + across, n, row[4]])


## Off his back: one limp loop from the pack's top to its bottom corner, lying on the floor.
func _draw_limp(side: int, step: float, reset: bool) -> void:
	var flip := Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0)
	var top: Vector3 = _pack.get_canvas_point(PACK_TOP * flip, Vector3.FORWARD)
	var bottom: Vector3 = _pack.get_canvas_point(PACK_BOTTOM * flip, Vector3.FORWARD)
	var pack_out: Vector3 = (_pack.get_canvas().global_basis * Vector3.FORWARD).normalized()
	## As long as the worn strap: along the body rows plus a third again for the free runs.
	var length: float = 0.0
	var rows: Array = _rows[side]
	for i: int in range(rows.size() - 1):
		length += (rows[i][1][0][0] as Vector3).distance_to(rows[i + 1][1][0][0])
	length = maxf(length * 1.35, 0.5)
	var straight: float = maxf(top.distance_to(bottom), 0.01)
	var run: Array = _chain(_limp, side, top, bottom, LIMP_POINTS, length / straight - 1.0, step, reset, pack_out * 0.12)
	var floor_y: float = _pack.get_canvas().global_position.y + 0.005
	var path: Array[Vector3] = []
	for k: int in range(run.size()):
		var p: Vector3 = run[k]
		## It lies on the floor; the chain is kept there so it settles rather than sinks.
		if p.y < floor_y:
			p.y = floor_y
			run[k] = p
		path.append(p)
	var band: Array = []
	for k: int in path.size():
		var along: Vector3 = (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
		var across: Vector3 = along.cross(pack_out).normalized() * WIDTH_M * 0.5
		band.append([path[k] - across, path[k], path[k] + across, pack_out, WEBBING_M])
	_band(band)


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


## A band along `rows` ([left, centre, right, outward normal, thickness]): its underside GAP_M off them; ten vertices per row (top and underside left/centre/right, both edges), joined by the cached index list.
func _band(rows: Array) -> void:
	var count: int = rows.size()
	if count < 2:
		return
	if _vertices.size() < _count + count * 10:
		_vertices.resize(_count + count * 10)
		_normals.resize(_count + count * 10)
	var k: int = _count
	for i: int in count:
		var row: Array = rows[i]
		var out: Vector3 = row[3]
		var side: Vector3 = ((row[2] as Vector3) - (row[0] as Vector3)).normalized()
		var low: Vector3 = out * GAP_M
		var high: Vector3 = out * (GAP_M + float(row[4]))
		for c: int in 3:
			_vertices[k + c] = (row[c] as Vector3) + high
			_vertices[k + 3 + c] = (row[c] as Vector3) + low
			_normals[k + c] = out
			_normals[k + 3 + c] = -out
		_vertices[k + 6] = (row[0] as Vector3) + high
		_vertices[k + 7] = (row[0] as Vector3) + low
		_vertices[k + 8] = (row[2] as Vector3) + high
		_vertices[k + 9] = (row[2] as Vector3) + low
		_normals[k + 6] = -side
		_normals[k + 7] = -side
		_normals[k + 8] = side
		_normals[k + 9] = side
		k += 10
	_strips.append(count)
	_count = k


## Triangles joining each strip's rows: top and underside (two quads each) and both edges.
func _strip_indices() -> PackedInt32Array:
	var key: String = str(_strips)
	if _index_cache.has(key):
		return _index_cache[key]
	var indices := PackedInt32Array()
	var base: int = 0
	for count: int in _strips:
		for i: int in range(count - 1):
			var a: int = base + i * 10
			var b: int = a + 10
			for pair: Array in [[0, 1], [1, 2], [4, 3], [5, 4], [7, 6], [8, 9]]:
				indices.append_array([a + pair[0], a + pair[1], b + pair[1], a + pair[0], b + pair[1], b + pair[0]])
		base += count * 10
	_index_cache[key] = indices
	return indices

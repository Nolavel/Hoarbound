class_name PackShoulderStraps
extends MeshInstance3D

## The pack's two shoulder straps (#260): the school backpack's own pad, webbing and buckle (tools/blender/
## build_pack_straps.py) bent along a path on the GPU. Worn, the path's points are jacket triangles
## (strap_points.json), skinned as the GPU skins the jacket, with straight runs to the pack; off his back, a limp loop.

const POINTS_FILE: String = "res://scenes/actors/player/henry/strap_points.json"
## The straightened straps (strap space: x across, y off the body, z along, metres) and their lengths.
const STRAP_MESHES: Array[String] = ["res://assets/characters/gear/pack_strap_pos.glb", "res://assets/characters/gear/pack_strap_neg.glb"]
const STRAP_INFO: String = "res://assets/characters/gear/pack_strap.json"
const STRAP_TAGS: Array[String] = ["pos", "neg"]
const BEND_SHADER: Shader = preload("res://shaders/items/pack_strap_bend.gdshader")
const TEXTURES: Array[String] = ["res://assets/characters/gear/school_backpack_0.jpg", "res://assets/characters/gear/school_backpack_1.png", "res://assets/characters/gear/school_backpack_2.png"]
## The school pad's half width as built (build_pack_straps.py PAD_WIDTH_M / 2): over the pad the strap
## spreads from it to the path's row width.
const PAD_HALF_M: float = 0.0225
## Path frames per strap the shader holds (its MAX_FRAMES).
const MAX_FRAMES: int = 96
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

## The straps' colour: the pack's grey-blue canvas (the school pack's texture adds only weave and wear).
@export var colour: Color = BackpackModel.CANVAS

var _skeleton: Skeleton3D
var _pack: PackRig
var _jacket: MeshInstance3D
## Both straps in one surface, built once; each frame only the path frames (shader uniforms) change.
var _mesh := ArrayMesh.new()
var _material := ShaderMaterial.new()
## Per strap mesh: its length (m) and where its pad ends (share of its length).
var _length: Array[float] = [1.0, 1.0]
var _pad_end: Array[float] = [0.45, 0.45]
var _centres := PackedVector4Array()
var _across := PackedVector4Array()
var _outs := PackedVector4Array()
var _frame_counts: Array[int] = [0, 0]
## Per side ([+X, -X]): rows across the strap, each [left, centre, right, rest outward normal]; a point is
## [rest positions of its triangle's 3 vertices, their skeleton bones (4 each), weights (4 each), barycentric].
var _rows: Array = [[], []]
## Skin bind index to [skeleton bone, bind pose]; per-frame bone matrices for the binds in use.
var _binds: Array = []
var _bind_xf: Dictionary = {}
## Per side: the limp loop's verlet chain [points, previous points, segment length].
var _limp: Array = [[], []]
var _worn_last: bool = false
## Per side, per free run (to the back, back to the pack): how far each sample is bowed out over the cloth
## (learned by measure_straps.gd --learn), metres.
var _free_lift: Array = [[PackedFloat32Array(), PackedFloat32Array()], [PackedFloat32Array(), PackedFloat32Array()]]
var _pressed: bool = false
var _delta: float = 0.0


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material.shader = BEND_SHADER
	_material.set_shader_parameter(&"strap_colour", colour)
	for k: int in TEXTURES.size():
		_material.set_shader_parameter([&"albedo_texture", &"metal_rough_texture", &"normal_texture"][k], load(TEXTURES[k]))
	_material.set_shader_parameter(&"gap", GAP_M)
	_centres.resize(MAX_FRAMES * 2)
	_across.resize(MAX_FRAMES * 2)
	_outs.resize(MAX_FRAMES * 2)
	_build_mesh()
	mesh = _mesh


## Reparenting and unloading a character must not leave a redraw callback on
## a skeleton whose global transform can no longer be read.
func _enter_tree() -> void:
	_sync_skeleton_updates(true)


func _exit_tree() -> void:
	_sync_skeleton_updates(false)


func _sync_skeleton_updates(connect_updates: bool) -> void:
	if not is_instance_valid(_skeleton):
		return
	var subscribed: bool = _skeleton.skeleton_updated.is_connected(_redraw)
	if connect_updates and not subscribed:
		_skeleton.skeleton_updated.connect(_redraw)
	elif not connect_updates and subscribed:
		_skeleton.skeleton_updated.disconnect(_redraw)


func _can_skin() -> bool:
	return is_inside_tree() and is_instance_valid(_skeleton) and _skeleton.is_inside_tree()


## Ties the straps to Henry's skeleton, jacket and pack. Drawn when the skeleton's final pose is
## ready (after every modifier), the same pose the jacket is skinned with.
func setup(skeleton: Skeleton3D, pack: PackRig) -> void:
	_skeleton = skeleton
	_pack = pack
	_material.set_shader_parameter(&"strap_colour", colour)
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
	_add_arm_clearance(skeleton)
	if data.has("free_lift"):
		for side: int in 2:
			for run: int in 2:
				_free_lift[side][run] = PackedFloat32Array(data["free_lift"][side][run])
	if is_inside_tree():
		_sync_skeleton_updates(true)


## The upper arms are turned off the straps under them (ArmStrapClearance), before the jacket springs swing.
func _add_arm_clearance(skeleton: Skeleton3D) -> void:
	var clearance := ArmStrapClearance.new()
	clearance.name = "ArmStrapClearance"
	skeleton.add_child(clearance)
	var springs: Node = skeleton.get_node_or_null(^"JacketSprings")
	if springs != null:
		skeleton.move_child(clearance, springs.get_index())
	clearance.straps = self
	clearance.measure_sleeves(_jacket)


## Whether the pack is on Henry's back (the straps lie on the jacket).
func is_worn() -> bool:
	return _pressed


## The strap's surface points from the last drawn frames, world space: each frame's centre and edges on top.
func strap_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for slot: int in 2:
		for i: int in _frame_counts[slot]:
			var k: int = slot * MAX_FRAMES + i
			var c := Vector3(_centres[k].x, _centres[k].y, _centres[k].z)
			var x := Vector3(_across[k].x, _across[k].y, _across[k].z) * _across[k].w
			var n := Vector3(_outs[k].x, _outs[k].y, _outs[k].z) * THICK_M
			out.append_array([c + n, c - x + n, c + x + n])
	return out


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
	# Skeleton3D can still issue a queued skeleton_updated during scene teardown.
	# Never query global transforms of detached/invalid nodes.
	if not _can_skin():
		return
	global_transform = Transform3D.IDENTITY
	_frame_counts = [0, 0]
	var shown: bool = _pack != null and _pack.get_canvas() != null and _pack.is_visible_in_tree()
	var worn: bool = shown and _pack.get_parent() is BoneAttachment3D
	if worn != _pressed:
		_set_press(worn)
	if shown:
		var step: float = clampf(_delta, 0.0, 0.05)
		var changed: bool = worn != _worn_last
		_worn_last = worn
		_bind_xf.clear()
		for side: int in range(2):
			if worn:
				_draw_worn(side)
			else:
				_draw_limp(side, step, changed)
	_material.set_shader_parameter(&"frame_centre", _centres)
	_material.set_shader_parameter(&"frame_across", _across)
	_material.set_shader_parameter(&"frame_out", _outs)
	_material.set_shader_parameter(&"frame_count_0", _frame_counts[0])
	_material.set_shader_parameter(&"frame_count_1", _frame_counts[1])


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
	if not _can_skin():
		return []
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
	_free_run(band, _pack_end(PACK_TOP, rows[0][1]), pack_out, rows[0], true, _free_lift[side][0])
	band.append_array(rows.slice(1, rows.size() - 1))
	_free_run(band, _pack_end(PACK_BOTTOM, rows[rows.size() - 1][1]), pack_out, rows[rows.size() - 1], false, _free_lift[side][1])
	return {"band": band, "rows": rows}


func _draw_worn(side: int) -> void:
	var worn: Dictionary = worn_band(side)
	if not worn.is_empty():
		_bend(worn["band"], true)


## A cinched run between the pack (`at`, its face normal `face_out`) and a row on the jacket, as wide as that
## row, each sample bowed out by `lift` over the cloth it would cut; `into` runs pack to body, else body to pack.
func _free_run(band: Array, at: Vector3, face_out: Vector3, row: Array, into: bool, lift: PackedFloat32Array) -> void:
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
		if k < lift.size():
			centre += n * lift[k]
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
	_bend(band, false)


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


## Hands one path (rows [left, centre, right, outward normal, thickness]) to the strap mesh on its side of the
## pack: frames with t along the strap; worn, the pad's end lands on the path's last padded row.
func _bend(rows: Array, worn: bool) -> void:
	var count: int = mini(rows.size(), MAX_FRAMES)
	if count < 2:
		return
	var mid: Vector3 = (rows[count / 2] as Array)[1]
	## The school pack's +X strap is worn on the pack's -X side (its back faces -Y, ours -Z).
	var slot: int = 0 if (_pack.get_canvas().global_transform.affine_inverse() * mid).x < 0.0 else 1
	var arc := PackedFloat32Array([0.0])
	for i: int in range(1, count):
		arc.append(arc[i - 1] + ((rows[i][1] as Vector3) - (rows[i - 1][1] as Vector3)).length())
	var total: float = maxf(arc[count - 1], 0.0001)
	var pad_last: int = -1
	if worn:
		for i: int in count:
			if float(rows[i][4]) > (WEBBING_M + THICK_M) * 0.5:
				pad_last = i
	var pad_at: float = arc[pad_last] if pad_last > 0 else 0.0
	var pad_end: float = _pad_end[slot]
	for i: int in count:
		var row: Array = rows[i]
		var t: float = arc[i] / total
		if pad_last > 0 and pad_last < count - 1:
			t = arc[i] / pad_at * pad_end if arc[i] <= pad_at else pad_end + (arc[i] - pad_at) / (total - pad_at) * (1.0 - pad_end)
		var centre: Vector3 = row[1]
		var out: Vector3 = row[3]
		var along: Vector3 = (rows[mini(i + 1, count - 1)][1] as Vector3) - (rows[maxi(i - 1, 0)][1] as Vector3)
		var across: Vector3 = along.cross(out).normalized()
		var chord: Vector3 = ((row[0] as Vector3) + (row[2] as Vector3)) * 0.5
		var k: int = slot * MAX_FRAMES + i
		_centres[k] = Vector4(centre.x, centre.y, centre.z, t)
		_across[k] = Vector4(across.x, across.y, across.z, (row[2] as Vector3).distance_to(row[0]) * 0.5)
		_outs[k] = Vector4(out.x, out.y, out.z, (centre - chord).dot(out))
	_frame_counts[slot] = count


## The bent strap's vertices this frame (every `stride`-th): world position and, in w, the share along the
## strap (0 at the pack's top). The shader's bend on the CPU, for measuring.
func bent_vertices(stride: int = 1) -> PackedVector4Array:
	var out := PackedVector4Array()
	var arrays: Array = _mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tags: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	for v: int in range(0, verts.size(), stride):
		var slot: int = 1 if tags[v].x > 0.5 else 0
		var count: int = _frame_counts[slot]
		if count < 2:
			continue
		var base: int = slot * MAX_FRAMES
		var t: float = clampf(verts[v].z / _length[slot], 0.0, 1.0)
		var i: int = 0
		for k: int in range(1, count - 1):
			if _centres[base + k].w > t:
				break
			i = k
		var c0: Vector4 = _centres[base + i]
		var c1: Vector4 = _centres[base + i + 1]
		var f: float = clampf((t - c0.w) / maxf(c1.w - c0.w, 0.000001), 0.0, 1.0)
		var a: Vector4 = _across[base + i].lerp(_across[base + i + 1], f)
		var o: Vector4 = _outs[base + i].lerp(_outs[base + i + 1], f)
		var along: Vector3 = Vector3(c1.x - c0.x, c1.y - c0.y, c1.z - c0.z).normalized()
		var out_dir: Vector3 = Vector3(o.x, o.y, o.z)
		out_dir = (out_dir - along * out_dir.dot(along)).normalized()
		var across: Vector3 = along.cross(out_dir)
		var padness: float = 1.0 - smoothstep(_pad_end[slot] - 0.05, _pad_end[slot], t)
		var x: float = verts[v].x * lerpf(1.0, a.w / PAD_HALF_M, padness)
		var r: float = x / maxf(a.w, 0.005)
		var centre: Vector3 = Vector3(c0.x, c0.y, c0.z).lerp(Vector3(c1.x, c1.y, c1.z), f)
		var p: Vector3 = centre + across * x + out_dir * (verts[v].y + GAP_M - o.w * minf(r * r, 1.5))
		out.append(Vector4(p.x, p.y, p.z, t))
	return out


## Both straightened straps in one surface; UV2.x tells the shader which strap (path slot) a vertex is on.
func _build_mesh() -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STRAP_INFO))
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	var keys: Array[int] = [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]
	var empty: Array = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	for j: int in keys.size():
		merged[keys[j]] = empty[j]
	for slot: int in 2:
		_length[slot] = float(info[STRAP_TAGS[slot]]["length_m"])
		_pad_end[slot] = float(info[STRAP_TAGS[slot]]["pad_end"])
		var scene: Node = (load(STRAP_MESHES[slot]) as PackedScene).instantiate()
		var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var arrays: Array = source.mesh.surface_get_arrays(0)
		scene.free()
		var base: int = (merged[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tag := PackedVector2Array()
		tag.resize(verts.size())
		tag.fill(Vector2(float(slot), 0.0))
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i: int in indices.size():
			indices[i] += base
		## Packed arrays are values: append into the merged copy and store it back.
		for pair: Array in [[Mesh.ARRAY_VERTEX, verts], [Mesh.ARRAY_NORMAL, arrays[Mesh.ARRAY_NORMAL]], [Mesh.ARRAY_TANGENT, arrays[Mesh.ARRAY_TANGENT]],
				[Mesh.ARRAY_TEX_UV, arrays[Mesh.ARRAY_TEX_UV]], [Mesh.ARRAY_TEX_UV2, tag], [Mesh.ARRAY_INDEX, indices]]:
			var into: Variant = merged[pair[0]]
			into.append_array(pair[1])
			merged[pair[0]] = into
	_material.set_shader_parameter(&"strap_length_0", _length[0])
	_material.set_shader_parameter(&"strap_length_1", _length[1])
	_material.set_shader_parameter(&"pad_end_0", _pad_end[0])
	_material.set_shader_parameter(&"pad_end_1", _pad_end[1])
	_material.set_shader_parameter(&"pad_half", PAD_HALF_M)
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	_mesh.surface_set_material(0, _material)
	## Its vertices are placed by the shader along paths anywhere in the world.
	_mesh.custom_aabb = AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)

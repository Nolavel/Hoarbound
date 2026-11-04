class_name PackStraps
extends Node3D

## The main compartment held by straps, not physics (3D inventory): three straps run across the back wall, one
## per tier of the compartment's height. An item goes into the lowest tier with room, standing against the back
## wall beside the last one; when a tier's first layer is full, the next layer stands in front of it while the
## depth allows. Each tier's strap is fixed to both side walls; it lies on the back wall empty and draws out
## round the front of what it holds, buckled in the middle. All sizes are the items'
## real outlines in metres; what fits nowhere is refused. Pack space (BackpackModel): x across, y up, z out.

signal refused(item_id: StringName, reason: StringName)

## Tiers (one strap each) the compartment's height is split into.
const TIERS: int = 3
## Room kept clear of the canvas lining on every side, and between neighbouring items, metres.
const CLEAR_M: float = 0.004
const GAP_M: float = 0.004
## Strap webbing: width, thickness, and how far it stands off what it holds, metres.
const STRAP_W_M: float = 0.028
const STRAP_T_M: float = 0.004
const STRAP_OFF_M: float = 0.003
## Buckle: size, and its tail hanging below it, metres.
const BUCKLE: Vector3 = Vector3(0.042, 0.036, 0.012)
const TAIL: Vector2 = Vector2(0.022, 0.07)
const WEBBING: Color = Color(0.09, 0.09, 0.1)
const METAL: Color = Color(0.42, 0.42, 0.44)
## An item comes in over the mouth and settles into its place, then the strap pulls in, seconds.
const DROP_S: float = 0.35
const CINCH_S: float = 0.22
const TOO_BIG: StringName = &"INVENTORY_TOO_BIG"
const NO_ROOM: StringName = &"INVENTORY_NO_ROOM"

## Per item: {"id", "visual": Node3D, "box": AABB (its place, pack space), "tier": int}.
var items: Array[Dictionary] = []
var model: BackpackModel
## Per tier: the strap's node (moves along z) and where it rests when the tier is empty.
var _straps: Array[Node3D] = []


func setup(pack: BackpackModel) -> void:
	model = pack
	for tier: int in TIERS:
		_straps.append(_build_strap(tier))


## The compartment's usable inside, pack space. Across, it keeps a canvas bulge's reach off the side walls: the
## straps hold things to the back wall, and the side walls (with the pockets sewn on them) stay flat.
static func room() -> AABB:
	var inner: Vector3 = BackpackModel.BODY * 0.5 - Vector3.ONE * (BackpackModel.CANVAS_LINING_M + CLEAR_M)
	inner.x = BackpackModel.BODY.x * 0.5 - BackpackModel.CANVAS_LINING_M - BackpackModel.CANVAS_SOFT_M
	var centre := Vector3(0.0, BackpackModel.BODY.y * 0.5, BackpackModel.BODY.z * 0.5)
	return AABB(centre - inner, inner * 2.0)


static func tier_height() -> float:
	return room().size.y / float(TIERS)


## Lays out `ids` in order (the pack's contents); what is already in keeps its visual, new ones drop in.
## Returns the ids that fit nowhere.
func sync(ids: Array[StringName]) -> Array[StringName]:
	var old: Array[Dictionary] = items.duplicate()
	items.clear()
	var left_out: Array[StringName] = []
	var plan: Array = _plan(ids, left_out)
	for entry: Array in plan:
		var id: StringName = entry[0]
		var reuse: int = -1
		for k: int in old.size():
			if old[k]["id"] == id:
				reuse = k
				break
		var visual: Node3D
		var fresh: bool = reuse < 0
		if fresh:
			visual = SurvivalItemVisual.make(id)
			add_child(visual)
		else:
			visual = old[reuse]["visual"]
			old.remove_at(reuse)
		var place: Transform3D = entry[2]
		if fresh:
			visual.transform = Transform3D(place.basis, place.origin + Vector3(0.0, 0.12, 0.22))
			var tween: Tween = visual.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(visual, ^"transform", place, DROP_S)
		else:
			visual.transform = place
		items.append({"id": id, "visual": visual, "box": entry[1], "tier": entry[3]})
	for gone: Dictionary in old:
		(gone["visual"] as Node3D).queue_free()
	_cinch(plan.size() > 0)
	model.set_interior_boxes(boxes())
	return left_out


## Why `item_id` could not go in beside what is in now (TOO_BIG: no tier takes its outline in any turn;
## NO_ROOM: no tier has room left), or &"".
func refusal(item_id: StringName) -> StringName:
	var size: Vector3 = _outline(item_id).size
	if _turns(size).is_empty():
		return TOO_BIG
	var ids: Array[StringName] = []
	for item: Dictionary in items:
		ids.append(item["id"])
	ids.append(item_id)
	var left_out: Array[StringName] = []
	_plan(ids, left_out)
	return NO_ROOM if left_out.has(item_id) else &""


## Adds `item_id` after what is in; false with refused(...) when it does not fit.
func add(item_id: StringName) -> bool:
	var why: StringName = refusal(item_id)
	if why != &"":
		refused.emit(item_id, why)
		return false
	var ids: Array[StringName] = []
	for item: Dictionary in items:
		ids.append(item["id"])
	ids.append(item_id)
	sync(ids)
	return true


## The item a pack-space segment from `from` to `to` meets first (on its place's box), or -1.
func pick(from: Vector3, to: Vector3) -> int:
	var best: float = INF
	var found: int = -1
	for i: int in items.size():
		var hit: Variant = (items[i]["box"] as AABB).intersects_segment(from, to)
		if hit != null and from.distance_to(hit) < best:
			best = from.distance_to(hit)
			found = i
	return found


## Hides item i's visual while a hand carries it out (shown again with false).
func set_lifted(i: int, lifted: bool) -> void:
	if i >= 0 and i < items.size():
		(items[i]["visual"] as Node3D).visible = not lifted


func boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for item: Dictionary in items:
		out.append(item["box"])
	return out


## Places for `ids`, in order: [[id, box, transform, tier], ...]; what fits nowhere goes to `left_out`.
func _plan(ids: Array[StringName], left_out: Array[StringName]) -> Array:
	var space: AABB = room()
	var height: float = tier_height()
	## Per tier: layers of [z start, depth, x used].
	var tiers: Array = []
	for _t: int in TIERS:
		tiers.append([[space.position.z, 0.0, 0.0]])
	var out: Array = []
	for id: StringName in ids:
		var outline: AABB = _outline(id)
		var placed: bool = false
		for tier: int in TIERS:
			if placed:
				break
			var layers: Array = tiers[tier]
			## Beside the last one in this tier's front layer, in any turn; else a new layer in front of it.
			for fresh_layer: bool in [false, true]:
				if placed:
					break
				var layer: Array = layers[layers.size() - 1]
				var z_start: float = layer[0] + layer[1] + GAP_M if fresh_layer else layer[0]
				var x_used: float = 0.0 if fresh_layer else layer[2]
				if fresh_layer and float(layer[1]) == 0.0:
					continue
				for turn: Basis in _turns(outline.size):
					var dims: Vector3 = (turn * outline.size).abs()
					if x_used + dims.x > space.size.x or z_start + dims.z > space.end.z:
						continue
					if fresh_layer:
						layers.append([z_start, 0.0, 0.0])
						layer = layers[layers.size() - 1]
					var lo := Vector3(space.position.x + x_used, space.position.y + float(tier) * height, z_start)
					var box := AABB(lo, dims)
					layer[1] = maxf(float(layer[1]), dims.z)
					layer[2] = x_used + dims.x + GAP_M
					## The visual turned so its outline lands on the box.
					var turned: AABB = Transform3D(turn, Vector3.ZERO) * outline
					out.append([id, box, Transform3D(turn, box.position - turned.position), tier])
					placed = true
					break
		if not placed:
			left_out.append(id)
	return out


## Turns that put an item's thinnest side front to back: standing (its longest side up) first, so more fit side
## by side under a strap, then lying; only turns that fit a tier.
static func _turns(size: Vector3) -> Array[Basis]:
	var order: Array = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return size[a] < size[b])
	var out: Array[Basis] = []
	for pair: Array in [[order[1], order[2]], [order[2], order[1]]]:
		var columns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		columns[pair[0]] = Vector3.RIGHT
		columns[pair[1]] = Vector3.UP
		columns[order[0]] = Vector3.BACK
		var turn := Basis(columns[0], columns[1], columns[2])
		if turn.determinant() < 0.0:
			columns[order[0]] = Vector3.FORWARD
			turn = Basis(columns[0], columns[1], columns[2])
		var room_size: Vector3 = room().size
		var dims: Vector3 = (turn * size).abs()
		if dims.x <= room_size.x and dims.y <= tier_height() - GAP_M and dims.z <= room_size.z:
			out.append(turn)
	return out


static func _outline(id: StringName) -> AABB:
	var visual: Node3D = SurvivalItemVisual.make(id)
	var box: AABB = BackpackModel._local_bounds(visual)
	visual.free()
	return box


## Each tier's strap draws in round what it holds: [left x, right x, front z] of its contents (or flat on the
## back wall when it holds nothing), eased there after the item lands.
func _cinch(animate: bool) -> void:
	var space: AABB = room()
	var shapes: Array[Vector3] = []
	for _t: int in TIERS:
		shapes.append(Vector3(0.0, 0.0, space.position.z))
	var spans: Array = []
	for _t: int in TIERS:
		spans.append([INF, -INF, space.position.z])
	for item: Dictionary in items:
		var box: AABB = item["box"]
		var span: Array = spans[int(item["tier"])]
		span[0] = minf(float(span[0]), box.position.x)
		span[1] = maxf(float(span[1]), box.end.x)
		span[2] = maxf(float(span[2]), box.end.z)
	for tier: int in TIERS:
		var span: Array = spans[tier]
		var want := Vector3(0.0, 0.0, space.position.z) if float(span[0]) == INF else Vector3(span[0], span[1], span[2])
		var strap: Node3D = _straps[tier]
		var now: Vector3 = strap.get_meta(&"shape", Vector3(0.0, 0.0, space.position.z))
		if animate and now.distance_to(want) > 0.001:
			var tween: Tween = strap.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_interval(DROP_S)
			tween.tween_method(_shape_strap.bind(strap), now, want, CINCH_S)
		else:
			_shape_strap(want, strap)


## The strap's webbing along its path: fixed to both side walls by the back wall, out round the front of its
## contents [left x, right x, front z] (a flat run on the back wall when left == right), the buckle on the
## front run's middle.
func _shape_strap(shape: Vector3, strap: Node3D) -> void:
	strap.set_meta(&"shape", shape)
	var wall: float = BackpackModel.BODY.x * 0.5 - BackpackModel.CANVAS_LINING_M
	var back: float = room().position.z + STRAP_T_M * 0.5
	var front: float = maxf(shape.z, room().position.z) + STRAP_OFF_M + STRAP_T_M * 0.5
	var path: Array[Vector3] = [Vector3(-wall, 0.0, back)]
	if shape.x < shape.y:
		path.append(Vector3(shape.x - STRAP_OFF_M, 0.0, front))
		path.append(Vector3(shape.y + STRAP_OFF_M, 0.0, front))
	path.append(Vector3(wall, 0.0, back))
	var webbing := strap.get_node(^"Webbing") as MeshInstance3D
	webbing.mesh = _band(path)
	var middle: Vector3 = (path[1] + path[path.size() - 2]) * 0.5 if path.size() > 2 else Vector3(0.0, 0.0, back)
	(strap.get_node(^"Buckle") as Node3D).position = middle + Vector3(0.0, 0.0, BUCKLE.z * 0.5)
	(strap.get_node(^"Tail") as Node3D).position = middle + Vector3(BUCKLE.x * 0.5 + 0.004, -TAIL.y * 0.5, STRAP_T_M)


## A flat band STRAP_W_M tall along `path` (in the strap's plane), both faces drawn.
static func _band(path: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Vector3(0.0, STRAP_W_M * 0.5, 0.0)
	for k: int in path.size() - 1:
		var a: Vector3 = path[k]
		var b: Vector3 = path[k + 1]
		for tri: Array in [[a - half, b - half, b + half], [a - half, b + half, a + half]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _build_strap(tier: int) -> Node3D:
	var space: AABB = room()
	var strap := Node3D.new()
	strap.name = "Strap%d" % tier
	strap.position = Vector3(0.0, space.position.y + (float(tier) + 0.5) * tier_height(), 0.0)
	add_child(strap)
	var webbing := MeshInstance3D.new()
	webbing.name = "Webbing"
	webbing.material_override = _material(WEBBING)
	(webbing.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	strap.add_child(webbing)
	_box(strap, BUCKLE, Vector3.ZERO, METAL).name = "Buckle"
	_box(strap, Vector3(TAIL.x, TAIL.y, STRAP_T_M), Vector3.ZERO, WEBBING).name = "Tail"
	_shape_strap(Vector3(0.0, 0.0, space.position.z), strap)
	return strap


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour)
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.4 if colour == METAL else 0.8
	material.metallic = 0.6 if colour == METAL else 0.0
	return material

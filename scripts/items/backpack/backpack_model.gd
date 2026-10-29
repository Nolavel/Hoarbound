class_name BackpackModel
extends Node3D

## A front-loading backpack (#260): a canvas shell, a front panel on a two-slider zip that folds out
## where the sliders have passed, slots for what it carries, a pocket and a carabiner either side and a
## bedroll under it. The canvas takes its shape from the contents (backpack_canvas.gdshader).
## Pack space: origin at the bottom of the back face, +Y up, +Z out to the front, +X to the right.

signal opened_changed(open: bool)

const CANVAS_SHADER: Shader = preload("res://shaders/items/backpack_canvas.gdshader")
const MAX_ITEMS: int = 16
## Outer size of the main body (width, height, depth) and the rounding of its edges, metres.
const BODY: Vector3 = Vector3(0.34, 0.52, 0.22)
const ROUND_M: float = 0.06
## Grid steps along each face; enough vertices for a can or a flask to show as a bulge.
const STEPS: Vector3i = Vector3i(14, 26, 10)
## The open front panel hangs this far past flat, degrees.
const OPEN_DEG: float = 104.0
## Panel swing and droop springs: frequency (Hz) and damping (under 1 overshoots a little).
const SWING_HZ: float = 1.6
const SWING_DAMPING: float = 0.62
const DROOP_HZ: float = 2.2
const DROOP_DAMPING: float = 0.35
## How far the free top of the panel sags when it lies flat.
const DROOP_FLAT_M: float = 0.07
## Litres the main body holds when full: fill is the share the contents take up.
const CAPACITY_L: float = 24.0
const FILL_HZ: float = 1.2
## Slots: name -> [centre, half size] in pack space. Shelf on top, three columns below.
const SLOTS: Dictionary = {
	&"shelf": [Vector3(0.0, 0.42, 0.11), Vector3(0.145, 0.055, 0.08)],
	&"low_left": [Vector3(-0.09, 0.13, 0.11), Vector3(0.055, 0.11, 0.08)],
	&"low_mid": [Vector3(0.0, 0.17, 0.11), Vector3(0.04, 0.15, 0.08)],
	&"low_right": [Vector3(0.095, 0.17, 0.11), Vector3(0.05, 0.15, 0.08)],
	&"side_left": [Vector3(-POCKET_X - POCKET_SLOT_OUT_M, 0.15, 0.11), Vector3(0.035, 0.11, 0.06)],
	&"side_right": [Vector3(POCKET_X + POCKET_SLOT_OUT_M, 0.15, 0.11), Vector3(0.035, 0.11, 0.06)],
}
## Which faces of a rounded box to build: every one, all but the front, or the front alone.
const FACES_ALL: int = 0
const FACES_SHELL: int = 1
const FACES_FRONT: int = 2
const FACES_OPEN_TOP: int = 3
## Side pockets: open-topped pouches either side, sized for a bottle that stands out of them.
const POCKET_X: float = 0.205
## What stands in a pocket sits this far outboard of its middle, clear of the body's wall.
const POCKET_SLOT_OUT_M: float = 0.01
const POCKET_HALF: Vector3 = Vector3(0.04, 0.07, 0.065)
const CANVAS: Color = Color(0.30, 0.32, 0.34)
const STRAP: Color = Color(0.22, 0.23, 0.25)
## Zip: each slider runs from the top centre to a top corner and down its side to the bottom rounding
## (ZIP_FULL_M = BODY.x / 2 + BODY.y - ROUND_M), at ZIP_SPEED m/s.
const ZIP_FULL_M: float = 0.63
const ZIP_SPEED: float = 0.9
const SLIDER_HALF_M: float = 0.013
## The panel's top lifts this far between sliders still on the top edge; the walls by the open
## seam give this far once the panel folds out.
const MOUTH_M: float = 0.022
const SIDE_GIVE_M: float = 0.014
## The empty slump in backpack_canvas.gdshader, for parts that ride on the canvas.
const SLUMP_TOP_M: float = 0.07
const SLUMP_WALL_M: float = 0.018
## Strap loop at the rim of each side pocket's outer face, and the carabiner's pivot just above it so
## what hangs ends near the pack's bottom (x for the +X side; the face is at POCKET_X + POCKET_HALF.x).
const LOOP_AT: Vector3 = Vector3(0.251, 0.182, 0.11)
const CARABINER_AT: Vector3 = Vector3(0.262, 0.198, 0.11)
const ZIP_METAL: Color = Color(0.16, 0.16, 0.17)
## Loose contents: their floor inside the main body and the gap they keep from its walls.
const LOOSE_FLOOR_M: float = 0.02
const LOOSE_MARGIN_M: float = 0.03
## The grab handle's foot on the top, behind its middle where the top is flat (pack space, at rest).
const HANDLE_AT: Vector3 = Vector3(0.0, 0.514, 0.03)
## The bedroll lies across the top in front of the handle (pack space at rest: where it rests).
const BEDROLL_AT: Vector3 = Vector3(0.0, 0.52, 0.14)
const BEDROLL_RADIUS_M: float = 0.062
## The maker's patch on the front panel, as the panel's UV rect (up its height, across its width).
const PATCH_RECT: Vector4 = Vector4(0.55, 0.33, 0.67, 0.67)
## How far inside the mug handle's outer edge a carabiner rod rests, metres.
const MUG_HANDLE_GRIP_M: float = 0.012
## What is clipped on swings slower than the carabiner (longer, heavier) and wider, Hz/degrees.
const CLIPPED_SWING_HZ: float = 1.3
const CLIPPED_SWING_DAMPING: float = 0.12
const CLIPPED_MAX_SWING_DEG: float = 75.0
const BEDROLL: Color = Color(0.33, 0.27, 0.18)

var _shell_material: ShaderMaterial
var _panel_material: ShaderMaterial
var _pocket_materials: Array[ShaderMaterial] = []
var _strap_material: ShaderMaterial
var _hinge: Node3D
var _hinge_at: Vector3 = Vector3.ZERO
var _panel: MeshInstance3D
var _sliders: Array[Node3D] = []
var _tabs: Array[Node3D] = []
var _carabiners: Array[Carabiner] = []
var _zip: float = 0.0
var _zip_target: float = 0.0
var _hung: Array[Node3D] = []
var _main_count: int = 0
var _handle: Node3D
var _bedroll: Node3D
var _items: Array[Dictionary] = []
var _contents: Node3D
var _open: bool = false
var _swing: float = 0.0
var _swing_speed: float = 0.0
var _droop: float = 0.0
var _droop_speed: float = 0.0
var _fill: float = 0.0
var _fill_speed: float = 0.0
var _open_deg: float = 0.0
## Fill from the carried weight (0..1) when the pack is worn; below 0 the slotted items decide.
var load_fill: float = -1.0
## Render layers given to what is clipped on a carabiner (the worn pack draws in the portrait too).
var layers_for_contents: int = 1


func _ready() -> void:
	build()


## Builds the shell, panel, pocket, bedroll and straps. Safe to call once.
func build() -> void:
	if _hinge != null:
		return
	_shell_material = _canvas_material(Vector4.ZERO)
	_shell_material.set_shader_parameter(&"zipper_on", true)
	_panel_material = _canvas_material(Vector4(0.1, 0.15, 0.55, 0.85))
	_panel_material.set_shader_parameter(&"zipper_on", true)
	_panel_material.set_shader_parameter(&"is_panel", true)
	_panel_material.set_shader_parameter(&"patch_rect", PATCH_RECT)
	## Each side pocket is its own cloth: flat on the wall when empty, wrapped round what it holds.
	for side: float in [-1.0, 1.0]:
		var pocket: ShaderMaterial = _canvas_material(Vector4.ZERO)
		pocket.set_shader_parameter(&"is_pocket", true)
		pocket.set_shader_parameter(&"pocket_wall_x", side * BODY.x * 0.5)
		pocket.set_shader_parameter(&"lining_m", 0.004)
		_pocket_materials.append(pocket)
	_strap_material = _canvas_material(Vector4.ZERO)
	_strap_material.set_shader_parameter(&"canvas_colour", STRAP)
	_strap_material.set_shader_parameter(&"lining_colour", STRAP)
	_strap_material.set_shader_parameter(&"roughness_value", 0.7)
	_strap_material.set_shader_parameter(&"leather_on", false)
	## Shell and panel are one rounded box split at the front: each owns half of the front edge,
	## so the closed panel meets the shell with no seam.
	var centre := Vector3(0.0, BODY.y * 0.5, BODY.z * 0.5)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_SHELL, true)
	shell.material_override = _shell_material
	add_child(shell)
	var panel_mesh: ArrayMesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_FRONT, true)
	_hinge_at = _hinge_point(panel_mesh)
	## The panel folds in the shader round the line the sliders reached; the node stays put.
	_hinge = Node3D.new()
	_hinge.name = "PanelHinge"
	_hinge.position = _hinge_at
	add_child(_hinge)
	_panel = MeshInstance3D.new()
	_panel.name = "FrontPanel"
	_panel.mesh = panel_mesh
	_panel.position = -_hinge_at
	_panel.material_override = _panel_material
	_hinge.add_child(_panel)
	_panel_material.set_shader_parameter(&"bend_z", _hinge_at.z)
	_panel_material.set_shader_parameter(&"top_y", BODY.y)
	for side: float in [-1.0, 1.0]:
		var pocket := MeshInstance3D.new()
		pocket.name = "SidePocketLeft" if side < 0.0 else "SidePocketRight"
		pocket.mesh = _rounded_box(POCKET_HALF, Vector3(side * POCKET_X, POCKET_HALF.y + 0.03, BODY.z * 0.5), 0.03, Vector3i(8, 14, 12), FACES_OPEN_TOP)
		pocket.material_override = _pocket_materials[0 if side < 0.0 else 1]
		add_child(pocket)
	_add_shelf()
	_add_bedroll()
	_add_straps()
	_add_sliders()
	_add_carabiners()
	_contents = Node3D.new()
	_contents.name = "Contents"
	add_child(_contents)
	_refresh_proxies()


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	set_open_degrees(OPEN_DEG if open else 0.0)


## Fully unzips and folds the panel to degrees (0 closes it); see set_opening().
func set_open_degrees(degrees: float) -> void:
	set_opening(ZIP_FULL_M if degrees > 0.0 else 0.0, degrees)


## Each slider runs zip_m from the top centre (0 closed, ZIP_FULL_M at the bottom), and the panel
## folds out by degrees round the line they reached. Closing folds it back before the sliders return.
func set_opening(zip_m: float, degrees: float) -> void:
	_zip_target = clampf(zip_m, 0.0, ZIP_FULL_M)
	_open_deg = clampf(degrees, 0.0, OPEN_DEG) if _zip_target > 0.0 else 0.0
	var open: bool = _zip_target > 0.0
	if open != _open:
		_open = open
		opened_changed.emit(open)


## How far each slider has run from the top centre, metres.
func get_zip() -> float:
	return _zip


## The panel's current fold, degrees.
func get_fold_degrees() -> float:
	return rad_to_deg(_swing)


## The carabiner on the left (0) or right (1) side, for things clipped on later.
func get_carabiner(index: int) -> Carabiner:
	build()
	return _carabiners[index] if index >= 0 and index < _carabiners.size() else null


## Puts item_id in the named slot (see SLOTS); its proxy shapes the canvas. False if taken.
func add_item(item_id: StringName, slot: StringName, along: float = 0.0) -> bool:
	if not SLOTS.has(slot) or _items.size() >= MAX_ITEMS:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if box.size == Vector3.ZERO:
		return false
	var rest: Array = SLOTS[slot]
	var centre: Vector3 = rest[0]
	var half: Vector3 = rest[1]
	## Stand it on the slot floor; on the shelf it lies along X; in a side pocket its flat side
	## lies against the pack's wall.
	var basis := Basis(Vector3.FORWARD, PI * 0.5) if slot == &"shelf" and box.size.y > box.size.x else Basis()
	if String(slot).begins_with("side_") and box.size.x > box.size.z:
		basis = Basis(Vector3.UP, PI * 0.5)
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * box
	var at := Vector3(centre.x + along, centre.y - half.y - placed.position.y, centre.z)
	visual.transform = Transform3D(basis, at)
	_contents.add_child(visual)
	_items.append({"id": item_id, "slot": slot, "node": visual, "box": Transform3D(basis, at) * box})
	_refresh_proxies()
	return true


## Drops item_id loose into the main body: a random spot and pose on the floor or on what is
## already there, the same for the same items in the same order. False when it is full.
func add_loose(item_id: StringName) -> bool:
	if _items.size() >= MAX_ITEMS:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if box.size == Vector3.ZERO:
		visual.free()
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(item_id)) + _items.size() * 7919
	## Standing, or lying on its side, at any heading.
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if rng.randf() < 0.5:
		basis = basis * Basis(Vector3.FORWARD, PI * 0.5)
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * box
	var room := Vector2(BODY.x * 0.5 - LOOSE_MARGIN_M, BODY.z - LOOSE_MARGIN_M)
	var best := Vector3.ZERO
	var best_y: float = INF
	for _try: int in range(12):
		var x: float = rng.randf_range(-room.x - placed.position.x, room.x - placed.end.x)
		var z: float = rng.randf_range(LOOSE_MARGIN_M - placed.position.z, room.y - placed.end.z)
		## It settles on the floor or on top of whatever it lands over.
		var floor_y: float = LOOSE_FLOOR_M
		var footprint := AABB(Vector3(x, 0.0, z) + placed.position * Vector3(1, 0, 1), Vector3(placed.size.x, 10.0, placed.size.z))
		for item: Dictionary in _items:
			var other: AABB = item["box"]
			if footprint.intersects(other):
				floor_y = maxf(floor_y, other.end.y)
		if floor_y < best_y:
			best_y = floor_y
			best = Vector3(x, floor_y - placed.position.y, z)
	visual.transform = Transform3D(basis, best)
	_contents.add_child(visual)
	_items.append({"id": item_id, "slot": &"", "node": visual, "box": Transform3D(basis, best) * box})
	_refresh_proxies()
	return true


## Clips item_id onto a carabiner (0 left, 1 right). It swings on the carabiner's rod, which swings
## in its loop: a double pendulum. A mug hangs by its handle (authored towards +X), anything else
## by its top.
func hang_item(item_id: StringName, carabiner_index: int) -> bool:
	var carabiner: Carabiner = get_carabiner(carabiner_index)
	if carabiner == null:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if String(item_id).contains("mug"):
		## The rod runs through the handle's opening: just inside its outer edge, at mid height.
		var handle := Vector3(box.end.x - MUG_HANDLE_GRIP_M, box.get_center().y, box.get_center().z)
		var turn := Basis(Vector3.BACK, PI * 0.5)
		visual.transform = Transform3D(turn, -(turn * handle))
	else:
		visual.position = Vector3(-box.get_center().x, -box.end.y, -box.get_center().z)
	var swing := PendulumHang.new()
	swing.name = "Clipped"
	swing.swing_hz = CLIPPED_SWING_HZ
	swing.swing_damping = CLIPPED_SWING_DAMPING
	swing.max_swing_deg = CLIPPED_MAX_SWING_DEG
	carabiner.get_hang_point().add_child(swing)
	swing.add_child(visual)
	for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			(mesh as MeshInstance3D).layers = layers_for_contents
	_hung.append(visual)
	return true


func clear_items() -> void:
	for item: Dictionary in _items:
		(item["node"] as Node).queue_free()
	_items.clear()
	for visual: Node3D in _hung:
		visual.get_parent().queue_free()
	_hung.clear()
	_refresh_proxies()


## Where the canvas moves a pack-space point p (outward normal n) as it slumps empty.
func canvas_point(p: Vector3, n: Vector3) -> Vector3:
	return _on_canvas(p, n, 0.0)


## Share of the main body the contents fill, 0..1 (the target the canvas springs toward).
func get_fill_target() -> float:
	if load_fill >= 0.0:
		return clampf(load_fill, 0.0, 1.0)
	var litres: float = 0.0
	for item: Dictionary in _items:
		var size: Vector3 = (item["box"] as AABB).size
		litres += size.x * size.y * size.z * 1000.0 * 1.6  # packed items leave air round them
	return clampf(litres / CAPACITY_L, 0.0, 1.0)


func _process(delta: float) -> void:
	var half_w: float = BODY.x * 0.5
	var swing_target: float = deg_to_rad(_open_deg)
	if _zip_target >= _zip:
		_zip = move_toward(_zip, _zip_target, ZIP_SPEED * delta)
		## The panel folds out only as far as the sliders have freed its sides.
		var side_run: float = _zip_target - half_w
		swing_target *= clampf((_zip - half_w) / side_run, 0.0, 1.0) if side_run > 0.0 else 0.0
	elif _swing <= swing_target + deg_to_rad(4.0):
		_zip = move_toward(_zip, _zip_target, ZIP_SPEED * delta)
	var omega: float = TAU * SWING_HZ
	_swing_speed += (omega * omega * (swing_target - _swing) - 2.0 * SWING_DAMPING * omega * _swing_speed) * delta
	_swing += _swing_speed * delta
	var seam: Array = _seam_point(maxf(_zip, half_w + 0.001), 1.0)
	var bend_y: float = BODY.y + 1.0
	if _zip > half_w:
		bend_y = lerpf((seam[0] as Vector3).y, _hinge_at.y, smoothstep(ZIP_FULL_M - 0.1, ZIP_FULL_M, _zip))
	_panel_material.set_shader_parameter(&"bend_y", bend_y)
	_panel_material.set_shader_parameter(&"bend_angle", _swing)
	_panel_material.set_shader_parameter(&"mouth_m", MOUTH_M * clampf(_zip / half_w, 0.0, 1.0))
	var give: float = SIDE_GIVE_M * clampf(_swing / deg_to_rad(30.0), 0.0, 1.0)
	_shell_material.set_shader_parameter(&"side_give_m", give)
	for material: ShaderMaterial in [_shell_material, _panel_material]:
		material.set_shader_parameter(&"zip_s", _zip)
	_place_sliders(give)
	_place_carabiners()
	## The handle sits where the canvas top is now, however far it has slumped.
	_handle.position = _on_canvas(HANDLE_AT, Vector3.UP, 0.0)
	_bedroll.position = _on_canvas(BEDROLL_AT, Vector3.UP, 0.0) + Vector3(0.0, BEDROLL_RADIUS_M - 0.008, 0.0)
	## The free edge sags most with the panel flat; the swing's speed flicks it the other way.
	var droop_target: float = DROOP_FLAT_M * sin(clampf(_swing, 0.0, PI))
	var droop_omega: float = TAU * DROOP_HZ
	_droop_speed += (droop_omega * droop_omega * (droop_target - _droop) - 2.0 * DROOP_DAMPING * droop_omega * _droop_speed) * delta
	_droop += _droop_speed * delta
	var fill_omega: float = TAU * FILL_HZ
	_fill_speed += (fill_omega * fill_omega * (get_fill_target() - _fill) - 2.0 * 0.8 * fill_omega * _fill_speed) * delta
	_fill += _fill_speed * delta
	var panel_xf: Transform3D = global_transform.affine_inverse() * _panel.global_transform if is_inside_tree() else _hinge.transform
	_panel_material.set_shader_parameter(&"to_pack", Projection(panel_xf))
	_panel_material.set_shader_parameter(&"droop_m", _droop)
	_panel_material.set_shader_parameter(&"droop_dir", (global_basis.inverse() * Vector3.DOWN).normalized() if is_inside_tree() else Vector3.DOWN)
	## Only the closed panel holds the contents in; an open one does not bulge.
	_panel_material.set_shader_parameter(&"item_count", _main_count if _swing < 0.2 else 0)
	for material: ShaderMaterial in [_shell_material, _panel_material, _strap_material] + _pocket_materials:
		material.set_shader_parameter(&"fill", _fill)


## Item boxes the canvas wraps: what is in the main body shapes the shell, panel and straps;
## what is in a side pocket shapes only the pockets, never the wall between them.
func _refresh_proxies() -> void:
	var main: Array[AABB] = []
	var left: Array[AABB] = []
	var right: Array[AABB] = []
	for item: Dictionary in _items:
		match String(item["slot"]):
			"side_left":
				left.append(item["box"])
			"side_right":
				right.append(item["box"])
			_:
				main.append(item["box"])
	var groups: Array = [[[_shell_material, _panel_material, _strap_material], main]]
	if _pocket_materials.size() == 2:
		groups.append([[_pocket_materials[0]], left])
		groups.append([[_pocket_materials[1]], right])
	for entry: Array in groups:
		var centres: Array = []
		var halves: Array = []
		for box: AABB in entry[1]:
			centres.append(Vector4(box.get_center().x, box.get_center().y, box.get_center().z, 0.0))
			halves.append(Vector4(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5, 0.0))
		var count: int = centres.size()
		if entry[1] == main:
			_main_count = count
		while centres.size() < MAX_ITEMS:
			centres.append(Vector4(0.0, -10.0, 0.0, 0.0))
			halves.append(Vector4.ZERO)
		for material: ShaderMaterial in entry[0]:
			if material == null:
				continue
			material.set_shader_parameter(&"item_centre", centres)
			material.set_shader_parameter(&"item_half", halves)
			material.set_shader_parameter(&"item_count", count)


func _canvas_material(pocket: Vector4) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANVAS_SHADER
	material.set_shader_parameter(&"canvas_colour", CANVAS)
	material.set_shader_parameter(&"pack_height_m", BODY.y)
	material.set_shader_parameter(&"mesh_pocket", pocket)
	return material


## A box with rounded edges as a grid on each face (faces_built picks which). Every grid
## point is pulled onto the rounded surface: clamp to the inner box, then out by the radius.
static func _rounded_box(half: Vector3, centre: Vector3, radius: float, steps: Vector3i, faces_built: int, zipped: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Vector3 = half - Vector3.ONE * radius
	## Each face: its normal axis, its sign, and the two axes it spans.
	var faces: Array = [[2, -1.0, 0, 1], [2, 1.0, 1, 0], [0, -1.0, 1, 2], [0, 1.0, 2, 1], [1, -1.0, 2, 0], [1, 1.0, 0, 2]]
	for face: Array in faces:
		var axis: int = face[0]
		var sign: float = face[1]
		var front: bool = axis == 2 and sign > 0.0
		var top: bool = axis == 1 and sign > 0.0
		if (faces_built == FACES_SHELL and front) or (faces_built == FACES_FRONT and not front) \
				or (faces_built == FACES_OPEN_TOP and top):
			continue
		var u_axis: int = face[2]
		var v_axis: int = face[3]
		var nu: int = steps[u_axis]
		var nv: int = steps[v_axis]
		var grid: Array = []
		for j: int in range(nv + 1):
			var row: Array = []
			for i: int in range(nu + 1):
				var cube := Vector3.ZERO
				cube[axis] = sign
				cube[u_axis] = lerpf(-1.0, 1.0, float(i) / nu)
				cube[v_axis] = lerpf(-1.0, 1.0, float(j) / nv)
				var raw: Vector3 = cube * half
				var core: Vector3 = raw.clamp(-inner, inner)
				var out: Vector3 = raw - core
				var normal: Vector3 = out.normalized() if out.length_squared() > 0.000001 else cube.normalized()
				var zip: Vector2 = _zip_coords(raw, half, axis, sign) if zipped else Vector2(1.0, 0.0)
				row.append([centre + core + normal * radius, normal, Vector2(float(i) / nu, float(j) / nv), zip])
			grid.append(row)
		for j: int in range(nv):
			for i: int in range(nu):
				var quad: Array = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					for k: int in _front_wound(quad[tri[0]][0], quad[tri[1]][0], quad[tri[2]][0], quad[tri[0]][1], tri):
						st.set_normal(quad[k][1])
						st.set_uv(quad[k][2])
						st.set_uv2(quad[k][3])
						st.add_vertex(quad[k][0])
	st.index()
	return st.commit()


## (distance to the zip seam, run along it from the top centre) for a point raw on the box, metres.
## The seam is the panel's top and side edges; past ZIP_FULL_M and off those faces there is none.
static func _zip_coords(raw: Vector3, half: Vector3, axis: int, sign: float) -> Vector2:
	var to_side: float = half.x - absf(raw.x)
	var to_top: float = half.y - raw.y
	var run: float = absf(raw.x) if axis == 1 or (axis == 2 and to_top < to_side) else half.x + to_top
	var distance: float = 1.0
	if axis == 2 and sign > 0.0:
		distance = minf(to_side, to_top)
	elif axis == 0 or (axis == 1 and sign > 0.0):
		distance = half.z - raw.z
	return Vector2(distance if run <= ZIP_FULL_M else 1.0, run)


## A point on the zip seam `run` metres from the top centre on one side (-1 left, +1 right):
## [position, outward normal, direction of travel], in pack space with the canvas at rest.
static func _seam_point(run: float, side: float) -> Array:
	var half: Vector3 = BODY * 0.5
	var at: Vector3 = _seam_surface(run, side, half)
	var ahead: Vector3 = _seam_surface(run + 0.004, side, half)
	var behind: Vector3 = _seam_surface(run - 0.004, side, half)
	var raw := Vector3(side * minf(run, half.x), half.y - maxf(run - half.x, 0.0), half.z)
	var core: Vector3 = raw.clamp(-half + Vector3.ONE * ROUND_M, half - Vector3.ONE * ROUND_M)
	return [at, (raw - core).normalized(), (ahead - behind).normalized()]


static func _seam_surface(run: float, side: float, half: Vector3) -> Vector3:
	var raw := Vector3(side * clampf(run, 0.0, half.x), half.y - clampf(run - half.x, 0.0, BODY.y - ROUND_M), half.z)
	var core: Vector3 = raw.clamp(-half + Vector3.ONE * ROUND_M, half - Vector3.ONE * ROUND_M)
	return Vector3(0.0, half.y, half.z) + core + (raw - core).normalized() * ROUND_M


## Where the canvas moves a point at rest p (outward normal n): the empty slump plus `give` outward.
func _on_canvas(p: Vector3, n: Vector3, give: float) -> Vector3:
	var empty: float = 1.0 - clampf(_fill, 0.0, 1.0)
	var high: float = smoothstep(BODY.y * 0.45, BODY.y, p.y)
	var slump := Vector3(0.0, -SLUMP_TOP_M * high, 0.0) - n * SLUMP_WALL_M * smoothstep(0.1, 0.4, p.y / BODY.y)
	return p + slump * empty + n * give


## Where the panel's bottom edge sits (its lowest vertex), in pack space: the hinge line.
static func _hinge_point(panel: ArrayMesh) -> Vector3:
	var lowest := Vector3(0.0, INF, 0.0)
	for v: Vector3 in panel.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if v.y < lowest.y:
			lowest = v
	return Vector3(0.0, lowest.y, lowest.z)


## Triangle order that faces normal (Godot's front faces wind clockwise seen from outside).
static func _front_wound(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, tri: Array) -> Array:
	return tri if (c - a).cross(b - a).dot(normal) >= 0.0 else [tri[0], tri[2], tri[1]]


func _add_shelf() -> void:
	var shelf := MeshInstance3D.new()
	shelf.name = "Shelf"
	var board := BoxMesh.new()
	## Clear of the panel even when the empty walls cave in.
	board.size = Vector3(BODY.x - 0.08, 0.008, BODY.z - 0.08)
	shelf.mesh = board
	shelf.material_override = _plain(Color(0.2, 0.2, 0.19))
	shelf.position = Vector3(0.0, 0.355, BODY.z * 0.46)
	add_child(shelf)


## The bedroll strapped across the top, in front of the handle; placed on the canvas each frame.
## With it up there the bottom is flat leather, so the pack stands on it anywhere.
func _add_bedroll() -> void:
	_bedroll = Node3D.new()
	_bedroll.name = "Bedroll"
	add_child(_bedroll)
	var roll := MeshInstance3D.new()
	roll.name = "Roll"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = BEDROLL_RADIUS_M
	cylinder.bottom_radius = BEDROLL_RADIUS_M
	cylinder.height = BODY.x + 0.06
	cylinder.radial_segments = 20
	roll.mesh = cylinder
	roll.material_override = _plain(BEDROLL)
	roll.rotation.z = PI * 0.5
	_bedroll.add_child(roll)
	## Two straps cinch it down onto the top.
	for x: float in [-0.1, 0.1]:
		var band := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = BEDROLL_RADIUS_M + 0.004
		ring.bottom_radius = BEDROLL_RADIUS_M + 0.004
		ring.height = 0.025
		band.mesh = ring
		band.material_override = _plain(STRAP)
		band.rotation.z = PI * 0.5
		band.position.x = x
		_bedroll.add_child(band)


func _add_straps() -> void:
	## Padded strips down the back where the shoulder straps are sewn, and the grab handle. The
	## strips wear the canvas shader, so they move with it.
	for x: float in [-0.11, 0.11]:
		_strap(Vector3(0.055, BODY.y * 0.78, 0.014), Vector3(x, BODY.y * 0.5, -0.009), Vector3.ZERO)
	_add_handle()


## A strap or buckle box baked into pack space, so the canvas shader shapes it with the shell.
func _strap(size: Vector3, at: Vector3, tilt: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var xf := Transform3D(Basis.from_euler(tilt), at)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in range(verts.size()):
		verts[i] = xf * verts[i]
		normals[i] = xf.basis * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var strap := MeshInstance3D.new()
	strap.name = "Strap"
	strap.mesh = mesh
	strap.material_override = _strap_material
	add_child(strap)


## The grab handle: a webbing arch whose two feet stand on the top; placed on the canvas each frame.
func _add_handle() -> void:
	_handle = Node3D.new()
	_handle.name = "Handle"
	add_child(_handle)
	var webbing: StandardMaterial3D = _plain(STRAP)
	for x: float in [-0.045, 0.045]:
		var leg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.006, 0.034, 0.022)
		leg.mesh = box
		leg.material_override = webbing
		## Each foot is sewn flat to the top; the leg leans in towards the bar.
		leg.transform = Transform3D(Basis(Vector3.BACK, signf(x) * 0.5), Vector3(x, 0.015, 0.0))
		_handle.add_child(leg)
	var bar := MeshInstance3D.new()
	var grip := BoxMesh.new()
	grip.size = Vector3(0.08, 0.007, 0.022)
	bar.mesh = grip
	bar.material_override = webbing
	bar.position = Vector3(0.0, 0.031, 0.0)
	_handle.add_child(bar)
	for x: float in [-0.05, 0.05]:
		var foot := MeshInstance3D.new()
		var tab := BoxMesh.new()
		tab.size = Vector3(0.03, 0.004, 0.024)
		foot.mesh = tab
		foot.material_override = webbing
		foot.position = Vector3(x, 0.001, 0.0)
		_handle.add_child(foot)


## Two zip sliders, each with a pull tab that hangs toward the ground.
func _add_sliders() -> void:
	var metal: StandardMaterial3D = _plain(ZIP_METAL)
	metal.metallic = 0.7
	metal.roughness = 0.4
	for side: float in [-1.0, 1.0]:
		var slider := Node3D.new()
		slider.name = "SliderLeft" if side < 0.0 else "SliderRight"
		add_child(slider)
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(SLIDER_HALF_M * 2.0, 0.015, 0.009)
		body.mesh = box
		body.material_override = metal
		body.position.z = 0.003
		slider.add_child(body)
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.0, 0.008)
		slider.add_child(pivot)
		var tab := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(0.011, 0.034, 0.003)
		tab.mesh = plate
		tab.material_override = metal
		tab.position.y = -0.017
		pivot.add_child(tab)
		_sliders.append(slider)
		_tabs.append(pivot)


func _place_sliders(give: float) -> void:
	for i: int in range(_sliders.size()):
		var side: float = -1.0 if i == 0 else 1.0
		## Closed, the two sliders sit nose to nose either side of the top centre.
		var seam: Array = _seam_point(_zip + SLIDER_HALF_M, side)
		var normal: Vector3 = seam[1]
		var along: Vector3 = seam[2]
		var slider: Node3D = _sliders[i]
		slider.transform = Transform3D(Basis(along, normal.cross(along), normal).orthonormalized(), _on_canvas(seam[0], normal, give))
		if slider.is_inside_tree():
			## The tab hangs toward the ground, lying on the canvas.
			var out: Vector3 = (slider.global_basis * Vector3.BACK).normalized()
			var hang: Vector3 = Vector3.DOWN - out * Vector3.DOWN.dot(out)
			hang = hang.normalized() if hang.length() > 0.2 else (slider.global_basis * Vector3.DOWN).normalized()
			var scale_kept: Vector3 = _tabs[i].global_basis.get_scale()
			_tabs[i].global_basis = Basis(hang.cross(out).normalized() * -1.0, -hang, out).orthonormalized().scaled(scale_kept)


## A strap loop on each side pocket with a carabiner hanging from it.
func _add_carabiners() -> void:
	for side: float in [-1.0, 1.0]:
		_strap(Vector3(0.012, 0.05, 0.024), Vector3(side * LOOP_AT.x, LOOP_AT.y, LOOP_AT.z), Vector3.ZERO)
		var pivot := Node3D.new()
		pivot.name = "CarabinerLoopLeft" if side < 0.0 else "CarabinerLoopRight"
		add_child(pivot)
		var carabiner := Carabiner.new()
		carabiner.name = "Carabiner"
		## The ring lies along the wall, its gate toward the front.
		carabiner.face_yaw = -PI * 0.5
		pivot.add_child(carabiner)
		carabiner.build()
		_carabiners.append(carabiner)


func _place_carabiners() -> void:
	for i: int in range(_carabiners.size()):
		var side: float = -1.0 if i == 0 else 1.0
		var rest := Vector3(side * CARABINER_AT.x, CARABINER_AT.y, CARABINER_AT.z)
		_carabiners[i].get_parent_node_3d().position = _on_canvas(rest, Vector3(side, 0.0, 0.0), 0.0)


func _plain(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	return material


## Bounds of a freshly built visual in its own space.
static func _local_bounds(visual: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for node: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var xf: Transform3D = Transform3D.IDENTITY
		var walk: Node = mesh_node
		while walk != visual and walk is Node3D:
			xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var part: AABB = xf * mesh_node.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

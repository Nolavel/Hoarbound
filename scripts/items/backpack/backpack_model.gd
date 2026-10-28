class_name BackpackModel
extends Node3D

## A front-loading backpack (#260): a canvas shell, a front panel that unzips and folds down on a
## bottom hinge, slots for what it carries, a pocket either side and a bedroll strapped under it. The
## canvas takes its shape from the contents (backpack_canvas.gdshader); no soft-body physics.
## Pack space: origin at the bottom of the back face, +Y up, +Z out to the front, +X to the right.

signal opened_changed(open: bool)

const CANVAS_SHADER: Shader = preload("res://shaders/items/backpack_canvas.gdshader")
const MAX_ITEMS: int = 16
## Outer size of the main body (width, height, depth) and the rounding of its edges, metres.
const BODY: Vector3 = Vector3(0.34, 0.52, 0.22)
const ROUND_M: float = 0.06
## Grid steps along each face; enough vertices for a can or a flask to show as a bulge.
const STEPS: Vector3i = Vector3i(14, 20, 10)
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
	&"side_left": [Vector3(-POCKET_X, 0.15, 0.11), Vector3(0.035, 0.11, 0.04)],
	&"side_right": [Vector3(POCKET_X, 0.15, 0.11), Vector3(0.035, 0.11, 0.04)],
}
## Which faces of a rounded box to build: every one, all but the front, or the front alone.
const FACES_ALL: int = 0
const FACES_SHELL: int = 1
const FACES_FRONT: int = 2
const FACES_OPEN_TOP: int = 3
## Side pockets: open-topped pouches either side, sized for a bottle that stands out of them.
const POCKET_X: float = 0.205
const POCKET_HALF: Vector3 = Vector3(0.04, 0.07, 0.05)
const CANVAS: Color = Color(0.37, 0.33, 0.21)
const STRAP: Color = Color(0.28, 0.19, 0.12)
const BEDROLL: Color = Color(0.24, 0.27, 0.30)

var _shell_material: ShaderMaterial
var _panel_material: ShaderMaterial
var _pocket_material: ShaderMaterial
var _strap_material: ShaderMaterial
var _hinge: Node3D
var _panel: MeshInstance3D
var _items: Array[Dictionary] = []
var _contents: Node3D
var _open: bool = false
var _swing: float = 0.0
var _swing_speed: float = 0.0
var _droop: float = 0.0
var _droop_speed: float = 0.0
var _fill: float = 0.0
var _fill_speed: float = 0.0


func _ready() -> void:
	build()


## Builds the shell, panel, pocket, bedroll and straps. Safe to call once.
func build() -> void:
	if _hinge != null:
		return
	_shell_material = _canvas_material(Vector4.ZERO)
	_panel_material = _canvas_material(Vector4(0.1, 0.15, 0.55, 0.85))
	_pocket_material = _canvas_material(Vector4.ZERO)
	## The pocket is a thin pouch round a hard bottle: more slack, so the corners never poke through.
	_pocket_material.set_shader_parameter(&"lining_m", 0.008)
	_pocket_material.set_shader_parameter(&"soft_m", 0.025)
	_pocket_material.set_shader_parameter(&"max_stretch_m", 0.03)
	_strap_material = _canvas_material(Vector4.ZERO)
	_strap_material.set_shader_parameter(&"canvas_colour", STRAP)
	_strap_material.set_shader_parameter(&"lining_colour", STRAP)
	_strap_material.set_shader_parameter(&"roughness_value", 0.7)
	## Shell and panel are one rounded box split at the front: each owns half of the front edge,
	## so the closed panel meets the shell with no seam.
	var centre := Vector3(0.0, BODY.y * 0.5, BODY.z * 0.5)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_SHELL)
	shell.material_override = _shell_material
	add_child(shell)
	var panel_mesh: ArrayMesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_FRONT)
	var hinge_at: Vector3 = _hinge_point(panel_mesh)
	_hinge = Node3D.new()
	_hinge.name = "PanelHinge"
	_hinge.position = hinge_at
	add_child(_hinge)
	_panel = MeshInstance3D.new()
	_panel.name = "FrontPanel"
	_panel.mesh = panel_mesh
	_panel.position = -hinge_at
	_panel.material_override = _panel_material
	_hinge.add_child(_panel)
	_panel_material.set_shader_parameter(&"panel_length_m", BODY.y)
	for side: float in [-1.0, 1.0]:
		var pocket := MeshInstance3D.new()
		pocket.name = "SidePocketLeft" if side < 0.0 else "SidePocketRight"
		pocket.mesh = _rounded_box(POCKET_HALF, Vector3(side * POCKET_X, POCKET_HALF.y + 0.03, BODY.z * 0.5), 0.03, Vector3i(8, 14, 12), FACES_OPEN_TOP)
		pocket.material_override = _pocket_material
		add_child(pocket)
	_add_shelf()
	_add_bedroll()
	_add_straps()
	_contents = Node3D.new()
	_contents.name = "Contents"
	add_child(_contents)
	_refresh_proxies()


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	if _open == open:
		return
	_open = open
	opened_changed.emit(open)


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
	## Stand it on the slot floor; on the shelf it lies along X.
	var basis := Basis(Vector3.FORWARD, PI * 0.5) if slot == &"shelf" and box.size.y > box.size.x else Basis()
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * box
	var at := Vector3(centre.x + along, centre.y - half.y - placed.position.y, centre.z)
	visual.transform = Transform3D(basis, at)
	_contents.add_child(visual)
	_items.append({"id": item_id, "slot": slot, "node": visual, "box": Transform3D(basis, at) * box})
	_refresh_proxies()
	return true


func clear_items() -> void:
	for item: Dictionary in _items:
		(item["node"] as Node).queue_free()
	_items.clear()
	_refresh_proxies()


## Share of the main body the contents fill, 0..1 (the target the canvas springs toward).
func get_fill_target() -> float:
	var litres: float = 0.0
	for item: Dictionary in _items:
		var size: Vector3 = (item["box"] as AABB).size
		litres += size.x * size.y * size.z * 1000.0 * 1.6  # packed items leave air round them
	return clampf(litres / CAPACITY_L, 0.0, 1.0)


func _process(delta: float) -> void:
	var swing_target: float = deg_to_rad(OPEN_DEG) if _open else 0.0
	var omega: float = TAU * SWING_HZ
	_swing_speed += (omega * omega * (swing_target - _swing) - 2.0 * SWING_DAMPING * omega * _swing_speed) * delta
	_swing += _swing_speed * delta
	_hinge.rotation.x = _swing
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
	_panel_material.set_shader_parameter(&"droop_dir", (_panel.global_basis.inverse() * Vector3.DOWN).normalized() if is_inside_tree() else Vector3.DOWN)
	## Only the closed panel holds the contents in; an open one does not bulge.
	_panel_material.set_shader_parameter(&"item_count", _items.size() if _swing < 0.2 else 0)
	for material: ShaderMaterial in [_shell_material, _panel_material, _pocket_material, _strap_material]:
		material.set_shader_parameter(&"fill", _fill)


func _refresh_proxies() -> void:
	var centres: Array = []
	var halves: Array = []
	for item: Dictionary in _items:
		var box: AABB = item["box"]
		centres.append(Vector4(box.get_center().x, box.get_center().y, box.get_center().z, 0.0))
		halves.append(Vector4(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5, 0.0))
	while centres.size() < MAX_ITEMS:
		centres.append(Vector4(0.0, -10.0, 0.0, 0.0))
		halves.append(Vector4.ZERO)
	for material: ShaderMaterial in [_shell_material, _panel_material, _pocket_material, _strap_material]:
		if material == null:
			continue
		material.set_shader_parameter(&"item_centre", centres)
		material.set_shader_parameter(&"item_half", halves)
		material.set_shader_parameter(&"item_count", _items.size())


func _canvas_material(pocket: Vector4) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANVAS_SHADER
	material.set_shader_parameter(&"canvas_colour", CANVAS)
	material.set_shader_parameter(&"pack_height_m", BODY.y)
	material.set_shader_parameter(&"mesh_pocket", pocket)
	return material


## A box with rounded edges as a grid on each face (faces_built picks which). Every grid
## point is pulled onto the rounded surface: clamp to the inner box, then out by the radius.
static func _rounded_box(half: Vector3, centre: Vector3, radius: float, steps: Vector3i, faces_built: int) -> ArrayMesh:
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
				row.append([centre + core + normal * radius, normal, Vector2(float(i) / nu, float(j) / nv)])
			grid.append(row)
		for j: int in range(nv):
			for i: int in range(nu):
				var quad: Array = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					for k: int in _front_wound(quad[tri[0]][0], quad[tri[1]][0], quad[tri[2]][0], quad[tri[0]][1], tri):
						st.set_normal(quad[k][1])
						st.set_uv(quad[k][2])
						st.add_vertex(quad[k][0])
	st.index()
	return st.commit()


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
	board.size = Vector3(BODY.x - 0.05, 0.008, BODY.z - 0.04)
	shelf.mesh = board
	shelf.material_override = _plain(Color(0.2, 0.2, 0.19))
	shelf.position = Vector3(0.0, 0.355, BODY.z * 0.5)
	add_child(shelf)


func _add_bedroll() -> void:
	var roll := MeshInstance3D.new()
	roll.name = "Bedroll"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.075
	cylinder.bottom_radius = 0.075
	cylinder.height = BODY.x + 0.1
	cylinder.radial_segments = 20
	roll.mesh = cylinder
	roll.material_override = _plain(BEDROLL)
	roll.rotation.z = PI * 0.5
	roll.position = Vector3(0.0, -0.06, BODY.z * 0.55)
	add_child(roll)
	for x: float in [-0.1, 0.1]:
		var band := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = 0.079
		ring.bottom_radius = 0.079
		ring.height = 0.025
		band.mesh = ring
		band.material_override = _plain(STRAP)
		band.rotation.z = PI * 0.5
		band.position = Vector3(x, -0.06, BODY.z * 0.55)
		add_child(band)


func _add_straps() -> void:
	## Shoulder straps flat down the back, a grab handle at the top of the back, compression
	## straps down the sides with a buckle each. They wear the canvas shader, so they move with it.
	for x: float in [-0.085, 0.085]:
		_strap(Vector3(0.055, BODY.y * 0.78, 0.014), Vector3(x, BODY.y * 0.5, -0.009), Vector3.ZERO)
	_strap(Vector3(0.1, 0.016, 0.022), Vector3(0.0, BODY.y + 0.006, 0.05), Vector3.ZERO)
	for x: float in [-1.0, 1.0]:
		_strap(Vector3(0.008, BODY.y * 0.66, 0.026), Vector3(x * (BODY.x * 0.5 + 0.002), BODY.y * 0.52, BODY.z * 0.55), Vector3.ZERO)
		_strap(Vector3(0.012, 0.03, 0.035), Vector3(x * (BODY.x * 0.5 + 0.006), BODY.y * 0.6, BODY.z * 0.55), Vector3.ZERO)


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

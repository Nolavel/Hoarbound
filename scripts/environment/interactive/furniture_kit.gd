class_name FurnitureKit
extends RefCounted

## Searchable furniture built from box panels (owner: one kit for every kind): a floor cabinet, a kitchen
## cupboard hung on a wall, a dresser with three drawers, a floor chest with a lid. Each piece's front faces its
## own +Z and its origin sits on the floor at the middle of its footprint; the test row and the 727 shelter use it.
## Every build returns {"piece": Node3D, "containers": {name: ItemContainer}, "openers": {name: InteractiveArea}}.

const WOOD: Color = Color(0.42, 0.33, 0.24)
const PAINT: Color = Color(0.36, 0.38, 0.42)
## How far the back of each piece stands out from its origin (a wall behind it touches there), metres.
const FLOOR_CABINET_BACK_M: float = 0.225
const CUPBOARD_BACK_M: float = 0.175
const DRESSER_BACK_M: float = 0.225
const CHEST_BACK_M: float = 0.225


## Like the 727 waiting-room cabinet: two shelves, one door hinged on the left.
static func floor_cabinet(parent: Node3D, piece_name: String, id: StringName, items: Array[StringName]) -> Dictionary:
	var piece: Node3D = _piece(parent, piece_name, Vector3(0.8, 0.9, 0.45), Vector3(0.0, 0.45, 0.0))
	for panel: Array in [
		[Vector3(0.8, 0.9, 0.03), Vector3(0.0, 0.45, -0.21)],
		[Vector3(0.03, 0.9, 0.45), Vector3(-0.385, 0.45, 0.0)],
		[Vector3(0.03, 0.9, 0.45), Vector3(0.385, 0.45, 0.0)],
		[Vector3(0.8, 0.03, 0.45), Vector3(0.0, 0.885, 0.0)],
		[Vector3(0.8, 0.06, 0.45), Vector3(0.0, 0.03, 0.0)],
		[Vector3(0.74, 0.02, 0.4), Vector3(0.0, 0.45, 0.0)],
	]:
		_panel(piece, panel[0], panel[1], PAINT)
	var shelves: Array[AABB] = ItemContainer.shelves_from_furniture(piece, null)
	var door: Cabinet = _door(piece, "Door", Vector3(-0.39, 0.45, 0.225), Vector3(0.78, 0.84, 0.025), 1.0, -105.0)
	var container: ItemContainer = _container(piece, id, shelves, [door], false, items)
	return {"piece": piece, "containers": {"shelves": container}, "openers": {"door": door}}


## A kitchen cupboard hung on a wall, its bottom 1.45 m above the floor: one shelf, two doors hinged at its sides.
static func kitchen_cupboard(parent: Node3D, piece_name: String, id: StringName, items: Array[StringName]) -> Dictionary:
	var piece: Node3D = _piece(parent, piece_name, Vector3(1.0, 0.7, 0.35), Vector3(0.0, 1.8, 0.0))
	for panel: Array in [
		[Vector3(1.0, 0.7, 0.02), Vector3(0.0, 1.8, -0.165)],
		[Vector3(0.02, 0.7, 0.35), Vector3(-0.49, 1.8, 0.0)],
		[Vector3(0.02, 0.7, 0.35), Vector3(0.49, 1.8, 0.0)],
		[Vector3(1.0, 0.02, 0.35), Vector3(0.0, 2.14, 0.0)],
		[Vector3(1.0, 0.03, 0.35), Vector3(0.0, 1.465, 0.0)],
		[Vector3(0.96, 0.02, 0.32), Vector3(0.0, 1.8, 0.0)],
	]:
		_panel(piece, panel[0], panel[1], WOOD)
	var shelves: Array[AABB] = ItemContainer.shelves_from_furniture(piece, null)
	var left: Cabinet = _door(piece, "DoorLeft", Vector3(-0.5, 1.8, 0.175), Vector3(0.495, 0.68, 0.02), 1.0, -105.0)
	var right: Cabinet = _door(piece, "DoorRight", Vector3(0.5, 1.8, 0.175), Vector3(0.495, 0.68, 0.02), -1.0, 105.0)
	var container: ItemContainer = _container(piece, id, shelves, [left, right], false, items)
	return {"piece": piece, "containers": {"shelves": container}, "openers": {"left": left, "right": right}}


## A dresser with three drawers (`bottom`, `middle`, `top`, each with its own items): each slides out and opens up.
static func dresser(parent: Node3D, piece_name: String, id: StringName, drawer_items: Dictionary) -> Dictionary:
	var piece: Node3D = _piece(parent, piece_name, Vector3(0.9, 0.85, 0.45), Vector3(0.0, 0.425, 0.0))
	for panel: Array in [
		[Vector3(0.9, 0.85, 0.02), Vector3(0.0, 0.425, -0.215)],
		[Vector3(0.02, 0.85, 0.45), Vector3(-0.44, 0.425, 0.0)],
		[Vector3(0.02, 0.85, 0.45), Vector3(0.44, 0.425, 0.0)],
		[Vector3(0.9, 0.03, 0.45), Vector3(0.0, 0.835, 0.0)],
		[Vector3(0.9, 0.05, 0.45), Vector3(0.0, 0.025, 0.0)],
	]:
		_panel(piece, panel[0], panel[1], WOOD)
	var containers: Dictionary = {}
	var openers: Dictionary = {}
	for row: Array in [["bottom", 0.18], ["middle", 0.44], ["top", 0.70]]:
		var slide := Node3D.new()
		slide.name = "Drawer" + String(row[0]).capitalize()
		slide.position = Vector3(0.0, row[1], 0.0)
		piece.add_child(slide)
		for panel: Array in [
			[Vector3(0.84, 0.015, 0.42), Vector3(0.0, -0.1, 0.0)],
			[Vector3(0.015, 0.2, 0.42), Vector3(-0.41, 0.0, 0.0)],
			[Vector3(0.015, 0.2, 0.42), Vector3(0.41, 0.0, 0.0)],
			[Vector3(0.84, 0.2, 0.015), Vector3(0.0, 0.0, -0.2)],
			[Vector3(0.88, 0.24, 0.02), Vector3(0.0, 0.0, 0.225)],
			[Vector3(0.12, 0.025, 0.02), Vector3(0.0, 0.0, 0.245)],
		]:
			_panel(slide, panel[0], panel[1], WOOD.lightened(0.1))
		var handle := Node3D.new()
		handle.name = "Handle"
		handle.position = Vector3(0.0, -0.02, 0.27)
		slide.add_child(handle)
		var drawer := Drawer.new()
		drawer.name = "Pull" + String(row[0]).capitalize()
		drawer.slide = slide
		drawer.handle = handle
		drawer.focus_radius = 0.05
		piece.add_child(drawer)
		var space := AABB(Vector3(-0.395, -0.0925, -0.19), Vector3(0.79, 0.19, 0.38))
		var start: Array[StringName] = []
		start.assign(drawer_items.get(row[0], []))
		var container: ItemContainer = _container(slide, StringName("%s_%s" % [id, row[0]]), [space] as Array[AABB],
			[drawer], true, start)
		container.furniture = piece
		containers[row[0]] = container
		openers[row[0]] = drawer
	return {"piece": piece, "containers": containers, "openers": openers}


## A chest on the floor, its lid hinged at the back.
static func chest(parent: Node3D, piece_name: String, id: StringName, items: Array[StringName]) -> Dictionary:
	var piece: Node3D = _piece(parent, piece_name, Vector3(0.8, 0.45, 0.45), Vector3(0.0, 0.225, 0.0))
	for panel: Array in [
		[Vector3(0.8, 0.03, 0.45), Vector3(0.0, 0.015, 0.0)],
		[Vector3(0.8, 0.45, 0.02), Vector3(0.0, 0.225, -0.215)],
		[Vector3(0.8, 0.45, 0.02), Vector3(0.0, 0.225, 0.215)],
		[Vector3(0.02, 0.45, 0.45), Vector3(-0.39, 0.225, 0.0)],
		[Vector3(0.02, 0.45, 0.45), Vector3(0.39, 0.225, 0.0)],
	]:
		_panel(piece, panel[0], panel[1], WOOD.darkened(0.15))
	var lid: Cabinet = _door(piece, "Lid", Vector3(0.0, 0.45, -0.225), Vector3(0.82, 0.025, 0.47), 0.0, -105.0)
	lid.swing_axis = Vector3.RIGHT
	lid.open_key = "CHEST_OPEN"
	lid.close_key = "CHEST_CLOSE"
	var space := AABB(Vector3(-0.375, 0.03, -0.2), Vector3(0.75, 0.41, 0.4))
	var container: ItemContainer = _container(piece, id, [space] as Array[AABB], [lid], true, items)
	return {"piece": piece, "containers": {"shelves": container}, "openers": {"lid": lid}}


## A piece's root under `parent` with a static box of `size` around `centre` (its own space), so Henry cannot
## walk into it.
static func _piece(parent: Node3D, piece_name: String, size: Vector3, centre: Vector3) -> Node3D:
	var piece := Node3D.new()
	piece.name = piece_name
	parent.add_child(piece)
	var body := StaticBody3D.new()
	body.name = "Solid"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = centre
	body.add_child(shape)
	piece.add_child(body)
	return piece


## A door (or a lid) on a hinge at `hinge_at`: its leaf of `size` beside the hinge toward `side` (+1 right of it,
## -1 left, 0 out ahead for a lid), opening to `open_deg`.
static func _door(piece: Node3D, door_name: String, hinge_at: Vector3, size: Vector3, side: float, open_deg: float) -> Cabinet:
	var hinge := Node3D.new()
	hinge.name = door_name + "Hinge"
	hinge.position = hinge_at
	piece.add_child(hinge)
	var leaf_at := Vector3(side * size.x * 0.5, 0.0, size.z * 0.5) if side != 0.0 else Vector3(0.0, size.y * 0.5, size.z * 0.5)
	_panel(hinge, size, leaf_at, PAINT.lightened(0.08))
	var focus := Node3D.new()
	focus.name = "Focus"
	focus.position = leaf_at + Vector3(0.0, 0.0, 0.04) if side != 0.0 else leaf_at + Vector3(0.0, 0.04, 0.2)
	hinge.add_child(focus)
	var door := Cabinet.new()
	door.name = door_name
	door.door_hinge = hinge
	door.open_angle_deg = open_deg
	door.focus_anchor = focus
	piece.add_child(door)
	return door


static func _container(parent: Node3D, id: StringName, shelves: Array[AABB], ways: Array, up: bool,
		start: Array[StringName]) -> ItemContainer:
	var container := ItemContainer.new()
	container.name = "Shelves"
	container.container_id = id
	container.shelves = shelves
	container.opens_up = up
	for way: InteractiveArea in ways:
		container.openers.append(way)
	parent.add_child(container)
	for item_id: StringName in start:
		container.put(item_id)
	return container


static func _panel(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = colour
	paint.roughness = 0.85
	mesh.material_override = paint
	mesh.position = at
	parent.add_child(mesh)
	return mesh

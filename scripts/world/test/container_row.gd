class_name ContainerRow
extends Node3D

## A row of furniture for trying the container search (owner): a floor cabinet, a kitchen cupboard with two doors
## high on the wall, a dresser with three drawers, a floor chest with a lid. Some hold things, some are empty.
## Built when it enters the tree; each piece's front faces this node's +Z, spaced along +X.

## Each piece's distance from the last along +X, metres.
const SPACING_M: float = 1.7
const WOOD: Color = Color(0.42, 0.33, 0.24)
const PAINT: Color = Color(0.36, 0.38, 0.42)
const WALL: Color = Color(0.55, 0.55, 0.52)

## What each container holds at start (ids); missing or empty lists start empty.
@export var floor_cabinet_items: Array[StringName] = [&"tinned_stew", &"tinned_pineapple", &"spov_can", &"spov_can"]
@export var cupboard_items: Array[StringName] = [&"tinned_stew", &"spov_can"]
@export var top_drawer_items: Array[StringName] = [&"spov_can", &"lighter"]
@export var middle_drawer_items: Array[StringName] = [&"tinder"]
@export var bottom_drawer_items: Array[StringName] = []
@export var chest_items: Array[StringName] = []

## The row's containers by name (floor_cabinet, cupboard, drawer_top, drawer_middle, drawer_bottom, chest).
var containers: Dictionary = {}
## The ways in by name (floor_cabinet, cupboard_left, cupboard_right, drawer_top, ..., chest).
var openers: Dictionary = {}


func _ready() -> void:
	_build_floor_cabinet(Vector3(0.0, 0.0, 0.0))
	_build_cupboard(Vector3(SPACING_M, 0.0, 0.0))
	_build_dresser(Vector3(SPACING_M * 2.0, 0.0, 0.0))
	_build_chest(Vector3(SPACING_M * 3.0, 0.0, 0.0))


## Like the 727 waiting-room cabinet: two shelves, one door hinged on the left.
func _build_floor_cabinet(at: Vector3) -> void:
	var piece: Node3D = _piece("FloorCabinet", at, Vector3(0.8, 0.9, 0.45), Vector3(0.0, 0.45, 0.0))
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
	openers["floor_cabinet"] = door
	_container(piece, "floor_cabinet", shelves, [door], false, floor_cabinet_items)


## A kitchen cupboard on the wall, its bottom at 1.45 m: one shelf, two doors hinged at its sides.
func _build_cupboard(at: Vector3) -> void:
	var wall := MeshInstance3D.new()
	wall.name = "KitchenWall"
	_shape(wall, Vector3(1.3, 2.4, 0.04), WALL)
	wall.position = at + Vector3(0.0, 1.2, -0.2)
	add_child(wall)
	var piece: Node3D = _piece("KitchenCupboard", at, Vector3(1.0, 0.7, 0.35), Vector3(0.0, 1.8, 0.0))
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
	openers["cupboard_left"] = left
	openers["cupboard_right"] = right
	_container(piece, "cupboard", shelves, [left, right], false, cupboard_items)


## A dresser with three drawers: each slides out and opens upward.
func _build_dresser(at: Vector3) -> void:
	var piece: Node3D = _piece("Dresser", at, Vector3(0.9, 0.85, 0.45), Vector3(0.0, 0.425, 0.0))
	for panel: Array in [
		[Vector3(0.9, 0.85, 0.02), Vector3(0.0, 0.425, -0.215)],
		[Vector3(0.02, 0.85, 0.45), Vector3(-0.44, 0.425, 0.0)],
		[Vector3(0.02, 0.85, 0.45), Vector3(0.44, 0.425, 0.0)],
		[Vector3(0.9, 0.03, 0.45), Vector3(0.0, 0.835, 0.0)],
		[Vector3(0.9, 0.05, 0.45), Vector3(0.0, 0.025, 0.0)],
	]:
		_panel(piece, panel[0], panel[1], WOOD)
	var rows: Array = [["drawer_bottom", 0.18, bottom_drawer_items], ["drawer_middle", 0.44, middle_drawer_items],
		["drawer_top", 0.70, top_drawer_items]]
	for row: Array in rows:
		var slide := Node3D.new()
		slide.name = String(row[0]).to_pascal_case()
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
		drawer.name = "Pull"
		drawer.slide = slide
		drawer.handle = handle
		drawer.focus_radius = 0.05
		piece.add_child(drawer)
		openers[row[0]] = drawer
		var space := AABB(Vector3(-0.395, -0.0925, -0.19), Vector3(0.79, 0.19, 0.38))
		_container(slide, row[0], [space] as Array[AABB], [drawer], true, row[2])


## A chest on the floor, its lid hinged at the back.
func _build_chest(at: Vector3) -> void:
	var piece: Node3D = _piece("Chest", at, Vector3(0.8, 0.45, 0.45), Vector3(0.0, 0.225, 0.0))
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
	openers["chest"] = lid
	var space := AABB(Vector3(-0.375, 0.03, -0.2), Vector3(0.75, 0.41, 0.4))
	_container(piece, "chest", [space] as Array[AABB], [lid], true, chest_items)


## A piece's root at `at` with a static box of `size` around `centre` (its own space), so Henry cannot walk in.
func _piece(piece_name: String, at: Vector3, size: Vector3, centre: Vector3) -> Node3D:
	var piece := Node3D.new()
	piece.name = piece_name
	piece.position = at
	add_child(piece)
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
func _door(piece: Node3D, door_name: String, hinge_at: Vector3, size: Vector3, side: float, open_deg: float) -> Cabinet:
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


func _container(parent: Node3D, id: String, shelves: Array[AABB], ways: Array, up: bool, start: Array[StringName]) -> void:
	var container := ItemContainer.new()
	container.name = "Shelves"
	container.container_id = StringName("test_row_" + id)
	container.shelves = shelves
	container.opens_up = up
	for way: InteractiveArea in ways:
		container.openers.append(way)
	parent.add_child(container)
	for item_id: StringName in start:
		container.put(item_id)
	containers[id] = container


func _panel(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	_shape(mesh, size, colour)
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _shape(mesh: MeshInstance3D, size: Vector3, colour: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = colour
	paint.roughness = 0.85
	mesh.material_override = paint

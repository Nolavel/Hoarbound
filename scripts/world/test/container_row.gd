class_name ContainerRow
extends Node3D

## A row of furniture for trying the container search (owner): a floor cabinet, a kitchen cupboard with two doors
## high on the wall, a dresser with three drawers, a floor chest with a lid. Some hold things, the bottom drawer is empty.
## Built when it enters the tree from FurnitureKit; each piece's front faces this node's +Z, spaced along +X.

## Each piece's distance from the last along +X, metres.
const SPACING_M: float = 1.7
const WALL: Color = Color(0.55, 0.55, 0.52)

## What each container holds at start (ids); missing or empty lists start empty.
@export var floor_cabinet_items: Array[StringName] = [&"tinned_stew", &"tinned_pineapple", &"spov_can", &"spov_can"]
@export var cupboard_items: Array[StringName] = [&"tinned_stew", &"spov_can"]
@export var top_drawer_items: Array[StringName] = [&"spov_can", &"lighter"]
@export var middle_drawer_items: Array[StringName] = [&"tinder"]
@export var bottom_drawer_items: Array[StringName] = []
@export var chest_items: Array[StringName] = [&"tinned_pineapple", &"spov_can", &"lighter"]

## The row's containers by name (floor_cabinet, cupboard, drawer_top, drawer_middle, drawer_bottom, chest).
var containers: Dictionary = {}
## The ways in by name (floor_cabinet, cupboard_left, cupboard_right, drawer_top, ..., chest).
var openers: Dictionary = {}


func _ready() -> void:
	var cabinet: Dictionary = FurnitureKit.floor_cabinet(self, "FloorCabinet", &"test_row_floor_cabinet", floor_cabinet_items)
	(cabinet["piece"] as Node3D).position = Vector3.ZERO
	containers["floor_cabinet"] = cabinet["containers"]["shelves"]
	openers["floor_cabinet"] = cabinet["openers"]["door"]
	var wall := MeshInstance3D.new()
	wall.name = "KitchenWall"
	var plane := BoxMesh.new()
	plane.size = Vector3(1.3, 2.4, 0.04)
	wall.mesh = plane
	var paint := StandardMaterial3D.new()
	paint.albedo_color = WALL
	wall.material_override = paint
	wall.position = Vector3(SPACING_M, 1.2, -0.2)
	add_child(wall)
	var cupboard: Dictionary = FurnitureKit.kitchen_cupboard(self, "KitchenCupboard", &"test_row_cupboard", cupboard_items)
	(cupboard["piece"] as Node3D).position = Vector3(SPACING_M, 0.0, 0.0)
	containers["cupboard"] = cupboard["containers"]["shelves"]
	openers["cupboard_left"] = cupboard["openers"]["left"]
	openers["cupboard_right"] = cupboard["openers"]["right"]
	var dresser: Dictionary = FurnitureKit.dresser(self, "Dresser", &"test_row_drawer",
		{"bottom": bottom_drawer_items, "middle": middle_drawer_items, "top": top_drawer_items})
	(dresser["piece"] as Node3D).position = Vector3(SPACING_M * 2.0, 0.0, 0.0)
	for row: String in ["bottom", "middle", "top"]:
		containers["drawer_" + row] = dresser["containers"][row]
		openers["drawer_" + row] = dresser["openers"][row]
	var chest: Dictionary = FurnitureKit.chest(self, "Chest", &"test_row_chest", chest_items)
	(chest["piece"] as Node3D).position = Vector3(SPACING_M * 3.0, 0.0, 0.0)
	containers["chest"] = chest["containers"]["shelves"]
	openers["chest"] = chest["openers"]["lid"]

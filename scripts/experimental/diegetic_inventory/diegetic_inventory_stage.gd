class_name DiegeticInventoryStage
extends Node3D

## Issue #203 preparation stage. This intentionally implements no backpack packing.
## It isolates production Henry, the production TPS camera, the real shelter meal
## table and real production pickup visuals so item handling can be judged before
## the actual diegetic-inventory interaction is written.

const FIRST_EXIT_SOURCE: PackedScene = preload("res://scenes/world/first_exit/first_exit_blockout.tscn")
const ITEM_NAMES: Array[StringName] = [
	&"FlaskShelterTest",
	&"PineappleShelterTest",
	&"StewShelterTest",
	&"HammerShelter",
]
const ITEM_POSITIONS: Array[Vector3] = [
	Vector3(-0.17, MealTable.TOP_Y + 0.02, -0.08),
	Vector3(0.00, MealTable.TOP_Y + 0.02, -0.08),
	Vector3(0.16, MealTable.TOP_Y + 0.02, -0.07),
	Vector3(0.00, MealTable.TOP_Y + 0.035, 0.11),
]

@onready var player: Player = $Player
@onready var camera: TpsCamera = $PlayerCamera
@onready var stage_items: Node3D = $StageItems

var table: MealTable
var items: Array[ItemPickup] = []


func _ready() -> void:
	camera.player = player
	_disable_player_ui(player)
	_extract_production_props()
	prepare_capture_pose(0)


## Three viewpoints, all produced by the shipping TPS camera rather than a free
## capture camera. The player stays a normal production Player when this scene is
## opened interactively in Godot.
func prepare_capture_pose(index: int) -> void:
	var positions: Array[Vector3] = [
		Vector3(0.0, 1.0, 2.45),
		Vector3(0.72, 1.0, 1.62),
		Vector3(-0.90, 1.0, 1.85),
	]
	var pitches: Array[float] = [-12.0, -21.0, -18.0]
	index = clampi(index, 0, positions.size() - 1)
	player.global_position = positions[index]
	player.velocity = Vector3.ZERO
	var heading: Vector3 = (table.global_position - player.global_position) if table != null else -Vector3.FORWARD
	heading.y = 0.0
	if heading.length_squared() < 0.001:
		heading = Vector3.FORWARD * -1.0
	heading = heading.normalized()
	var yaw: float = atan2(-heading.x, -heading.z)
	player.global_rotation.y = yaw
	player.reset_physics_interpolation()
	camera.set_look(yaw, pitches[index])
	if camera.has_method(&"snap_to_target"):
		camera.call(&"snap_to_target")


func _extract_production_props() -> void:
	var source := FIRST_EXIT_SOURCE.instantiate() as Node3D
	add_child(source)
	var source_table := source.find_child("MealTable", true, false) as MealTable
	if source_table == null:
		push_error("diegetic inventory stage: production MealTable not found")
		return
	source_table.reparent(stage_items, false)
	source_table.transform = Transform3D.IDENTITY
	table = source_table

	for i: int in range(ITEM_NAMES.size()):
		var pickup := source.find_child(String(ITEM_NAMES[i]), true, false) as ItemPickup
		if pickup == null:
			push_error("diegetic inventory stage: production pickup missing: %s" % ITEM_NAMES[i])
			continue
		pickup.reparent(stage_items, false)
		pickup.position = ITEM_POSITIONS[i]
		pickup.rotation = Vector3.ZERO
		items.append(pickup)

	## Everything else in the generated First Exit blockout is deliberately left
	## out. The table and pickups above are the exact production nodes/scripts.
	source.queue_free()


func _disable_player_ui(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false
		_disable_player_ui(child)

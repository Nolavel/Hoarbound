class_name MealTable
extends Node3D

## A small table with a cloth by the stove. While Henry sits beside it, the food
## and drink he carries (pack and pockets) is laid out on the cloth; eating stays Use.

const GROUP: StringName = &"meal_table"
## Henry's seat must be this close for the table to be his.
const REACH_M: float = 1.6
const TOP_Y: float = 0.46
const CLOTH: Vector2 = Vector2(0.46, 0.34)
## Props per row on the cloth.
const ROW: int = 3
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"

var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _props: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	_build()


## The table nearest a seat within reach, or null.
static func near(tree: SceneTree, at: Vector3) -> MealTable:
	var best: MealTable = null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var table := node as MealTable
		if table != null and table.global_position.distance_to(at) <= REACH_M:
			if best == null or table.global_position.distance_to(at) < best.global_position.distance_to(at):
				best = table
	return best


## Lays out what Henry carries and keeps it current until clear().
func lay_out(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:
	clear()
	_inventory = inventory
	_equipment = equipment
	if _inventory != null:
		_inventory.item_added.connect(_on_changed)
		_inventory.item_removed.connect(_on_changed)
	if _equipment != null:
		_equipment.slot_changed.connect(_on_slot_changed)
	_refresh()


func clear() -> void:
	if _inventory != null and _inventory.item_added.is_connected(_on_changed):
		_inventory.item_added.disconnect(_on_changed)
		_inventory.item_removed.disconnect(_on_changed)
	if _equipment != null and _equipment.slot_changed.is_connected(_on_slot_changed):
		_equipment.slot_changed.disconnect(_on_slot_changed)
	_inventory = null
	_equipment = null
	for child: Node in _props.get_children():
		child.queue_free()


## Item ids currently laid on the cloth, one entry per unit.
func get_laid_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child: Node in _props.get_children():
		if not child.is_queued_for_deletion():
			ids.append(StringName(child.get_meta(&"item_id", &"")))
	return ids


func _on_changed(_item: ItemResource, _count: int) -> void:
	_refresh()


func _on_slot_changed(_path: StringName, _item_id: StringName) -> void:
	_refresh()


func _refresh() -> void:
	for child: Node in _props.get_children():
		child.queue_free()
	var foods: Array[StringName] = []
	if _inventory != null:
		for entry: Dictionary in _inventory.get_entries():
			var item: ItemResource = ItemCatalog.get_item(entry["id"])
			if item != null and item.consumable != null:
				for i: int in range(int(entry["count"])):
					foods.append(item.id)
	if _equipment != null:
		for pocket: Dictionary in _equipment.get_available_pockets():
			var pocketed: ItemResource = ItemCatalog.get_item(pocket["item_id"]) if pocket["item_id"] != &"" else null
			if pocketed != null and pocketed.consumable != null:
				foods.append(pocketed.id)
	var step := Vector2(CLOTH.x / float(ROW), CLOTH.y / 2.0)
	var presented: Array[StringName] = []
	for item_id: StringName in foods:
		if not presented.has(item_id) and presented.size() < ROW * 2:
			presented.append(item_id)
	for item_id: StringName in foods:
		if presented.size() >= ROW * 2:
			break
		if presented.count(item_id) < foods.count(item_id):
			presented.append(item_id)
	var first_of: Dictionary = {}  # item id -> the prop that carries its F target
	for i: int in range(presented.size()):
		var prop: Node3D = _food_prop(presented[i])
		prop.set_meta(&"item_id", presented[i])
		prop.position = Vector3(-CLOTH.x * 0.5 + step.x * (float(i % ROW) + 0.5), TOP_Y + 0.012,
			-CLOTH.y * 0.5 + step.y * (float(i / ROW) + 0.5))
		_props.add_child(prop)
		if not first_of.has(presented[i]):
			first_of[presented[i]] = prop
	## One F target per kind of food, sitting on its first prop: "Eat: Tinned stew ×2".
	for item_id: StringName in first_of:
		_add_target(first_of[item_id], item_id, foods.count(item_id))


func _add_target(prop: Node3D, item_id: StringName, amount: int) -> void:
	var area: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	area.name = "Eat"
	area.set_script(load("res://scripts/environment/interactive/table_food.gd"))
	area.set(&"item_id", item_id)
	area.set(&"count", amount)
	area.set(&"interactable_scene", null)
	area.set(&"interactive_mesh", prop.get_child(0))
	area.set(&"object_on_ground", false)
	area.set(&"info_height_offset", 0.3)
	var col := area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.16, 0.2, 0.16)
		col.shape = shape
		col.position = Vector3(0.0, 0.05, 0.0)
	prop.add_child(area)


## Food targets on the cloth, one per kind; for tests.
func get_targets() -> Array[TableFood]:
	var found: Array[TableFood] = []
	for node: Node in _props.find_children("*", "", true, false):
		if node is TableFood and not node.get_parent().is_queued_for_deletion():
			found.append(node as TableFood)
	return found


## A tin for stew, a snowball for snow, a small parcel for anything else.
func _food_prop(item_id: StringName) -> Node3D:
	if String(item_id).begins_with("water_flask") or String(item_id).begins_with("tinned_pineapple"):
		return SurvivalItemVisual.make(item_id)
	var node := MeshInstance3D.new()
	match item_id:
		&"tinned_stew":
			var tin := CylinderMesh.new()
			tin.top_radius = 0.037
			tin.bottom_radius = 0.037
			tin.height = 0.075
			tin.material = _material(Color(0.62, 0.6, 0.55), 0.4, 0.8)
			node.mesh = tin
			node.position.y = 0.0375
			var band := MeshInstance3D.new()
			var label := CylinderMesh.new()
			label.top_radius = 0.038
			label.bottom_radius = 0.038
			label.height = 0.04
			label.material = _material(Color(0.62, 0.18, 0.12), 0.8, 0.0)
			band.mesh = label
			node.add_child(band)
		&"snow_handful":
			var ball := SphereMesh.new()
			ball.radius = 0.04
			ball.height = 0.07
			ball.material = _material(Color(0.93, 0.95, 0.98), 0.9, 0.0)
			node.mesh = ball
			node.position.y = 0.03
		_:
			var parcel := BoxMesh.new()
			parcel.size = Vector3(0.08, 0.04, 0.06)
			parcel.material = _material(Color(0.55, 0.45, 0.3), 0.9, 0.0)
			node.mesh = parcel
			node.position.y = 0.02
	var holder := Node3D.new()
	holder.add_child(node)
	return holder


func _build() -> void:
	var wood := _material(Color(0.4, 0.28, 0.18), 0.85, 0.0)
	_box(Vector3(0.5, 0.03, 0.4), Vector3(0.0, TOP_Y - 0.015, 0.0), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.035, TOP_Y - 0.03, 0.035), Vector3(sx * 0.21, (TOP_Y - 0.03) * 0.5, sz * 0.16), wood)
	_box(Vector3(CLOTH.x, 0.004, CLOTH.y), Vector3(0.0, TOP_Y + 0.002, 0.0), _material(Color(0.72, 0.66, 0.52), 1.0, 0.0))
	_props = Node3D.new()
	_props.name = "Food"
	add_child(_props)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	add_child(node)


func _material(albedo: Color, roughness: float, metallic: float) -> Material:
	return StylizedEnvironmentMaterial.make(albedo, roughness, false, false, metallic)

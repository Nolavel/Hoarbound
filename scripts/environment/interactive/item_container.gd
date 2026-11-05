class_name ItemContainer
extends Node3D

## What a piece of furniture holds: items standing on its shelves by their real size, each an ItemPickup
## (F still takes it). The item list is the truth; it is saved, and the pickups follow it.

signal contents_changed

const GROUP: StringName = &"item_container"
const NO_ROOM: StringName = &"CONTAINER_NO_ROOM"
## Items keep this gap from each other and from a shelf's sides, metres.
const GAP_M: float = 0.02
## A panel thinner than this along an axis counts as a wall, a shelf or a lid (shelves_from_furniture), metres.
const PANEL_M: float = 0.07

## Stable id for the save ("container/<id>").
@export var container_id: StringName = &""
## The free space above each shelf, in this node's space: its bottom face is the shelf's top.
@export var shelves: Array[AABB] = []

## Per item: {"id", "state": Dictionary, "world_id": StringName (seeded from the world, or &""),
## "pickup": ItemPickup}.
var items: Array[Dictionary] = []
## Each item id's outline as a pickup stands (its own space), measured once.
static var _outlines: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	add_to_group(GROUP)


## Puts `item_id` on the first shelf with room; &"" when it went in, else why not (NO_ROOM).
func put(item_id: StringName, state: Dictionary = {}) -> StringName:
	var why: StringName = refusal(item_id)
	if why != &"":
		return why
	items.append({"id": item_id, "state": state.duplicate(true), "world_id": &"", "pickup": null})
	_layout()
	contents_changed.emit()
	return &""


## Takes item `index` out: {"id", "state"}, or {} for a bad index. Its pickup goes with it.
func take(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var item: Dictionary = items[index]
	items.remove_at(index)
	var pickup: ItemPickup = item["pickup"]
	if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
		pickup.queue_free()
	_layout()
	contents_changed.emit()
	return {"id": item["id"], "state": item["state"]}


## Why `item_id` would not go in beside what is there now (NO_ROOM), or &"".
func refusal(item_id: StringName) -> StringName:
	var ids: Array[StringName] = []
	for item: Dictionary in items:
		ids.append(item["id"])
	ids.append(item_id)
	return NO_ROOM if _plan(ids).has(null) else &""


## The index of the item `pickup` shows, or -1.
func index_of(pickup: Node) -> int:
	for i: int in items.size():
		if items[i]["pickup"] == pickup:
			return i
	return -1


## Moves the world's pickups into this container (each unit an item); the pickups themselves go.
func adopt(pickups: Array[ItemPickup]) -> void:
	for pickup: ItemPickup in pickups:
		for _n: int in pickup.count:
			items.append({"id": pickup.item_id, "state": pickup.instance_state.duplicate(true), "world_id": pickup.world_id, "pickup": null})
		pickup.free()
	_layout()
	contents_changed.emit()


## An older save took some of the seeded items from the world (PickupLedger): they are not here any more.
func drop_taken(ledger: PickupLedger) -> void:
	var before: int = items.size()
	for i: int in range(items.size() - 1, -1, -1):
		var world_id: StringName = items[i]["world_id"]
		if world_id != &"" and ledger.is_taken(world_id):
			take(i)
	if items.size() != before:
		contents_changed.emit()


func get_save_key() -> StringName:
	return StringName("container/%s" % container_id)


func get_save_data() -> Dictionary:
	var out: Array = []
	for item: Dictionary in items:
		out.append({"id": String(item["id"]), "state": (item["state"] as Dictionary).duplicate(true)})
	return {"items": out}


## Replaces the contents with the saved list (unknown ids are dropped).
func load_save_data(data: Dictionary) -> void:
	for item: Dictionary in items:
		if is_instance_valid(item["pickup"]):
			(item["pickup"] as Node).queue_free()
	items.clear()
	for entry: Variant in data.get("items", []):
		if typeof(entry) == TYPE_DICTIONARY and ItemCatalog.get_item(StringName(entry.get("id", ""))) != null:
			items.append({"id": StringName(entry["id"]), "state": entry.get("state", {}), "world_id": &"", "pickup": null})
	_layout()
	contents_changed.emit()


## The free space above each shelf of a piece of furniture made of box panels (`root`'s meshes, in `root`'s
## space, `skip` and below left out): between its side walls, from its back wall to its front, panel to panel.
static func shelves_from_furniture(root: Node3D, skip: Node = null) -> Array[AABB]:
	var panels: Array[AABB] = []
	var outer := AABB()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or (skip != null and (skip == mesh or skip.is_ancestor_of(mesh))):
			continue
		var to_root: Transform3D = Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != root and walk is Node3D:
			to_root = (walk as Node3D).transform * to_root
			walk = walk.get_parent()
		var box: AABB = to_root * mesh.mesh.get_aabb()
		panels.append(box)
		outer = box if outer.size == Vector3.ZERO else outer.merge(box)
	var inner_low: Vector3 = outer.position
	var inner_high: Vector3 = outer.end
	var floors: Array[Vector2] = []  # [bottom y, top y] of each horizontal panel
	for box: AABB in panels:
		if box.size.x < PANEL_M and box.size.y > PANEL_M:
			if box.get_center().x < outer.get_center().x:
				inner_low.x = maxf(inner_low.x, box.end.x)
			else:
				inner_high.x = minf(inner_high.x, box.position.x)
		elif box.size.z < PANEL_M and box.size.x > PANEL_M and box.size.y > PANEL_M and box.get_center().z < outer.get_center().z:
			inner_low.z = maxf(inner_low.z, box.end.z)
		elif box.size.y < PANEL_M and box.size.x > PANEL_M:
			floors.append(Vector2(box.position.y, box.end.y))
	floors.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[AABB] = []
	for i: int in range(floors.size() - 1):
		var low := Vector3(inner_low.x, floors[i].y, inner_low.z)
		var high := Vector3(inner_high.x, floors[i + 1].x, inner_high.z)
		if high.y - low.y > PANEL_M:
			out.append(AABB(low, high - low))
	return out


## Places a pickup for every item, standing on the shelves in order, left to right.
func _layout() -> void:
	var ids: Array[StringName] = []
	for item: Dictionary in items:
		ids.append(item["id"])
	var spots: Array = _plan(ids)
	for i: int in items.size():
		var item: Dictionary = items[i]
		var pickup: ItemPickup = item["pickup"]
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			pickup = _make_pickup(item)
			item["pickup"] = pickup
		if spots[i] != null:
			pickup.position = spots[i]
			pickup.visible = true
		else:
			pickup.visible = false  # an over-full save: kept, not shown, until there is room


## Where each id would stand (its pickup's origin, this node's space), or null where none has room: on the
## first shelf with room, leftmost, clear of what is placed already.
func _plan(ids: Array[StringName]) -> Array:
	var taken: Array[Array] = []  # per shelf: [x from, x to] spans in use
	for shelf: AABB in shelves:
		taken.append([])
	var out: Array = []
	for id: StringName in ids:
		var box: AABB = _outline(id)
		var spot: Variant = null
		for s: int in shelves.size():
			var shelf: AABB = shelves[s]
			if box.size.y > shelf.size.y or box.size.z > shelf.size.z - GAP_M * 2.0:
				continue
			var x: float = _free_x(shelf, taken[s], box.size.x)
			if is_nan(x):
				continue
			spot = Vector3(x - box.position.x, shelf.position.y - box.position.y, shelf.get_center().z - box.get_center().z)
			taken[s].append(Vector2(x, x + box.size.x))
			break
		out.append(spot)
	return out


## The leftmost x on `shelf` where `width` fits clear of `spans` (GAP_M around), or NAN.
static func _free_x(shelf: AABB, spans: Array, width: float) -> float:
	var x: float = shelf.position.x + GAP_M
	var moved: bool = true
	while moved:
		moved = false
		for span: Vector2 in spans:
			if x < span.y + GAP_M and x + width + GAP_M > span.x:
				x = span.y + GAP_M
				moved = true
	return x if x + width + GAP_M <= shelf.end.x else NAN


func _make_pickup(item: Dictionary) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item_id = item["id"]
	pickup.instance_state = item["state"]
	pickup.show_ground_highlight = false  # it stands on a shelf, not the ground
	add_child(pickup)
	var box: AABB = BackpackModel._local_bounds(pickup)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size.max(Vector3.ONE * 0.03)
	collision.shape = shape
	collision.position = box.get_center()
	pickup.add_child(collision)
	pickup.picked_up.connect(_on_picked_up.bind(pickup))
	return pickup


## F took a pickup straight into the pack: its item leaves the list.
func _on_picked_up(_item_id: StringName, _count: int, pickup: ItemPickup) -> void:
	var index: int = index_of(pickup)
	if index >= 0:
		items.remove_at(index)
		_layout()
		contents_changed.emit()


## `id`'s outline as its pickup stands, measured once from a pickup made and freed for it.
func _outline(id: StringName) -> AABB:
	if _outlines.has(id):
		return _outlines[id]
	var probe := ItemPickup.new()
	probe.item_id = id
	probe.show_ground_highlight = false
	add_child(probe)
	var box: AABB = BackpackModel._local_bounds(probe)
	probe.free()
	_outlines[id] = box
	return box

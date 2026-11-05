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

## Henry stands this far out from the front and past the side edge to visit; shelves topping out below
## LOW_TOP_M above the floor make him crouch there, metres.
const VISIT_OUT_M: float = 0.45
const VISIT_PAST_M: float = 0.58
const LOW_TOP_M: float = 1.1
## F opening the door sends a player this near on a visit (PlayerHubComponent.visit_container), metres.
const VISIT_CALL_M: float = 3.0

## Stable id for the save ("container/<id>").
@export var container_id: StringName = &""
## The free space above each shelf, in this node's space: its bottom face is the shelf's top.
@export var shelves: Array[AABB] = []
## The door that must be open to reach in (null: always open).
@export var door: Cabinet

## Per item: {"id", "state": Dictionary, "world_id": StringName (seeded from the world, or &""),
## "pickup": ItemPickup}.
var items: Array[Dictionary] = []
## Each item id's outline as a pickup stands (its own space), measured once.
static var _outlines: Dictionary = {}
var _body := AABB()


func _ready() -> void:
	add_to_group(&"saveable")
	add_to_group(GROUP)
	if door != null:
		door.door_toggled.connect(_on_door_toggled)


## The front: the middle of the shelves' open face, its outward way (flat) and the right of one looking in,
## world: [Vector3, Vector3, Vector3].
func front() -> Array:
	var box: AABB = shelves_box()
	var out: Vector3 = (global_basis.orthonormalized() * Vector3.BACK).slide(Vector3.UP).normalized()
	var front_at: Vector3 = global_transform * Vector3(box.get_center().x, box.get_center().y, box.end.z)
	return [front_at, out, Vector3.UP.cross(out).normalized()]


## Where Henry stands to use it, coming from `from` (world): out from the front, past the edge on the free side
## (free_side); {"at": Vector3 (floor height of `from`), "side": -1.0 left or 1.0 right, as one looks in}.
func visit_spot(from: Vector3) -> Dictionary:
	var face: Array = front()
	var right: Vector3 = face[2]
	var side: float = free_side(from)
	var at: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * VISIT_OUT_M + right * side * (shelves_box().size.x * 0.5 + VISIT_PAST_M)
	at.y = from.y
	return {"at": at, "side": side}


## The side the pack goes (-1 left, 1 right, as one looks in): away from the door's hinge, where the open door
## swings; with no door, the side `from` (world) is on.
func free_side(from: Vector3) -> float:
	if door != null and door.door_hinge != null:
		var hinge: Vector3 = global_transform.affine_inverse() * door.door_hinge.global_position
		return -1.0 if hinge.x > shelves_box().get_center().x else 1.0
	return 1.0 if (from - (front()[0] as Vector3)).dot(front()[2] as Vector3) >= 0.0 else -1.0


## The furniture's own outline, this node's space: every mesh of its parent but the door's (measured once).
func body_box() -> AABB:
	if _body.size != Vector3.ZERO:
		return _body
	var skip: Node = door.door_hinge if door != null and door.door_hinge != null else null
	var to_here: Transform3D = global_transform.affine_inverse()
	for node: Node in get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or is_ancestor_of(mesh) or (skip != null and skip.is_ancestor_of(mesh)) or not mesh.is_visible_in_tree():
			continue
		var part: AABB = (to_here * mesh.global_transform) * mesh.mesh.get_aabb()
		_body = part if _body.size == Vector3.ZERO else _body.merge(part)
	if _body.size == Vector3.ZERO:
		_body = shelves_box()
	return _body


## Whether the shelves are low enough that Henry crouches to them (top below LOW_TOP_M over `floor_y`).
func is_low(floor_y: float) -> bool:
	return (global_transform * shelves_box().end).y - floor_y < LOW_TOP_M


## F opened the door: the player who did it walks over, crouches if low, and the pack opens beside it.
func _on_door_toggled(open: bool) -> void:
	if not open or shelves.is_empty():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > VISIT_CALL_M:
		return
	var hub := player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if hub != null and not hub.is_open():
		hub.visit_container(self)


## Whether Henry can reach in now (its door, if it has one, is open).
func is_reachable() -> bool:
	return door == null or door.is_open()


## The shelves' whole space, this node's space.
func shelves_box() -> AABB:
	var box := AABB()
	for shelf: AABB in shelves:
		box = shelf if box.size == Vector3.ZERO else box.merge(shelf)
	return box


## The item whose pickup shows under `screen` (viewport pixels) as `camera` sees it, or -1: hit on its own
## silhouette, the smallest when several overlap.
func pick(screen: Vector2, camera: Camera3D) -> int:
	var best: int = -1
	var best_area: float = INF
	for i: int in items.size():
		var pickup: ItemPickup = items[i]["pickup"]
		if not is_instance_valid(pickup) or not pickup.is_visible_in_tree():
			continue
		var outline: PackedVector2Array = PackHandling.screen_outline(pickup, camera)
		if outline.size() < 3 or not Geometry2D.is_point_in_polygon(screen, outline):
			continue
		var box := Rect2(outline[0], Vector2.ZERO)
		for point: Vector2 in outline:
			box = box.expand(point)
		if box.get_area() < best_area:
			best = i
			best_area = box.get_area()
	return best


## The reachable container whose shelves are nearest ahead of `body` within `reach_m` (`forward`: where it
## faces, flat), or null.
static func find_open_near(body: Node3D, forward: Vector3, reach_m: float) -> ItemContainer:
	var best: ItemContainer = null
	var best_m: float = reach_m
	for node: Node in body.get_tree().get_nodes_in_group(GROUP):
		var container := node as ItemContainer
		if container == null or not container.is_reachable() or container.shelves.is_empty():
			continue
		var to: Vector3 = container.global_transform * container.shelves_box().get_center() - body.global_position
		to.y = 0.0
		if to.length() < best_m and (to.length() < 0.2 or forward.dot(to.normalized()) > 0.3):
			best = container
			best_m = to.length()
	return best


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

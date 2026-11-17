class_name ItemContainer
extends Node3D

## What a piece of furniture holds (a cabinet, a kitchen cupboard, a drawer, a chest): items standing on its
## shelves by their real size, each an ItemPickup reached through its search. The list is saved; pickups follow.

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
## The frosted veil over the open face (owner: unclear shapes until searched) and how far out of it it stands.
const VEIL_SHADER: Shader = preload("res://shaders/items/frosted_veil.gdshader")
const VEIL_OUT_M: float = 0.004

## Stable id for the save ("container/<id>").
@export var container_id: StringName = &""
## The free space above each shelf, in this node's space: its bottom face is the shelf's top.
@export var shelves: Array[AABB] = []
## The door that must be open to reach in (null: always open).
@export var door: Cabinet
## More ways in (kitchen doors side by side, a drawer, a chest's lid): open when any of them is (each an Opener:
## a Cabinet, a Drawer, or any new kind). `door`, when set, counts as one of them.
@export var openers: Array[Opener] = []
## The shelves open upward (a drawer, a chest): the frost and the search sit on their top face, not the front.
@export var opens_up: bool = false
## The whole piece of furniture these shelves are in (a dresser for one of its drawers); null: the parent.
@export var furniture: Node3D

## Per item: {"id", "state": Dictionary, "world_id": StringName (seeded from the world, or &""),
## "pickup": ItemPickup}.
var items: Array[Dictionary] = []
## Each item id's outline as a pickup stands (its own space), measured once.
static var _outlines: Dictionary = {}
var _body := AABB()
var _veil: MeshInstance3D
var _search: ContainerSearch


func _ready() -> void:
	add_to_group(&"saveable")
	add_to_group(GROUP)
	## F on the door only opens and shuts it; what is inside is searched with a second F (ContainerSearch).
	_search = ContainerSearch.new()
	_search.container = self
	add_child(_search)
	## Filled before it entered the tree (a house built off-tree): laid out now, when items can be measured.
	if not items.is_empty():
		_layout()


## While the door is open and something is inside, the open face is frosted over (items read as blurs) and
## the search marker is offered; at Henry's own visit (the Hub holds this container) the frost lifts.
func _process(_delta: float) -> void:
	if shelves.is_empty():
		return
	if _veil == null:
		_veil = _make_veil()
	var player := get_tree().get_first_node_in_group(&"player")
	var hub := player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null
	var at_it: bool = hub != null and hub.container == self
	_veil.visible = is_reachable() and not items.is_empty() and not at_it


func _make_veil() -> MeshInstance3D:
	var box: AABB = shelves_box()
	var veil := MeshInstance3D.new()
	veil.name = "FrostedVeil"
	var quad := QuadMesh.new()
	veil.mesh = quad
	if opens_up:
		## Over the top face, lying flat (the quad faces +Z; turned to face up).
		quad.size = Vector2(box.size.x, box.size.z)
		veil.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(box.get_center().x, box.end.y + VEIL_OUT_M, box.get_center().z))
	else:
		quad.size = Vector2(box.size.x, box.size.y)
		veil.position = Vector3(box.get_center().x, box.get_center().y, box.end.z + VEIL_OUT_M)
	var frost := ShaderMaterial.new()
	frost.shader = VEIL_SHADER
	veil.material_override = frost
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)
	return veil


## The whole piece of furniture these shelves are in (furniture, else the parent).
func furniture_root() -> Node3D:
	return furniture if furniture != null else get_parent() as Node3D


## The front: the middle of the shelves' open face, its outward way (flat) and the right of one looking in,
## world: [Vector3, Vector3, Vector3].
func front() -> Array:
	var box: AABB = shelves_box()
	var out: Vector3 = (global_basis.orthonormalized() * Vector3.BACK).slide(Vector3.UP).normalized()
	var front_at: Vector3 = global_transform * Vector3(box.get_center().x, box.get_center().y, box.end.z)
	return [front_at, out, Vector3.UP.cross(out).normalized()]


## Where Henry stands to use it, coming from `from` (world): the owner's Henry point (ContainerFraming) on the
## free side (free_side), else out from the front past the edge; {"at": Vector3 (floor height of `from`),
## "face": Vector3 (a point he turns to), "side": -1.0 left or 1.0 right, as one looks in}.
func visit_spot(from: Vector3) -> Dictionary:
	var face: Array = front()
	var right: Vector3 = face[2]
	var side: float = free_side(from)
	var at: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * VISIT_OUT_M + right * side * (shelves_box().size.x * 0.5 + VISIT_PAST_M)
	var facing: Vector3 = face[0]
	var framing: ContainerFraming = ContainerFraming.load_saved()
	if framing != null:
		var henry: Transform3D = ContainerFraming.front_of(self) * ContainerFraming.on_side(framing.henry, side)
		at = henry.origin
		facing = henry.origin + henry.basis.z.slide(Vector3.UP).normalized()  # his visual faces +Z
	at.y = from.y
	facing.y = from.y
	return {"at": at, "face": facing, "side": side}


## The side the pack goes (-1 left, 1 right, as one looks in): away from the side-hinged doors swung open there
## (a single door counts open or not: it will be); otherwise (no door, open doors on both sides, a lid, a
## drawer) the side `from` (world) is on.
func free_side(from: Vector3) -> float:
	var doors: Array[Cabinet] = []
	for opener: Opener in all_openers():
		var cabinet := opener as Cabinet
		if cabinet != null and cabinet.door_hinge != null and cabinet.swing_axis.is_equal_approx(Vector3.UP):
			doors.append(cabinet)
	var blocked := Vector2.ZERO  # open doors on the left (x) and the right (y)
	for cabinet: Cabinet in doors:
		if doors.size() > 1 and not cabinet.is_open():
			continue
		var hinge: Vector3 = global_transform.affine_inverse() * cabinet.door_hinge.global_position
		if hinge.x > shelves_box().get_center().x:
			blocked.y += 1.0
		else:
			blocked.x += 1.0
	if blocked.x > 0.0 and blocked.y == 0.0:
		return 1.0
	if blocked.y > 0.0 and blocked.x == 0.0:
		return -1.0
	return 1.0 if (from - (front()[0] as Vector3)).dot(front()[2] as Vector3) >= 0.0 else -1.0


## The furniture's own outline, this node's space: every mesh of its parent but the door's (measured once).
func body_box() -> AABB:
	if _body.size != Vector3.ZERO:
		return _body
	var skips: Array[Node] = []
	for opener: Opener in all_openers():
		var cabinet := opener as Cabinet
		if cabinet != null and cabinet.door_hinge != null:
			skips.append(cabinet.door_hinge)
	var to_here: Transform3D = global_transform.affine_inverse()
	for node: Node in get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or is_ancestor_of(mesh) or not mesh.is_visible_in_tree():
			continue
		if skips.any(func(skip: Node) -> bool: return skip.is_ancestor_of(mesh)):
			continue
		var part: AABB = (to_here * mesh.global_transform) * mesh.mesh.get_aabb()
		_body = part if _body.size == Vector3.ZERO else _body.merge(part)
	if _body.size == Vector3.ZERO:
		_body = shelves_box()
	return _body


## Whether the shelves are low enough that Henry crouches to them (top below LOW_TOP_M over `floor_y`).
func is_low(floor_y: float) -> bool:
	return (global_transform * shelves_box().end).y - floor_y < LOW_TOP_M


## Whether Henry can reach in now: always with no way in to open, else when any of its ways in is open.
func is_reachable() -> bool:
	var ways: Array[Opener] = all_openers()
	if ways.is_empty():
		return true
	for opener: Opener in ways:
		if opener.is_open():
			return true
	return false


## Its ways in: `door` (when set) and `openers`.
func all_openers() -> Array[Opener]:
	var out: Array[Opener] = []
	if door != null:
		out.append(door)
	for opener: Opener in openers:
		if opener != null and not out.has(opener):
			out.append(opener)
	return out


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
	if not is_inside_tree():
		return &""  # nothing can be measured off-tree: what a built house holds is laid out on entering the tree
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
		SurvivalItemVisual.release(pickup)
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
	if not is_inside_tree():
		return  # _ready lays it out (an item measures only in the tree, where its model is built)
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
	pickup.in_container = true  # reached through the search, not F on it
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
	if not is_inside_tree():
		return AABB()  # a probe builds its model in _ready: off-tree it would measure, and cache, nothing
	var probe := ItemPickup.new()
	probe.item_id = id
	probe.show_ground_highlight = false
	add_child(probe)
	var box: AABB = BackpackModel._local_bounds(probe)
	SurvivalItemVisual.release(probe)
	_outlines[id] = box
	return box

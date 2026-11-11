class_name PlayerHubComponent
extends Node

## Henry's inspection state (Tab): movement stops, a camera frames his back and
## the pack opens on him. Presents InventoryComponent and pockets; stores nothing.

signal hub_opened
signal hub_closed
## Result of a completed 3D Hub action. Cancelling a drag has no result.
signal action_result(success: bool)
## Emitted after an item moved between the pack and a Quick Access zone.
signal contents_changed
## Emitted when a quick-stowed item has dropped into the pack.
signal stow_landed
## Full inspection: the pack is off, in front of Henry, fully open. Future
## sorting, sections, repair and crafting attach here.
signal inspection_opened(pack: PackRig)
signal inspection_closed

const ACTION: StringName = &"open hub"
const CLOSE_ACTION: StringName = &"pause"
const OVERWEIGHT: StringName = &"overweight"
## Pockets the pack contents already stand for; not offered as Quick Access.
## Seconds the stowed item rises, then drops into the open top flap.
const STOW_LIFT_TIME: float = 0.28
const STOW_DROP_TIME: float = 0.32
## Where inspection stands the pack and Kenny, in Henry's space (he faces -Z).
const INSPECT_PACK_SPOT: Vector3 = Vector3(0.0, -0.9, -0.75)
const INSPECT_KENNY_SPOT: Vector3 = Vector3(0.7, -0.9, -0.3)
## A threat shuts the open Hub (Green Hell): damage, or falling faster than this, m/s (interrupt()).
const INTERRUPT_FALL_SPEED: float = 2.0
## An open container this near ahead of Henry joins the held pack (its shelves), metres.
const CONTAINER_REACH_M: float = 1.3
## Something put down from the open pack lands this far ahead of Henry, metres.
const DROP_AHEAD_M: float = 0.7
## route_destination's answer when the item stays in the pack.
const PACK_DESTINATION: StringName = &"pack"

@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export_group("Camera")
## Metres out from the pack, to its side and above it, the Hub camera stands.
@export var camera_back: float = 1.3
@export var camera_side: float = 0.4
@export var camera_height: float = 0.3
@export var camera_blend_time: float = 0.45
## The pack-in-hands view's angle of view, degrees.
@export var pack_view_fov: float = 50.0
## At a container: a longer lens, so the pack and the furniture side by side keep their shape.
@export var container_view_fov: float = 34.0
## 3D inventory: Tab takes the pack into Henry's hands, open toward a camera facing him (else it opens on his back).
@export var pack_in_hands: bool = true

## The pack on Henry; resolved from his visual when left empty.
var pack: PackRig
var _open: bool = false
var _stows_in_flight: int = 0
var _camera: Camera3D
var _previous_camera: Camera3D
var _panel: PlayerHubPanel
var _inspecting: bool = false
## True when inspection took the pack off Henry's back (not already set down seated).
var _took_pack_off: bool = false
## Restore the gameplay mouse mode exactly when leaving the Hub.
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _thermal_manager: ThermalManager
## The pack held before Henry while the Hub is open in pack_in_hands mode.
var _front_hold: PackFrontHold
## The open container Henry stands at while the pack is held (its shelves join the inventory), or null.
var container: ItemContainer
## The Quick Access cards beside the held pack and the hands working in it (pack_in_hands mode).
var _shelf: PackQuickShelf
var _hands: PackHandling
## Set while full inspection opens the Hub: it sets the pack down instead of taking it in hand.
var _opening_inspection: bool = false


## A UI composition root owns the presentation panel, not Henry.
func bind_panel(panel: PlayerHubPanel) -> void:
	_panel = panel


func _ready() -> void:
	var body: Node = get_parent()
	var health := body.get_node_or_null(^"PlayerHealthSystem") as PlayerHealthSystem if body != null else null
	if health != null:
		health.hurt.connect(func(_amount: float, _source: String) -> void: interrupt())
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null and body != null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent


## Henry searches `shelves` where he stands (owner: he walks up himself): he faces it, crouches at a low one
## and takes the pack off together, and the view cuts to the working frame (_cut_to_container).
func visit_container(shelves: ItemContainer) -> bool:
	var body := get_parent() as Player
	if _open or body == null or not _can_open() or not shelves.is_reachable():
		return false
	var spot: Dictionary = shelves.visit_spot(body.global_position)
	body.stop_moving()
	body.face_work_target(shelves.front()[0])
	if shelves.is_low(body.global_position.y - 1.0):  # the body's origin is the capsule centre
		body.set_work_crouch(true)
	if not _open_at(shelves, spot["side"]):
		_end_visit()
		return false
	return true


## At a container, until the cut, the view eases toward the Tab view of Henry as he is now: he crouches while the
## pack comes off, so a target fixed at the start would aim where his chest was standing.
func _process(delta: float) -> void:
	if not _open or not is_instance_valid(_camera) or not is_instance_valid(_front_hold) or container == null:
		return
	if _front_hold.is_container_cut():
		return
	var ease: float = 1.0 - exp(-delta / maxf(camera_blend_time * 0.35, 0.01))
	_camera.global_transform = _camera.global_transform.interpolate_with(get_camera_target(), ease)


## A threat (damage, a fall; later thin ice and the like): the open Hub shuts at once.
## Time never stops in the Hub, so this is what makes an open pack a risk.
func interrupt() -> void:
	if _open:
		close()


## The container view's angle: the owner's framing camera, else container_view_fov, degrees.
func _container_fov() -> float:
	var framing: ContainerFraming = ContainerFraming.load_saved()
	return framing.camera_fov if framing != null else container_view_fov


func _physics_process(_delta: float) -> void:
	var falling := get_parent() as CharacterBody3D
	if _open and falling != null and falling.velocity.y < -INTERRUPT_FALL_SPEED:
		interrupt()


## He stands up from a container's crouch (the pack closed, or it could not open).
func _end_visit() -> void:
	var body := get_parent() as Player
	if body != null and body.is_work_crouching():
		body.set_work_crouch(false)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


## Esc closes the Hub before the pause menu hears it.
func _input(event: InputEvent) -> void:
	if _open and InputMap.has_action(CLOSE_ACTION) and event.is_action_pressed(CLOSE_ACTION):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## World pickup's visible stow animation, not a second pickup state.
func is_stowing_pickup() -> bool:
	return _stows_in_flight > 0


func toggle() -> bool:
	return close() if _open else open()


## Enters the Hub. Refused mid-fall, while carrying in both hands or mid-action. By an open container within
## reach Henry first steps over to it (visit_container) and the pack opens there.
func open() -> bool:
	if _open:
		return false
	var body := get_parent() as Node3D
	if pack_in_hands and body != null and not _opening_inspection:
		var near: ItemContainer = ItemContainer.find_open_near(body, -body.global_basis.z.slide(Vector3.UP).normalized(), CONTAINER_REACH_M)
		if near != null:
			return visit_container(near)
	return _open_at(null, 1.0)


## Enters the Hub, at `shelves` (null: none) with the pack held on `side` of it.
func _open_at(shelves: ItemContainer, side: float) -> bool:
	if _open or not _can_open() or not _stow_safe_held_items():
		_end_visit()
		return false
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open = true
	var pack: PackRig = _pack()
	var visual: HenryUALAnimation = _visual()
	## 3D inventory (stage 3): Henry takes the pack off into his hands and opens it toward the camera.
	if pack_in_hands and not _opening_inspection and visual != null and pack != null and not visual.is_pack_down():
		_front_hold = visual.hold_pack_front()
		## At an open container (visited), its shelves join the pack (ItemContainer).
		container = shelves
		if _front_hold != null and container != null:
			_front_hold.begin_container(container, side, _container_fov())
	elif pack != null:
		pack.set_openness(PackRig.Openness.FULL)
	_enter_camera()
	if _front_hold == null:
		_show_panel()
	elif is_instance_valid(_camera):
		## Quick Access beside the open pack: the real pockets' 3D items on cards at the frame's sides.
		_shelf = PackQuickShelf.new()
		_shelf.name = "QuickShelf"
		_camera.add_child(_shelf)
		_shelf.setup(self, _camera)
		## The ring cursor and hands: take from the pack or a pocket, put it in the other, G puts it down.
		var layer := CanvasLayer.new()
		layer.name = "PackCursorLayer"
		## Keep the ring, readout and weight above the fullscreen Hub glow (layer 1).
		layer.layer = 3
		add_child(layer)
		var ring := PackCursor.new()
		layer.add_child(ring)
		_hands = PackHandling.new()
		_hands.name = "PackHandling"
		add_child(_hands)
		_hands.setup(self, pack.get_straps(), _shelf, _camera, ring, container)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if container != null:
			## At a container the game view stays while he takes the pack off; the frame and its UI come at the cut.
			_shelf.visible = false
			_hands.enabled = false
			_front_hold.settled.connect(_cut_to_container, CONNECT_ONE_SHOT)
	hub_opened.emit()
	return true


## The pack opens fully with a pack item under the cursor, to be dragged into a
## pocket or left in the pack. Releasing the drag closes the Hub.
func open_placement(item_id: StringName) -> bool:
	if inventory == null or not inventory.has_item(item_id) or not open():
		return false
	if is_instance_valid(_panel):
		_panel.begin_placement(item_id)
	return true


## Full inspection (#75): the pack comes off and stands in front of Henry, fully
## open, the camera looks down at it. Seated with the pack already down, it opens there.
func open_inspection() -> bool:
	if _inspecting:
		return false
	var visual: HenryUALAnimation = _visual()
	if visual == null or _pack() == null:
		return false
	_opening_inspection = true
	var opened: bool = _open or open()
	_opening_inspection = false
	if not opened:
		return false
	var body := get_parent() as Node3D
	_took_pack_off = not visual.is_pack_down()
	if _took_pack_off:
		var front: Transform3D = body.global_transform * Transform3D(Basis(Vector3.UP, PI), INSPECT_PACK_SPOT)  # flaps face Henry
		var beside: Transform3D = body.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), INSPECT_KENNY_SPOT)
		visual.set_pack_down(front, beside)
	_inspecting = true
	_pack().set_openness(PackRig.Openness.FULL)
	if is_instance_valid(_camera):
		create_tween().set_trans(Tween.TRANS_SINE).tween_property(_camera, ^"global_transform", get_camera_target(), camera_blend_time)
	if is_instance_valid(_panel):
		_panel.set_inspecting(true)
	inspection_opened.emit(_pack())
	return true


## The live Quick Access cards while the pack is held open, or null.
func get_quick_shelf() -> PackQuickShelf:
	return _shelf if is_instance_valid(_shelf) else null


## The hands working in the held pack (ring cursor, take and put), or null.
func get_pack_hands() -> PackHandling:
	return _hands if is_instance_valid(_hands) else null


func is_inspecting() -> bool:
	return _inspecting


func close() -> bool:
	if not _open:
		return false
	_open = false
	var pack: PackRig = _pack()
	var visual: HenryUALAnimation = _visual()
	if _inspecting:
		_inspecting = false
		if _took_pack_off and visual != null:
			visual.pick_pack_up()
		_took_pack_off = false
		inspection_closed.emit()
	if _front_hold != null and visual != null:
		## It swings back on and shuts there (PackFrontHold).
		visual.release_pack_front()
		_front_hold = null
	elif pack != null:
		## Set down by the stove it stays ajar; on the back it shuts.
		var down: bool = visual != null and visual.is_pack_down()
		pack.set_openness(PackRig.Openness.AJAR if down else PackRig.Openness.CLOSED)
	if is_instance_valid(_shelf):
		_shelf.queue_free()
	_shelf = null
	if is_instance_valid(_hands):
		_hands.queue_free()
		var layer: Node = get_node_or_null(^"PackCursorLayer")
		if layer != null:
			layer.queue_free()
	_hands = null
	container = null
	_end_visit()
	_exit_camera()
	if is_instance_valid(_panel):
		_panel.hide_hub()
	Input.mouse_mode = _previous_mouse_mode
	hub_closed.emit()
	return true


## Pack contents: id, count, name, weight and size class per stack.
func get_pack_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if inventory == null:
		return out
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item == null or item.carried_in_hands:
			continue
		out.append({"id": item.id, "count": entry["count"], "name": item.display_name,
			"weight": item.weight, "size": item.size_class})
	return out


## Quick Access zones: pockets on what Henry wears. Keys: path, name, max_size, item_id.
func get_quick_access_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if equipment == null:
		return out
	for pocket: Dictionary in equipment.get_available_pockets():
		var path: StringName = equipment.pocket_path(pocket["body_slot"], pocket["pocket"])
		var definition: EquipmentSlotDefinition = pocket["definition"]
		if not definition.quick_access:
			continue
		out.append({"path": path, "name": definition.display_name,
			"max_size": definition.max_size, "item_id": pocket["item_id"]})
	return out


## Whether an item from the pack fits a zone, and why not.
func can_place(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	if equipment == null or inventory == null or not inventory.has_item(item_id):
		return EquipmentComponent.Refusal.UNKNOWN_ITEM
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2 or not _is_quick_zone(zone_path):
		return EquipmentComponent.Refusal.NO_SUCH_SLOT
	return equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id)


## Moves one item from the pack into a Quick Access zone.
func move_to_zone(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	var refusal: EquipmentComponent.Refusal = can_place(item_id, zone_path)
	if refusal != EquipmentComponent.Refusal.NONE:
		return refusal
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	var payload: Dictionary = inventory.take_instance(item_id)
	if payload.is_empty():
		return EquipmentComponent.Refusal.UNKNOWN_ITEM
	var state: Dictionary = payload.get("instance_state", {})
	refusal = equipment.stow_instance(StringName(parts[0]), StringName(parts[1]), item_id, state)
	if refusal != EquipmentComponent.Refusal.NONE:
		# Even a re-entrant refusal must not delete the source instance.
		if not inventory.try_add_instance(payload["item"] as ItemResource, state):
			push_error("Hub: failed to restore item after rejected pocket placement")
		return refusal
	contents_changed.emit()
	return EquipmentComponent.Refusal.NONE


## Returns a zone's item to the pack. Empty on success, else a refusal reason.
func move_to_pack(zone_path: StringName) -> StringName:
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or inventory == null or parts.size() != 2:
		return &"no_such_slot"
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	var payload: Dictionary = equipment.take_pocket_instance(body_slot, pocket)
	if payload.is_empty():
		return &"empty"
	var item_id: StringName = payload["id"]
	var state: Dictionary = payload.get("instance_state", {})
	## Taken out first, so its weight is not counted twice before adding to the pack.
	if not inventory.try_add_instance(ItemCatalog.get_item(item_id), state):
		if equipment.stow_instance(body_slot, pocket, item_id, state) != EquipmentComponent.Refusal.NONE:
			push_error("Hub: failed to restore pocket after rejected pack transfer")
		return OVERWEIGHT
	contents_changed.emit()
	return &""


## Takes item `index` off `shelves` into the pack, or into the quick pocket `zone_path`: &"" when it moved,
## else why not (OVERWEIGHT, or the pocket's refusal as &"pocket_refused").
func move_from_container(shelves: ItemContainer, index: int, zone_path: StringName = &"") -> StringName:
	if shelves == null or inventory == null or index < 0 or index >= shelves.items.size():
		return &"empty"
	var item_id: StringName = shelves.items[index]["id"]
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if zone_path != &"":
		var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
		if equipment == null or parts.size() != 2:
			return &"no_such_slot"
		if equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id) != EquipmentComponent.Refusal.NONE:
			return &"pocket_refused"
		var into_pocket: Dictionary = shelves.take(index)
		if equipment.stow_instance(StringName(parts[0]), StringName(parts[1]), item_id, into_pocket["state"]) != EquipmentComponent.Refusal.NONE:
			shelves.put(item_id, into_pocket["state"])
			return &"pocket_refused"
	else:
		if item == null or inventory.get_add_refusal(item) != &"":
			return OVERWEIGHT
		var into_pack: Dictionary = shelves.take(index)
		if not inventory.try_add_instance(item, into_pack["state"]):
			shelves.put(item_id, into_pack["state"])
			return OVERWEIGHT
	contents_changed.emit()
	return &""


## Puts one `item_id` from the pack, or the quick pocket `zone_path`'s item, onto `shelves`: &"" when it moved,
## else why not (ItemContainer.NO_ROOM).
func move_to_container(shelves: ItemContainer, item_id: StringName = &"", zone_path: StringName = &"") -> StringName:
	if shelves == null or inventory == null:
		return &"empty"
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if zone_path != &"":
		if equipment == null or parts.size() != 2:
			return &"no_such_slot"
		item_id = equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1]))
	if item_id == &"" or (zone_path == &"" and not inventory.has_item(item_id)):
		return &"empty"
	var why: StringName = shelves.refusal(item_id)
	if why != &"":
		return why
	var payload: Dictionary = equipment.take_pocket_instance(StringName(parts[0]), StringName(parts[1])) if zone_path != &"" else inventory.take_instance(item_id)
	if payload.is_empty():
		return &"empty"
	shelves.put(item_id, payload.get("instance_state", {}))
	contents_changed.emit()
	return &""


## Puts one `item_id` from the pack down on the ground ahead of Henry (its state kept). False with no ground there.
func drop_from_pack(item_id: StringName) -> bool:
	var body := get_parent() as Node3D
	var at: Vector3 = ItemPickup.ground_ahead(body, DROP_AHEAD_M)
	if inventory == null or at == Vector3.INF or not inventory.has_item(item_id):
		return false
	var payload: Dictionary = inventory.take_instance(item_id)
	if payload.is_empty():
		return false
	ItemPickup.spawn_dropped(body, item_id, payload.get("instance_state", {}), at)
	contents_changed.emit()
	return true


## Puts a quick pocket's item down on the ground ahead of Henry. False with no ground there or an empty pocket.
func drop_from_zone(zone_path: StringName) -> bool:
	var body := get_parent() as Node3D
	var at: Vector3 = ItemPickup.ground_ahead(body, DROP_AHEAD_M)
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or at == Vector3.INF or parts.size() != 2:
		return false
	var payload: Dictionary = equipment.take_pocket_instance(StringName(parts[0]), StringName(parts[1]))
	if payload.is_empty():
		return false
	ItemPickup.spawn_dropped(body, payload["id"], payload.get("instance_state", {}), at)
	contents_changed.emit()
	return true


## Moves a quick pocket's item into another quick pocket, or says why not (that pocket full, too small).
func move_between_zones(from_path: StringName, to_path: StringName) -> EquipmentComponent.Refusal:
	var source: PackedStringArray = String(from_path).split(EquipmentComponent.POCKET_SEPARATOR)
	var target: PackedStringArray = String(to_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or source.size() != 2 or target.size() != 2 or not _is_quick_zone(to_path):
		return EquipmentComponent.Refusal.NO_SUCH_SLOT
	var item_id: StringName = equipment.get_pocket_item(StringName(source[0]), StringName(source[1]))
	var refusal: EquipmentComponent.Refusal = equipment.can_stow(StringName(target[0]), StringName(target[1]), item_id)
	if refusal != EquipmentComponent.Refusal.NONE:
		return refusal
	var payload: Dictionary = equipment.take_pocket_instance(StringName(source[0]), StringName(source[1]))
	refusal = equipment.stow_instance(StringName(target[0]), StringName(target[1]), item_id, payload.get("instance_state", {}))
	if refusal != EquipmentComponent.Refusal.NONE:
		equipment.stow_instance(StringName(source[0]), StringName(source[1]), item_id, payload.get("instance_state", {}))
		return refusal
	contents_changed.emit()
	return EquipmentComponent.Refusal.NONE


## Tap-F stow: the item's visual lifts, flies into the top flap and is freed.
## The item is already in the inventory; this is presentation only.
func stow_visual(visual: Node3D, item_id: StringName = &"") -> void:
	var rig: PackRig = _pack()
	if visual == null:
		return
	if rig == null or not rig.is_inside_tree() or not visual.is_inside_tree():
		visual.queue_free()
		_auto_stow_preferred(item_id)
		stow_landed.emit()
		return
	_stows_in_flight += 1
	if not _open:
		rig.set_openness(PackRig.Openness.TOP_ONLY)
	var start: Vector3 = visual.global_position
	var mouth: Vector3 = rig.global_transform * Vector3(0.0, rig.size.y * 0.5 + 0.08, 0.0)
	var peak: Vector3 = start.lerp(mouth, 0.35) + Vector3(0.0, 0.45, 0.0)
	var tween: Tween = visual.create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, ^"global_position", peak, STOW_LIFT_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, ^"global_position", mouth, STOW_DROP_TIME).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(visual, ^"scale", visual.scale * 0.35, STOW_DROP_TIME)
	tween.tween_callback(_on_stow_landed.bind(visual, item_id))


func _on_stow_landed(visual: Node3D, item_id: StringName = &"") -> void:
	visual.queue_free()
	_stows_in_flight = maxi(0, _stows_in_flight - 1)
	_auto_stow_preferred(item_id)
	stow_landed.emit()
	var rig: PackRig = _pack()
	if rig != null and not _open and _stows_in_flight == 0:
		rig.set_openness(PackRig.Openness.CLOSED)


## Where a picked-up item settles: the first free Quick Access pocket that fits a
## preferred item, else the pack. Pockets and pack both carry its weight.
func route_destination(item_id: StringName) -> StringName:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null or not item.prefer_quick_access or equipment == null:
		return PACK_DESTINATION
	for zone: Dictionary in get_quick_access_zones():
		if zone["item_id"] != &"":
			continue
		var path: StringName = zone["path"]
		var parts: PackedStringArray = String(path).split(EquipmentComponent.POCKET_SEPARATOR)
		if parts.size() == 2 and equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id) == EquipmentComponent.Refusal.NONE:
			return path
	return PACK_DESTINATION


## Moves a just-picked item to its route destination at once (hand pickups skip the flight).
func route_now(item_id: StringName) -> StringName:
	var path: StringName = route_destination(item_id)
	if _open or path == PACK_DESTINATION or inventory == null or not inventory.has_item(item_id):
		return PACK_DESTINATION
	return path if move_to_zone(item_id, path) == EquipmentComponent.Refusal.NONE else PACK_DESTINATION


## Tap-F auto-sort is deliberately narrow: only explicitly preferred items move,
## and only into Quick Access pockets. The item first lands in InventoryComponent.
func _auto_stow_preferred(item_id: StringName) -> void:
	if _open or item_id == &"" or inventory == null or equipment == null or not inventory.has_item(item_id):
		return
	var path: StringName = route_destination(item_id)
	if path != PACK_DESTINATION and can_place(item_id, path) == EquipmentComponent.Refusal.NONE:
		move_to_zone(item_id, path)


## Item Use contract: a sibling component with can_use(id) and use(id) handles it.
func can_use(item_id: StringName) -> bool:
	return _user_for(item_id) != null


## Closes the Hub and hands the item to its user (bedroll: placement preview).
func use_item(item_id: StringName) -> bool:
	var user: Node = _user_for(item_id)
	if user == null:
		return false
	close()
	return ItemUserCapability.use(user, item_id)


## Uses a pocketed item: it passes through the pack to its user and goes back
## to the pocket if nothing could use it.
func use_from_zone(zone_path: StringName) -> bool:
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or parts.size() != 2:
		return false
	var item_id: StringName = equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1]))
	var item: ItemResource = ItemCatalog.get_item(item_id) if item_id != &"" else null
	if item_id == &"" or move_to_pack(zone_path) != &"":
		return false
	if use_item(item_id):
		if item != null and item.opens_into != &"":
			move_to_zone(item.opens_into, zone_path)
		elif item != null and item.water_capacity_ml > 0 and item.consumable != null:
			move_to_zone(item.consumable.leaves_behind_id, zone_path)
		return true
	move_to_zone(item_id, zone_path)
	return false


func _user_for(item_id: StringName) -> Node:
	var body: Node = get_parent()
	if body == null or inventory == null or not inventory.has_item(item_id):
		return null
	for child: Node in body.get_children():
		if child != self and ItemUserCapability.can_use(child, item_id):
			return child
	return null


## Where the Hub camera settles: out from the pack's face, looking at it.
func get_camera_target() -> Transform3D:
	var body := get_parent() as Node3D
	var pack: PackRig = _pack()
	if is_instance_valid(_front_hold):
		## At a container: the Tab view while the pack comes off, the furniture's frame after the cut.
		return _front_hold.container_view(_container_fov()) if is_instance_valid(_front_hold.container) and _front_hold.is_container_cut() else _front_hold.front_view(pack_view_fov)
	if _inspecting and pack != null and pack.is_inside_tree():
		## Beside Henry, past his left shoulder, looking down into the open pack on the floor.
		var basis: Basis = body.global_transform.basis.orthonormalized()
		var eye: Vector3 = body.global_position - basis.x * 0.9 + basis.z * 0.2 + Vector3(0.0, 0.7, 0.0)
		return Transform3D(Basis.IDENTITY, eye).looking_at(pack.global_position, Vector3.UP)
	var centre: Vector3
	var outward: Vector3
	if pack != null and pack.is_inside_tree():
		centre = pack.global_position
		outward = -pack.global_transform.basis.z
	else:
		## The body faces -Z, so its back is +Z.
		centre = body.global_position + Vector3(0.0, 1.2, 0.0) + body.global_transform.basis.z * 0.25
		outward = body.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized() if outward.length() > 0.01 else Vector3.BACK
	var side: Vector3 = Vector3.UP.cross(outward).normalized()
	var eye: Vector3 = centre + outward * camera_back + side * camera_side + Vector3(0.0, camera_height, 0.0)
	return Transform3D(Basis.IDENTITY, eye).looking_at(centre, Vector3.UP)


## How cold Henry's hands are, 0..1 (ExtremityCold load): slower, shakier hands in the open pack.
func get_hands_cold() -> float:
	return _thermal_manager.get_extremity_cold(&"hands") if _thermal_manager != null else 0.0


func set_thermal_manager(thermal: ThermalManager) -> void:
	_thermal_manager = thermal


## Detailed Hub readout, sourced from the systems that own the formulas.
func get_survival_readout() -> Dictionary:
	var body: Node = get_parent()
	var movement := body.get_node_or_null(^"MovementController") as MovementController if body != null else null
	var bio := body.get_node_or_null(^"BioMonitorManager") as BioMonitorManager if body != null else null
	var result := {
		"weight": get_weight(),
		"max_weight": get_max_weight(),
		"load_fraction": inventory.get_load_fraction() if inventory != null else 0.0,
		"move_multiplier": movement.get_load_speed_multiplier() if movement != null else 1.0,
		"energy_multiplier": bio.get_energy_drain_multiplier() if bio != null else 1.0,
		"energy_reason": bio.get_energy_drain_reason() if bio != null else &"normal",
		"wetness": -1.0,
		"wetness_stage": -1,
		"drying": false,
		"insulation_multiplier": 1.0,
	}
	if _thermal_manager != null:
		result["wetness"] = _thermal_manager.get_wetness()
		result["wetness_stage"] = int(_thermal_manager.get_wetness_stage())
		result["drying"] = _thermal_manager.is_clothing_drying()
		result["insulation_multiplier"] = _thermal_manager.get_wetness_insulation_multiplier()
	return result


func get_weight() -> float:
	return inventory.get_total_weight() if inventory != null else 0.0


func get_max_weight() -> float:
	return inventory.max_carry_weight if inventory != null else 0.0


## The held pack dips under `kg` put into it (PackFrontHold.jolt); nothing when it is not held.
func jolt_held_pack(kg: float) -> void:
	if is_instance_valid(_front_hold):
		_front_hold.jolt(kg)


## The share of the carry limit past which Henry starts to slow (MovementController.load_penalty_starts).
func get_load_slows_at() -> float:
	var body: Node = get_parent()
	var movement := body.get_node_or_null(^"MovementController") as MovementController if body != null else null
	return movement.load_penalty_starts if movement != null else 1.0


func _can_open() -> bool:
	var body := get_parent() as CharacterBody3D
	if body != null and body.velocity.y < -0.5:
		return false
	var light := get_parent().get_node_or_null(^"HeldLightComponent") as HeldLightComponent if get_parent() != null else null
	if light != null and light.is_burning():
		return false
	var visual: HenryUALAnimation = _visual()
	return visual == null or not (visual.is_carrying() or visual.is_action_locking())


func _stow_safe_held_items() -> bool:
	return get_parent() == null or HeldReleaseCapability.release_all(get_parent())


func _visual() -> HenryUALAnimation:
	var body: Node = get_parent()
	return body.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if body != null else null


func _pack() -> PackRig:
	if pack == null:
		var visual: HenryUALAnimation = _visual()
		pack = visual.get_pack_rig() if visual != null else null
	return pack


## Blends from the game camera to one over Henry's shoulder, facing his pack.
func _enter_camera() -> void:
	var body := get_parent() as Node3D
	if body == null or not body.is_inside_tree():
		return
	_previous_camera = body.get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "HubCamera"
	_camera.top_level = true
	_camera.fov = pack_view_fov if is_instance_valid(_front_hold) else 50.0
	## It sees what the game camera sees: reserved layers (dev map labels, snow contact) stay out.
	if _previous_camera != null:
		_camera.cull_mask = _previous_camera.cull_mask
		_camera.environment = _previous_camera.environment
		_camera.attributes = _previous_camera.attributes
		_camera.compositor = _previous_camera.compositor
	body.add_child(_camera)
	var target: Transform3D = get_camera_target()
	_camera.global_transform = _previous_camera.global_transform if _previous_camera != null else target
	_camera.make_current()
	## At a container the pack comes off as by Tab (the same view, so its turn off his back shows); the frame,
	## its blur and UI come at the cut (_cut_to_container).
	if is_instance_valid(_front_hold) and container != null:
		return  # the Tab view follows him as he crouches (_process), then the cut
	if is_instance_valid(_front_hold):
		_add_focus_blur()
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(_camera, ^"global_transform", target, camera_blend_time)


## The held pack in focus: everything else, Henry too, blurs (a stencil mask, not depth).
func _add_focus_blur() -> void:
	var blur := PackFocusBlur.new()
	blur.name = "PackFocusBlur"
	_camera.add_child(blur)
	blur.setup(_pack(), container.get_parent() as Node3D if container != null else null)


## The pack is off his back at a container: a hard cut to the working frame (owner), its blur and UI on.
func _cut_to_container() -> void:
	if not _open or not is_instance_valid(_camera) or container == null:
		return
	_camera.fov = _container_fov()
	_camera.global_transform = get_camera_target()
	_add_focus_blur()
	## Outlines traced in this frame would use the view before the jump: the cards and ring wait one frame.
	PackHandling.clear_outline_cache()
	await get_tree().process_frame
	if not _open:
		return
	if is_instance_valid(_shelf):
		_shelf.visible = true
	if is_instance_valid(_hands):
		_hands.enabled = true


func _exit_camera() -> void:
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null
	_previous_camera = null


func _show_panel() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_panel):
		_panel.show_hub()


## Whether a worn pocket is reached without opening anything (see EquipmentSlotDefinition).
func _is_quick_zone(zone_path: StringName) -> bool:
	for zone: Dictionary in get_quick_access_zones():
		if zone["path"] == zone_path:
			return true
	return false

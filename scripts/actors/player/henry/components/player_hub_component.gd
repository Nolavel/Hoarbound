class_name PlayerHubComponent
extends Node

## Henry's inspection state (Tab): movement stops, a camera frames his back and
## the pack opens on him. Presents InventoryComponent and pockets; stores nothing.

signal hub_opened
signal hub_closed
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
const EXCLUDED_ZONES: Array[StringName] = [&"pack/pack_main"]
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

## The pack on Henry; resolved from his visual when left empty.
var pack: PackRig
var _open: bool = false
var _stows_in_flight: int = 0
## F press tracking for hold-to-place: the item stowed during the current press.
var _camera: Camera3D
var _previous_camera: Camera3D
var _panel: PlayerHubPanel
var _inspecting: bool = false
## True when inspection took the pack off Henry's back (not already set down seated).
var _took_pack_off: bool = false
## Restore the gameplay mouse mode exactly when leaving the Hub.
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _thermal_manager: ThermalManager


func _ready() -> void:
	var body: Node = get_parent()
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null and body != null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent


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


func toggle() -> bool:
	return close() if _open else open()


## Enters the Hub. Refused mid-fall, while carrying in both hands or mid-action.
func open() -> bool:
	if _open or not _can_open() or not _stow_safe_held_items():
		return false
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_open = true
	var pack: PackRig = _pack()
	if pack != null:
		pack.set_openness(PackRig.Openness.FULL)
	_enter_camera()
	_show_panel()
	hub_opened.emit()
	return true


## Hold F: the pack opens fully with the just-picked item under the cursor, to be
## dragged into a pocket or left in the pack. Releasing the drag closes the Hub.
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
	if not _open and not open():
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
	if pack != null:
		## Set down by the stove it stays ajar; on the back it shuts.
		var down: bool = visual != null and visual.is_pack_down()
		pack.set_openness(PackRig.Openness.AJAR if down else PackRig.Openness.CLOSED)
	_exit_camera()
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
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
		if EXCLUDED_ZONES.has(path):
			continue
		var definition: EquipmentSlotDefinition = pocket["definition"]
		out.append({"path": path, "name": definition.display_name,
			"max_size": definition.max_size, "item_id": pocket["item_id"]})
	return out


## Whether an item from the pack fits a zone, and why not.
func can_place(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	if equipment == null or inventory == null or not inventory.has_item(item_id):
		return EquipmentComponent.Refusal.UNKNOWN_ITEM
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2 or EXCLUDED_ZONES.has(zone_path):
		return EquipmentComponent.Refusal.NO_SUCH_SLOT
	return equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id)


## Moves one item from the pack into a Quick Access zone.
func move_to_zone(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	var refusal: EquipmentComponent.Refusal = can_place(item_id, zone_path)
	if refusal != EquipmentComponent.Refusal.NONE:
		return refusal
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	inventory.try_remove(item_id)
	equipment.stow(StringName(parts[0]), StringName(parts[1]), item_id)
	contents_changed.emit()
	return EquipmentComponent.Refusal.NONE


## Returns a zone's item to the pack. Empty on success, else a refusal reason.
func move_to_pack(zone_path: StringName) -> StringName:
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or inventory == null or parts.size() != 2:
		return &"no_such_slot"
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	var item_id: StringName = equipment.take_from_pocket(body_slot, pocket)
	if item_id == &"":
		return &"empty"
	## Taken out first, so its own weight is not counted twice by the pack.
	if not inventory.try_add(ItemCatalog.get_item(item_id)):
		equipment.stow(body_slot, pocket, item_id)
		return OVERWEIGHT
	contents_changed.emit()
	return &""


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
	return bool(user.call(&"use", item_id))


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
		if child != self and child.has_method(&"can_use") and bool(child.call(&"can_use", item_id)):
			return child
	return null


## Where the Hub camera settles: out from the pack's face, looking at it.
func get_camera_target() -> Transform3D:
	var body := get_parent() as Node3D
	var pack: PackRig = _pack()
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
	var body: Node = get_parent()
	if body == null:
		return true
	for child: Node in body.get_children():
		if child.has_method(&"is_burning") and bool(child.call(&"is_burning")):
			return false
		if not child.has_method(&"is_holding") or not bool(child.call(&"is_holding")):
			continue
		if child.has_method(&"put_away_unlit") and bool(child.call(&"put_away_unlit")):
			continue
		if child.has_method(&"put_away") and bool(child.call(&"put_away")):
			continue
		return false
	return true


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
	_camera.fov = 50.0
	body.add_child(_camera)
	var target: Transform3D = get_camera_target()
	_camera.global_transform = _previous_camera.global_transform if _previous_camera != null else target
	_camera.make_current()
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(_camera, ^"global_transform", target, camera_blend_time)


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
	_panel = PlayerHubPanel.new()
	_panel.hub = self
	add_child(_panel)

class_name HeldItemComponent
extends Node

## Presents an owned pack/pocket item in the hand; storage remains its save authority.

## Held RMB: raise the held lighter before the chest and keep its flame lit.
const PRESENT_ACTION: StringName = &"present_held"
## The thumb gives out after this long; a fresh press lights it again.
const LIGHTER_FLAME_MAX_SECONDS: float = 10.0
## Arm rise before the wheel is struck.
const LIGHTER_RAISE_SECONDS: float = 0.3
## Lighter base under the solved palm, so the nozzle stands just above the fist.
const LIGHTER_BASE_BELOW_PALM: float = 0.035
const LIGHTER_STRIKE_EVENT: SoundEvent = preload("res://resources/audio/lighter_strike.tres")

@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var consumption: ConsumptionController

var _prop: Node3D
var _item_id: StringName = &""
var _source_zone: StringName = &""
var _using: bool = false
var _hint: Label
var _message_left: float = 0.0
var _presenting: bool = false
var _present_seconds: float = 0.0
## The upright lighter in the raised hand's frame, kept from the last full raise.
var _present_local: Transform3D = Transform3D.IDENTITY
var _has_present_local: bool = false


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if equipment == null:
		equipment = get_parent().get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if consumption == null:
		consumption = get_parent().get_node_or_null(^"ConsumptionController") as ConsumptionController
	if inventory != null:
		inventory.weight_changed.connect(func(_a: float, _b: float) -> void: _queue_sync())
	if equipment != null:
		equipment.slot_changed.connect(func(_a: StringName, _b: StringName) -> void: _queue_sync())


func supports_item(item_id: StringName) -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	return item != null and item.garment == null and not item.carried_in_hands \
		and item.size_class == ItemTraits.SizeClass.POCKET and item_id not in [&"hammer", &"road_flare"]


func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if not supports_item(item_id) or equipment == null:
		return false
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2 or equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1])) != item_id:
		return false
	if is_holding():
		return _item_id == item_id and _source_zone == zone_path
	var visual: HenryUALAnimation = _animation()
	var carry := get_parent().get_node_or_null(^"CarryComponent") as CarryComponent
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var use_offhand: bool = item != null and item.held_fit != null and item.held_fit.hand == HeldFit.Hand.RIGHT
	var socket: BoneAttachment3D = visual.get_offhand_socket() if visual != null and use_offhand else (visual.get_hand_socket() if visual != null else null)
	if visual == null or socket == null or visual.get_held_prop() != null or visual.get_offhand_prop() != null \
		or (carry != null and carry.is_carrying()) or visual.is_action_locking():
		return false
	_item_id = item_id
	_source_zone = zone_path
	_draw()
	return is_holding()


## Shows an item Henry already owns in his hand. Its pocket or the pack keeps the
## item and its weight; nothing is taken out of storage.
func present_owned(item_id: StringName) -> bool:
	if not supports_item(item_id) or is_holding():
		return false
	var zone: StringName = HeldOwnership.pocket_holding(equipment, item_id)
	if not HeldOwnership.owns(inventory, equipment, item_id, zone):
		return false
	var visual: HenryUALAnimation = _animation()
	var carry := get_parent().get_node_or_null(^"CarryComponent") as CarryComponent
	if visual == null or visual.get_held_prop() != null or visual.get_offhand_prop() != null \
		or (carry != null and carry.is_carrying()):
		return false
	_item_id = item_id
	_source_zone = zone
	_draw()
	return is_holding()


func is_holding() -> bool:
	return is_instance_valid(_prop)


func get_item_id() -> StringName:
	return _item_id if is_holding() else &""


## The pocket the shown item belongs to, or "" for the pack.
func get_source_zone() -> StringName:
	return _source_zone if is_holding() else &""


func get_held_prop() -> Node3D:
	return _prop if is_holding() else null


func use_held() -> bool:
	if not is_holding():
		return false
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	if item == null:
		put_away()
		return true
	if item.consumable == null or consumption == null:
		_show_hint()
		return true
	_using = true
	var refusal: ConsumptionController.Refusal = consumption.consume_from_zone(_source_zone) \
		if _source_zone != &"" else consumption.consume(_item_id)
	if refusal == ConsumptionController.Refusal.NONE:
		var next: StringName = item.opens_into if item.opens_into != &"" else item.consumable.leaves_behind_id
		if item.opens_into != &"":
			get_parent().call(&"play_action_animation", &"fix")
		if next != &"":
			_item_id = next
			if HeldOwnership.zone_item(equipment, _source_zone) != next:
				_source_zone = &""
			_draw()
		else:
			put_away()
	else:
		_show_hint(tr(ConsumptionController.describe_refusal(refusal)))
	_using = false
	return true


## True while the held lighter shows its flame.
func is_flame_lit() -> bool:
	var flame: LighterFlame = _lighter_flame()
	return flame != null and flame.is_lit()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(PRESENT_ACTION) or _lighter_flame() == null or event.is_echo():
		return
	if event.is_action_pressed(PRESENT_ACTION):
		_presenting = true
		_present_seconds = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released(PRESENT_ACTION):
		_stop_present()
		get_viewport().set_input_as_handled()


func put_away_unlit() -> bool:
	return put_away()


func put_away() -> bool:
	if not is_holding():
		return false
	_clear_prop()
	_item_id = &""
	_source_zone = &""
	if is_instance_valid(_hint):
		_hint.visible = false
	return true


func _draw() -> void:
	_clear_prop()
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	if item == null:
		return
	_prop = HeldPropFactory.make(_item_id, item)
	if _prop == null:
		return
	_prop.name = "Held_%s" % _item_id
	var visual: HenryUALAnimation = _animation()
	if item.held_fit != null and item.held_fit.hand == HeldFit.Hand.RIGHT:
		visual.hold_in_offhand(_prop)
	else:
		visual.hold_in_hand(_prop)
	if item.held_fit != null:
		item.held_fit.apply_to(_prop)
	else:
		## Preserve the production pose until an item receives an authored fit.
		HeldFit.apply_legacy_adjustment(_prop, _item_id)
	_show_hint()


func _clear_prop() -> void:
	_stop_present()
	_restore_fit()
	if not is_instance_valid(_prop):
		return
	var visual: HenryUALAnimation = _animation()
	if visual != null:
		if visual.get_held_prop() == _prop:
			visual.release_hand()
		elif visual.get_offhand_prop() == _prop:
			visual.release_offhand()
	_prop.queue_free()
	_prop = null


func _queue_sync() -> void:
	if not _using:
		call_deferred(&"_sync_owned")


func _sync_owned() -> void:
	if not is_holding() or _using:
		return
	var visual: HenryUALAnimation = _animation()
	var owns: bool = HeldOwnership.owns(inventory, equipment, _item_id, _source_zone)
	var attached: bool = visual != null and (visual.get_held_prop() == _prop or visual.get_offhand_prop() == _prop)
	if not owns or not attached:
		put_away()


func _show_hint(message: String = "") -> void:
	if not is_instance_valid(_hint):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_hint = Label.new()
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		_hint.add_theme_font_size_override("font_size", 20)
		_hint.add_theme_constant_override("outline_size", 4)
		layer.add_child(_hint)
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	var action: String = tr("HAND_TOOL_HINT")
	if item.water_capacity_ml > 0:
		action = tr("CONSUME_REFUSED_EMPTY_FLASK") if item.water_remaining_ml == 0 else "LMB · " + tr("FLASK_DRINK_ACTION")
	elif item.opens_into != &"":
		action = "LMB · " + tr("PINEAPPLE_OPEN_ACTION")
	elif item.consumable != null:
		action = "LMB · " + tr("HAND_EAT_ACTION")
	elif _item_id == &"axe":
		action = tr("AXE_BOARD_HINT")
	elif _item_id == &"knife":
		action = tr("KNIFE_PURPOSE")
	elif _item_id == &"empty_tin":
		action = tr("EMPTY_TIN_HELD_HINT")
	elif _item_id == &"lighter":
		action = "RMB · " + tr("LIGHTER_FLAME_ACTION")
	_hint.text = "%s\n%s" % [tr(item.display_name), message if message != "" else action]
	if item.water_capacity_ml > 0:
		_hint.text += "\n" + item.get_status_text()
	_message_left = 3.0 if message != "" else 0.0
	_hint.visible = true


func _process(delta: float) -> void:
	if _presenting:
		_advance_present(delta)
	elif is_holding() and _prop.top_level:
		_settle_present()
	if not is_holding() or not is_instance_valid(_hint):
		return
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	_hint.size.x = minf(640.0, view_size.x - 32.0)
	_hint.position = Vector2((view_size.x - _hint.size.x) * 0.5, view_size.y * 0.84)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_show_hint()


## Raises the lighter hand before the chest, strikes once it is up, and lets the flame
## go after LIGHTER_FLAME_MAX_SECONDS even with RMB still held.
func _advance_present(delta: float) -> void:
	var flame: LighterFlame = _lighter_flame()
	var visual: HenryUALAnimation = _animation()
	if flame == null or visual == null or visual.skeleton == null or visual.is_action_locking():
		_stop_present()
		return
	_present_seconds += delta
	if _present_seconds >= LIGHTER_RAISE_SECONDS + LIGHTER_FLAME_MAX_SECONDS:
		_stop_present()
		return
	_aim_present(visual)
	if _present_seconds >= LIGHTER_RAISE_SECONDS and not flame.is_lit():
		flame.strike()
		flame.set_lit(true)
		var sound: Node = get_node_or_null(^"/root/SoundSystem")
		if sound != null:
			sound.call(&"play", LIGHTER_STRIKE_EVENT, flame.global_position)


## Fist a forearm before the chest on the holding side, knuckles forward, thumb up.
## The outward palm frame keeps the hanging wrist roll, so the hand never twists over.
func _aim_present(visual: HenryUALAnimation) -> void:
	var reach: StoveHandReach = visual.get_present_reach()
	var rig: Skeleton3D = visual.skeleton
	var left: bool = visual.get_held_prop() == _prop
	var chest_bone: int = rig.find_bone(&"spine_03")
	var shoulder_bone: int = rig.find_bone(&"upperarm_l" if left else &"upperarm_r")
	if reach == null or chest_bone < 0 or shoulder_bone < 0:
		return
	reach.use_left_hand(left)
	if not reach.hand_solved.is_connected(_on_present_hand_solved):
		reach.hand_solved.connect(_on_present_hand_solved)
	var chest: Vector3 = rig.to_global(rig.get_bone_global_pose(chest_bone).origin)
	var side: Vector3 = rig.to_global(rig.get_bone_global_pose(shoulder_bone).origin) - chest
	side.y = 0.0
	var forward: Vector3 = visual.global_basis.z
	forward.y = 0.0
	if side.length_squared() < 1e-6 or forward.length_squared() < 1e-6:
		return
	forward = forward.normalized()
	reach.palm_into_world = side.normalized()
	reach.aim(chest + forward * 0.32 + side * 0.4 - Vector3.UP * 0.1, forward, 1.0)


## The held fit is authored for the hanging arm; raised, the lighter stands upright in the fist.
## Both poses are blended in the hand's frame between fixed ends, so rising and lowering never flip.
func _on_present_hand_solved(palm: Vector3) -> void:
	if _lighter_flame() == null or not (_presenting or _prop.top_level):
		return
	var reach: StoveHandReach = _animation().get_present_reach()
	var hand: Transform3D = _hand_transform()
	var upright := Transform3D(Basis.looking_at(reach.fingers_world, Vector3.UP),
		palm - reach.palm_into_world * 0.015 - Vector3.UP * LIGHTER_BASE_BELOW_PALM)
	var weight: float = reach.get_weight()
	if weight >= 0.99 or not _has_present_local:
		_present_local = hand.affine_inverse() * upright
		_has_present_local = true
	_prop.top_level = true
	if weight >= 0.99:
		_prop.global_transform = upright
		return
	_prop.global_transform = hand * _fit_local().interpolate_with(_present_local, smoothstep(0.0, 1.0, weight))


## The solved hand bone the prop's socket follows, in world space.
func _hand_transform() -> Transform3D:
	var socket := _prop.get_parent() as BoneAttachment3D
	var rig: Skeleton3D = _animation().skeleton
	var bone: int = rig.find_bone(socket.bone_name) if socket != null else -1
	return rig.global_transform * rig.get_bone_global_pose(bone) if bone >= 0 else _prop.global_transform


func _fit_local() -> Transform3D:
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	if item == null or item.held_fit == null:
		return Transform3D.IDENTITY
	var fit: HeldFit = item.held_fit
	return Transform3D(Basis.from_euler(fit.rotation_deg * (PI / 180.0)).scaled(fit.scale), fit.offset)


## Once the lowering arm is back on the animation, the prop rejoins its socket fit.
func _settle_present() -> void:
	var visual: HenryUALAnimation = _animation()
	if visual != null and visual.skeleton != null and visual.get_present_reach().get_weight() > 0.001:
		return
	_restore_fit()


func _restore_fit() -> void:
	if not is_holding() or not _prop.top_level:
		return
	_prop.top_level = false
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	if item != null and item.held_fit != null:
		item.held_fit.apply_to(_prop)


func _stop_present() -> void:
	_presenting = false
	_present_seconds = 0.0
	var flame: LighterFlame = _lighter_flame()
	if flame != null:
		flame.set_lit(false)
	var visual: HenryUALAnimation = _animation()
	if visual != null and visual.skeleton != null:
		visual.get_present_reach().release()


func _lighter_flame() -> LighterFlame:
	if not is_holding() or _item_id != &"lighter":
		return null
	return _prop.get_node_or_null(^"Flame") as LighterFlame


func _animation() -> HenryUALAnimation:
	return get_parent().get_node_or_null(^"HenryUALVisual") as HenryUALAnimation

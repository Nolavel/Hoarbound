class_name HeldItemComponent
extends Node

signal hint_changed(text: String)

## Presents an owned pack/pocket item in the hand; storage remains its save authority.

## Held RMB: raise the held lighter before the chest and keep its flame lit.
const PRESENT_ACTION: StringName = &"present_held"
## G puts whatever is in Henry's hand down on the ground ahead (armfuls and a burning flare have their own G).
const DROP_ACTION: StringName = &"drop_carried"
## Held LMB raises the searchlight forward to aim it.
const AIM_ACTION: StringName = &"fire"
## The thumb gives out after this long; a fresh press lights it again.
const LIGHTER_FLAME_MAX_SECONDS: float = 10.0
## Arm rise before the wheel is struck.
const LIGHTER_RAISE_SECONDS: float = 0.3
## Lighter base under the fist's hollow, so the nozzle stands just above the fist.
const LIGHTER_BASE_BELOW_PALM: float = 0.035
## The lighter body's half thickness: the fingers close onto it, metres.
const LIGHTER_HANDLE_RADIUS: float = 0.011
const LIGHTER_STRIKE_EVENT: SoundEvent = preload("res://resources/audio/lighter_strike.tres")
## The searchlight's carry bar radius (the fist closes on it), metres.
const SEARCHLIGHT_HANDLE_RADIUS: float = 0.012
## How far a carrying arm turns the beam off the body's forward (forearm roll), and tilts it (wrist), degrees.
const SEARCHLIGHT_YAW_DEG: float = 50.0
const SEARCHLIGHT_PITCH_DEG: float = 40.0
## Where the carrying hand sits, as shares of the arm's reach below and ahead of the shoulder.
const SEARCHLIGHT_ARM_DOWN: float = 0.72
const SEARCHLIGHT_ARM_FORWARD: float = 0.45
## The carrying hand sits this far out from under the shoulder, so the lamp body clears the hip, metres.
const SEARCHLIGHT_HIP_CLEAR_M: float = 0.05
## Raised to aim (held LMB): the hand before the chest, as shares of the arm below and ahead of the shoulder.
const SEARCHLIGHT_AIM_DOWN: float = 0.3
const SEARCHLIGHT_AIM_FORWARD: float = 0.8
## How fast the arm rises to aim and lowers again, share of the way per second.
const SEARCHLIGHT_RAISE_RATE: float = 4.0
## The pan's handle: radius, and the point the fist closes on (between the bowl and the hanging eye), pan space.
const PAN_HANDLE_RADIUS: float = 0.011
const PAN_GRIP_POINT: Vector3 = Vector3(0.17, 0.045, 0.0)
## A dropped item lands this far ahead of Henry, metres.
const DROP_AHEAD_M: float = 0.7

@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var consumption: ConsumptionController

var _prop: Node3D
var _item_id: StringName = &""
var _source_zone: StringName = &""
var _using: bool = false
var _message_left: float = 0.0
var _presenting: bool = false
var _present_seconds: float = 0.0
## The upright lighter in the raised hand's frame, kept from the last full raise.
var _present_local: Transform3D = Transform3D.IDENTITY
var _has_present_local: bool = false
## 0 carried low, 1 raised to aim (eased).
var _raise: float = 0.0


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
		and (item.size_class == ItemTraits.SizeClass.POCKET or item.one_hand_held) and item_id not in [&"hammer", &"road_flare"]


## Existing Hub Use route for authored large one-hand tools, not consumables.
func can_use(item_id: StringName) -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	return item != null and item.one_hand_held and supports_item(item_id) and not is_holding() and inventory != null and inventory.has_item(item_id)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and present_owned(item_id)


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
		var next: StringName = item.opens_into if item.opens_into != &"" else \
			(&"" if item.consumable.discard_leftover else item.consumable.leaves_behind_id)
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
	var searchlight := _prop as HeldSearchlight
	var hub := get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if is_holding() and (hub == null or not hub.is_open()) and not event.is_echo() and event.is_action_pressed(DROP_ACTION):
		var carry := get_parent().get_node_or_null(^"CarryComponent") as CarryComponent
		if (carry == null or not carry.is_carrying()) and drop_held():
			get_viewport().set_input_as_handled()
			return
	if searchlight != null and (hub == null or not hub.is_open()) and not event.is_echo() and event.is_action_pressed(PRESENT_ACTION):
		searchlight.toggle()
		get_viewport().set_input_as_handled()
		return
	if not InputMap.has_action(PRESENT_ACTION) or _lighter_flame() == null or event.is_echo():
		return
	if event.is_action_pressed(PRESENT_ACTION):
		_presenting = true
		_present_seconds = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released(PRESENT_ACTION):
		_stop_present()
		get_viewport().set_input_as_handled()


## Puts the item in hand down on the ground ahead as a pickup, its runtime state kept (a searchlight's
## charge); it leaves the pocket or pack it was shown from. False if there is no ground there.
func drop_held() -> bool:
	if not is_holding():
		return false
	var body := get_parent() as Node3D
	var at: Vector3 = ItemPickup.ground_ahead(body, DROP_AHEAD_M)
	if at == Vector3.INF:
		return false
	var item_id: StringName = _item_id
	var payload: Dictionary = HeldOwnership.take(inventory, equipment, item_id, _source_zone)
	if payload.is_empty():
		return false
	put_away()
	ItemPickup.spawn_dropped(body, item_id, payload.get("instance_state", {}), at)
	return true


func put_away_unlit() -> bool:
	return put_away()


func put_away() -> bool:
	if not is_holding():
		return false
	_clear_prop()
	_item_id = &""
	_source_zone = &""
	hint_changed.emit("")
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
	if _prop is HeldSearchlight:
		var searchlight := _prop as HeldSearchlight
		var state: Dictionary = inventory.get_first_instance_state(_item_id)
		searchlight.set_runtime_hours(float(state.get("searchlight_runtime_hours", 0.0)))
		searchlight.apply_enabled(bool(state.get("searchlight_on", false)))
		searchlight.toggled.connect(_on_searchlight_toggled)
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
	if _swung_item() and visual != null:
		for left: bool in [false, true]:
			visual.get_hand_grip(left).release()
	if _prop is HeldSearchlight:
		(_prop as HeldSearchlight).apply_enabled(false)
		if visual != null:
			visual.look_with_light = false
			for left: bool in [false, true]:
				visual.get_hand_grip(left).release()
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
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	var action: String = tr("HAND_TOOL_HINT")
	if item.water_capacity_ml > 0:
		action = tr("CONSUME_REFUSED_EMPTY_FLASK") if item.water_remaining_ml == 0 else "LMB · " + tr("FLASK_DRINK_ACTION")
	elif item.opens_into != &"":
		action = "LMB · " + tr(ConsumptionController.open_action_key(item))
	elif item.throw_speed_mps > 0.0:
		action = "RMB · " + tr("THROW_AIM_ACTION")
		if item.consumable != null:
			action = "LMB · " + tr("HAND_EAT_ACTION") + "   " + action
	elif item.consumable != null:
		action = "LMB · " + tr("HAND_EAT_ACTION")
	elif _item_id == &"axe":
		action = tr("AXE_BOARD_HINT")
	elif _item_id == &"knife":
		action = tr("KNIFE_PURPOSE")
	elif _item_id == &"empty_tin":
		action = tr("EMPTY_TIN_HELD_HINT")
	elif _item_id == &"searchlight":
		action = tr("SEARCHLIGHT_HELD_HINT")
	elif _item_id == &"lighter":
		action = "RMB · " + tr("LIGHTER_FLAME_ACTION")
	var text := "%s\n%s" % [tr(item.display_name), message if message != "" else action]
	if item.water_capacity_ml > 0:
		text += "\n" + item.get_status_text()
	_message_left = 3.0 if message != "" else 0.0
	hint_changed.emit(text)


func _process(delta: float) -> void:
	if _prop is HeldSearchlight:
		_aim_searchlight(delta)
	elif _swung_item():
		_fit_swung()
	elif _presenting:
		_advance_present(delta)
	elif is_holding() and _prop.top_level:
		_settle_present()
	if not is_holding():
		return
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


## Fist a forearm before the chest on the holding side, thumb up: HandGrip holds the lighter's body upright in
## the fist (index to pinky down its length), the wrist continuing the forearm.
func _aim_present(visual: HenryUALAnimation) -> void:
	var rig: Skeleton3D = visual.skeleton
	var left: bool = visual.get_held_prop() == _prop
	var grip: HandGrip = visual.get_hand_grip(left)
	var chest_bone: int = rig.find_bone(&"spine_03")
	var shoulder_bone: int = rig.find_bone(&"upperarm_l" if left else &"upperarm_r")
	if grip == null or chest_bone < 0 or shoulder_bone < 0:
		return
	if not grip.gripped.is_connected(_on_present_gripped):
		grip.gripped.connect(_on_present_gripped.bind(grip))
	grip.handle_radius = LIGHTER_HANDLE_RADIUS
	var chest: Vector3 = rig.to_global(rig.get_bone_global_pose(chest_bone).origin)
	var shoulder: Vector3 = rig.to_global(rig.get_bone_global_pose(shoulder_bone).origin)
	var side: Vector3 = shoulder - chest
	side.y = 0.0
	var forward: Vector3 = visual.global_basis.z
	forward.y = 0.0
	if side.length_squared() < 1e-6 or forward.length_squared() < 1e-6:
		return
	forward = forward.normalized()
	var out: Vector3 = side.normalized()
	var wrist: Vector3 = chest + forward * 0.24 + side * 0.4 - Vector3.UP * 0.1
	## The hand continues the forearm from a relaxed elbow (below and out from the shoulder), square to the lighter.
	var line: Vector3 = wrist - (shoulder + Vector3.DOWN * 0.25 + out * 0.1)
	var along: Vector3 = Vector3(line.x, 0.0, line.z).normalized()
	grip.hold(wrist, along, Vector3.DOWN, shoulder + Vector3.DOWN * 0.3 + out * 0.3 - forward * 0.2, 1.0)


## The held fit is authored for the hanging arm; raised, the lighter stands upright in the fist's hollow (its
## base below, nozzle above the thumb). Both are blended in the hand's frame as the grip eases in and out.
func _on_present_gripped(grip: HandGrip) -> void:
	if _lighter_flame() == null or not (_presenting or _prop.top_level):
		return
	var hand: Transform3D = _hand_transform()
	var y: Vector3 = -grip.handle_axis
	var z: Vector3 = (-grip.hand_along - y * (-grip.hand_along).dot(y)).normalized()
	var upright := Transform3D(Basis(y.cross(z), y, z), grip.handle_centre - y * LIGHTER_BASE_BELOW_PALM)
	var weight: float = grip.get_weight()
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
	if visual != null and visual.skeleton != null and visual.get_hand_grip(visual.get_held_prop() == _prop).get_weight() > 0.001:
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
	if visual != null and visual.skeleton != null and not _prop is HeldSearchlight:
		for left: bool in [false, true]:
			visual.get_hand_grip(left).release()


func _lighter_flame() -> LighterFlame:
	if not is_holding() or _item_id != &"lighter":
		return null
	return _prop.get_node_or_null(^"Flame") as LighterFlame


func _animation() -> HenryUALAnimation:
	return get_parent().get_node_or_null(^"HenryUALVisual") as HenryUALAnimation


func _on_searchlight_toggled(enabled: bool) -> void:
	if inventory != null and _source_zone == &"":
		inventory.update_first_instance_state(_item_id, {"searchlight_on": enabled})


func get_simulation_priority() -> int:
	return 550


func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
	var searchlight := _prop as HeldSearchlight
	if searchlight == null or inventory == null or _source_zone != &"" or not searchlight.is_enabled():
		return
	searchlight.consume_game_hours(hours)
	inventory.update_first_instance_state(_item_id, {"searchlight_runtime_hours": searchlight.runtime_hours})


## True while the item in hand is one Henry swings (it has a strike impulse): the frying pan.
func _swung_item() -> bool:
	if not is_holding():
		return false
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	return item != null and item.strike_impulse > 0.0


## A swung item rides the animated hand: HandGrip only closes the fist on its handle, the item follows the fist.
func _fit_swung() -> void:
	var visual: HenryUALAnimation = _animation()
	if visual == null or visual.skeleton == null:
		return
	var grip: HandGrip = visual.get_hand_grip(visual.get_held_prop() == _prop)
	if not grip.gripped.is_connected(_on_swung_gripped):
		grip.gripped.connect(_on_swung_gripped.bind(grip))
	grip.handle_radius = PAN_HANDLE_RADIUS
	grip.fit(1.0)


## The pan's handle in the fist: its pommel eye out past the little finger, its cooking face toward the palm.
func _on_swung_gripped(grip: HandGrip) -> void:
	if not _swung_item() or not grip.fit_only:
		return
	var x: Vector3 = grip.handle_axis
	var y: Vector3 = (grip.palm_out - x * grip.palm_out.dot(x)).normalized()
	var pan := Basis(x, y, x.cross(y))
	_prop.top_level = true
	_prop.global_transform = Transform3D(pan, grip.handle_centre - pan * PAN_GRIP_POINT)


## The light points where Henry's head looks, carried as a lantern is: the arm hangs, the carry bar lies in the
## fist along the beam, the forearm turns the beam (HandGrip spreads the roll), the wrist tilts it a little.
func _aim_searchlight(delta: float) -> void:
	var visual: HenryUALAnimation = _animation()
	var searchlight := _prop as HeldSearchlight
	if visual == null or visual.skeleton == null or searchlight == null:
		return
	var left: bool = visual.get_held_prop() == searchlight
	var grip: HandGrip = visual.get_hand_grip(left)
	if visual.is_action_locking():
		grip.release()
		return
	visual.look_with_light = true
	if not grip.gripped.is_connected(_on_searchlight_gripped):
		grip.gripped.connect(_on_searchlight_gripped.bind(grip))
	grip.handle_radius = SEARCHLIGHT_HANDLE_RADIUS
	var rig: Skeleton3D = visual.skeleton
	var s: String = "l" if left else "r"
	var upper: int = rig.find_bone("upperarm_" + s)
	var lower: int = rig.find_bone("lowerarm_" + s)
	var hand: int = rig.find_bone("hand_" + s)
	var chest_bone: int = rig.find_bone(&"spine_03")
	if mini(mini(upper, lower), mini(hand, chest_bone)) < 0:
		return
	var shoulder: Vector3 = rig.to_global(rig.get_bone_global_pose(upper).origin)
	var out: Vector3 = shoulder - rig.to_global(rig.get_bone_global_pose(chest_bone).origin)
	out.y = 0.0
	out = out.normalized()
	var forward: Vector3 = visual.global_basis.z.normalized()
	var right: Vector3 = visual.global_basis.x.normalized()
	## The head's facing, kept inside what a carrying arm can turn to (forearm roll) and tilt (wrist).
	var aim: Vector3 = visual.get_head_facing()
	var flat: Vector3 = Vector3(aim.x, 0.0, aim.z).normalized()
	var yaw: float = clampf(atan2(flat.dot(right), flat.dot(forward)), -deg_to_rad(SEARCHLIGHT_YAW_DEG), deg_to_rad(SEARCHLIGHT_YAW_DEG))
	var pitch: float = clampf(asin(clampf(aim.y, -1.0, 1.0)), -deg_to_rad(SEARCHLIGHT_PITCH_DEG), deg_to_rad(SEARCHLIGHT_PITCH_DEG))
	aim = (forward * cos(yaw) + right * sin(yaw)) * cos(pitch) + Vector3.UP * sin(pitch)
	var player := get_parent() as CharacterBody3D
	searchlight.advance_inertia(delta, aim, player.velocity if player != null else Vector3.ZERO)
	var beam: Vector3 = searchlight.direction
	## Arm length from the rig, so the hanging hand sits where this body's arm reaches.
	var arm: float = rig.get_bone_rest(lower).origin.length() + rig.get_bone_rest(hand).origin.length()
	## The arm a little forward (owner): the hand ahead of the thigh; held LMB raises it before the chest to aim.
	var hub := get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	var aiming: bool = InputMap.has_action(AIM_ACTION) and Input.is_action_pressed(AIM_ACTION) and (hub == null or not hub.is_open())
	_raise = move_toward(_raise, 1.0 if aiming else 0.0, SEARCHLIGHT_RAISE_RATE * delta)
	var lift: float = smoothstep(0.0, 1.0, _raise)
	var down: float = lerpf(SEARCHLIGHT_ARM_DOWN, SEARCHLIGHT_AIM_DOWN, lift)
	var ahead: float = lerpf(SEARCHLIGHT_ARM_FORWARD, SEARCHLIGHT_AIM_FORWARD, lift)
	var wrist: Vector3 = shoulder + Vector3.DOWN * arm * down + forward * arm * ahead + out * SEARCHLIGHT_HIP_CLEAR_M * (1.0 - lift) + searchlight.inertia_offset
	## The hand continues the hanging arm's line (shoulder to wrist), square to the bar it holds.
	var line: Vector3 = (wrist - shoulder).normalized()
	var along: Vector3 = (line - beam * line.dot(beam)).normalized()
	var pole: Vector3 = shoulder + Vector3.DOWN * arm * 0.5 + out * 0.25 - forward * 0.25
	## Index to pinky runs back along the bar, so the palm faces the thigh on either hand.
	grip.hold(wrist, along, -beam, pole, 1.0)


## The lamp hangs from the solved fist: its bar on the handle line, its beam along the bar, its top toward the wrist.
func _on_searchlight_gripped(grip: HandGrip) -> void:
	var searchlight := _prop as HeldSearchlight
	if searchlight == null:
		return
	searchlight.top_level = true
	var z: Vector3 = grip.handle_axis
	var y: Vector3 = (-grip.hand_along - z * (-grip.hand_along).dot(z)).normalized()
	searchlight.global_transform = Transform3D(Basis(y.cross(z), y, z), grip.handle_centre)

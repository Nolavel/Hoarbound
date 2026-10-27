class_name HeatSourceFeed
extends InteractiveArea

## Firebox operations for the stove ritual: one log, the tinder, the existing held lighter.
## HeatSource owns combustion; StoveInteractionController owns the mode, the walk and the input.
signal act_started(kind: Act)
signal act_finished(kind: Act, committed: bool)
signal fuel_added(source: HeatSource, remaining_hours: float)
signal feed_refused(reason: Refusal)
signal lighter_struck(success: bool, strike_index: int)
## Anything the ring shows changed: the act, the fuel, the tinder or the fire.
signal state_changed

enum Refusal {
	NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY, NO_LIGHTER, BUSY, HANDS_OCCUPIED,
	CANNOT_TAKE, NO_DROP_SPACE, EMPTY_FIREBOX, TINDER_READY, ALREADY_BURNING, NEED_TINDER, NOT_WORKING,
}
enum StrikeResult { IGNORED, SPARK, FLAME }
enum Stage { IDLE, TRANSFERRING, PREPARING, READY, HOLDING, TINDERING }
enum Act { NONE, FUEL, TINDER, LIGHT }

const LIGHT_SECONDS: float = 3.0
## One log reached in and laid down; the tinder tucked under the logs, seconds.
const FUEL_SECONDS: float = 2.2
const TINDER_SECONDS: float = 1.8
## One log diameter above its rest pose clears the existing floor load on insertion.
const LOG_INSERT_CLEARANCE: float = 0.10
## Longest wait for the hand to settle before the lighter is ready; IK only presents it.
const PREPARE_SECONDS: float = 0.4
const STRIKE_EVENT: SoundEvent = preload("res://resources/audio/lighter_strike.tres")

@export var heat_source: HeatSource
@export var fuel_item_id: StringName = &"firewood"
## Further item ids that burn as one log each; the first one carried is used.
@export var extra_fuel_item_ids: Array[StringName] = []
@export var tinder_item_id: StringName = &"tinder"
@export var units_per_item: float = 1.0
@export_range(0.1, 60.0, 0.1) var light_time_cost_minutes: float = 2.0
@export_range(0.1, 60.0, 0.1) var add_time_cost_minutes: float = 0.5
@export_range(0.05, 60.0, 0.05) var tinder_time_cost_minutes: float = 0.25
@export_range(0.1, 1.0, 0.05) var strike_interval_seconds: float = 0.25

var door_control: StoveDoorControl
var controller: StoveInteractionController
## True while Henry works the stove (StoveInteractionController); every act needs it.
var session_active: bool = false
## Legacy tool parameters retained for compatibility; stove strikes always succeed.
var strike_success_chance: float = 1.0
var guaranteed_success_strike: int = 1

var _inventory: InventoryComponent
var _player: Node3D
var _animation: HenryUALAnimation
var _equipment: EquipmentComponent
var _held_item: HeldItemComponent
var _actions_cache: TimeCostedActionSystem
var _act: Act = Act.NONE
var _act_left: float = 0.0
var _door_open: bool = false
var _action_managed: bool = false
var _action_id: StringName = &""
var _transfer_item: StringName = &""
var _stage: Stage = Stage.IDLE
var _strike_count: int = 0
var _last_strike_seconds: float = -1000.0
var _flame_held: bool = false
var _hold_seconds: float = 0.0
var _transfer_zone: StringName = &""
var _transfer_committed: bool = false
var _transfer_was_held: bool = false
var _held_pickup_world: Transform3D
var _held_left: bool = false
var _transfer_prop: Node3D
var _reach: StoveHandReach
var _actual_palm: Vector3 = Vector3.ZERO
var _pickup_palm: Vector3
var _placement: Dictionary = {}
var _prop_basis: Basis = Basis.IDENTITY
var _pickup_prop_basis: Basis = Basis.IDENTITY
var _contact_prop_basis: Basis = Basis.IDENTITY
var _grip_offset: Vector3 = Vector3.ZERO
var _contact_palm: Vector3
var _light_reach: float = 0.0
var _prepare_seconds: float = 0.0
var _lighter: LighterStrikeVFX


func _ready() -> void:
	if heat_source == null:
		heat_source = _find_source()
	if interactive_mesh == null and heat_source != null:
		interactive_mesh = _first_mesh(heat_source)
	if heat_source != null and focus_bodies.is_empty():
		for solid: Node in heat_source.find_children("*", "StaticBody3D", true, false):
			focus_bodies.append(solid as CollisionObject3D)
	if focus_anchor == null:
		var anchor := Marker3D.new()
		anchor.name = "FeedFocus"
		anchor.position = Vector3(0.34, 0.43, 0.0) - position
		add_child(anchor)
		focus_anchor = anchor
	player_animation_action = &"none"
	_get_inventory()
	_actions_cache = TimeCostedActionSystem.find(get_tree())
	super()
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state != null:
		state.connect(&"mode_changed", _on_mode_changed)
	if heat_source != null:
		heat_source.fuel_changed.connect(func(_f: float) -> void: state_changed.emit())
		heat_source.burning_changed.connect(func(_b: bool) -> void: state_changed.emit())
		heat_source.tinder_changed.connect(func(_p: bool) -> void: state_changed.emit())
		heat_source.state_restoring.connect(_on_source_restoring)
	if controller == null:
		controller = get_node_or_null(^"Interaction") as StoveInteractionController
	if controller == null:
		controller = StoveInteractionController.new()
		controller.name = "Interaction"
		add_child(controller)
	controller.feed = self
	set_item_name(tr("FEED_PROMPT"))


## Offered only outside the ritual: inside it F is claimed and the ring speaks for the stove.
func can_interact() -> bool:
	return heat_source != null and not (controller != null and controller.is_active())


func is_acting() -> bool:
	return _stage != Stage.IDLE


func get_stage() -> Stage:
	return _stage


func get_act() -> Act:
	return _act


## 0..1 through a log or tinder act; the lighter reports through get_light_progress().
func get_act_progress() -> float:
	if _act not in [Act.FUEL, Act.TINDER]:
		return 0.0
	return clampf(1.0 - _act_left / maxf(_act_duration_seconds(), 0.001), 0.0, 1.0)


## Seconds the flame must be held: LIGHT_SECONDS, longer with numb or frostbitten hands.
func get_light_seconds() -> float:
	return LIGHT_SECONDS * StatusModifierCapability.multiplier(_player, &"fine_motor_duration_multiplier")


## 0..1 of the flame held to the tinder, over get_light_seconds().
func get_light_progress() -> float:
	return clampf(_hold_seconds / get_light_seconds(), 0.0, 1.0) if _stage == Stage.HOLDING else 0.0


func is_lighter_ready() -> bool:
	return _stage in [Stage.READY, Stage.HOLDING]


func is_door_open() -> bool:
	return _door_open


func set_door_open(open: bool) -> void:
	if open == _door_open:
		return
	if not open and is_acting():
		cancel_act(&"door_closed")
	_feedback_until_ms = 0
	_door_open = open
	if _visual() != null:
		_visual().set_door_open(open)
	state_changed.emit()


func toggle_door() -> void:
	set_door_open(not _door_open)


## The carried fuel the next log comes from, or &"" when Henry has none.
func get_fuel_item() -> StringName:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return &""
	for id: StringName in [fuel_item_id] + extra_fuel_item_ids:
		if id != &"" and inventory.has_item(id):
			return id
	return &""


func get_fuel_refusal() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if heat_source.get_log_room() <= 0:
		return Refusal.ALREADY_FULL
	if _get_inventory() == null:
		return Refusal.NO_INVENTORY
	if get_fuel_item() == &"":
		return Refusal.NO_FUEL
	if not _hands_free(true):
		return Refusal.HANDS_OCCUPIED
	return Refusal.NONE


func get_tinder_refusal() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if heat_source.is_burning():
		return Refusal.ALREADY_BURNING
	if heat_source.is_tinder_prepared():
		return Refusal.TINDER_READY
	if heat_source.get_loaded_log_count() <= 0:
		return Refusal.EMPTY_FIREBOX
	if tinder_item_id != &"" and not _has_accessible_tinder():
		return Refusal.NO_TINDER
	if not _hands_free(true):
		return Refusal.HANDS_OCCUPIED
	return Refusal.NONE


func get_lighter_refusal() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if heat_source.is_burning():
		return Refusal.ALREADY_BURNING
	if heat_source.get_loaded_log_count() <= 0:
		return Refusal.EMPTY_FIREBOX
	if not heat_source.is_tinder_prepared():
		return Refusal.NEED_TINDER
	if not _has_lighter():
		return Refusal.NO_LIGHTER
	if not _hands_free(true):
		return Refusal.HANDS_OCCUPIED
	return Refusal.NONE


## RMB: one log from Henry's hands into the firebox; it changes hands only when the act completes.
func insert_fuel() -> Refusal:
	if not session_active:
		return Refusal.NOT_WORKING
	if _stage in [Stage.PREPARING, Stage.READY]:
		cancel_act(&"lighter_put_away")
	if is_acting():
		return Refusal.BUSY
	var refusal: Refusal = get_fuel_refusal()
	return _start_action(Act.FUEL) if refusal == Refusal.NONE else refusal


## LMB: tinder under the loaded logs; it never lights anything by itself.
func insert_tinder() -> Refusal:
	if not session_active:
		return Refusal.NOT_WORKING
	if is_acting():
		return Refusal.BUSY
	var refusal: Refusal = get_tinder_refusal()
	return _start_action(Act.TINDER) if refusal == Refusal.NONE else refusal


## Takes out the existing lighter for the strike-and-hold; a no-op once it is out.
func prepare_lighter() -> Refusal:
	if not session_active:
		return Refusal.NOT_WORKING
	if _stage in [Stage.PREPARING, Stage.READY, Stage.HOLDING]:
		return Refusal.NONE
	if is_acting():
		return Refusal.BUSY
	var refusal: Refusal = get_lighter_refusal()
	return _start_action(Act.LIGHT) if refusal == Refusal.NONE else refusal


func _process(delta: float) -> void:
	if not is_acting() or _ui_blocked():
		return
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and (actions == null or actions.get_active_action_id() != _action_id):
		cancel_act(&"action_lost")
		show_message(tr("STOVE_ACTION_INTERRUPTED"))
		return
	var stop_reason: StringName = _light_stop_reason() if _act == Act.LIGHT else _transfer_stop_reason()
	if stop_reason != &"":
		cancel_act(stop_reason)
		return
	if _act == Act.LIGHT:
		_prepare_seconds += delta
		if _stage == Stage.PREPARING and (_prepare_seconds >= PREPARE_SECONDS or _actual_palm.distance_to(_pickup_palm) < 0.045):
			_stage = Stage.READY
			state_changed.emit()
		_update_hand_action(delta)
		advance_lighter_hold(delta)
		return
	_update_hand_action(delta)
	if get_act_progress() >= 0.64 and not _transfer_committed:
		_commit_transfer()
	if not is_acting():
		return
	if _action_managed:
		actions.advance_presentation(delta)
		if is_acting() and actions.get_active_action_id() == _action_id:
			_act_left = _act_duration_seconds() * (1.0 - actions.get_progress())
		return
	_act_left -= delta
	if _act_left <= 0.0:
		_finish_current()


func _exit_tree() -> void:
	cancel_act(&"target_lost")
	_clear_lighter()


func _start_action(act: Act) -> Refusal:
	if is_instance_valid(_held_item) and _held_item.get_item_id() == &"lighter":
		_held_item.put_away()
	_feedback_until_ms = 0
	_act = act
	_transfer_item = get_fuel_item() if act == Act.FUEL else (tinder_item_id if act == Act.TINDER else &"")
	_transfer_committed = false
	_transfer_was_held = _transfer_item != &"" and is_instance_valid(_held_item) and _held_item.is_holding() and _held_item.get_item_id() == _transfer_item
	_transfer_zone = _held_item.get_source_zone() if _transfer_was_held else (HeldOwnership.pocket_holding(_equipment,tinder_item_id) if act == Act.TINDER else &"")
	if _transfer_was_held:
		_held_pickup_world = _held_item.get_held_prop().global_transform
		_held_left = _animation != null and _animation.get_held_prop() == _held_item.get_held_prop()
		_held_item.put_away()
	_act_left = _act_duration_seconds()
	_stage = {Act.FUEL: Stage.TRANSFERRING, Act.TINDER: Stage.TINDERING, Act.LIGHT: Stage.PREPARING}[act]
	var lighting: bool = act == Act.LIGHT
	set_process(true)
	if lighting:
		_strike_count = 0
		_last_strike_seconds = -1000.0
		_build_lighter()
	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		var names: Dictionary = {Act.FUEL: "fuel", Act.TINDER: "tinder", Act.LIGHT: "light"}
		_action_id = StringName("stove:%d:%s" % [get_instance_id(), names[act]])
		request.action_id = _action_id
		var minutes: Dictionary = {Act.FUEL: add_time_cost_minutes, Act.TINDER: tinder_time_cost_minutes, Act.LIGHT: light_time_cost_minutes}
		request.duration_hours = float(minutes[act]) / 60.0
		request.presentation_seconds = 0.0 if lighting else _act_left
		request.external_presentation = not lighting
		var reasons: Dictionary = {Act.FUEL: &"feed_stove", Act.TINDER: &"lay_tinder", Act.LIGHT: &"light_stove"}
		request.reason = reasons[act]
		request.actor = _player
		request.target = heat_source
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.stop_check = _light_stop_reason if lighting else _transfer_stop_reason
		request.on_complete = _action_completed
		request.on_cancel = _action_cancelled
		_action_managed = actions.start_manual_action(request) if lighting else actions.start_action(request)
		if not _action_managed:
			_clear_act()
			return Refusal.BUSY
	if _player != null and _player.has_method(&"face_work_target"):
		_player.call(&"face_work_target", focus_anchor.global_position)
	if _animation == null or not _begin_hand_action():
		cancel_act(&"animation_unavailable")
		return Refusal.BUSY
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.begin_act(lighting, _act_left, 1, false)
	act_started.emit(act)
	state_changed.emit()
	return Refusal.NONE


func attempt_lighter_strike(now_seconds: float = -1.0) -> int:
	if _stage != Stage.READY or _ui_blocked() or _light_stop_reason() != &"":
		return StrikeResult.IGNORED
	var now: float = float(Time.get_ticks_msec()) / 1000.0 if now_seconds < 0.0 else now_seconds
	if now - _last_strike_seconds < strike_interval_seconds:
		return StrikeResult.IGNORED
	_last_strike_seconds = now
	_strike_count += 1
	if _lighter != null:
		_lighter.strike(true)
	var sound: Node = get_node_or_null(^"/root/SoundSystem")
	if sound != null:
		sound.call(&"play", STRIKE_EVENT, _lighter.global_position if _lighter != null else global_position)
	_stage = Stage.HOLDING
	_flame_held = true
	_hold_seconds = 0.0
	lighter_struck.emit(true, _strike_count)
	state_changed.emit()
	return StrikeResult.FLAME


func release_lighter() -> void:
	var was_holding: bool = _stage == Stage.HOLDING
	_flame_held = false
	_hold_seconds = 0.0
	if was_holding:
		_stage = Stage.READY
	if _lighter != null:
		_lighter.set_flame(false)
	if was_holding:
		state_changed.emit()


func advance_lighter_hold(seconds: float) -> void:
	if _stage != Stage.HOLDING or not _flame_held or _ui_blocked():
		return
	if _light_stop_reason() != &"":
		cancel_act(&"target_lost")
		return
	if _light_reach < 0.99:
		return
	_hold_seconds += maxf(0.0, seconds)
	if _hold_seconds < get_light_seconds():
		return
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and actions != null and actions.get_active_action_id() == _action_id:
		actions.complete_active()
	else:
		_finish_ignition()


## Stops the current act; nothing changes hands unless the act had already committed.
func cancel_act(reason: StringName = &"cancelled") -> void:
	var kind: Act = _act
	var committed: bool = _transfer_committed
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and actions != null and actions.get_active_action_id() == _action_id:
		if actions.cancel(reason):
			return
	_clear_act()
	if _visual() != null:
		_visual().end_act(_door_open)
	if kind != Act.NONE:
		act_finished.emit(kind, committed)


func _action_completed(_hours: float) -> void:
	_action_managed = false
	_finish_current()


func _action_cancelled(_hours: float, _reason: StringName) -> void:
	var kind: Act = _act
	var committed: bool = _transfer_committed
	_clear_act()
	if _visual() != null:
		_visual().end_act(_door_open)
	if kind != Act.NONE:
		act_finished.emit(kind, committed)


func _finish_current() -> void:
	match _act:
		Act.LIGHT:
			_finish_ignition()
		Act.FUEL:
			_finish_fuel()
		Act.TINDER:
			_finish_tinder()


func _finish_ignition() -> void:
	if _stage != Stage.HOLDING or _hold_seconds < get_light_seconds() or _light_stop_reason() != &"":
		_clear_act()
		if _visual() != null:
			_visual().end_act(_door_open)
		return
	var manager := get_tree().root.find_child("DayNightManager", true, false) as DayNightManager
	var rate: float = 1.0 / 3600.0
	if manager != null and manager.settings != null:
		rate = 24.0 / maxf(manager.settings.day_duration + manager.settings.night_duration, 0.001)
	heat_source.start_loaded_fire(rate)
	_clear_act()
	if _visual() != null:
		_visual().end_act(true)
	show_message(tr("STOVE_KINDLING"))
	act_finished.emit(Act.LIGHT, true)


## One contact transaction; the action then returns the empty hand before finishing.
func _commit_transfer() -> void:
	if _transfer_committed or _transfer_stop_reason() != &"":
		return
	var inventory: InventoryComponent = _get_inventory()
	var taken: Dictionary = HeldOwnership.take(inventory, _equipment, _transfer_item, _transfer_zone)
	if taken.is_empty():
		cancel_act(&"resource_lost")
		return
	if _act == Act.FUEL:
		_visual().set_log_release(_transfer_prop.global_transform)
		if not heat_source.add_logs(1):
			HeldOwnership.restore(inventory, _equipment, taken, _transfer_zone)
			cancel_act(&"target_full")
			return
		fuel_added.emit(heat_source,heat_source.get_remaining_hours())
	else:
		_visual().prepare_tinder_position()
		heat_source.set_tinder_prepared(true)
	_transfer_committed = true
	_transfer_prop.visible = false
	_animation.reserve_stove_carry(false)
	state_changed.emit()

func _finish_fuel() -> void:
	_finish_transfer(Act.FUEL)

func _finish_tinder() -> void:
	_finish_transfer(Act.TINDER)

func _finish_transfer(kind: Act) -> void:
	var committed: bool = _transfer_committed
	_clear_act()
	if _visual() != null:
		_visual().end_act(true)
	if committed:
		show_message(tr("STOVE_LOADED") % 1 if kind == Act.FUEL else tr("STOVE_TINDER_LAID"))
	act_finished.emit(kind,committed)


func _light_stop_reason() -> StringName:
	var reason: StringName = _activity_stop_reason()
	if reason != &"":
		return reason
	if heat_source.is_burning() or heat_source.get_remaining_hours() <= 0.0:
		return &"target_lost"
	if not _has_lighter() or not _hands_free(true):
		return &"tool_lost"
	if not heat_source.is_tinder_prepared():
		return &"resource_lost"
	return &""


func _transfer_stop_reason() -> StringName:
	var reason: StringName = _activity_stop_reason()
	if reason != &"":
		return reason
	if _transfer_committed:
		return &""
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or not _hands_free(true):
		return &"resource_lost"
	if _act == Act.FUEL:
		if inventory.get_count(_transfer_item) < 1 or heat_source.get_log_room() < 1:
			return &"resource_lost"
	elif _act == Act.TINDER:
		if heat_source.is_burning() or heat_source.is_tinder_prepared() or heat_source.get_loaded_log_count() <= 0 \
			or (tinder_item_id != &"" and not HeldOwnership.owns(inventory,_equipment,tinder_item_id,_transfer_zone)):
			return &"resource_lost"
	return &""


func _clear_act() -> void:
	var restore_hand: bool = _transfer_was_held and not _transfer_committed
	var held_id: StringName = _transfer_item
	release_lighter()
	_clear_lighter()
	if is_instance_valid(_transfer_prop):
		_transfer_prop.visible = false
		_transfer_prop.queue_free()
	_transfer_prop = null
	if is_instance_valid(_reach):
		_reach.release()
	if is_instance_valid(_animation):
		_animation.reserve_stove_carry(false)
	if _visual() != null:
		_visual().cancel_log_placement()
	_transfer_committed = false
	_transfer_was_held = false
	if restore_hand and is_instance_valid(_held_item):
		_held_item.present_owned(held_id)
	if _act != Act.NONE and is_instance_valid(_animation):
		_animation.end_work_pose(session_active)
	_stage = Stage.IDLE
	_act = Act.NONE
	_act_left = 0.0
	_action_managed = false
	_action_id = &""
	_transfer_item = &""
	state_changed.emit()


func _build_lighter() -> void:
	_lighter = LighterStrikeVFX.new()
	add_child(_lighter)


func _clear_lighter() -> void:
	if not is_instance_valid(_lighter):
		_lighter = null
		return
	if is_instance_valid(_animation) and _animation.get_held_prop() == _lighter:
		_animation.release_hand()
	_lighter.queue_free()
	_lighter = null


## Hands are free of anything but fuel (allow_logs) and the stove's own lighter.
func _hands_free(allow_logs: bool = false) -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return false
	var fuels: Array[StringName] = [fuel_item_id]
	fuels.append_array(extra_fuel_item_ids)
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.carried_in_hands and (not allow_logs or not fuels.has(item.id)):
			return false
	var prop: Node3D = _animation.get_held_prop() if is_instance_valid(_animation) else null
	if prop == null or prop == _lighter:
		return true
	return is_instance_valid(_held_item) and _held_item.get_item_id() in [&"lighter",tinder_item_id] \
		and _held_item.get_held_prop() == prop


func _has_lighter() -> bool:
	return _has_owned_item(&"lighter")


func _has_owned_item(item_id: StringName) -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory != null and inventory.has_item(item_id):
		return true
	if is_instance_valid(_equipment):
		for pocket: Dictionary in _equipment.get_available_pockets():
			if pocket["item_id"] == item_id:
				return true
	return false


## Consumes from the owning storage, the pack first, then the Quick Access pockets.
func _consume_owned_item(item_id: StringName) -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory != null and inventory.try_remove(item_id):
		return true
	if is_instance_valid(_equipment):
		for pocket: Dictionary in _equipment.get_available_pockets():
			if pocket["item_id"] == item_id:
				return _equipment.take_pocket_instance(pocket["body_slot"], pocket["pocket"]).get("id", &"") == item_id
	return false


func _ui_blocked() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))


func _get_inventory() -> InventoryComponent:
	if not is_instance_valid(_player) and is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_inventory):
		_inventory = InventoryComponent.find_in(_player)
	if is_instance_valid(_player):
		if not is_instance_valid(_equipment):
			_equipment = _player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
		if not is_instance_valid(_held_item):
			_held_item = _player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
		if not is_instance_valid(_animation):
			for child: Node in _player.get_children():
				if child is HenryUALAnimation:
					_animation = child as HenryUALAnimation
	return _inventory


func _actions() -> TimeCostedActionSystem:
	if not is_instance_valid(_actions_cache) and is_inside_tree():
		_actions_cache = TimeCostedActionSystem.find(get_tree())
	return _actions_cache


func _visual() -> StoveVisual:
	return heat_source.find_child("StoveVisual", true, false) as StoveVisual if is_instance_valid(heat_source) else null


func _act_duration_seconds() -> float:
	match _act:
		Act.LIGHT:
			return get_light_seconds()
		Act.FUEL:
			return FUEL_SECONDS
		Act.TINDER:
			return TINDER_SECONDS
	return 0.0


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return int(state.get_script().get_script_constant_map().get("Mode", {}).get(String(mode_name), -1)) if state != null else -1


## F on the stove (or its door) starts the ritual: StoveInteractionController walks Henry over.
func _on_interaction_performed() -> void:
	if controller != null:
		controller.request_enter()


func report(refusal: Refusal) -> void:
	if refusal != Refusal.NONE:
		feed_refused.emit(refusal)
		show_message(tr(describe_refusal(refusal)))


## While Henry works the stove the firebox keeps focus so the door cannot steal it.
func keeps_focus() -> bool:
	return session_active or is_acting()


func resolve_focus(from: Vector3, direction: Vector3) -> InteractiveArea:
	if session_active or is_acting():
		return self
	if is_instance_valid(door_control) and door_control.is_aim_on_door(from, direction):
		return door_control
	return self


func _on_mode_changed(_old_mode: int, _new_mode: int) -> void:
	if _ui_blocked():
		release_lighter()


func _get_interaction_text() -> String:
	if session_active:
		set_description("")
		return ""
	set_description(get_status_text())
	return "[%s] %s" % [_interact_key_label(), tr("FEED_PROMPT")]


## Short factual state of the firebox for the prompt detail.
func get_status_text() -> String:
	if heat_source == null:
		return ""
	if heat_source.is_burning():
		return tr("STOVE_WARMING" if heat_source.get_intensity() < 1.0 else "STOVE_BURNING")
	var text: String = tr("STOVE_FUEL_STATUS") % [heat_source.get_loaded_log_count(), heat_source.get_log_capacity()]
	if heat_source.is_tinder_prepared():
		text += " · " + tr("STOVE_TINDER_READY")
	return text


func get_interaction_prompt_data() -> Dictionary:
	var data: Dictionary = super()
	if session_active:
		data["key"] = ""
	return data


## In the ritual F (claimed) steps back and the right bracket names the stove; outside it, nothing.
func get_session_prompt_data() -> Dictionary:
	if not session_active:
		return {}
	return {"key": _interact_key_label(), "back": tr(&"WORK_SESSION_BACK"), "title": tr(&"STOVE_SESSION_TITLE")}


func _is_lighting() -> bool:
	return _stage in [Stage.PREPARING, Stage.READY, Stage.HOLDING]


func _activity_stop_reason() -> StringName:
	if not is_instance_valid(heat_source) or heat_source.is_queued_for_deletion() or not _door_open:
		return &"target_lost"
	if not session_active:
		return &"target_lost"
	return &""


static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.NO_SOURCE: return "FEED_REFUSED_NO_SOURCE"
		Refusal.ALREADY_FULL: return "FEED_REFUSED_ALREADY_FULL"
		Refusal.NO_FUEL: return "FEED_REFUSED_NO_FUEL"
		Refusal.NO_TINDER: return "FEED_REFUSED_NO_TINDER"
		Refusal.NO_INVENTORY: return "FEED_REFUSED_NO_INVENTORY"
		Refusal.NO_LIGHTER: return "STOVE_NEED_LIGHTER"
		Refusal.HANDS_OCCUPIED: return "STOVE_FREE_HANDS"
		Refusal.CANNOT_TAKE: return "STOVE_CANNOT_TAKE"
		Refusal.NO_DROP_SPACE: return "STOVE_OVERFLOW_BLOCKED"
		Refusal.EMPTY_FIREBOX: return "STOVE_NEED_LOG_FIRST"
		Refusal.TINDER_READY: return "STOVE_TINDER_ALREADY"
		Refusal.ALREADY_BURNING: return "STOVE_BURNING"
		Refusal.NEED_TINDER: return "STOVE_NEED_TINDER_FIRST"
		_: return "ACTION_REFUSED_BUSY"


## Compatibility for isolated tools (no player, no ritual): feeds and lights in one call.
func can_feed() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if heat_source.get_log_room() <= 0:
		return Refusal.ALREADY_FULL
	if _get_inventory() == null:
		return Refusal.NO_INVENTORY
	if not _get_inventory().has_item(fuel_item_id):
		return Refusal.NO_FUEL
	if not heat_source.is_burning() and tinder_item_id != &"" and not _get_inventory().has_item(tinder_item_id):
		return Refusal.NO_TINDER
	return Refusal.NONE


func feed() -> Refusal:
	var refusal: Refusal = can_feed()
	if refusal != Refusal.NONE:
		return refusal
	if not heat_source.is_burning() and tinder_item_id != &"":
		_get_inventory().try_remove(tinder_item_id)
	_get_inventory().try_remove(fuel_item_id)
	heat_source.refuel(units_per_item)
	return Refusal.NONE


static func _first_mesh(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested: MeshInstance3D = _first_mesh(child)
		if nested != null:
			return nested
	return null


func _find_source() -> HeatSource:
	if get_parent() is HeatSource:
		return get_parent() as HeatSource
	for child: Node in get_parent().get_children():
		if child is HeatSource:
			return child as HeatSource
	return null


func _has_accessible_tinder() -> bool:
	_get_inventory()
	if is_instance_valid(_held_item) and _held_item.get_item_id() == tinder_item_id:
		return true
	return HeldOwnership.pocket_holding(_equipment,tinder_item_id) != &""

func _begin_hand_action() -> bool:
	var visual: StoveVisual = _visual()
	if visual == null:
		return false
	_reach = _animation.get_stove_reach()
	if _reach == null:
		return false
	_reach.use_left_hand(_transfer_was_held and _held_left)
	if not _reach.hand_solved.is_connected(_on_hand_solved):
		_reach.hand_solved.connect(_on_hand_solved)
	var pickup: Dictionary = _animation.get_stove_pickup(_act == Act.FUEL)
	_pickup_palm = pickup["point"]
	_pickup_prop_basis = pickup["basis"]
	_actual_palm = _pickup_palm
	_light_reach = 0.0
	_prepare_seconds = 0.0
	if _act == Act.FUEL:
		_placement = visual.reserve_log_placement()
		if _placement.is_empty():
			return false
		_prop_basis = visual.global_basis*Basis.from_euler(_placement["rotation"])
		_grip_offset = Vector3(-0.04,0.055,0.265)
		_contact_palm = visual.to_global(_placement["position"]+Vector3.UP*LOG_INSERT_CLEARANCE)+_prop_basis*_grip_offset
		_transfer_prop = StoveVisual.LOG_VISUAL.new()
		add_child(_transfer_prop)
		_animation.reserve_stove_carry(true)
	elif _act == Act.TINDER:
		visual.reserve_tinder_position()
		_prop_basis = visual.global_basis
		_grip_offset = Vector3(0.035,0.04,0)
		_contact_palm = visual.to_global(visual.get_tinder_contact()-Vector3(0,0.022,0))+_prop_basis*_grip_offset
		_transfer_prop = visual.create_tinder_prop()
		add_child(_transfer_prop)
	else:
		var direction := Vector3(-1,-0.3,0).normalized()
		var x := Vector3(0,0,-1)
		_prop_basis = visual.global_basis*Basis(x,direction,x.cross(direction))
		_grip_offset = Vector3(0,-0.008,0)
		_contact_palm = visual.to_global(visual.get_tinder_contact())-_prop_basis.y*0.061+_prop_basis*_grip_offset
	_contact_prop_basis = _prop_basis
	if _act != Act.FUEL:
		_pickup_prop_basis = _prop_basis
	if _transfer_was_held:
		_pickup_prop_basis = _held_pickup_world.basis
		_pickup_palm = _held_pickup_world*_grip_offset
		_on_hand_solved(_pickup_palm)
	_update_hand_action(0.0)
	return true

func _update_hand_action(delta: float) -> void:
	if _reach == null:
		return
	var amount: float
	var goal: Vector3
	var fingers: Vector3 = -heat_source.global_basis.x
	if _act == Act.LIGHT:
		_light_reach = move_toward(_light_reach,1.0 if _stage == Stage.HOLDING else 0.0,delta/0.65)
		amount = smoothstep(0,1,_light_reach)
		goal = _pickup_palm.lerp(_contact_palm,amount)
		fingers = _prop_basis.y
	else:
		var p: float = get_act_progress()
		var approach: Vector3 = heat_source.to_global(Vector3(0.67,0.50,heat_source.to_local(_contact_palm).z))
		_prop_basis = _pickup_prop_basis.slerp(_contact_prop_basis,smoothstep(0.15,0.30,p))
		var lowered: Vector3 = _pickup_palm
		lowered.y = minf(lowered.y,heat_source.to_global(Vector3(0,0.55,0)).y)
		if p < 0.15:
			goal = _pickup_palm.lerp(lowered,smoothstep(0.0,0.15,p))
			amount = 0.0
		elif p < 0.35:
			goal = lowered.lerp(approach,smoothstep(0.15,0.35,p))
			amount = 0.0
		elif p < 0.72:
			amount = smoothstep(0.35,0.60,p)
			goal = approach.lerp(_contact_palm,amount)
		else:
			amount = 1.0-smoothstep(0.72,1.0,p)
			goal = _pickup_palm.lerp(_contact_palm,amount)
		if _act == Act.FUEL:
			fingers = -_prop_basis.z
		if is_instance_valid(_transfer_prop):
			_transfer_prop.visible = (p >= 0.12 or _transfer_was_held) and not _transfer_committed
	_reach.grip_weight = 0.9 if _act == Act.LIGHT else (0.7 if get_act_progress() >= 0.12 and not _transfer_committed else 0.0)
	_reach.lean_weight = amount
	_reach.aim(goal,fingers,1.0)

func _on_hand_solved(palm: Vector3) -> void:
	_actual_palm = palm
	var prop: Node3D = _lighter if _act == Act.LIGHT else _transfer_prop
	if is_instance_valid(prop):
		prop.global_transform = Transform3D(_prop_basis,palm-_prop_basis*_grip_offset)


func did_commit_transfer() -> bool:
	return _transfer_committed


func _on_source_restoring() -> void:
	cancel_act(&"save_restored")
	if controller != null and controller.is_active():
		controller.request_exit()

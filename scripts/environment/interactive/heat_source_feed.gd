class_name HeatSourceFeed
extends InteractiveArea

## Firebox interaction owns staged log transfers and a held lighter; HeatSource owns combustion.
signal act_started(lighting: bool)
signal fuel_added(source: HeatSource, remaining_hours: float)
signal feed_refused(reason: Refusal)
signal lighter_struck(success: bool, strike_index: int)

enum Refusal { NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY, NO_LIGHTER, BUSY, HANDS_OCCUPIED, CANNOT_TAKE, NO_DROP_SPACE }
enum StrikeResult { IGNORED, SPARK, FLAME }
enum Stage { IDLE, TRANSFERRING, PREPARING, READY, HOLDING }

const LIGHT_SECONDS: float = 3.0
const ADD_SECONDS: float = 2.0
const STRIKE_EVENT: SoundEvent = preload("res://resources/audio/lighter_strike.tres")

@export var heat_source: HeatSource
@export var fuel_item_id: StringName = &"firewood"
@export var tinder_item_id: StringName = &"tinder"
@export var units_per_item: float = 1.0
@export_range(0.1, 60.0, 0.1) var light_time_cost_minutes: float = 2.0
@export_range(0.1, 60.0, 0.1) var add_time_cost_minutes: float = 0.5
@export_range(0.1, 1.0, 0.05) var strike_interval_seconds: float = 0.25

var door_control: StoveDoorControl
## Legacy tool parameters retained for compatibility; stove strikes always succeed.
var strike_success_chance: float = 1.0
var guaranteed_success_strike: int = 1

var _inventory: InventoryComponent
var _player: Node3D
var _animation: HenryUALAnimation
var _equipment: EquipmentComponent
var _held_item: HeldItemComponent
var _actions_cache: TimeCostedActionSystem
var _act_left: float = 0.0
var _act_lighting: bool = false
var _door_open: bool = false
var _action_managed: bool = false
var _action_id: StringName = &""
var _transfer_count: int = 0
var _removing: bool = false
var _stage: Stage = Stage.IDLE
var _strike_count: int = 0
var _last_strike_seconds: float = -1000.0
var _flame_held: bool = false
var _hold_seconds: float = 0.0
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
	set_item_name(tr("FEED_PROMPT"))


func can_interact() -> bool:
	return heat_source != null


func is_acting() -> bool:
	return _stage != Stage.IDLE


func is_door_open() -> bool:
	return _door_open


func toggle_door() -> void:
	if is_acting():
		return
	_feedback_until_ms = 0
	_door_open = not _door_open
	if _visual() != null:
		_visual().set_door_open(_door_open)


func set_target_state(targeted: bool, in_prompt_range: bool) -> void:
	var lost: bool = _targeted and not targeted
	super(targeted, in_prompt_range)
	if lost:
		cancel_act(&"target_lost")


## F loads the armful and prepares ignition; RMB explicitly retrieves cold wood.
func begin_act() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if is_acting():
		cancel_act()
		return Refusal.NONE
	if not _door_open:
		toggle_door()
		return Refusal.NONE
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return Refusal.NO_INVENTORY
	if inventory.has_item(fuel_item_id) and heat_source.get_log_room() > 0:
		return transfer_logs(inventory.get_count(fuel_item_id))
	if not heat_source.is_burning() and heat_source.get_remaining_hours() > 0.0:
		return _prepare_ignition()
	return Refusal.ALREADY_FULL if heat_source.get_log_room() <= 0 else Refusal.NO_FUEL


func _input(event: InputEvent) -> void:
	if _player == null:
		_get_inventory()
	if _player == null or _ui_blocked():
		return
	if is_acting() and event.is_action_pressed(&"interact"):
		if not event.is_echo():
			cancel_act()
		get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if _is_lighting():
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				attempt_lighter_strike()
			else:
				release_lighter()
		elif mouse.pressed:
			cancel_act()
			_report(transfer_logs(2, true))
		get_viewport().set_input_as_handled()
	elif _targeted and prompt_shown and _door_open and _in_reach():
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and not is_acting():
			_report(transfer_logs(2, true))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_acting() or _ui_blocked():
		return
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and (actions == null or actions.get_active_action_id() != _action_id):
		cancel_act(&"action_lost")
		show_message(tr("STOVE_ACTION_INTERRUPTED"))
		return
	var stop_reason: StringName = _light_stop_reason() if _is_lighting() else _transfer_stop_reason()
	if stop_reason != &"":
		cancel_act(stop_reason)
		return
	if _is_lighting():
		if _stage == Stage.PREPARING and (_animation == null or _animation.is_work_pose_ready()):
			_stage = Stage.READY
		advance_lighter_hold(delta)
		return
	if _action_managed:
		actions.advance_presentation(delta)
		if _stage == Stage.TRANSFERRING and actions.get_active_action_id() == _action_id:
			_act_left = _act_duration_seconds() * (1.0 - actions.get_progress())
		return
	_act_left -= delta
	if _act_left <= 0.0:
		_finish_transfer()


func _exit_tree() -> void:
	cancel_act(&"target_lost")
	_clear_lighter()


func transfer_logs(requested: int, removing: bool = false) -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if is_acting() or not _door_open:
		return Refusal.BUSY
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return Refusal.NO_INVENTORY
	if not _hands_free(true):
		return Refusal.HANDS_OCCUPIED
	var item: ItemResource = ItemCatalog.get_item(fuel_item_id)
	var count: int = mini(maxi(requested, 1), heat_source.get_recoverable_log_count() if removing else heat_source.get_log_room())
	if removing:
		while count > 0 and inventory.get_add_refusal(item, count) != &"":
			count -= 1
		if count <= 0:
			return Refusal.CANNOT_TAKE
	else:
		count = mini(count, inventory.get_count(fuel_item_id))
		if count <= 0:
			return Refusal.ALREADY_FULL if heat_source.get_log_room() <= 0 else Refusal.NO_FUEL
	return _start_action(false, count, removing)


func _start_action(lighting: bool, count: int, removing: bool) -> Refusal:
	if is_instance_valid(_held_item) and _held_item.get_item_id() == &"lighter":
		_held_item.put_away()
	_feedback_until_ms = 0
	_act_lighting = lighting
	_transfer_count = count
	_removing = removing
	_act_left = LIGHT_SECONDS if lighting else ADD_SECONDS * count
	_stage = Stage.PREPARING if lighting else Stage.TRANSFERRING
	set_process(true)
	if lighting:
		_strike_count = 0
		_last_strike_seconds = -1000.0
		_build_lighter()
	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("stove:%d:%s" % [get_instance_id(), "light" if lighting else "transfer"])
		request.action_id = _action_id
		request.duration_hours = (light_time_cost_minutes if lighting else add_time_cost_minutes * count) / 60.0
		request.presentation_seconds = 0.0 if lighting else _act_left
		request.external_presentation = not lighting
		request.reason = &"light_stove" if lighting else &"take_stove_logs" if removing else &"feed_stove"
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
	if lighting and _animation != null and not _animation.begin_work_pose():
		cancel_act(&"animation_unavailable")
		return Refusal.BUSY
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.begin_act(lighting, _act_left, count, removing)
	if _player != null and _player.has_method(&"play_action_animation") and not lighting:
		_player.call(&"play_action_animation", &"interact")
	act_started.emit(lighting)
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
	return StrikeResult.FLAME


func release_lighter() -> void:
	_flame_held = false
	_hold_seconds = 0.0
	if _stage == Stage.HOLDING:
		_stage = Stage.READY
	if _lighter != null:
		_lighter.set_flame(false)


func advance_lighter_hold(seconds: float) -> void:
	if _stage != Stage.HOLDING or not _flame_held or _ui_blocked():
		return
	if _light_stop_reason() != &"":
		cancel_act(&"target_lost")
		return
	_hold_seconds += maxf(0.0, seconds)
	if _hold_seconds < LIGHT_SECONDS:
		return
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and actions != null and actions.get_active_action_id() == _action_id:
		actions.complete_active()
	else:
		_finish_ignition()


func cancel_act(reason: StringName = &"cancelled") -> void:
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and actions != null and actions.get_active_action_id() == _action_id:
		actions.cancel(reason)
	else:
		_clear_act()
	if _visual() != null:
		_visual().end_act(_door_open)


func _action_completed(_hours: float) -> void:
	_action_managed = false
	if _act_lighting:
		_finish_ignition()
	else:
		_finish_transfer()


func _action_cancelled(_hours: float, _reason: StringName) -> void:
	_clear_act()
	if _visual() != null:
		_visual().end_act(_door_open)


func _finish_ignition() -> void:
	if _stage != Stage.HOLDING or _hold_seconds < LIGHT_SECONDS or _light_stop_reason() != &"":
		_clear_act()
		if _visual() != null:
			_visual().end_act(_door_open)
		return
	if tinder_item_id != &"" and not _consume_owned_item(tinder_item_id):
		_clear_act()
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


func _finish_transfer() -> void:
	if _stage != Stage.TRANSFERRING:
		return
	if _transfer_stop_reason() != &"":
		_clear_act()
		return
	var inventory: InventoryComponent = _get_inventory()
	var count: int = _transfer_count
	var removing: bool = _removing
	if removing:
		if not heat_source.remove_cold_logs(count):
			_clear_act()
			return
		for _i: int in range(count):
			inventory.try_add(ItemCatalog.get_item(fuel_item_id))
	else:
		for _i: int in range(count):
			inventory.try_remove(fuel_item_id)
		heat_source.add_logs(count)
	_clear_act()
	if _visual() != null:
		_visual().end_act(true)
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	show_message(tr("STOVE_TAKEN" if removing else "STOVE_LOADED") % count)
	if not removing:
		var refusal: Refusal = Refusal.NONE
		if not _put_down_overflow():
			refusal = Refusal.NO_DROP_SPACE
		elif not heat_source.is_burning():
			refusal = _prepare_ignition()
		if refusal != Refusal.NONE:
			feed_refused.emit(refusal)
			show_message(tr("STOVE_LOADED") % count + " · " + tr(describe_refusal(refusal)))


func _light_stop_reason() -> StringName:
	var reason: StringName = _activity_stop_reason()
	if reason != &"":
		return reason
	if heat_source.is_burning() or heat_source.get_remaining_hours() <= 0.0:
		return &"target_lost"
	if not _has_lighter() or not _hands_free():
		return &"tool_lost"
	if tinder_item_id != &"" and not _has_owned_item(tinder_item_id):
		return &"resource_lost"
	return &""


func _transfer_stop_reason() -> StringName:
	var reason: StringName = _activity_stop_reason()
	if reason != &"":
		return reason
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or not _hands_free(true):
		return &"resource_lost"
	if _removing:
		if _transfer_count > heat_source.get_recoverable_log_count():
			return &"fuel_changed"
		if inventory.get_add_refusal(ItemCatalog.get_item(fuel_item_id), _transfer_count) != &"":
			return &"hands_full"
	elif inventory.get_count(fuel_item_id) < _transfer_count or heat_source.get_log_room() < _transfer_count:
		return &"resource_lost"
	return &""


func _clear_act() -> void:
	release_lighter()
	_clear_lighter()
	if _act_lighting and is_instance_valid(_animation):
		_animation.end_work_pose()
	_stage = Stage.IDLE
	_act_left = 0.0
	_act_lighting = false
	_action_managed = false
	_action_id = &""
	_transfer_count = 0


func _build_lighter() -> void:
	_lighter = LighterStrikeVFX.new()
	if _animation != null:
		_animation.hold_in_hand(_lighter)
	else:
		add_child(_lighter)
		_lighter.position = focus_anchor.position


func _clear_lighter() -> void:
	if not is_instance_valid(_lighter):
		_lighter = null
		return
	if is_instance_valid(_animation) and _animation.get_held_prop() == _lighter:
		_animation.release_hand()
	_lighter.queue_free()
	_lighter = null


func _hands_free(allow_logs: bool = false) -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return false
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.carried_in_hands and (not allow_logs or item.id != fuel_item_id):
			return false
	var prop: Node3D = _animation.get_held_prop() if is_instance_valid(_animation) else null
	if prop == null or prop == _lighter:
		return true
	return is_instance_valid(_held_item) and _held_item.get_item_id() == &"lighter" \
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


## Consume from the owning storage only when the held flame has caught.
func _consume_owned_item(item_id: StringName) -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory != null and inventory.try_remove(item_id):
		return true
	if is_instance_valid(_equipment):
		for pocket: Dictionary in _equipment.get_available_pockets():
			if pocket["item_id"] == item_id:
				return _equipment.take_from_pocket(pocket["body_slot"], pocket["pocket"]) == item_id
	return false


func _ui_blocked() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))


func _in_reach() -> bool:
	var interact: InteractComponent = _player.get_node_or_null(^"InteractComponent") as InteractComponent if _player != null else null
	return interact != null and interact.current_target == self and interact.is_target_in_reach()


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
	return LIGHT_SECONDS if _act_lighting else ADD_SECONDS * _transfer_count


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return int(state.get_script().get_script_constant_map().get("Mode", {}).get(String(mode_name), -1)) if state != null else -1


func _on_interaction_performed() -> void:
	_report(begin_act())


func _report(refusal: Refusal) -> void:
	if refusal != Refusal.NONE:
		feed_refused.emit(refusal)
		show_message(tr(describe_refusal(refusal)))


## A running load or ignition holds focus so the door cannot steal it mid-action.
func keeps_focus() -> bool:
	return is_acting()


func resolve_focus(from: Vector3, direction: Vector3) -> InteractiveArea:
	if is_acting():
		return self
	if is_instance_valid(door_control) and door_control.is_aim_on_door(from, direction):
		return door_control
	return self if _door_open else door_control


func _on_mode_changed(_old_mode: int, _new_mode: int) -> void:
	if _ui_blocked():
		release_lighter()


func _get_interaction_text() -> String:
	if not _door_open:
		set_description("")
		return "[%s] %s" % [_interact_key_label(), tr("STOVE_OPEN")]
	if _is_lighting():
		set_description("[%s] %s" % [_interact_key_label(), tr("STOVE_CANCEL_LIGHTER")])
		return tr("STOVE_PREPARING" if _stage == Stage.PREPARING else "STOVE_LIGHTER_HOLD")
	if is_acting():
		var progress: int = int(roundf(100.0 * (1.0 - _act_left / maxf(_act_duration_seconds(), 0.001))))
		set_description("[%s] %s" % [_interact_key_label(), tr("STOVE_CANCEL_TRANSFER")])
		return tr("STOVE_RETURN_PROGRESS" if _removing else "STOVE_TRANSFER_PROGRESS") % [_transfer_count, clampi(progress, 0, 100)]
	var count: int = _available_logs(false)
	var detail: String = tr("STOVE_MOUSE_TAKE") if _available_logs(true) > 0 else ""
	if count > 0:
		set_description(detail)
		return "[%s] %s" % [_interact_key_label(), tr("STOVE_LOAD_COUNT") % count]
	if not heat_source.is_burning() and heat_source.get_remaining_hours() > 0.0:
		var refusal: Refusal = _ignition_refusal()
		set_description(detail)
		if refusal != Refusal.NONE:
			return tr(describe_refusal(refusal))
		return "[%s] %s" % [_interact_key_label(), tr("STOVE_IGNITE")]
	if heat_source.is_burning():
		set_description(tr("FEED_REFUSED_ALREADY_FULL") if heat_source.get_log_room() <= 0 else detail)
		return tr("STOVE_WARMING" if heat_source.get_intensity() < 1.0 else "STOVE_BURNING")
	set_description(detail)
	return tr("STOVE_EMPTY")


func get_interaction_prompt_data() -> Dictionary:
	var data: Dictionary = super()
	if _stage == Stage.TRANSFERRING:
		data["key"] = ""
	elif _stage == Stage.PREPARING:
		data["key"] = ""
	elif _is_lighting():
		data["key"] = tr("STOVE_MOUSE_KEY")
		data["action"] = tr("STOVE_LIGHTER_HOLD")
		data["detail"] = "[%s] %s" % [_interact_key_label(), tr("STOVE_CANCEL_LIGHTER")]
		if _available_logs(true) > 0:
			data["detail"] += " · " + tr("STOVE_MOUSE_TAKE")
	elif _door_open and not is_acting() and _available_logs(false) <= 0 \
		and (heat_source.is_burning() or heat_source.get_remaining_hours() <= 0.0 or _ignition_refusal() != Refusal.NONE):
		data["key"] = ""
	return data


func _is_lighting() -> bool:
	return _stage in [Stage.PREPARING, Stage.READY, Stage.HOLDING]


func _prepare_ignition() -> Refusal:
	if not _hands_free(true):
		return Refusal.HANDS_OCCUPIED
	if not _put_down_overflow():
		return Refusal.NO_DROP_SPACE
	var refusal: Refusal = _ignition_refusal()
	return _start_action(true, 0, false) if refusal == Refusal.NONE else refusal


func _ignition_refusal() -> Refusal:
	if not _hands_free():
		return Refusal.HANDS_OCCUPIED
	if not _has_lighter():
		return Refusal.NO_LIGHTER
	if tinder_item_id != &"" and not _has_owned_item(tinder_item_id):
		return Refusal.NO_TINDER
	return Refusal.NONE


func _put_down_overflow() -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or not inventory.has_item(fuel_item_id):
		return true
	var work: WoodWorkComponent = _player.get_node_or_null(^"WoodWorkComponent") as WoodWorkComponent if _player != null else null
	return work != null and work.drop_carried_nearby()


func _activity_stop_reason() -> StringName:
	if not is_instance_valid(heat_source) or heat_source.is_queued_for_deletion() or not _door_open:
		return &"target_lost"
	if _player != null and _player.get_node_or_null(^"InteractComponent") != null and not _in_reach():
		return &"target_lost"
	return &""


func _available_logs(removing: bool) -> int:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or not _hands_free(true):
		return 0
	if not removing:
		return mini(heat_source.get_log_room(), inventory.get_count(fuel_item_id))
	var count: int = heat_source.get_recoverable_log_count()
	var item: ItemResource = ItemCatalog.get_item(fuel_item_id)
	while count > 0 and inventory.get_add_refusal(item, count) != &"":
		count -= 1
	return count


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
		_: return "ACTION_REFUSED_BUSY"


## Compatibility for isolated tools; normal input always uses staged transfers.
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

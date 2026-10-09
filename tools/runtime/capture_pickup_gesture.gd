extends SceneTree

## One consolidated proof in the real First Exit shelter, driven through real input:
## tap stores, the segmented ring fills top-down into the hand, cancel and swap, red-key
## refusals, the hammer and an unlit flare keep their weight in hand, a lit flare is
## dropped with G and burns out on the floor, and the stove keeps the world prompt.
## Run under Movie Maker for frames:
##   godot --path . --write-movie <dir>/f.png --fixed-fps 10 --resolution 1280x720 \
##     --script res://tools/runtime/capture_pickup_gesture.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"
const FPS: int = 10

var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent
var _marker: PickupMarkerUI
var _held: HeldItemComponent
var _inventory: InventoryComponent
var _caption: Label
var _status: Label
var _report: Array[String] = []
var _max_pickup_weight: float = 0.0
var _segment: String = ""
var _aim_point: Vector3 = Vector3.ZERO
var _hammer: HammerComponent
var _light: HeldLightComponent
var _hub: PlayerHubComponent
var _quick: QuickAccessComponent
var _weight_note: String = ""
var _watched_flare: HeldFlare


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build_world()
	_interact.pickup_stored.connect(func(item_id: StringName, destination: StringName) -> void:
		_report.append("stored %s -> %s" % [item_id, destination]))
	_interact.pickup_gesture_finished.connect(func(target: InteractiveArea, result: StringName) -> void:
		_report.append("gesture %s on %s, hand=%s" % [result, target.name if is_instance_valid(target) else "-", _held.get_item_id()]))
	await _seconds(1.0)
	await _tap_tin()
	await _hold_knife()
	await _cancel_lighter()
	await _swap_with_lighter()
	await _overweight()
	await _hammer_weight()
	await _unlit_flare_weight()
	await _flare_g_drop()
	await _stove_wins()
	for line: String in _report:
		print("[PickupGestureCapture] " + line)
	print("[PickupGestureCapture] max shoulder override weight with no world target held by framing: %.4f" % _max_pickup_weight)
	quit(0)


func _build_world() -> void:
	_scene = (load(BLOCKOUT) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.6
	root.add_child(lamp)
	lamp.global_position = _local(Vector3(0.5, 2.6, 0.5))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_marker = _player.get_node(^"PickupMarkerUI") as PickupMarkerUI
	_held = _player.get_node(^"HeldItemComponent") as HeldItemComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_hammer = _player.get_node(^"HammerComponent") as HammerComponent
	_light = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_quick = _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	_camera = (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	_caption = _label(layer, Vector2(16.0, 12.0), 22)
	_status = _label(layer, Vector2(16.0, 44.0), 15)


func _tap_tin() -> void:
	_segment = "1  Tap F: the tin goes to storage by the existing route"
	var tin := _scene.get_node(^"StewShelterTest") as InteractiveArea
	await _approach(_local(Vector3(2.55, 0.91, 0.05)), tin)
	await _f(0.1)
	await _seconds(1.5)


func _hold_knife() -> void:
	_segment = "2  Hold F: F framed in place, hand inside, three arcs fill from the top -> knife in hand"
	var knife := _scene.get_node(^"KnifeShelterTest") as InteractiveArea
	await _approach(_local(Vector3(1.6, 0.91, 2.12)), knife)
	await _f(1.3)
	await _seconds(1.5)


func _cancel_lighter() -> void:
	_segment = "3  Partial hold, release: cancelled, nothing taken, knife stays in hand"
	var lighter := _scene.get_node(^"LighterShelterTest") as InteractiveArea
	await _approach(_local(Vector3(2.5, 0.91, 2.12)), lighter)
	await _f(0.6)
	await _seconds(1.2)


func _swap_with_lighter() -> void:
	_segment = "4  Hold again to 1.0 s: knife put away into storage, lighter in hand"
	var lighter := _scene.get_node(^"LighterShelterTest") as InteractiveArea
	_aim_at(lighter.get_focus_point(_player.global_position))
	await _seconds(0.5)
	await _f(1.3)
	await _seconds(1.5)


func _overweight() -> void:
	_segment = "5  Overweight: tap -> red F + centre x; hold -> red [F] + centre x"
	var flask := _scene.get_node(^"FlaskShelterTest") as InteractiveArea
	var max_weight: float = _inventory.max_carry_weight
	_inventory.max_carry_weight = _inventory.get_total_weight() + 0.01
	await _approach(_local(Vector3(1.35, 0.91, 0.05)), flask)
	await _f(0.1)
	await _seconds(1.2)
	await _f(1.3)
	await _seconds(1.2)
	_inventory.max_carry_weight = max_weight


func _hammer_weight() -> void:
	_segment = "6  Hammer from Quick Access: storage keeps it, carried weight unchanged"
	_held.put_away()
	var zone: StringName = _stow_in_pocket(&"hammer")
	var before: float = _inventory.get_total_weight()
	_select(zone)
	await _seconds(0.8)
	_quick.use_selected()
	await _seconds(1.5)
	var held: float = _inventory.get_total_weight()
	_hammer.put_away()
	await _seconds(0.8)
	_weight_note = "hammer: before %.2f / held %.2f / after %.2f kg" % [before, held, _inventory.get_total_weight()]
	_report.append(_weight_note)


func _unlit_flare_weight() -> void:
	_segment = "7  Unlit flare in hand: still in its pocket, weight unchanged"
	var zone: StringName = _stow_in_pocket(&"road_flare")
	var before: float = _inventory.get_total_weight()
	_light.equip_from_zone(&"road_flare", zone)
	await _seconds(1.5)
	var held: float = _inventory.get_total_weight()
	_light.put_away_unlit()
	await _seconds(0.6)
	_weight_note = "unlit flare: before %.2f / held %.2f / after %.2f kg" % [before, held, _inventory.get_total_weight()]
	_report.append(_weight_note)


func _flare_g_drop() -> void:
	_segment = "8  Lit flare: same weight while burning in hand; G drops the same flare, it burns out on time"
	var zone: StringName = _stow_in_pocket(&"road_flare")
	var pocket: float = _inventory.get_total_weight()
	_light.equip_from_zone(&"road_flare", zone)
	_watched_flare = _player.animation_component.get_held_prop() as HeldFlare
	if _watched_flare == null:
		_watched_flare = _player.animation_component.get_offhand_prop() as HeldFlare
	_watched_flare.burn_duration_s = 6.0
	_light.ignite_held()
	await _seconds(1.5)
	var burning: float = _inventory.get_total_weight()
	var remaining: float = _watched_flare.get_remaining_seconds()
	var down := InputEventAction.new()
	down.action = HeldLightComponent.DROP_ACTION
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = HeldLightComponent.DROP_ACTION
	Input.parse_input_event(up)
	await _seconds(0.3)
	var after_drop: float = _inventory.get_total_weight()
	_weight_note = "flare: pocket %.2f / burning in hand %.2f / after G %.2f kg" % [pocket, burning, after_drop]
	_report.append(_weight_note)
	_report.append("flare dropped with %.2f s left; same instance under %s, burning=%s" % [
		remaining, _watched_flare.get_parent().name, _watched_flare.is_burning()])
	var frames: int = 3
	while is_instance_valid(_watched_flare) and not _watched_flare.is_spent() and frames < 120:
		await _seconds(0.1)
		frames += 1
	_report.append("flare went out %.1f frames after G at %d fps (expected ~%.1f)" % [frames, FPS, remaining * FPS])
	await _seconds(2.0)
	_watched_flare = null
	_weight_note = ""


func _stow_in_pocket(item_id: StringName) -> StringName:
	_inventory.try_add(ItemCatalog.get_item(item_id))
	for entry: Dictionary in _hub.get_quick_access_zones():
		if entry["item_id"] == &"" and _hub.move_to_zone(item_id, entry["path"]) == EquipmentComponent.Refusal.NONE:
			return entry["path"]
	return HeldOwnership.pocket_holding(_player.get_node(^"EquipmentComponent") as EquipmentComponent, item_id)


func _select(zone: StringName) -> void:
	var zones: Array[Dictionary] = _hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		if zones[i]["path"] == zone:
			_quick.select(i)


func _stove_wins() -> void:
	_segment = "9  Stove under the view: central prompt, immediate F, no pickup ring"
	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: Node3D = feed.heat_source
	var tin: ItemPickup = _spawn_tin(source.to_global(Vector3(1.3, 0.03, -0.75)))
	_player.global_position = source.to_global(Vector3(1.2, 0.9, 0.0)) + Vector3.UP * 1.0
	_player.look_at(Vector3(feed.focus_anchor.global_position.x, _player.global_position.y, feed.focus_anchor.global_position.z), Vector3.UP)
	_aim_point = feed.focus_anchor.global_position
	await _seconds(1.5)
	await _f(0.1)
	await _seconds(1.5)
	_report.append("stove: world=%s door_open=%s tin_still_here=%s" % [
		_name(_interact.get_world_target()), feed.is_door_open(), is_instance_valid(tin) and not tin.is_queued_for_deletion()])


func _spawn_tin(at: Vector3) -> ItemPickup:
	var area: Node = (load("res://scenes/environment/interactive/InteractiveArea.tscn") as PackedScene).instantiate()
	area.set_script(load("res://scripts/environment/interactive/item_pickup.gd"))
	var pickup := area as ItemPickup
	pickup.item_id = &"tinned_stew"
	root.add_child(pickup)
	pickup.global_position = at
	return pickup


func _approach(feet: Vector3, target: InteractiveArea) -> void:
	_player.global_position = feet + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	var point: Vector3 = target.get_focus_point(_player.global_position)
	_player.look_at(Vector3(point.x, _player.global_position.y, point.z), Vector3.UP)
	_player.reset_physics_interpolation()
	_aim_point = point
	await _seconds(1.2)


## Presses F through the real input path and holds it for seconds.
func _f(seconds: float) -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _seconds(seconds)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _aim_at(point: Vector3) -> void:
	_aim_point = point
	var to_point: Vector3 = (point - TpsCamera.aim_origin(_camera)).normalized()
	_camera.set_look(atan2(-to_point.x, -to_point.z), rad_to_deg(asin(clampf(to_point.y, -1.0, 1.0))))


func _seconds(seconds: float) -> void:
	for _i: int in range(maxi(1, int(round(seconds * FPS)))):
		_aim_at(_aim_point)
		await process_frame
		_status_update()


func _status_update() -> void:
	## Framing holds a lost world target 0.25 s; only weight with no world target held could come from a pickup.
	var framing := _camera.get_node_or_null(^"InteractionFraming") as TpsInteractionFraming
	if _interact.get_world_target() == null and (framing == null or not is_instance_valid(framing._held_target)):
		_max_pickup_weight = maxf(_max_pickup_weight, _camera._shoulder.get_interaction_weight())
	var v: Dictionary = _marker.get_visual_state()
	_caption.text = _segment
	_status.text = "pickup: %s   gesture: %s   hold: %s  %.0f%%\nring: %s   hand: %s   world: %s\ncarried weight: %.2f kg   shoulder override weight: %.3f" % [
		_name(_interact.get_pickup_target()), _name(_interact.get_gesture_target()), _interact.is_gesture_holding(),
		_interact.get_gesture_progress() * 100.0, v["mode"], _hand_name(), _name(_interact.get_world_target()),
		_inventory.get_total_weight(), _camera._shoulder.get_interaction_weight()]
	if _weight_note != "":
		_status.text += "\n" + _weight_note
	if is_instance_valid(_watched_flare):
		_status.text += "\nflare: %s, %.1f s left, parent %s" % [
			"burning" if _watched_flare.is_burning() else ("spent" if _watched_flare.is_spent() else "unlit"),
			_watched_flare.get_remaining_seconds(), _watched_flare.get_parent().name if _watched_flare.get_parent() != null else "-"]


func _hand_name() -> String:
	if _hammer.is_holding():
		return "hammer"
	if _light.is_holding():
		return "road_flare (burning)" if _light.is_burning() else "road_flare"
	return String(_held.get_item_id())


func _local(point: Vector3) -> Vector3:
	return _house.to_global(point)


func _name(area: InteractiveArea) -> String:
	return "-" if area == null else String(area.name)


func _label(layer: CanvasLayer, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.97, 0.9))
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(label)
	return label

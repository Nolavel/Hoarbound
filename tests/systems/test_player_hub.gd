extends SceneTree

## Player Hub (#68): the four-flap pack opens top-only or fully; the Hub opens,
## lists the real inventory and moves an item pack → pocket → pack without duplicating it.
## Run: godot --headless --script tests/systems/test_player_hub.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"

var _failures: int = 0
var _frame: int = 0
var _time: float = 0.0
var _stow_hub: PlayerHubComponent
var _stow_pickup: ItemPickup
var _stow_visual: Node3D
var _stow_inventory: InventoryComponent
var _saw_top_only: bool = false
var _hold_started: bool = false
var _expected_route: StringName = &""


func _process(delta: float) -> bool:
	_frame += 1
	_time += delta
	if _frame == 1:
		_test_pack_rig()
		_test_hub_flow()
		_start_quick_stow()
	elif _stow_hub != null:
		if _stow_hub.pack.get_openness() == PackRig.Openness.TOP_ONLY:
			_saw_top_only = true
		if _time > 1.5 and not _hold_started:
			_check_quick_stow()
			_start_hold()
		elif _hold_started and _time > 2.3:
			_check_hold()
			_finish()
	return false


## Tap F: the pickup lands in the inventory at once; its mesh flies into the
## top flap, which opens alone and shuts once it lands.
func _start_quick_stow() -> void:
	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.layout = load(LAYOUT) as EquipmentLayout
	equipment.starter_garment_ids = [&"worn_coat"]
	body.add_child(equipment)
	_stow_inventory = InventoryComponent.new()
	_stow_inventory.equipment = equipment
	body.add_child(_stow_inventory)
	_stow_hub = PlayerHubComponent.new()
	_stow_hub.name = "PlayerHubComponent"
	body.add_child(_stow_hub)
	root.add_child(body)
	var pack := PackRig.new()
	pack.position = Vector3(0.0, 1.2, 0.2)
	body.add_child(pack)
	_stow_hub.pack = pack
	var area: Node = (load("res://scenes/environment/interactive/InteractiveArea.tscn") as PackedScene).instantiate()
	area.set_script(load("res://scripts/environment/interactive/item_pickup.gd"))
	area.set(&"interactable_scene", null)
	_stow_pickup = area as ItemPickup
	_stow_pickup.item_id = &"road_flare"
	_stow_pickup.position = Vector3(1.0, 0.0, 0.0)
	root.add_child(_stow_pickup)
	_stow_visual = _stow_pickup.interactive_mesh
	_check(_stow_pickup.pick_up(), "the flare was not picked up")
	_check(_stow_inventory.has_item(&"road_flare"), "the picked flare is not in the inventory at once")


func _check_quick_stow() -> void:
	_check(_saw_top_only, "the top flap alone did not open for the stow")
	_check(not is_instance_valid(_stow_visual), "the stowed mesh was not freed after landing")
	_check(_stow_hub.pack.get_openness() == PackRig.Openness.CLOSED, "the pack stayed open after the stow")
	_check(_stow_inventory.get_count(&"road_flare") == 0, "preferred light stayed in the pack after tap-F stow")
	var pocketed: int = 0
	for zone: Dictionary in _stow_hub.get_quick_access_zones():
		if zone["item_id"] == &"road_flare":
			pocketed += 1
	_check(pocketed == 1, "tap-F did not auto-sort exactly one preferred light into Quick Access")


func _test_pack_rig() -> void:
	var pack := PackRig.new()
	root.add_child(pack)
	_check(not pack.is_open(), "the pack starts open")
	pack.set_openness(PackRig.Openness.TOP_ONLY, true)
	_check(is_equal_approx(pack.get_flap_open(&"top"), 1.0), "top-only did not open the top flap")
	for side: StringName in [&"left", &"right", &"bottom"]:
		_check(is_zero_approx(pack.get_flap_open(side)), "top-only opened the %s flap" % side)
	pack.set_openness(PackRig.Openness.FULL, true)
	for flap: StringName in [&"top", &"left", &"right", &"bottom"]:
		_check(is_equal_approx(pack.get_flap_open(flap), 1.0), "full opening left the %s flap shut" % flap)
	pack.set_openness(PackRig.Openness.CLOSED, true)
	_check(is_zero_approx(pack.get_flap_open(&"left")), "closing left a flap open")
	pack.free()


func _test_hub_flow() -> void:
	var body := CharacterBody3D.new()
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.layout = load(LAYOUT) as EquipmentLayout
	equipment.starter_garment_ids = [&"worn_coat", &"work_trousers", &"backpack"]
	body.add_child(equipment)
	var inventory := InventoryComponent.new()
	inventory.equipment = equipment
	body.add_child(inventory)
	var hub := PlayerHubComponent.new()
	body.add_child(hub)
	root.add_child(body)
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	inventory.try_add(load("res://data/items/bedroll.tres") as ItemResource)

	_check(hub.open(), "the Hub did not open")
	_check(hub.is_open(), "the Hub does not report open")
	var ids: Array = hub.get_pack_items().map(func(item: Dictionary) -> StringName: return item["id"])
	_check(ids.has(&"road_flare") and ids.has(&"bedroll"), "the Hub does not list the inventory: %s" % [ids])
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	var paths: Array = zones.map(func(zone: Dictionary) -> StringName: return zone["path"])
	_check(not paths.is_empty(), "no Quick Access zone is offered")
	_check(not paths.has(&"pack/pack_main"), "the main compartment is offered as Quick Access")
	var pocket: StringName = paths[0] if not paths.is_empty() else &""

	var weight: float = hub.get_weight()
	_check(hub.move_to_zone(&"bedroll", pocket) == EquipmentComponent.Refusal.TOO_LARGE,
		"a bulky bedroll went into a pocket")
	_check(inventory.has_item(&"bedroll"), "a refused bedroll left the pack")
	_check(hub.move_to_zone(&"road_flare", pocket) == EquipmentComponent.Refusal.NONE, "the flare did not go into a pocket")
	_check(not inventory.has_item(&"road_flare"), "the pocketed flare is still in the pack (duplicated)")
	_check(_zone_item(hub, pocket) == &"road_flare", "the pocket does not hold the flare")
	_check(is_equal_approx(hub.get_weight(), weight), "pocketing changed the carried weight")
	_check(hub.move_to_zone(&"road_flare", pocket) != EquipmentComponent.Refusal.NONE, "a flare no longer in the pack moved again")
	_check(hub.move_to_pack(pocket) == &"", "the flare did not return to the pack")
	_check(inventory.get_count(&"road_flare") == 1, "returning did not give back exactly one flare")
	_check(_zone_item(hub, pocket) == &"", "the pocket still holds the flare")

	_check(hub.close(), "the Hub did not close")
	_check(not hub.is_open(), "the Hub reports open after closing")
	body.free()


func _zone_item(hub: PlayerHubComponent, path: StringName) -> StringName:
	for zone: Dictionary in hub.get_quick_access_zones():
		if zone["path"] == path:
			return zone["item_id"]
	return &"?"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("test_player_hub: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Hold F is the pickup gesture's now: a press held through a stow never opens the Hub,
## and the flare settles by the canonical route like any tap pickup.
func _start_hold() -> void:
	_hold_started = true
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	Input.action_press(&"interact")
	_stow_hub._input(press)
	_stow_inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	_expected_route = _stow_hub.route_destination(&"road_flare")
	var ghost := Node3D.new()
	root.add_child(ghost)
	_stow_hub.stow_visual(ghost, &"road_flare")


func _check_hold() -> void:
	Input.action_release(&"interact")
	_check(not _stow_hub.is_open(), "holding F through a pickup still opened the Hub")
	_check(_expected_route != PlayerHubComponent.PACK_DESTINATION, "no free Quick Access pocket for the second flare")
	if _expected_route == PlayerHubComponent.PACK_DESTINATION:
		return
	_check(_zone_item(_stow_hub, _expected_route) == &"road_flare", "the second flare did not take the canonical route")
	_stow_hub.move_to_pack(_expected_route)
	_check(_stow_hub.open_placement(&"road_flare"), "manual placement did not open for a pack flare")
	var panel: PlayerHubPanel = null
	for child: Node in _stow_hub.get_children():
		if child is PlayerHubPanel:
			panel = child
	_check(panel != null and panel.is_placing(), "the Hub opened without placing the picked item")
	if panel == null:
		return
	panel.drop_on(_expected_route)
	_check(not _stow_hub.is_open(), "dropping did not close the Hub")
	_check(_zone_item(_stow_hub, _expected_route) == &"road_flare", "the dropped flare is not in the chosen pocket")
	_check(_stow_inventory.get_count(&"road_flare") == 0, "manual placement left the flare in the pack")
	var carried_flares: int = 0
	for zone: Dictionary in _stow_hub.get_quick_access_zones():
		if zone["item_id"] == &"road_flare":
			carried_flares += 1
	_check(carried_flares == 2, "placement did not preserve the earlier auto-pocketed flare")

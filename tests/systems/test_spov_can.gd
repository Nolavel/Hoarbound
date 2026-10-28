extends SceneTree

## SPoV canned meat: catalogued, opened by its ring without a tool, eaten for its calories,
## the empty can tossed on the ground, survives a save, and lies as a pickup in the 727 cabinet.

const GAMEPLAY_SITES: String = "res://data/world/key_west/reality/overrides/first_exit_gameplay.json"

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_catalog()
	await _test_open_and_eat()
	_test_visuals()
	_test_placement()
	print("test_spov_can: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_catalog() -> void:
	var sealed: ItemResource = ItemCatalog.get_item(&"spov_can")
	var open: ItemResource = ItemCatalog.get_item(&"spov_can_open")
	_check(sealed != null and open != null, "SPoV can items are not in the catalog")
	if sealed == null or open == null:
		return
	_check(sealed.opens_into == &"spov_can_open", "sealed can does not open into the open can")
	_check(sealed.consumable != null and sealed.consumable.required_tool_id == &"", "ring-pull can needs a tool")
	_check(open.consumable != null and open.consumable.calories > 0.0, "open can restores no calories")
	_check(open.consumable.discard_leftover and open.consumable.leaves_behind_id == &"spov_can_empty",
		"the eaten can is not tossed as an empty SPoV can")
	_check(ConsumptionController.open_action_key(sealed) == "CAN_RING_OPEN_ACTION", "ring can shows the knife hint")
	_check(ConsumptionController.open_action_key(ItemCatalog.get_item(&"tinned_pineapple")) == "PINEAPPLE_OPEN_ACTION",
		"pineapple lost its knife hint")
	_check(tr("CAN_RING_OPEN_ACTION") != "CAN_RING_OPEN_ACTION" or TranslationServer.get_loaded_locales().is_empty(),
		"ring open action is not localised")


func _test_open_and_eat() -> void:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var eater := player.get_node(^"ConsumptionController") as ConsumptionController
	var bio: BioMonitorManager = eater.bio_monitor
	bio.current_calories = 1000.0
	inventory.try_add(ItemCatalog.get_item(&"spov_can"))
	_check(eater.consume(&"spov_can") == ConsumptionController.Refusal.NONE, "the ring did not open the can")
	_check(inventory.has_item(&"spov_can_open") and not inventory.has_item(&"spov_can"), "opening did not swap to the open can")
	_check(is_equal_approx(bio.current_calories, 1000.0), "opening the can fed Henry")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(inventory.get_save_data()))
	inventory.load_save_data(saved)
	_check(inventory.has_item(&"spov_can_open"), "the open can was lost by a save restore")
	var calories: float = ItemCatalog.get_item(&"spov_can_open").consumable.calories
	var tossed: Array[RigidBody3D] = []
	eater.leftover_discarded.connect(func(_id: StringName, litter: RigidBody3D) -> void: tossed.append(litter))
	_check(eater.consume(&"spov_can_open") == ConsumptionController.Refusal.NONE, "the open can could not be eaten")
	_check(is_equal_approx(bio.current_calories, minf(1000.0 + calories, bio.max_calories)),
		"eating gave %.0f kcal, expected %.0f" % [bio.current_calories - 1000.0, calories])
	_check(not inventory.has_item(&"empty_tin") and not inventory.has_item(&"spov_can_empty") and not inventory.has_item(&"spov_can_open"),
		"the empty can stayed in the inventory")
	_check(tossed.size() == 1 and is_instance_valid(tossed[0]) and tossed[0].is_inside_tree(), "the empty can was not tossed into the world")
	if tossed.size() == 1:
		var start_y: float = tossed[0].global_position.y
		for _i: int in range(10):
			await physics_frame
		_check(tossed[0].global_position.y < start_y, "the tossed can does not fall")
		_check(tossed[0].find_child("SPoV_Can_Body", true, false) != null, "the tossed can is not the SPoV model")
		tossed[0].queue_free()
	player.queue_free()
	await physics_frame


func _test_visuals() -> void:
	var sealed: Node3D = SurvivalItemVisual.make(&"spov_can")
	var ring := sealed.find_child("SPoV_Can_Ring", true, false) as Node3D
	_check(sealed.find_child("SPoV_Can_Body", true, false) != null and ring != null and ring.visible,
		"sealed can visual lacks the authored body or ring")
	var open: Node3D = SurvivalItemVisual.make(&"spov_can_open")
	var open_ring := open.find_child("SPoV_Can_Ring", true, false) as Node3D
	_check(open_ring != null and not open_ring.visible, "open can still shows its ring")
	var empty: Node3D = SurvivalItemVisual.make(&"spov_can_empty")
	_check(empty.find_child("SPoV_Can_Body", true, false) != null, "the empty can has no SPoV model")
	sealed.free()
	open.free()
	empty.free()


func _test_placement() -> void:
	var template := (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	var pickup := template.get_node_or_null(^"SPoVCanShelter") as ItemPickup
	_check(pickup != null and pickup.item_id == &"spov_can", "the template has no SPoV can pickup")
	template.free()
	var sites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GAMEPLAY_SITES))
	var site: Dictionary = sites.get("shelter_sockets", {}).get("SPoVCanShelter", {})
	_check(site.get("on") == "Cabinet" and site.get("room") == "waiting", "the can has no 727 cabinet site")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_spov_can: " + message)

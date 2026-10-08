extends SceneTree

## Real player components, shifted TPS projection and generated shelter collisions.
## Tests physical drop, floor pickups, staged boarding, cold loading and table eating.

var _failures: int = 0
var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent
var _inventory: InventoryComponent
var _clock: SimulationClock
var _actions: TimeCostedActionSystem
var _board_started_in_working: bool = false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_clock = SimulationClock.new()
	root.add_child(_clock)
	_clock.set_total_hours(12.0, &"test_seed")
	_actions = TimeCostedActionSystem.new()
	_actions.simulation_clock = _clock
	root.add_child(_actions)
	_actions.action_started.connect(_on_action_started)

	_scene = (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.set_physics_process(false)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.h_offset = 0.51
	_camera.current = true
	await physics_frame
	await physics_frame
	await _test_tools()
	await _test_supplies()
	_test_roof()
	await _test_boards()
	await _test_stove()
	await _test_table()
	await _test_drop()
	await _test_dismantle()
	print("test_shelter_workflow: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_tools() -> void:
	for node_name: String in ["HammerShelter", "NailsShelter", "LighterShelterTest", "AxeShelterTest"]:
		var pickup: ItemPickup = _scene.get_node(NodePath(node_name)) as ItemPickup
		_check(_house.to_local(pickup.global_position).y > 1.7, "%s is buried under the floor/bench" % node_name)
		var id: StringName = pickup.item_id
		var count: int = pickup.count
		await _aim(pickup, pickup.global_position + _house.global_basis.z * 0.8, pickup.get_focus_point(_player.global_position))
		_check_target(pickup, node_name)
		_press(&"interact")
		_check(pickup.is_queued_for_deletion() and _inventory.get_count(id) == count, "%s did not pick up with real F" % node_name)
		await physics_frame
	await create_timer(0.5).timeout
	_check((_player.get_node(^"HammerComponent") as HammerComponent).can_use(&"hammer")
		or _has_pocket(&"hammer"), "picked-up hammer became inaccessible after stowing")
	var floor_item := ItemPickup.new()
	floor_item.item_id = &"lighter"
	floor_item.position = _house.to_global(Vector3(0, 0.915, 1.5))
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	floor_item.add_child(col)
	root.add_child(floor_item)
	await _aim(floor_item, floor_item.global_position + _house.global_basis.z * 0.65 + Vector3.UP,
		floor_item.get_focus_point(_player.global_position))
	_check_target(floor_item, "floor item with shifted TPS camera")
	var lighter_count: int = _inventory.get_count(&"lighter")
	_press(&"interact")
	_check(floor_item.is_queued_for_deletion() and _inventory.get_count(&"lighter") == lighter_count + 1,
		"F did not pick up a floor item through the real camera projection")


func _test_supplies() -> void:
	for node_name: String in ["FlaskShelterTest", "PineappleShelterTest", "StewShelterTest"]:
		var pickup: ItemPickup = _scene.get_node(NodePath(node_name)) as ItemPickup
		_check(String(pickup.get_interaction_prompt_data()["detail"]).contains(pickup.item_name),
			"supply pickup prompt hides the item name behind its status")
		await _aim(pickup, pickup.global_position + _house.global_basis.z * 0.8, pickup.get_focus_point(_player.global_position))
		_check_target(pickup, "supply bench " + node_name)
		_press(&"interact")
		_check(pickup.is_queued_for_deletion(), "food/water could not be picked up with F")
		await physics_frame
	var eater: ConsumptionController = _player.get_node(^"ConsumptionController") as ConsumptionController
	var bio: BioMonitorManager = eater.bio_monitor
	bio.current_hydration = 20.0
	bio.current_calories = 1000.0
	_check(eater.consume(&"tinned_pineapple") == ConsumptionController.Refusal.NO_TOOL,
		"sealed pineapple did not require a knife")
	_check(_inventory.get_count(&"tinned_pineapple") == 2, "missing knife spent pineapple")
	var knife: ItemPickup = _scene.get_node(^"KnifeShelterTest") as ItemPickup
	await _aim(knife, knife.global_position + _house.global_basis.z * 0.8, knife.get_focus_point(_player.global_position))
	_check_target(knife, "knife on tool bench")
	_press(&"interact")
	_check(_inventory.has_item(&"knife"), "F did not pick up the knife")
	var hub: PlayerHubComponent = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_check(hub.use_item(&"water_flask"), "Hub Use did not drink from a carried flask")
	_check(is_equal_approx(bio.current_hydration, 32.0), "250 ml did not restore hydration")
	_check(_inventory.get_count(&"water_flask_750") == 1 and not _inventory.has_item(&"water_flask"),
		"one sip did not leave exactly 750 ml in one flask")
	_check(eater._feedback.visible and eater._feedback.text.contains("750"), "drinking has no remaining-water feedback")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_inventory.get_save_data()))
	_inventory.load_save_data(saved)
	_check(_inventory.get_count(&"water_flask_750") == 1, "partial flask was refilled/lost by save restore")
	_check(ItemCatalog.get_item(&"water_flask_750").water_remaining_ml == 750, "restored flask does not retain water volume")
	var zone: StringName = &""
	_inventory.try_add(ItemCatalog.get_item(&"water_flask"))
	for pocket: Dictionary in hub.get_quick_access_zones():
		if pocket["item_id"] == &"" and hub.move_to_zone(&"water_flask", pocket["path"]) == EquipmentComponent.Refusal.NONE:
			zone = pocket["path"]
			break
	_check(zone != &"", "second flask could not enter a fitting physical pocket")
	if zone != &"":
		var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
		for next: StringName in [&"water_flask_750", &"water_flask_500", &"water_flask_250", &"water_flask_empty"]:
			_check(hub.use_from_zone(zone), "pocket flask could not be used")
			_check(eater.equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1])) == next,
				"partial/empty flask did not return to the same physical pocket")
		_check(not hub.use_from_zone(zone), "empty flask supplied infinite water")
		_check(_inventory.get_count(&"water_flask_750") == 1, "using another flask modified the first one")
		_check(eater.equipment.take_from_pocket(StringName(parts[0]), StringName(parts[1])) == &"water_flask_empty",
			"empty flask vanished instead of remaining a container")
	await physics_frame


func _test_roof() -> void:
	var gable: MeshInstance3D = _house.get_node(^"FrontGable") as MeshInstance3D
	var width: float = gable.mesh.get_aabb().size.x
	var depth: float = absf(gable.position.z) * 2.0
	_check(gable.mesh != null and _house.has_node(^"BackGable"), "house gables remain open")
	var ridge_y: float = gable.mesh.get_aabb().end.y
	var roof_ray := PhysicsRayQueryParameters3D.create(_house.to_global(Vector3(0, ridge_y - 0.3, 0)),
		_house.to_global(Vector3(0, ridge_y + 0.3, 0)))
	_check(not _house.get_world_3d().direct_space_state.intersect_ray(roof_ray).is_empty(), "roof ridge remains open")
	var height: float = gable.mesh.get_aabb().get_center().y
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var from: Vector3 = _house.to_global(Vector3(0, height, 0))
		var to: Vector3 = _house.to_global(Vector3(0, height, direction.z * (depth * 0.5 + 0.5)))
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		_check(not _house.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "front/back roof aperture has no solid closure")
	for side: float in [-1.0, 1.0]:
		var from: Vector3 = _house.to_global(Vector3(0, gable.mesh.get_aabb().position.y + 0.1, 0))
		var to: Vector3 = _house.to_global(Vector3(side * (width * 0.5 + 0.5), gable.mesh.get_aabb().position.y + 0.1, 0))
		_check(not _house.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty(),
			"side eave remains open")


func _test_dismantle() -> void:
	var hammer: HammerComponent = _player.get_node(^"HammerComponent") as HammerComponent
	var work: TableSalvage = _house.get_node(^"ToolBench/Dismantle") as TableSalvage
	_check(not work.can_interact(), "ordinary table aiming destructively replaces interaction without a drawn hammer")
	var breach: BreachBoardUp = _house.get_node(^"ShelterZone/FrontWindow1/BoardUp") as BreachBoardUp
	breach._equip_hammer(hammer)
	_check(hammer.is_holding(), "could not draw owned hammer for dismantling")
	if not hammer.is_holding():
		return
	var supply := ItemPickup.new()
	supply.item_id = &"lighter"
	supply.world_id = &"dismantle_test_supply"
	_scene.add_child(supply)
	supply.global_position = work.table_owner.to_global(Vector3(0, 0.81, 0))
	await _aim(work, work.focus_anchor.global_position + _house.global_basis.z * 0.8, work.focus_anchor.global_position)
	_check_target(work, "wooden table with real tabletop collision")
	_press(&"interact")
	_check(work._work_left == 0.0 and not work._destroyed, "table with an uncollected supply was broken")
	for node: Node in _scene.get_children():
		if node is ItemPickup and not node.is_queued_for_deletion():
			var local: Vector3 = work.table_owner.to_local((node as ItemPickup).global_position)
			if absf(local.x) < 1.0 and absf(local.z) < 0.4 and local.y > 0.4:
				node.queue_free()
	await physics_frame
	await _aim(work, work.focus_anchor.global_position + _house.global_basis.z * 0.8, work.focus_anchor.global_position)
	_press(&"interact")
	_check(work._work_left > 0.0 and not work._destroyed, "F did not start an explicit timed dismantle")
	_actions._process(TableSalvage.WORK_SECONDS)
	_check(work._destroyed and not work.table_owner.visible, "finished dismantle did not remove the table")
	var logs: ItemPickup = work._logs
	_check(logs != null and logs.count == 3, "table did not yield three physical logs")
	if logs == null:
		return
	_check(absf(_house.to_local(logs.global_position).y - 0.925) < 0.01, "salvaged logs are not above the real floor")
	var state: Dictionary = work.get_save_data()
	work.load_save_data(state)
	_check(work._logs == logs, "repeated restore duplicated salvaged logs")
	hammer.put_away()
	await _aim(logs, logs.global_position + _house.global_basis.z * 0.8 + Vector3.UP, logs.get_focus_point(_player.global_position))
	_check_target(logs, "salvaged logs")
	_press(&"interact")
	_check(logs.is_queued_for_deletion() and _inventory.get_count(&"firewood") == 3, "F could not carry the salvaged logs")
	var ledger: PickupLedger = PickupLedger.find(root.get_tree())
	_check(ledger.is_taken(logs.world_id), "salvaged log pickup was not persisted")
	for _i: int in range(3):
		_inventory.try_remove(&"firewood")
	work.load_save_data({"destroyed": false})
	_check(work.table_owner.visible and not work._destroyed, "loading an older intact table state did not restore its geometry")
	work.load_save_data(state)
	_check(work._logs == null, "consumed salvage pile respawned from a broken table save")
	await physics_frame
	var collected_state: Dictionary = ledger.get_save_data()
	work.load_save_data(state)
	ledger.load_save_data({"taken": []})
	await physics_frame
	_check(is_instance_valid(work._logs) and not work._logs.is_queued_for_deletion(),
		"loading an earlier uncollected salvage save lost its pile when the ledger restored last")
	work.load_save_data(state)
	ledger.load_save_data(collected_state)
	await physics_frame
	_check(work._logs == null or work._logs.is_queued_for_deletion(), "restoring collected salvage duplicated its pile")
	breach._equip_hammer(hammer)
	for path: NodePath in [^"SupplyBench/Dismantle"]:
		var other: TableSalvage = _house.get_node(path) as TableSalvage
		_check(other.get_save_key() != work.get_save_key(), "two tables share a furniture save key")
		await _aim(other, other.focus_anchor.global_position + _house.global_basis.z * 0.8, other.focus_anchor.global_position)
		_check_target(other, "dismantle " + String(path))
		_press(&"interact")
		_check(other._work_left > 0.0, "seat interaction intercepted table dismantling")
		_actions._process(TableSalvage.WORK_SECONDS)
		_check(other._destroyed and other._logs != null and other._logs.count == 3, "another wooden table did not yield logs")
	var meal: MealTable = _house.get_node(^"ShelterZone/RestCrate/MealTable") as MealTable
	_check(not meal.has_node(^"Dismantle") and meal.visible and meal.is_in_group(MealTable.GROUP),
		"ritual table still has a destructive action")
	var sit: RestSpot = _house.get_node(^"ShelterZone/RestCrate/Sit") as RestSpot
	await _aim(sit, sit.focus_anchor.global_position + _house.global_basis.z * 0.75 + Vector3.UP * 0.5,
		sit.focus_anchor.global_position)
	_check_target(sit, "protected meal ritual with a drawn hammer")
	_press(&"interact")
	_check((_player.get_node(^"RestComponent") as RestComponent).is_sitting() and meal.visible,
		"drawn hammer intercepted or destroyed the meal ritual")
	_press(&"move_forward")


func _test_boards() -> void:
	var pickup: ItemPickup = _scene.get_node(^"BoardsShelterInside") as ItemPickup
	await _aim(pickup, pickup.global_position + _house.global_basis.z * 0.7 + Vector3.UP,
		pickup.get_focus_point(_player.global_position))
	_press(&"interact")
	_check(_inventory.get_count(&"boards") == 3, "real board stack did not reach the hands")
	var breach: ShelterBreach = _house.get_node(^"ShelterZone/FrontWindow1") as ShelterBreach
	var area: BreachBoardUp = breach.get_node(^"BoardUp") as BreachBoardUp
	await _aim(area, breach.to_global(Vector3(0, -0.35, 1.45)), area.focus_anchor.global_position)
	_check_target(area, "window staging")
	_press(&"interact")
	_check(breach.get_staged_boards() == 3 and _inventory.get_count(&"boards") == 0, "F did not stage the armful")
	var stack: Node3D = breach.get_node(^"StagedBoards") as Node3D
	_check(absf(_house.to_local((stack.get_child(0) as Node3D).global_position).y - 0.94) < 0.01,
		"staged boards float above the floor")
	## Staging plays Henry's interaction clip. Let that clip release the input lock
	## before the next F takes one staged board into the offhand.
	await _settle_interaction_fixture()
	_interact.detect_target()
	_check_target(area, "window take staged board")
	_press(&"interact")
	_check(area.is_placing_board(), "F did not take a board and equip the pocketed hammer")
	if not area.is_placing_board():
		return
	_check(String(area.get_interaction_prompt_data()["key"]) == "LMB", "placement still asks for F")
	var previous_nails: int = _inventory.get_count(&"nails")
	var before_board_time: float = _clock.get_total_hours()
	_point_camera(breach.to_global(Vector3(0, -0.43, 0)))
	area._update_preview()
	_check(area._preview_valid, "camera-centre ghost could not be placed at the real window")
	_point_camera(_camera.global_position + Vector3.UP * 4.0 + _house.global_basis.z)
	_press(&"fire")
	_check(breach.get_placed_board_positions().is_empty() and _inventory.get_count(&"nails") == previous_nails,
		"same-frame camera turn committed a stale board preview")
	_check(is_equal_approx(_clock.get_total_hours(), before_board_time),
		"invalid stale board placement billed game time")
	_point_camera(breach.to_global(Vector3(0, -0.43, 0)))
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1.0, 1.8, 0.1)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	root.add_child(wall)
	wall.global_position = _camera.project_ray_origin(root.get_visible_rect().size * 0.5).lerp(breach.global_position, 0.5)
	wall.global_basis = breach.global_basis
	await physics_frame
	area._update_preview()
	_press(&"fire")
	_check(breach.get_placed_board_positions().is_empty() and _inventory.get_count(&"nails") == previous_nails,
		"LMB placed/spent materials through an obstruction")
	_check(is_equal_approx(_clock.get_total_hours(), before_board_time),
		"obstructed board placement billed game time")
	wall.queue_free()
	await physics_frame
	await physics_frame
	area._update_preview()
	_press(&"fire")
	_check(breach.get_placed_board_positions().size() == 1 and breach.get_staged_boards() == 2,
		"LMB did not move one staged board onto the window")
	_check(_inventory.get_count(&"nails") == previous_nails - 2, "one placement did not consume exactly two nails")
	_check(
		is_equal_approx(
			_clock.get_total_hours() - before_board_time,
			area.board_time_cost_minutes / 60.0
		),
		"one fitted board billed the wrong game time"
	)
	_check(_board_started_in_working, "board_window action did not enter WORKING mode")
	await physics_frame
	_interact.detect_target()
	_press(&"interact")
	_check(area.is_placing_board(), "second board could not be selected")
	_press(&"pause")
	_check(not area.is_placing_board() and breach.get_staged_boards() == 2, "cancel wasted a staged board")
	for y: float in [-0.215, 0.0]:
		await _place_board(area, y)
	(_player.get_node(^"HammerComponent") as HammerComponent).put_away()
	var next_stack: ItemPickup = _scene.get_node(^"BoardsShelterTest1") as ItemPickup
	await _aim(next_stack, next_stack.global_position + Vector3(0, 1, 0.7), next_stack.get_focus_point(_player.global_position))
	_press(&"interact")
	_check(_inventory.get_count(&"boards") == 3, "next board armful could not be carried")
	await _aim(area, breach.to_global(Vector3(0, -0.35, 1.45)), area.focus_anchor.global_position)
	_press(&"interact")
	for y: float in [0.215, 0.43]:
		await _place_board(area, y)
	_check(breach.is_boarded() and breach.get_staged_boards() == 1, "five fitted boards did not seal the window and preserve the spare")
	_check(_inventory.get_count(&"nails") == previous_nails - 10, "sealing did not consume ten nails")
	(_player.get_node(^"HammerComponent") as HammerComponent).put_away()


func _place_board(area: BreachBoardUp, y: float) -> void:
	await _settle_interaction_fixture()
	_interact.detect_target()
	_press(&"interact")
	_check(area.is_placing_board(), "next staged board did not enter the offhand")
	_point_camera(area.breach.to_global(Vector3(0, y, 0)))
	area._update_preview()
	_check(area._preview_valid, "ghost lost the visible aperture at y=%s" % y)
	_press(&"fire")
	await physics_frame
	await physics_frame


func _test_stove() -> void:
	## This suite verifies the current shelter interaction contract only. Detailed
	## lighter behaviour belongs to its dedicated component tests; do not revive
	## the retired SPARK/SPARK/FLAME fixture here.
	var pickup: ItemPickup = _scene.get_node(^"FirewoodShelter") as ItemPickup
	await _aim(pickup, pickup.global_position + Vector3(0, 1, 0.7), pickup.get_focus_point(_player.global_position))
	_press(&"interact")
	_check(_inventory.get_count(&"firewood") == 3, "three logs did not enter the hands")

	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: HeatSource = feed.heat_source
	var stove_visual: StoveVisual = source.get_node(^"StoveVisual") as StoveVisual
	if not feed.is_door_open():
		feed.toggle_door()
	await create_timer(0.4).timeout
	await _aim(feed, source.to_global(Vector3(1.2, 0.9, 0)), feed.focus_anchor.global_position)
	_check_target(feed, "stove with solid hull")
	_check(not source.is_burning(), "opening the stove ignited it")

	## Current grammar: F loads the carried armful. Mouse buttons are not the
	## cold-feed command anymore.
	_press(&"interact")
	_check(feed.is_acting(), "F did not start the current armful stove load")
	if not feed.is_acting():
		return
	await _settle_interaction_fixture()
	_check(not source.is_burning(), "loading cold fuel ignited the stove")
	_check(source.get_recoverable_log_count() == 3, "F did not load the three-log armful")
	_check(_inventory.get_count(&"firewood") == 0, "loaded logs remained in Henry's hands")
	_check(stove_visual.get_visible_log_count() == 3, "loaded cold logs are not visible in the firebox")


func _test_table() -> void:
	var rest: RestSpot = _house.get_node(^"ShelterZone/RestCrate/Sit") as RestSpot
	await _aim(rest, rest.focus_anchor.global_position + _house.global_basis.z * 0.75 + Vector3.UP * 0.5,
		rest.focus_anchor.global_position)
	_check_target(rest, "table ritual entry")
	_press(&"interact")
	var component: RestComponent = _player.get_node(^"RestComponent") as RestComponent
	_check(component.is_sitting(), "F on table did not sit Henry on the seat")
	var table: MealTable = _house.get_node(^"ShelterZone/RestCrate/MealTable") as MealTable
	_check(not table.get_targets().is_empty(), "sitting did not lay carried food on the cloth")
	if table.get_targets().is_empty():
		return
	_camera.global_position = _player.global_position + Vector3.UP * 0.3
	for id: StringName in [&"water_flask_750", &"tinned_pineapple", &"tinned_pineapple_open", &"tinned_stew"]:
		var food: TableFood = null
		for target: TableFood in table.get_targets():
			if target.item_id == id:
				food = target
		_check(food != null, "carried food/water was not presented on the meal table: %s" % id)
		if food == null:
			continue
		_point_camera(food.get_focus_point(_player.global_position))
		await physics_frame
		_interact.detect_target()
		_check_target(food, "seated food with real projection")
		var previous: int = _inventory.get_count(id)
		var eater: ConsumptionController = _player.get_node(^"ConsumptionController") as ConsumptionController
		var calories: float = eater.bio_monitor.current_calories
		_press(&"interact")
		_check(_inventory.get_count(id) == previous - 1, "seated F opened waiting instead of consuming food")
		_check(_interact.current_target == null, "consumed table prop left its obsolete F target active")
		var meal: ItemResource = ItemCatalog.get_item(id)
		var gained: float = meal.consumable.calories if meal.opens_into == &"" else 0.0
		_check(is_equal_approx(eater.bio_monitor.current_calories, minf(eater.bio_monitor.max_calories, calories + gained)),
			"table food did not restore the actual hunger track")
		await physics_frame
		await physics_frame
	_check(_inventory.get_count(&"water_flask_500") == 1 and _inventory.has_item(&"knife"),
		"table drink lost its flask or eating consumed the reusable knife")
	_press(&"move_forward")
	_check(not component.is_sitting() and table.get_laid_ids().is_empty(), "standing left food/seat ritual active")


func _test_drop() -> void:
	_player.global_position = _house.to_global(Vector3(0, 1.95, 0))
	_inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	var held: HeldLightComponent = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	var lit: bool = held.light()
	_check(lit, "drop fixture could not light flare")
	if not lit:
		return
	_player.animation_component.animation_tree.advance(0.3)
	var flare: HeldFlare = _player.animation_component.get_held_prop() as HeldFlare
	_check(flare != null, "lit flare did not reach Henry's hand")
	if flare == null:
		return
	held.drop()
	var body: RigidBody3D = flare.get_parent() as RigidBody3D
	_check(body != null, "dropped flare has no gravity body")
	if body == null:
		return
	var initial: float = body.global_position.y
	for _i: int in range(120):
		await physics_frame
	_check(body.global_position.y < initial - 0.2, "flare stayed hanging at release height")
	var landed: float = _house.to_local(body.global_position).y
	_check(landed > 0.90 and landed < 1.05 and body.linear_velocity.length() < 0.2,
		"flare did not settle on the house floor: y=%.3f velocity=%s" % [landed, body.linear_velocity])
	_check(flare.is_burning(), "physical drop extinguished flare")


func _has_pocket(id: StringName) -> bool:
	for pocket: Dictionary in (_player.get_node(^"EquipmentComponent") as EquipmentComponent).get_available_pockets():
		if pocket["item_id"] == id:
			return true
	return false



## Keeps independent workflow steps independent: finish the previous staged
## presentation/action clip, then rebuild target focus before the next aim.
## This prevents one successful interaction from poisoning every assertion after it.
func _settle_interaction_fixture() -> void:
	## Finish/cancel whatever the previous isolated workflow step owned. Manual
	## actions have no presentation duration, so they must be cancelled explicitly.
	if _actions != null and _actions.is_active():
		var presentation: float = _actions.get_effective_presentation_seconds()
		if presentation > 0.0:
			_actions.advance_presentation(presentation + 0.05)
		if _actions.is_active():
			_actions.cancel(&"test_fixture_reset")
	if is_instance_valid(_player):
		_player._hold_until_ms = 0
		var visual: HenryUALAnimation = _player.animation_component
		if is_instance_valid(visual):
			visual.end_work_pose()
			visual.abort_action()
			visual.update_animation_blend(5.0)
			if visual.animation_tree != null:
				visual.animation_tree.advance(5.0)
	await process_frame
	await physics_frame
	if is_instance_valid(_interact):
		_interact.detect_target()


func _aim(target: InteractiveArea, from: Vector3, point: Vector3) -> void:
	await _settle_interaction_fixture()
	var local: Vector3 = _house.to_local(from)
	if absf(local.x) < 4.0 and absf(local.z) < 5.0:
		from.y = maxf(from.y, _house.to_global(Vector3(0, 1.91, 0)).y)
	_player.global_position = from
	_player.velocity = Vector3.ZERO
	## Henry faces what he walked up to; body facing is part of the target score.
	var flat_point := Vector3(point.x, from.y, point.z)
	if from.distance_to(flat_point) > 0.01:
		_player.look_at(flat_point, Vector3.UP)
	_camera.global_position = from + Vector3.UP * 0.65
	_point_camera(point)
	await physics_frame
	await physics_frame
	_interact.detect_target()


## Lens shift translates the ray origin: looking the camera basis at a prop is insufficient.
func _point_camera(point: Vector3) -> void:
	_camera.look_at(point)
	var center: Vector2 = root.get_visible_rect().size * 0.5
	for _i: int in range(12):
		var from: Vector3 = _camera.project_ray_origin(center)
		var actual: Vector3 = _camera.project_ray_normal(center).normalized()
		var desired: Vector3 = (point - from).normalized()
		_camera.global_basis = Basis(Quaternion(actual, desired)) * _camera.global_basis


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)


func _on_action_started(action_id: StringName, _duration_h: float) -> void:
	if not str(action_id).begins_with("board_window:"):
		return
	var state: Node = root.get_node_or_null(^"PlayerState")
	_board_started_in_working = state != null and int(state.get("mode")) == int(state.Mode.WORKING)


func _check_target(target: InteractiveArea, context: String) -> void:
	_check(_interact.current_target == target and target.prompt_shown,
		"%s selected %s" % [context, _interact.current_target])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("shelter workflow: " + message)


func _click(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = false
	root.push_input(event)

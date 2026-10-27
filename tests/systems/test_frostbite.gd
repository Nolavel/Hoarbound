extends SceneTree

## Frostbite consequences: stages by duration, afflictions and their modifiers, health drain,
## the lighter hold, the sprint, and gloves protecting the hands.
## Run: godot --headless --script tests/systems/test_frostbite.gd

var _failures: int = 0
var _frame: int = 0


## Runs on the first frame: nodes added in _initialize are not ready yet.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run()
	return false


func _run() -> void:
	_test_stages_follow_duration()
	_test_afflictions_and_health()
	_test_gloves()
	_test_old_save_layout()
	if _failures > 0:
		push_error("frostbite: %d check(s) failed" % _failures)
		quit(1)
		return
	print("frostbite: all checks passed")
	quit(0)


func _test_stages_follow_duration() -> void:
	var cold := ExtremityCold.new()
	var hands: BodyPartDefinition = BodyPartLibrary.shared().find(&"hands")
	var hours: float = 0.0
	while cold.get_stage(&"hands") == ExtremityCold.FrostStage.NONE and hours < 3.0:
		cold.advance(0.05, -32.0, 0.0, {})
		hours += 0.05
	_check(cold.get_stage(&"hands") == ExtremityCold.FrostStage.FROSTNIP, "bare hands at -32 °C never got frostnip")
	_check(hours > hands.frostnip_hours, "frostnip came before the load had been held: %.2f h" % hours)
	while cold.get_stage(&"hands") != ExtremityCold.FrostStage.FROSTBITE and hours < 4.0:
		cold.advance(0.05, -32.0, 0.0, {})
		hours += 0.05
	_check(cold.get_stage(&"hands") == ExtremityCold.FrostStage.FROSTBITE, "hands never reached frostbite")
	_check(hours < 2.0, "frostbite took implausibly long at -32 °C: %.2f h" % hours)
	var brief := ExtremityCold.new()
	brief.advance(0.1, -32.0, 0.0, {})
	_check(brief.get_stage(&"hands") == ExtremityCold.FrostStage.NONE, "a brief chill already numbed the hands")
	for _i: int in range(20):
		cold.advance(0.1, 15.0, 0.0, {})
	_check(cold.get_stage(&"hands") == ExtremityCold.FrostStage.FROSTBITE, "frostbite healed in two warm hours")
	for _i: int in range(80):
		cold.advance(0.1, 15.0, 0.0, {})
	_check(cold.get_stage(&"hands") == ExtremityCold.FrostStage.NONE, "frostbite never healed in warmth")
	_check(ExtremityCold.new().reset().is_empty(), "resetting a clean model reported changes")


func _test_afflictions_and_health() -> void:
	var player := CharacterBody3D.new()
	player.name = "Player"
	var health := PlayerHealthSystem.new()
	health.name = "PlayerHealthSystem"
	player.add_child(health)
	var aff := AfflictionComponent.new()
	aff.name = "AfflictionComponent"
	player.add_child(aff)
	var movement := MovementController.new()
	movement.name = "MovementController"
	player.add_child(movement)
	root.add_child(player)
	var thermal := ThermalManager.new()
	thermal.ambient_min_c = -32.0
	thermal.ambient_max_c = -32.0
	root.add_child(thermal)
	aff.bind_thermal(thermal)
	for _i: int in range(40):
		thermal._advance_hours(0.05, 3.0)
	_check(thermal.get_frost_stage(&"hands") == ExtremityCold.FrostStage.FROSTBITE, "two hours at -32 °C did not frostbite bare hands")
	_check(aff.has_affliction(&"frostbite_hands") and not aff.has_affliction(&"frostnip_hands"), "afflictions do not mirror the hand stage")
	_check(aff.has_affliction(&"frostbite_feet") or aff.has_affliction(&"frostnip_feet"), "bare feet at -32 °C took no frost at all")
	_check(StatusModifierCapability.multiplier(player, &"fine_motor_duration_multiplier") > 1.5, "frostbitten hands did not slow fine work")
	if aff.has_affliction(&"frostbite_feet"):
		_check(movement.get_status_sprint_multiplier() == 0.0, "frostbitten feet still allow a sprint")
	var feed := HeatSourceFeed.new()
	feed._player = player
	_check(feed.get_light_seconds() > HeatSourceFeed.LIGHT_SECONDS * 1.5, "the lighter hold ignores numb hands: %.2f s" % feed.get_light_seconds())
	feed.free()
	var before: float = health.current_health
	aff.advance_simulation(1.0, null)
	_check(health.current_health < before - 1.0, "an hour of frostbite cost no health (%.1f -> %.1f)" % [before, health.current_health])
	thermal.restore_body_temperature()
	_check(not aff.has_affliction(&"frostbite_hands"), "warm sleep left frostbite active")
	_check(is_equal_approx(StatusModifierCapability.multiplier(player, &"fine_motor_duration_multiplier"), 1.0), "recovered hands still slow")
	thermal.free()
	player.free()


func _test_gloves() -> void:
	var gloves: ItemResource = ItemCatalog.get_item(&"work_gloves")
	_check(gloves != null and gloves.garment != null and gloves.garment.body_region == &"hands", "work gloves are not a hand garment")
	var bare := ExtremityCold.new()
	var gloved := ExtremityCold.new()
	var cover: Dictionary = {&"hands": {"insulation_c": gloves.garment.get_base_insulation_c(), "windproof": gloves.garment.windproof}}
	for _i: int in range(16):
		bare.advance(0.1, -20.0, 10.0, {})
		gloved.advance(0.1, -20.0, 10.0, cover)
	_check(gloved.get_load(&"hands") < bare.get_load(&"hands") - 0.2, "gloves barely protect the hands (%.2f vs %.2f)" % [gloved.get_load(&"hands"), bare.get_load(&"hands")])
	var equipment := EquipmentComponent.new()
	equipment.layout = load("res://data/equipment/player_layout.tres") as EquipmentLayout
	root.add_child(equipment)
	_check(equipment.equip(&"hands_outer", &"work_gloves") == EquipmentComponent.Refusal.NONE, "gloves cannot be worn")
	_check(float(equipment.get_region_protection(&"hands").get("insulation_c", 0.0)) > 3.0, "worn gloves add no hand cover")
	equipment.free()
	var outfit: Node = (load("res://assets/characters/henry/henry_outfit.glb") as PackedScene).instantiate()
	_check(outfit.find_child("Outfit_Gloves", true, false) is MeshInstance3D, "Henry's outfit has no glove mesh")
	_check(outfit.find_child("Skin_Gloves", true, false) != null, "no skin split under the gloves")
	_check(HenryUALAnimation.GARMENT_PARTS.has(gloves.garment.mesh_node_name), "the gloves' mesh name maps to no outfit part")
	outfit.free()


func _test_old_save_layout() -> void:
	var cold := ExtremityCold.new()
	cold.load_save_data({"hands": 0.4})
	_check(is_equal_approx(cold.get_load(&"hands"), 0.4) and cold.get_stage(&"hands") == ExtremityCold.FrostStage.NONE, "the first save layout no longer loads")
	var staged := ExtremityCold.new()
	staged.load_save_data({"feet": {"load": 0.9, "stage": ExtremityCold.FrostStage.FROSTBITE}})
	_check(staged.get_stage(&"feet") == ExtremityCold.FrostStage.FROSTBITE, "a saved frostbite stage was lost")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("frostbite: %s" % message)

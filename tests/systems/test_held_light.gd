extends SceneTree

## Held flare: Quick Access shows it unlit in the shared hand socket while its pocket
## keeps it; Use lights it (out of storage), Use again drops it, burn-out drops it too.
## Run: godot --headless --script tests/systems/test_held_light.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
const BODY_SOURCE: String = """extends CharacterBody3D
var animation_component: HenryUALAnimation
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / 2.2, 0.0, 1.0)
func get_crouch_speed_ratio() -> float:
	return 0.0
func is_crouching() -> bool:
	return false
func get_view_direction() -> Vector3:
	return Vector3.FORWARD
"""

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _visual: HenryUALAnimation
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _light: HeldLightComponent
var _pocket_path: StringName
var _spent_flare: HeldFlare


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_check(not _light.light(), "a flare lit with none carried")
			_check(_equipment.stow_anywhere(&"road_flare") == EquipmentComponent.Refusal.NONE,
				"test flare would not enter a Quick Access pocket")
			_pocket_path = _flare_pocket_path()
			_check(_pocket_path != &"", "could not locate the flare pocket")
			_check(_light.equip_from_zone(&"road_flare", _pocket_path), "slot key could not draw the flare")
			var flare := _visual.get_held_prop() as HeldFlare
			_check(flare != null, "drawn flare is not in Henry's hand")
			_check(flare != null and not flare.is_burning(), "drawn flare ignited before Use")
			var core := flare.get_node_or_null(^"Tip/HotCore") as MeshInstance3D if flare != null else null
			var light := flare.get_node_or_null(^"Tip/FlareLight") as OmniLight3D if flare != null else null
			_check(core != null and not core.visible, "unlit flare shows the hot core")
			_check(light != null and not light.visible, "unlit flare already casts light")
			_check(flare != null and flare.get_parent() == _visual.get_hand_socket(), "flare is not on the shared hand socket")
			_check(_visual.get_hand_socket().bone_name == &"hand_l", "hand socket is not on the Idle_Torch hand")
			_check(_equipment_item(_pocket_path) == &"road_flare", "the drawn unlit flare left its pocket")
		10:
			_visual.update_animation_blend(0.5)
			_visual.animation_tree.advance(0.5)
			_check_nozzle_direction("standing")
			_body.velocity.z = -1.2
			_visual.update_animation_blend(0.5)
			_visual.animation_tree.advance(0.5)
			_check_nozzle_direction("walking")
			_body.velocity = Vector3.ZERO
			_check(float(_visual.animation_tree.get("parameters/hold_pose/blend_amount")) > 0.9,
				"the arm did not rise into the held pose")
			_check(_light.use_held(), "Use did not ignite the drawn flare")
			var flare := _visual.get_held_prop() as HeldFlare
			_check(flare != null and flare.is_burning(), "Use left the flare unlit")
			var core := flare.get_node_or_null(^"Tip/HotCore") as MeshInstance3D if flare != null else null
			var light := flare.get_node_or_null(^"Tip/FlareLight") as OmniLight3D if flare != null else null
			_check(core != null and core.visible, "ignition did not reveal the hot core")
			_check(light != null and light.visible and light.light_energy > 0.0, "ignition did not enable flare light")
			_check(_light.get_source_zone() == &"", "lit flare still claims a pocket owner")
			_check(_equipment_item(_pocket_path) == &"", "the lit flare is still stored in its pocket")
			_check(_light.use_held(), "second Use did not drop the burning flare")
			_check(not _light.is_holding() and _visual.get_held_prop() == null, "dropping left the flare in hand")
		11:
			_visual.update_animation_blend(0.5)
			_check(float(_visual.animation_tree.get("parameters/hold_pose/blend_amount")) < 0.1,
				"the arm stayed raised after the drop")
			var dropped: Array[Node] = root.find_children("*", "HeldFlare", true, false)
			_check(dropped.size() == 1 and (dropped[0] as HeldFlare).is_burning(),
				"the dropped flare is not burning on the ground")
			_test_unlit_put_away()
			_test_spent_while_held()
		12:
			_check(is_instance_valid(_spent_flare) and _spent_flare.is_spent(), "the spent flare did not burn out")
			_check(not _light.is_holding() and _visual.get_held_prop() == null, "the spent flare stayed in hand")
			_check(is_instance_valid(_spent_flare) and _spent_flare.get_parent() is RigidBody3D,
				"the spent flare did not fall into the world as itself")
			_finish()
	return false


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	_check(script.reload() == OK, "test body script did not compile")
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_equipment = EquipmentComponent.new()
	_equipment.name = "EquipmentComponent"
	_equipment.layout = load("res://data/equipment/player_layout.tres") as EquipmentLayout
	_equipment.starter_garment_ids = [&"worn_coat"]
	_body.add_child(_equipment)
	_inventory = InventoryComponent.new()
	_inventory.equipment = _equipment
	_body.add_child(_inventory)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	## Match the real player's model orientation, rather than the source GLB facing.
	_visual.rotation.y = PI
	_body.add_child(_visual)
	_body.set(&"animation_component", _visual)
	_light = HeldLightComponent.new()
	_light.inventory = _inventory
	_body.add_child(_light)
	root.add_child(_body)


func _check_nozzle_direction(context: String) -> void:
	var flare: Node3D = _visual.get_held_prop()
	var nozzle: Vector3 = (_body.global_basis.inverse() * flare.global_basis.y).normalized()
	_check(nozzle.y > 0.1 and nozzle.dot((Vector3.LEFT + Vector3.FORWARD).normalized()) > 0.6,
		"%s flare points towards Henry's legs/body: %s" % [context, nozzle])


func _test_unlit_put_away() -> void:
	_check(_equipment.stow_anywhere(&"road_flare") == EquipmentComponent.Refusal.NONE,
		"second flare would not enter a pocket")
	var path := _flare_pocket_path()
	_check(_light.equip_from_zone(&"road_flare", path), "second flare would not draw unlit")
	_check(_light.put_away_unlit(), "unlit flare would not return to storage")
	_check(_equipment_item(path) == &"road_flare" or _inventory.has_item(&"road_flare"),
		"put-away flare was lost instead of returning to carried storage")


func _test_spent_while_held() -> void:
	_check(_equipment.stow_anywhere(&"road_flare") == EquipmentComponent.Refusal.NONE,
		"spent-test flare would not enter a pocket")
	var path := _flare_pocket_path()
	_check(path != &"", "spent-test flare pocket could not be found")
	_check(_light.equip_from_zone(&"road_flare", path), "spent-test flare would not draw")
	_check(_light.use_held(), "spent-test flare would not ignite")
	_spent_flare = _visual.get_held_prop() as HeldFlare
	_check(_spent_flare != null, "spent-test flare is not in the hand")
	if _spent_flare == null:
		return
	## Run the real burn-out: the next frame's _process reaches the end of the burn.
	_spent_flare.burn_duration_s = 0.001


func _flare_pocket_path() -> StringName:
	for pocket: Dictionary in _equipment.get_available_pockets():
		if pocket["item_id"] == &"road_flare":
			return _equipment.pocket_path(pocket["body_slot"], pocket["pocket"])
	return &""


func _equipment_item(path: StringName) -> StringName:
	var parts: PackedStringArray = String(path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2:
		return &""
	return _equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1]))


func _finish() -> void:
	if _failures > 0:
		push_error("held light: %d check(s) failed" % _failures)
		quit(1)
		return
	print("held light: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held light: %s" % message)

class_name ItemPickup
extends InteractiveArea

## An item lying in the world. Ordinary items stow in the pack; two-hand loads
## stay visibly in Henry's arms. Refused pickups stay where they are.

## Emitted after the item went into the pack.
signal picked_up(item_id: StringName, count: int)
## Emitted when the pack refused it, carrying the item id.
signal pickup_refused(item_id: StringName)

## Stand-in shape and colour for items that have no mesh of their own yet.
const PLACEHOLDER_SIZE: Vector3 = Vector3(0.32, 0.16, 0.22)
const PLACEHOLDER_COLOR: Color = Color(0.42, 0.3, 0.2)
const ROAD_FLARE_ID: StringName = &"road_flare"
const HAMMER_ID: StringName = &"hammer"
const NAILS_ID: StringName = &"nails"
const TOO_HEAVY_KEY: String = "PICKUP_REFUSED_TOO_HEAVY"
const WORLD_GROUP: StringName = &"world_pickup"

@export_group("Item")
## Catalog id of what lies here.
@export var item_id: StringName = &""
## How many of it, picked up together.
@export_range(1, 99) var count: int = 1
## Stable id of an authored pickup (from the world layout); a taken one is saved
## in the PickupLedger and does not come back on reload. Empty for dropped items.
@export var world_id: StringName = &""

var _inventory: InventoryComponent


func _ready() -> void:
	## The base class sizes its highlight ring from a mesh; without one a pickup
	## is invisible and unhighlighted, so a placeholder crate stands in.
	if interactive_mesh == null:
		interactive_mesh = _make_placeholder()
	interaction_type = InteractionType.PICKUP
	object_on_ground = false
	auto_detect_ground = false
	if world_id != &"":
		add_to_group(WORLD_GROUP)
	super()
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item != null:
		var label: String = tr(item.display_name) if count == 1 else "%s ×%d" % [tr(item.display_name), count]
		set_item_name(label)
	var status: String = item.get_status_text() if item != null else ""
	set_description("%s · %s" % [item_name, status] if status != "" else "")


func get_interaction_channel() -> InteractionChannel:
	return InteractionChannel.PICKUP


func can_interact() -> bool:
	var work: WoodWorkComponent = _wood_work()
	return super() and ItemCatalog.get_item(item_id) != null and (work == null or not work.is_chopping(self))


## Adds every unit or none: a half-taken stack would leave the world lying.
func pick_up() -> bool:
	if is_queued_for_deletion():
		return false
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var inventory: InventoryComponent = _get_inventory()
	if item == null or inventory == null:
		pickup_refused.emit(item_id)
		return false
	if item.carried_in_hands and not _free_safe_held_item():
		pickup_refused.emit(item_id)
		show_message(tr("PICKUP_REFUSED_HANDS_OCCUPIED"))
		return false
	var refusal: StringName = inventory.get_add_refusal(item, count)
	if refusal != &"":
		pickup_refused.emit(item_id)
		show_message(tr(_refusal_key(refusal)))
		return false
	for i: int in range(count):
		inventory.try_add(item)
	var ledger: PickupLedger = PickupLedger.find(get_tree()) if is_inside_tree() else null
	if ledger != null:
		ledger.record(world_id)
	picked_up.emit(item_id, count)
	if not item.carried_in_hands:  # armfuls go to the hands, not the pack
		_hand_visual_to_pack()
	queue_free()
	return true


func _on_interaction_performed() -> void:
	var work: WoodWorkComponent = _wood_work()
	if item_id == &"boards" and work != null and work.axe_is_held():
		work.begin_chop(self)
		return
	if not pick_up():
		return
	## Ownership is settled now; camera movement during the clip cannot undo it.
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"play_action_animation"):
		var action: StringName = player_animation_action if player_animation_action != &"" else &"pickup"
		player.call(&"play_action_animation", action)


func _get_interaction_text() -> String:
	var work: WoodWorkComponent = _wood_work()
	if item_id == &"boards" and work != null and work.axe_is_held():
		player_animation_action = &"none"
		set_description(tr("WOOD_CHOP_DETAIL") % count)
		return "[%s] %s" % [_interact_key_label(), tr("WOOD_CHOP_ACTION")]
	if item_id == &"boards" and description != "":
		set_description("")
	player_animation_action = &""
	return super()


func _wood_work() -> WoodWorkComponent:
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	return player.get_node_or_null(^"WoodWorkComponent") as WoodWorkComponent if player != null else null


static func _refusal_key(reason: StringName) -> String:
	match reason:
		&"hands_full":
			return "PICKUP_REFUSED_HANDS_FULL"
		&"hands_occupied":
			return "PICKUP_REFUSED_HANDS_OCCUPIED"
		_:
			return TOO_HEAVY_KEY


## Passes the item's mesh to the player's Hub, which flies it into the pack.
func _hand_visual_to_pack() -> void:
	var visual := interactive_mesh as Node3D
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var hub: PlayerHubComponent = player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null
	if hub == null or visual == null or not is_ancestor_of(visual):
		return
	visual.reparent(get_tree().current_scene if get_tree().current_scene != null else get_tree().root)
	hub.stow_visual(visual, item_id)


## A small crate until items have their own meshes.
func _make_placeholder() -> MeshInstance3D:
	if String(item_id).begins_with("water_flask") or String(item_id).begins_with("tinned_pineapple") or item_id in [&"knife", &"axe", &"tinned_stew"]:
		var holder: Node3D = SurvivalItemVisual.make(item_id)
		if item_id == &"axe":
			holder.rotation.x = PI * 0.5
		add_child(holder)
		return holder.get_child(0) as MeshInstance3D
	if item_id == ROAD_FLARE_ID:
		return _make_road_flare()
	if item_id == HAMMER_ID:
		return _make_hammer()
	if item_id == NAILS_ID:
		return _make_nails()
	if item_id == &"boards" or item_id == &"firewood":
		return _make_wood_stack()
	if item_id == &"lighter":
		return _box_prop("Lighter", Vector3(0.045, 0.085, 0.025), Vector3(0, 0.045, 0), Color(0.9, 0.5, 0.08))
	var crate := MeshInstance3D.new()
	crate.name = "Placeholder"
	var box := BoxMesh.new()
	box.size = PLACEHOLDER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = PLACEHOLDER_COLOR
	box.material = material
	crate.mesh = box
	crate.position.y = PLACEHOLDER_SIZE.y * 0.5
	add_child(crate)
	return crate


## The starting light must read as a flare, not as the generic brown loot box.
## It matches the unlit tube dimensions used by HeldFlare and lies in the snow.
func _make_road_flare() -> MeshInstance3D:
	var tube := MeshInstance3D.new()
	tube.name = "RoadFlareVisual"
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.014
	tube_mesh.bottom_radius = 0.016
	tube_mesh.height = 0.22
	tube_mesh.radial_segments = 12
	tube.mesh = tube_mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.19, 0.035, 0.026, 1.0)
	body_material.metallic = 0.18
	body_material.roughness = 0.58
	tube.material_override = body_material
	tube.rotation.z = PI * 0.5
	tube.position.y = 0.02
	add_child(tube)

	var cap := MeshInstance3D.new()
	cap.name = "StrikerCap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.018
	cap_mesh.bottom_radius = 0.018
	cap_mesh.height = 0.025
	cap_mesh.radial_segments = 12
	cap.mesh = cap_mesh
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.055, 0.045, 0.04, 1.0)
	cap_material.roughness = 0.9
	cap.material_override = cap_material
	cap.position.y = 0.122
	tube.add_child(cap)
	return tube


func _make_hammer() -> MeshInstance3D:
	var handle := MeshInstance3D.new()
	handle.name = "HammerVisual"
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.035, 0.30, 0.035)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.26, 0.16, 0.08)
	handle_mesh.material = wood
	handle.mesh = handle_mesh
	handle.position = Vector3(0.0, 0.04, 0.0)
	handle.rotation.x = PI * 0.5
	add_child(handle)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.065, 0.065)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.25)
	metal.metallic = 0.7
	head_mesh.material = metal
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.16, 0.0)
	handle.add_child(head)
	return handle


## One pickup represents a box of thirty nails; three visible nails are enough
## to communicate what it is without drawing thirty tiny meshes.
func _make_nails() -> MeshInstance3D:
	var box := _box_prop("NailBox", Vector3(0.24, 0.065, 0.18), Vector3(0, 0.035, 0), Color(0.70, 0.51, 0.24))
	var first := MeshInstance3D.new()
	first.name = "NailsVisual"
	var nail_mesh := CylinderMesh.new()
	nail_mesh.top_radius = 0.005
	nail_mesh.bottom_radius = 0.005
	nail_mesh.height = 0.12
	nail_mesh.radial_segments = 7
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.36, 0.38, 0.40)
	metal.metallic = 0.8
	nail_mesh.material = metal
	first.mesh = nail_mesh
	first.rotation.z = PI * 0.5
	first.position = Vector3(-0.04, 0.025, 0.0)
	add_child(first)
	for offset: Vector3 in [Vector3(0.04, 0.026, 0.025), Vector3(0.0, 0.027, -0.035)]:
		var nail := MeshInstance3D.new()
		nail.mesh = nail_mesh
		nail.rotation.z = PI * 0.5
		nail.position = offset
		first.add_child(nail)
	first.reparent(box)
	first.position = Vector3(-0.04, 0.04, 0.0)
	return box


func _box_prop(prop_name: String, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var prop := MeshInstance3D.new()
	prop.name = prop_name
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	mesh.material = material
	prop.mesh = mesh
	prop.position = at
	add_child(prop)
	return prop


## Full-size loose planks and bark-covered logs communicate the carried load.
func _make_wood_stack() -> MeshInstance3D:
	var first: MeshInstance3D
	for i: int in range(count):
		var prop: MeshInstance3D
		if item_id == &"boards":
			prop = _box_prop("Plank%d" % i, Vector3(1.7, 0.065, 0.24),
				Vector3(0.04 * (i % 2), 0.04 + i * 0.07, 0), Color(0.56, 0.39, 0.22))
		else:
			prop = MeshInstance3D.new()
			prop.name = "Log%d" % i
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.075
			cylinder.bottom_radius = 0.085
			cylinder.height = 0.65
			var bark := StandardMaterial3D.new()
			bark.albedo_color = Color(0.30, 0.18, 0.09)
			cylinder.material = bark
			prop.mesh = cylinder
			prop.rotation.z = PI * 0.5
			prop.position = Vector3(0, 0.085 + (i / 2) * 0.14, (i % 2) * 0.17)
			add_child(prop)
			var cut := MeshInstance3D.new()
			var end := CylinderMesh.new()
			end.top_radius = 0.07
			end.bottom_radius = 0.07
			end.height = 0.004
			var grain := StandardMaterial3D.new()
			grain.albedo_color = Color(0.72, 0.53, 0.30)
			end.material = grain
			cut.mesh = end
			cut.position.y = 0.327
			prop.add_child(cut)
		if first == null:
			first = prop
	return first


func _free_safe_held_item() -> bool:
	if not is_inside_tree():
		return true
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null:
		return true
	for child: Node in player.get_children():
		if child.has_method(&"is_burning") and bool(child.call(&"is_burning")):
			return false
		if not child.has_method(&"is_holding") or not bool(child.call(&"is_holding")):
			continue
		if child.has_method(&"put_away_unlit") and bool(child.call(&"put_away_unlit")):
			continue
		if child.has_method(&"put_away") and bool(child.call(&"put_away")):
			continue
		return false
	return true


func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	if not is_inside_tree():
		return null
	_inventory = InventoryComponent.find_in(get_tree().get_first_node_in_group("player"))
	return _inventory

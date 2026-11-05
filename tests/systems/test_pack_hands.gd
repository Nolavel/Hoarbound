extends SceneTree

## Hands in the held pack (3D inventory) on the real player and Hub. Tab takes the pack into Henry's hands,
## half full of SPoV tins, a tin in the left coat pocket. The ring and LMB:
## - over the tin it shows its readout (name, weight); the load bar shows what Henry carries;
## - carry the tin from the coat pocket's card into the pack (it goes under the straps, the pocket empties);
## - take a tin out of the pack onto the empty card (into that pocket);
## - a full pocket refuses the axe (its reason shows, the axe stays in its sleeve);
## - the pack refuses the axe as too big;
## - the tin let go on the hand card becomes the pick (what Henry takes in hand);
## - RMB opens the tin in its pocket (the pack stays open), RMB on the open tin closes the pack to eat;
## - G puts a pack tin down on the ground.
## Eating closes the pack (Henry needs his hands).
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_pack_hands.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _failures: int = 0
var _player: Player
var _hub: PlayerHubComponent
var _inventory: InventoryComponent
var _hands: PackHandling


func _initialize() -> void:
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	await _frames(30)
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	for entry: Dictionary in _inventory.get_entries():
		if entry["id"] != &"bedroll":
			for _n: int in int(entry["count"]):
				_inventory.take_instance(entry["id"])
	var tin: ItemResource = ItemCatalog.get_item(&"spov_can")
	for _n: int in 5:
		_inventory.try_add(tin)
	var coat_left: StringName = _zone_path(&"coat_left")
	var parts: PackedStringArray = String(coat_left).split(EquipmentComponent.POCKET_SEPARATOR)
	equipment.stow(StringName(parts[0]), StringName(parts[1]), &"spov_can")
	_check(_hub.open(), "Tab did not open the pack")
	await _frames(40)
	_hands = _hub.get_pack_hands()
	_check(_hands != null, "no hands in the held pack")
	if _hands == null:
		_finish()
		return
	var shelf: PackQuickShelf = _hub.get_quick_shelf()
	var straps: PackStraps = _hands.straps
	var left_card: int = _slot(shelf, coat_left)
	var sleeve_card: int = _slot_with(shelf, &"axe")
	print("pack hands: %d items in the pack, %d cards" % [straps.items.size(), shelf.slots.size()])

	## The tin from the coat pocket's card into the pack; what hangs outside keeps its node (no rebuild, no flicker).
	var strapped: int = straps.items.size()
	var thermos_before: Node3D = _hub.pack.get_pocket_visual(&"pack_side_left")
	await _aim(_card_screen(shelf, left_card))
	_check(_hands.hovered_slot == left_card, "the ring over the coat pocket's card does not hover it")
	var tin_kg: float = ItemCatalog.get_item(&"spov_can").weight
	_check(String(_hands.cursor.info.get("name", "")) != "" and is_equal_approx(float(_hands.cursor.info.get("kg", -1.0)), tin_kg),
		"the hovered tin shows no readout (name and weight)")
	_check(is_equal_approx(_hands.cursor.load_kg, _inventory.get_total_weight()) and _hands.cursor.load_max_kg > 0.0,
		"the load bar does not show what Henry carries")
	await _grab()
	await _glide(_pack_screen(straps))
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(20)
	_check(_inventory.get_count(&"spov_can") == 6 and StringName(shelf.slots[left_card]["item_id"]) == &"",
		"the tin did not go from the coat pocket into the pack")
	_check(straps.items.size() == strapped + 1, "the straps do not hold the tin (%d, had %d)" % [straps.items.size(), strapped])
	_check(thermos_before == null or thermos_before == _hub.pack.get_pocket_visual(&"pack_side_left"),
		"putting a tin in rebuilt the thermos outside (it would flicker)")
	print("pack hands: coat pocket -> pack, %d under the straps" % straps.items.size())

	## A tin out of the pack onto the empty coat pocket's card.
	await _aim(_item_screen(straps, 0))
	_check(_hands.hovered_item >= 0, "the ring over a strapped tin does not hover it")
	## Taking costs time: cold hands take longer, and LMB let go too soon takes nothing.
	_hands.hands_cold = 0.0
	var warm_s: float = _hands.take_seconds()
	_hands.hands_cold = 1.0
	var cold_s: float = _hands.take_seconds()
	_check(warm_s > 0.1 and cold_s > warm_s * 2.0, "cold hands do not take longer (warm %.2f s, cold %.2f s)" % [warm_s, cold_s])
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _frames(1)
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(3)
	_check(not _hands.is_carrying() and not _hands.is_taking() and straps.items.size() == strapped + 1, "LMB let go at once still took the tin")
	print("pack hands: a take lasts %.2f s warm, %.2f s with frozen hands; let go early takes nothing" % [warm_s, cold_s])
	await _grab()
	await _glide(_card_screen(shelf, left_card))
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(20)
	_check(StringName(shelf.slots[left_card]["item_id"]) == &"spov_can" and _inventory.get_count(&"spov_can") == 5,
		"the tin did not go from the pack into the coat pocket")
	print("pack hands: pack -> coat pocket")

	## The full coat pocket refuses the axe; it stays in its sleeve.
	if sleeve_card >= 0:
		await _aim(_card_screen(shelf, sleeve_card))
		await _grab()
		await _glide(_card_screen(shelf, left_card))
		_check(shelf.slots[left_card]["tint"] == PackQuickShelf.REFUSE, "the full coat pocket does not show it would refuse")
		_hands.press(PackHandling.GRAB_ACTION, false)
		await _frames(5)
		_check(StringName(shelf.slots[sleeve_card]["item_id"]) == &"axe", "the refused axe left its sleeve")
		_check(_hands.cursor.warning == tr(PackQuickShelf.FULL), "the full pocket showed no reason")
		## The pack refuses it as too big.
		await _aim(_card_screen(shelf, sleeve_card))
		await _grab()
		await _glide(_pack_screen(straps))
		_hands.press(PackHandling.GRAB_ACTION, false)
		await _frames(5)
		_check(StringName(shelf.slots[sleeve_card]["item_id"]) == &"axe", "the axe went into the pack")
		_check(_hands.cursor.warning == tr(PackStraps.TOO_BIG), "the pack showed no reason for the axe")
		print("pack hands: the axe was refused by a full pocket and by the pack")
	else:
		_check(false, "no sleeve card holds the axe")

	## The tin let go on the hand card becomes what Henry takes in hand; it stays in its pocket.
	await _aim(_card_screen(shelf, left_card))
	await _grab()
	await _glide(_hands.camera.unproject_position(shelf.hand_card.global_position))
	_check(_hands.hovered_hand, "the ring over the hand card does not hover it")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(5)
	_check(shelf.selected == left_card and StringName(shelf.slots[left_card]["item_id"]) == &"spov_can", "the hand card did not make the coat pocket the pick")
	_check(shelf.hand_visual() != null, "the hand card shows nothing")
	print("pack hands: the coat pocket's tin is the pick on the hand card")

	## RMB on the tin in the coat pocket opens it where it lies (the pack stays open).
	_check(_hands.use_verb(&"spov_can") == &"INVENTORY_HINT_OPEN", "a sealed tin offers no Open")
	await _aim(_card_screen(shelf, left_card))
	_hands.press(PackHandling.USE_ACTION, true)
	await _frames(5)
	var opened: StringName = shelf.slots[left_card]["item_id"]
	_check(opened == ItemCatalog.get_item(&"spov_can").opens_into and _hub.is_open(), "RMB did not open the tin in its pocket (now %s)" % opened)
	print("pack hands: RMB opened the tin in the coat pocket")

	## G puts a pack tin down on the ground.
	var before: int = _inventory.get_count(&"spov_can")
	await _aim(_item_screen(straps, 0))
	_hands.press(PackHandling.DROP_ACTION, true)
	await _frames(5)
	var pickups: Array = root.find_children("*", "ItemPickup", true, false)
	_check(_inventory.get_count(&"spov_can") == before - 1 and not pickups.is_empty(), "G did not put a tin down on the ground")
	print("pack hands: G put a tin down")

	## Eating the open tin needs Henry's hands: the pack closes and he eats.
	await _aim(_card_screen(shelf, left_card))
	_check(_hands.use_verb(StringName(shelf.slots[left_card]["item_id"])) == &"INVENTORY_HINT_EAT", "the open tin offers no Eat")
	_hands.press(PackHandling.USE_ACTION, true)
	await _frames(40)
	_check(not _hub.is_open() and _hub.get_pack_hands() == null, "eating did not close the pack")
	print("pack hands: RMB on the open tin closed the pack to eat")

	## Pad: a flick steps the ring to the next target that way; from the coat pocket's card rightward it lands on
	## something else (not off into nothing), and back leftward returns near where it was.
	_check(_hub.open(), "the pack did not open for the pad check")
	await _frames(45)
	_hands = _hub.get_pack_hands()
	shelf = _hub.get_quick_shelf()
	var start: Vector2 = shelf.aim_point(0)
	_hands.set_cursor(start)
	var targets: int = _hands.snap_targets().size()
	_check(targets >= 4, "too few pad targets (%d)" % targets)
	var moved_up: bool = _hands.snap(Vector2.UP)
	await _frames(3)
	_check(moved_up and _hands.cursor_at.y < start.y and (_hands.hovered_item >= 0 or _hands.hovered_slot >= 0 or _hands.hovered_hand),
		"a flick up from a card did not land on an item or a card")
	_hub.close()
	await _frames(40)
	print("pack hands: the pad steps the ring between %d targets" % targets)

	## Small things in numbers lie in as one bundle per stack, and the readout says how many.
	var strapped_before: int = _hub.pack.get_straps().items.size()
	for _n: int in 20:
		_inventory.try_add(ItemCatalog.get_item(&"nails"))
	await _frames(5)
	_check(_hub.pack.get_straps().items.filter(func(item: Dictionary) -> bool: return item["id"] == &"nails").size() == 1,
		"20 nails took more than one place under the straps")
	_check(ItemReadout.describe(&"nails", 20)["name"].ends_with("20"), "the nails' readout does not say how many")
	print("pack hands: 20 nails lie in as one bundle (%d -> %d places)" % [strapped_before, _hub.pack.get_straps().items.size()])

	## A threat shuts the open pack (time never stops in the Hub); frostbite's slow loss does not.
	var health := _hub.get_parent().get_node(^"PlayerHealthSystem") as PlayerHealthSystem
	_check(_hub.open(), "the pack did not open again")
	await _frames(45)
	health.drain(1.0, "frostbite")
	await _frames(2)
	_check(_hub.is_open(), "frostbite's slow loss shut the pack")
	health.take_damage(5.0, "test")
	await _frames(2)
	_check(not _hub.is_open(), "a blow did not shut the pack")
	print("pack hands: a blow shuts the open pack, frostbite does not")
	_finish()


func _finish() -> void:
	print("pack hands: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _zone_path(pocket: StringName) -> StringName:
	for zone: Dictionary in _hub.get_quick_access_zones():
		if String(zone["path"]).ends_with(String(pocket)):
			return zone["path"]
	return &""


func _slot(shelf: PackQuickShelf, path: StringName) -> int:
	for k: int in shelf.slots.size():
		if shelf.slots[k]["path"] == path:
			return k
	return -1


func _slot_with(shelf: PackQuickShelf, item_id: StringName) -> int:
	for k: int in shelf.slots.size():
		if shelf.slots[k]["item_id"] == item_id:
			return k
	return -1


func _card_screen(shelf: PackQuickShelf, k: int) -> Vector2:
	return shelf.aim_point(k)


func _item_screen(straps: PackStraps, i: int) -> Vector2:
	return _hands.camera.unproject_position(straps.model.global_transform * (straps.items[i]["box"] as AABB).get_center())


func _pack_screen(straps: PackStraps) -> Vector2:
	return _hands.camera.unproject_position(straps.model.global_transform * PackStraps.room().get_center())


## LMB held until the hand has taken the item (a take costs time, PackHandling.take_seconds).
func _grab() -> void:
	_hands.press(PackHandling.GRAB_ACTION, true)
	for _i: int in 90:
		if not _hands.is_taking():
			break
		await _frames(1)


func _aim(at: Vector2) -> void:
	_hands.set_cursor(at)
	await _frames(3)


func _glide(to: Vector2) -> void:
	var from: Vector2 = _hands.cursor_at
	for f: int in 12:
		_hands.set_cursor(from.lerp(to, float(f + 1) / 12.0))
		await _frames(1)


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pack hands: %s" % message)

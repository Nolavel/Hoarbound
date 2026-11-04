extends SceneTree

## Quick Access while the pack is open (3D inventory, stage 2). The pack hangs open with the axe, pan and hammer
## in it, beside it the quick pockets' cards: coat, thigh and lid on the left, side pocket, sleeves and
## carabiners on the right, with the SPoV tin, thermos and mug in some of them. Checks:
## - The ring over a filled card makes it active.
## - LMB carries its item into the pack.
## - A pack item dragged onto an empty card moves into that pocket.
## - A full pocket refuses, and the item goes back.
## - G throws a card's item out.
## Nothing comes through the cloth.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/systems/test_pack_shelf.gd

const PACK_AT: Vector3 = Vector3(0.0, 0.9, 0.0)
const BODY: Array = [[&"worn_coat", &"coat_left"], [&"worn_coat", &"coat_right"], [&"work_trousers", &"thigh_left"],
	[&"backpack", &"pack_lid"]]
const OUTSIDE: Array = [[&"backpack", &"pack_side_left"], [&"backpack", &"pack_side_right_front"],
	[&"backpack", &"pack_side_right_back"], [&"backpack", &"pack_carabiner"], [&"backpack", &"pack_carabiner_left"]]

var _failures: int = 0
var _interior: PackInterior
var _hands: PackHandling
var _shelf: PackQuickShelf
var _camera: Camera3D
var _worst_cloth: float = -1.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	pack.global_position = PACK_AT
	pack.set_open(true)
	_interior = PackInterior.new()
	pack.add_child(_interior)
	_interior.setup(pack)
	_interior.set_open(true)
	for id: StringName in [&"axe", &"frying_pan", &"hammer"]:
		_interior.add(id, Vector3(0.0, 0.36, 0.11))
		await _frames(20)
	await _frames(60)
	_camera = Camera3D.new()
	_camera.fov = 46.0
	root.add_child(_camera)
	_camera.look_at_from_position(PACK_AT + Vector3(0.0, 0.85, 0.75), PACK_AT + Vector3(0.0, 0.2, 0.11))
	_camera.make_current()
	var ring := PackCursor.new()
	root.add_child(ring)
	_shelf = PackQuickShelf.new()
	pack.add_child(_shelf)
	_shelf.setup(pack, _camera, BODY, OUTSIDE)
	_hands = PackHandling.new()
	root.add_child(_hands)
	_hands.setup(_interior, _camera, ring)
	_hands.setup_shelf(_shelf)
	var drops: Array[StringName] = []
	_hands.dropped.connect(func(id: StringName, _state: Dictionary) -> void: drops.append(id))
	_check(_shelf.slots.size() == BODY.size() + OUTSIDE.size(), "the shelf has %d cards, not %d" % [_shelf.slots.size(), BODY.size() + OUTSIDE.size()])
	var coat_left: int = _slot(&"coat_left")
	var coat_right: int = _slot(&"coat_right")
	var side: int = _slot(&"pack_side_left")
	var carabiner: int = _slot(&"pack_carabiner")
	_shelf.put(coat_left, &"spov_can")
	_shelf.put(side, &"water_flask")
	_shelf.put(carabiner, &"mug")
	await _frames(5)
	_check(_shelf.visual_of(coat_left) != null, "the SPoV tin does not stand on its card")

	## The ring over a filled card makes it active, with the drop hint.
	_aim_card(coat_left)
	await _frames(3)
	_check(_hands.hovered_slot == coat_left, "the ring over the coat pocket's card does not hover it")
	_check(_shelf.slots[coat_left]["tint"] == PackQuickShelf.ACTIVE, "the hovered card is not active")
	_check(ring.hovering, "the ring does not light up over a filled card")

	## LMB carries the tin into the pack.
	var in_pack: int = _interior.items.size()
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _frames(2)
	_check(not ring.shown, "the ring still shows while the tin is carried")
	await _glide(_camera.unproject_position(pack.global_transform * Vector3(0.0, 0.32, 0.11)), 20)
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(60)
	_check(_interior.items.size() == in_pack + 1 and StringName(_shelf.slots[coat_left]["item_id"]) == &"",
		"the tin did not go from the coat pocket into the pack")
	print("pack shelf: carried the SPoV tin from the coat pocket into the pack")

	## A pack item dragged onto the empty right coat pocket moves into it.
	var picked: int = await _aim_at_pack_item()
	if picked >= 0:
		var moving: StringName = _interior.items[picked]["id"]
		_hands.press(PackHandling.GRAB_ACTION, true)
		await _frames(2)
		await _glide(_card_screen(coat_right), 25)
		_check(_shelf.slots[coat_right]["tint"] == PackQuickShelf.ACTIVE, "the free coat pocket does not show it would take %s" % moving)
		_hands.press(PackHandling.GRAB_ACTION, false)
		await _frames(5)
		_check(StringName(_shelf.slots[coat_right]["item_id"]) == moving, "%s did not move into the right coat pocket" % moving)
		_check(_interior.items.size() == in_pack, "%s is still in the pack" % moving)
		print("pack shelf: moved %s from the pack into the right coat pocket" % moving)
	else:
		_check(false, "no pack item to drag onto a card")

	## A full pocket refuses: the thermos goes back to the side pocket, with the reason under the ring.
	_aim_card(side)
	await _frames(3)
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _frames(2)
	await _glide(_card_screen(coat_right), 25)
	_check(_shelf.slots[coat_right]["tint"] == PackQuickShelf.REFUSE, "the full coat pocket does not show it would refuse")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(3)
	_check(StringName(_shelf.slots[side]["item_id"]) == &"water_flask", "the refused thermos did not go back to the side pocket")
	_check(ring.warning == tr(PackQuickShelf.FULL) and ring.warning_s > 0.0, "the full pocket showed no reason")
	print("pack shelf: the full coat pocket refused the thermos (%s)" % ring.warning)

	## G throws the mug off the carabiner.
	_aim_card(carabiner)
	await _frames(3)
	_hands.press(PackHandling.DROP_ACTION, true)
	await _frames(3)
	_check(drops == [&"mug"] and StringName(_shelf.slots[carabiner]["item_id"]) == &"", "G over the carabiner did not throw the mug out")
	print("pack shelf: deepest past the cloth through it all %.1f mm" % (_worst_cloth * 1000.0))
	_check(_worst_cloth <= 0.002, "an item came through the canvas (%.1f mm)" % (_worst_cloth * 1000.0))
	print("pack shelf: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _slot(pocket_id: StringName) -> int:
	for k: int in _shelf.slots.size():
		if (_shelf.slots[k]["definition"] as EquipmentSlotDefinition).id == pocket_id:
			return k
	return -1


func _card_screen(k: int) -> Vector2:
	return _camera.unproject_position((_shelf.slots[k]["card"] as Node3D).global_position)


func _aim_card(k: int) -> void:
	_hands.set_cursor(_card_screen(k))


func _glide(to: Vector2, frames: int) -> void:
	var from: Vector2 = _hands.cursor_at
	for f: int in frames:
		_hands.set_cursor(from.lerp(to, float(f + 1) / float(frames)))
		await _frames(1)


func _aim_at_pack_item() -> int:
	for i: int in _interior.items.size():
		var centre: Vector3 = _interior.model.global_transform * _interior.extent(i).get_center()
		_hands.set_cursor(_camera.unproject_position(centre))
		await _frames(2)
		if _hands.hovered == i:
			return i
	return -1


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame
		if _interior != null:
			_worst_cloth = maxf(_worst_cloth, PackClothCheck.worst_past(_interior))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pack shelf: %s" % message)

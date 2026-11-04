class_name PackHandling
extends Node

## Hands in the open pack (3D inventory): the ring cursor hovers what is under it, a strapped item in the pack
## (PackStraps) or a quick pocket's card (PackQuickShelf). LMB (pad A) takes it and carries it on the cursor;
## letting go over a card puts it in that pocket, over the pack puts it under the straps, anywhere else puts it
## back. G (pad Y) puts the hovered item down on the ground. The mouse or the left stick moves the ring. What
## would not fit shows red with its reason. Every move goes through the Hub, so the inventory stays the truth.

signal dropped(item_id: StringName)

const GRAB_ACTION: StringName = &"pack_grab"
const DROP_ACTION: StringName = &"drop_carried"
const CURSOR_ACTIONS: Array[StringName] = [&"pack_cursor_left", &"pack_cursor_right", &"pack_cursor_up", &"pack_cursor_down"]
## Stick cursor speed at full tilt, share of the screen height per second.
const STICK_SPEED: float = 0.7
## How far the pick ray reaches, metres.
const RAY_M: float = 3.0
const OUTLINE_SHADER: Shader = preload("res://shaders/items/item_outline.gdshader")
const HOVER_RIM: Color = Color(1.0, 1.0, 1.0, 0.85)
const HELD_RIM: Color = Color(1.0, 0.78, 0.25, 0.95)
const REFUSED_RIM: Color = Color(1.0, 0.22, 0.18, 0.95)
## A refusal shows this long, seconds; a carried item hangs this share of the way from the camera to the pack.
const WARNING_S: float = 2.0
const CARRY_DEPTH: float = 0.85
## A carried item is drawn this big, metres.
const CARRY_SIZE_M: float = 0.12

var hub: PlayerHubComponent
var straps: PackStraps
var shelf: PackQuickShelf
var camera: Camera3D
var cursor: PackCursor
## The ring's position in the camera's viewport, pixels.
var cursor_at: Vector2 = Vector2.ZERO
## What is under the ring: a pack item's index, or a card's slot (-1 each when nothing).
var hovered_item: int = -1
var hovered_slot: int = -1
var enabled: bool = true
## The item a hand carries: {"id", "from_slot" or "from_item", "visual": Node3D}; empty when none.
var _carry: Dictionary = {}
var _pad_used: bool = false
var _rimmed: Node3D


## Hands for `quick_hub`'s pack (`pack_straps`) and quick pockets (`quick_shelf`), seen through `view`, the ring
## drawn on `ring`.
func setup(quick_hub: PlayerHubComponent, pack_straps: PackStraps, quick_shelf: PackQuickShelf, view: Camera3D, ring: PackCursor) -> void:
	hub = quick_hub
	straps = pack_straps
	shelf = quick_shelf
	camera = view
	cursor = ring
	cursor_at = camera.get_viewport().get_visible_rect().size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera == null:
		return
	if event is InputEventMouseMotion:
		set_cursor((event as InputEventMouseMotion).position)
		_pad_used = false
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_used = true
	for action: StringName in [GRAB_ACTION, DROP_ACTION]:
		if event.is_action(action) and not event.is_echo():
			press(action, event.is_pressed())
			get_viewport().set_input_as_handled()
			return


## Moves the ring to `at` (viewport pixels).
func set_cursor(at: Vector2) -> void:
	cursor_at = at.clamp(Vector2.ZERO, camera.get_viewport().get_visible_rect().size)


## One input: an action pressed or released (the stand and the pad come in here too).
func press(action: StringName, pressed: bool) -> void:
	match action:
		GRAB_ACTION:
			if pressed and _carry.is_empty():
				_take()
			elif not pressed and not _carry.is_empty():
				_release()
		DROP_ACTION:
			if pressed and _carry.is_empty():
				_drop_hovered()


## Shows why something would not go: the reason under the ring, and a red rim on `visual` if given.
func show_refusal(reason: StringName, visual: Node3D = null) -> void:
	if cursor != null:
		cursor.warning = tr(reason)
		cursor.warning_s = WARNING_S
	if visual != null:
		_rim(visual, REFUSED_RIM)


func is_carrying() -> bool:
	return not _carry.is_empty()


func _process(delta: float) -> void:
	if not enabled or camera == null or straps == null:
		if cursor != null:
			cursor.visible = false
		return
	_move_by_stick(delta)
	hovered_slot = shelf.pick(camera.project_ray_origin(cursor_at), camera.project_ray_normal(cursor_at)) if shelf != null else -1
	hovered_item = -1
	## A strapped item wins over the card behind an item on the pack's outside.
	if hovered_slot < 0 or shelf.slots[hovered_slot]["on_pack"]:
		var ray: Array = _pack_ray()
		hovered_item = straps.pick(ray[0], ray[0] + ray[1] * RAY_M)
		if hovered_item >= 0:
			hovered_slot = -1
	if not _carry.is_empty():
		_follow_carry()
	_show_hover()
	if cursor != null:
		cursor.visible = true
		cursor.at = cursor_at
		cursor.shown = _carry.is_empty()
		cursor.hovering = hovered_item >= 0 or (hovered_slot >= 0 and StringName(shelf.slots[hovered_slot]["item_id"]) != &"")
		cursor.hint = tr(&"INVENTORY_HINT_DROP") % ("Y" if _pad_used else "G")


## LMB on what is under the ring: it leaves its place and rides the cursor.
func _take() -> void:
	var id: StringName = &""
	if hovered_slot >= 0:
		id = shelf.slots[hovered_slot]["item_id"]
		if id == &"":
			return
		_carry = {"id": id, "from_slot": hovered_slot}
		var on_card: Node3D = shelf.visual_of(hovered_slot)
		if on_card != null:
			on_card.visible = false
	elif hovered_item >= 0:
		id = straps.items[hovered_item]["id"]
		_carry = {"id": id, "from_item": hovered_item}
		straps.set_lifted(hovered_item, true)
	else:
		return
	var visual: Node3D = SurvivalItemVisual.make(id)
	var box: AABB = BackpackModel._local_bounds(visual)
	var holder := Node3D.new()
	holder.add_child(visual)
	visual.position = -box.get_center()
	holder.scale = Vector3.ONE * (CARRY_SIZE_M / maxf(box.size[box.size.max_axis_index()], 0.001))
	camera.add_child(holder)
	_rim(visual, HELD_RIM)
	_carry["visual"] = holder
	_follow_carry()


## LMB let go: onto a card, into the pack, or back where it came from.
func _release() -> void:
	var carried: Dictionary = _carry
	_carry = {}
	(carried["visual"] as Node3D).queue_free()
	var id: StringName = carried["id"]
	var from_slot: int = carried.get("from_slot", -1)
	var from_item: int = carried.get("from_item", -1)
	var moved: bool = false
	if hovered_slot >= 0 and hovered_slot != from_slot:
		var why: StringName = shelf.refusal(hovered_slot, id)
		if why != &"":
			show_refusal(why)
		elif from_slot >= 0:
			moved = hub.move_between_zones(shelf.slots[from_slot]["path"], shelf.slots[hovered_slot]["path"]) == EquipmentComponent.Refusal.NONE
		else:
			moved = hub.move_to_zone(id, shelf.slots[hovered_slot]["path"]) == EquipmentComponent.Refusal.NONE
	elif from_slot >= 0 and _over_pack():
		var why: StringName = straps.refusal(id)
		if why != &"":
			show_refusal(why)
		else:
			moved = hub.move_to_pack(shelf.slots[from_slot]["path"]) == &""
	if not moved:
		if from_slot >= 0 and shelf.visual_of(from_slot) != null:
			shelf.visual_of(from_slot).visible = true
		if from_item >= 0:
			straps.set_lifted(from_item, false)
	shelf.refresh()


## G over something: it goes down on the ground ahead of Henry.
func _drop_hovered() -> void:
	if hovered_slot >= 0:
		var id: StringName = shelf.slots[hovered_slot]["item_id"]
		if id != &"" and hub.drop_from_zone(shelf.slots[hovered_slot]["path"]):
			shelf.refresh()
			dropped.emit(id)
	elif hovered_item >= 0:
		var id: StringName = straps.items[hovered_item]["id"]
		if hub.drop_from_pack(id):
			dropped.emit(id)


## The carried item hangs on the cursor's ray between the camera and the pack.
func _follow_carry() -> void:
	var depth: float = camera.global_position.distance_to(straps.model.global_transform * PackStraps.room().get_center()) * CARRY_DEPTH
	var at: Vector3 = camera.project_ray_origin(cursor_at) + camera.project_ray_normal(cursor_at) * depth
	(_carry["visual"] as Node3D).global_position = at


## Rims and card tints: the hovered thing pale, where a carried item would go warm, where it would not red.
func _show_hover() -> void:
	var carried: StringName = _carry.get("id", &"")
	var target: Node3D = null
	if carried == &"":
		if hovered_item >= 0:
			target = straps.items[hovered_item]["visual"]
		elif hovered_slot >= 0:
			target = shelf.visual_of(hovered_slot)
		var lit: int = hovered_slot if hovered_slot >= 0 and StringName(shelf.slots[hovered_slot]["item_id"]) != &"" else -1
		shelf.set_tint(lit, PackQuickShelf.ACTIVE)
	else:
		if hovered_slot >= 0 and hovered_slot != int(_carry.get("from_slot", -1)):
			shelf.set_tint(hovered_slot, PackQuickShelf.ACTIVE if shelf.refusal(hovered_slot, carried) == &"" else PackQuickShelf.REFUSE)
		else:
			shelf.set_tint(-1, Color.TRANSPARENT)
		var into_pack: bool = int(_carry.get("from_slot", -1)) >= 0 and hovered_slot < 0 and _over_pack()
		var held: Node3D = (_carry["visual"] as Node3D).get_child(0)
		_rim(held, REFUSED_RIM if into_pack and straps.refusal(carried) != &"" else HELD_RIM)
	if target != _rimmed:
		if is_instance_valid(_rimmed):
			_rim(_rimmed, Color.TRANSPARENT)
		if target != null:
			_rim(target, HOVER_RIM)
		_rimmed = target


func _move_by_stick(delta: float) -> void:
	var stick := Vector2(Input.get_axis(CURSOR_ACTIONS[0], CURSOR_ACTIONS[1]), Input.get_axis(CURSOR_ACTIONS[2], CURSOR_ACTIONS[3]))
	if stick.length() > 0.0:
		_pad_used = true
		set_cursor(cursor_at + stick * STICK_SPEED * camera.get_viewport().get_visible_rect().size.y * delta)


## The cursor's ray in pack space: [origin, direction].
func _pack_ray() -> Array:
	var to_pack: Transform3D = straps.model.global_transform.affine_inverse()
	return [to_pack * camera.project_ray_origin(cursor_at), (to_pack.basis * camera.project_ray_normal(cursor_at)).normalized()]


## Whether the cursor's ray passes through the pack's compartment.
func _over_pack() -> bool:
	var ray: Array = _pack_ray()
	return PackStraps.room().intersects_ray(ray[0], ray[1]) != null


## An outline of `colour` on every mesh of `visual` (none with a transparent colour).
static func _rim(visual: Node3D, colour: Color) -> void:
	var rim: ShaderMaterial = null
	if colour.a > 0.0:
		rim = ShaderMaterial.new()
		rim.shader = OUTLINE_SHADER
		rim.set_shader_parameter(&"rim_colour", colour)
	## An item on the pack keeps its card's stencil mask (PackQuickShelf); the rim draws after it.
	if visual.has_meta(&"backdrop_mask"):
		(visual.get_meta(&"backdrop_mask") as Material).next_pass = rim
		return
	for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			(mesh as MeshInstance3D).material_overlay = rim

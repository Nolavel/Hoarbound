class_name PackHandling
extends Node

## Hands in the open pack (3D inventory): the ring hovers a strapped item or a pocket; LMB (pad A) carries it to
## a pocket, the pack or back; RMB (pad X) opens, eats, drinks or uses it; G (pad Y) drops it. Moves go via the Hub.

signal dropped(item_id: StringName)

const GRAB_ACTION: StringName = &"pack_grab"
const DROP_ACTION: StringName = &"drop_carried"
const USE_ACTION: StringName = &"pack_use"
const CURSOR_ACTIONS: Array[StringName] = [&"pack_cursor_left", &"pack_cursor_right", &"pack_cursor_up", &"pack_cursor_down"]
## Pad: a flick of the stick past SNAP_TILT jumps the ring to the nearest target that way (items, cards, the
## hand, the pack, the shelves), within SNAP_CONE_DEG; held, it steps on every SNAP_REPEAT_S; it re-arms below
## SNAP_RELEASE. Off-axis targets count as farther (SNAP_OFF_AXIS).
const SNAP_TILT: float = 0.6
const SNAP_RELEASE: float = 0.3
const SNAP_REPEAT_S: float = 0.32
const SNAP_CONE_DEG: float = 55.0
const SNAP_OFF_AXIS: float = 2.0
## How far the pick ray reaches, metres.
const RAY_M: float = 3.0
const OUTLINE_SHADER: Shader = preload("res://shaders/items/item_outline.gdshader")
## Cloth handling (Freesound #237047, CC0): a rustle as a hand takes or puts, a softer pull when refused.
const RUSTLE: SoundEvent = preload("res://data/audio/backpack/pack_rustle.tres")
const RESIST: SoundEvent = preload("res://data/audio/backpack/pack_resist.tres")
## The ring's outline: at most this many triangles of a mesh, rasterised this many cells across.
const OUTLINE_TRIANGLES: int = 4000
const OUTLINE_GRID: float = 56.0
const HELD_RIM: Color = Color(1.0, 0.78, 0.25, 0.95)
const REFUSED_RIM: Color = Color(1.0, 0.22, 0.18, 0.95)
## A refusal shows this long, seconds; a carried item hangs this share of the way from the camera to the pack.
const WARNING_S: float = 2.0
const CARRY_DEPTH: float = 0.85
## Taking costs time (Project Zomboid's timed actions): LMB is held while the hand works an item free. A pocket
## or a shelf takes TAKE_REACH_S, a strapped item TAKE_STRAP_S plus up to TAKE_DEEP_S on the bottom tier; each kg
## adds TAKE_S_PER_KG (to TAKE_KG_MAX_S); cold hands (ExtremityCold load 0..1) multiply it up to 1 + COLD_SLOWS.
const TAKE_REACH_S: float = 0.2
const TAKE_STRAP_S: float = 0.28
const TAKE_DEEP_S: float = 0.3
const TAKE_S_PER_KG: float = 0.12
const TAKE_KG_MAX_S: float = 0.4
const COLD_SLOWS: float = 1.5
## Cold hands shake: the ring wanders up to TREMOR_PX at full cold load, TREMOR_HZ; it starts past TREMOR_FROM.
const TREMOR_PX: float = 9.0
const TREMOR_HZ: float = 7.0
const TREMOR_FROM: float = 0.25

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
## Whether the ring is over the hand card (what Henry takes in hand).
var hovered_hand: bool = false
## The item under the ring on an open container's shelf, or -1; the container itself (null when none).
var hovered_shelf: int = -1
var container: ItemContainer
var enabled: bool = true
## The item a hand carries: {"id", "from_slot" or "from_item", "visual": Node3D}; empty when none.
var _carry: Dictionary = {}
## A take under way (LMB held): {"hovered": [slot, item, shelf, hand], "s": done, "need": seconds}; empty when none.
var _taking: Dictionary = {}
## How cold Henry's hands are, 0..1 (the Hub's ExtremityCold load), and the tremor's clock.
var hands_cold: float = 0.0
var _tremor_t: float = 0.0
var _pad_used: bool = false
var _snap_armed: bool = true
var _snap_s: float = 0.0
## Sampled triangles per mesh resource, and each visual's last outline with the pose it was traced in.
static var _triangle_cache: Dictionary = {}
static var _outline_cache: Dictionary = {}


## Hands for `quick_hub`'s pack (`pack_straps`) and quick pockets (`quick_shelf`), seen through `view`, the ring
## drawn on `ring`.
func setup(quick_hub: PlayerHubComponent, pack_straps: PackStraps, quick_shelf: PackQuickShelf, view: Camera3D, ring: PackCursor, shelves: ItemContainer = null) -> void:
	container = shelves
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
	for action: StringName in [GRAB_ACTION, DROP_ACTION, USE_ACTION]:
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
			if pressed and _carry.is_empty() and _taking.is_empty():
				_begin_take()
			elif not pressed and not _taking.is_empty():
				_taking = {}  # let go before the hand had it: nothing taken
			elif not pressed and not _carry.is_empty():
				_release()
		DROP_ACTION:
			if pressed and _carry.is_empty():
				_drop_hovered()
		USE_ACTION:
			if pressed and _carry.is_empty():
				use_hovered()


## RMB (pad X) on what is under the ring: a tin opens where it lies; food and drink close the pack and Henry
## eats or drinks (his hands need to be free); what cannot be used says why.
func use_hovered() -> void:
	if hovered_shelf >= 0:
		return  # off the shelf it is used once it is in hand: carry it to the pack or a pocket first
	var id: StringName = _hovered_id()
	var verb: StringName = use_verb(id)
	if id == &"" or verb == &"":
		return
	var path: StringName = _hovered_path()
	var eater := hub.get_parent().get_node_or_null(^"ConsumptionController") as ConsumptionController
	if verb == &"INVENTORY_HINT_OPEN" and eater != null:
		var why: ConsumptionController.Refusal = eater.consume_from_zone(path) if path != &"" else eater.consume(id)
		if why != ConsumptionController.Refusal.NONE:
			show_refusal(StringName(ConsumptionController.describe_refusal(why)))
		else:
			_sound(RUSTLE)
			hub.action_result.emit(true)
			shelf.refresh()
		return
	var why: ConsumptionController.Refusal = eater.can_consume(id) if eater != null else ConsumptionController.Refusal.NOT_CONSUMABLE
	if path == &"" and not hub.can_use(id):
		show_refusal(StringName(ConsumptionController.describe_refusal(why)))
		return
	_sound(RUSTLE)
	## A pocket's item passes through the pack to its user and back (Hub.use_from_zone); refused, it says why.
	if path != &"" and not hub.use_from_zone(path):
		show_refusal(StringName(ConsumptionController.describe_refusal(why)))
	elif path == &"":
		hub.use_item(id)


## What RMB would do with `item_id`: a hint key (INVENTORY_HINT_OPEN, _DRINK, _EAT, _USE), or &"" for nothing.
func use_verb(item_id: StringName) -> StringName:
	var item: ItemResource = ItemCatalog.get_item(item_id) if item_id != &"" else null
	if item == null:
		return &""
	if item.opens_into != &"":
		return &"INVENTORY_HINT_OPEN"
	if item.water_capacity_ml > 0 or (item.consumable != null and item.consumable.hydration > 0.0 and item.consumable.calories <= 0.0):
		return &"INVENTORY_HINT_DRINK"
	if item.consumable != null:
		return &"INVENTORY_HINT_EAT"
	return &"INVENTORY_HINT_USE" if hub.can_use(item_id) else &""


## Shows why something would not go: the reason under the ring, and a red rim on `visual` if given.
func show_refusal(reason: StringName, visual: Node3D = null, report: bool = true) -> void:
	if report and hub != null:
		hub.action_result.emit(false)
	_sound(RESIST)
	if cursor != null:
		cursor.warning = tr(reason)
		cursor.warning_s = WARNING_S
	if visual != null:
		_rim(visual, REFUSED_RIM)


func is_carrying() -> bool:
	return not _carry.is_empty()


## Whether a take is under way (LMB held, the hand still working the item free).
func is_taking() -> bool:
	return not _taking.is_empty()


## How long taking what is under the ring would take now, seconds (0 when nothing is there).
func take_seconds() -> float:
	var id: StringName = _hovered_id()
	if id == &"":
		return 0.0
	var need: float = TAKE_REACH_S
	if hovered_item >= 0:
		var depth: float = 1.0 - float(straps.items[hovered_item]["tier"]) / maxf(PackStraps.TIERS - 1, 1)
		need = TAKE_STRAP_S + TAKE_DEEP_S * depth
	need += minf(float(ItemReadout.describe(id).get("kg", 0.0)) * TAKE_S_PER_KG, TAKE_KG_MAX_S)
	return need * (1.0 + COLD_SLOWS * clampf(hands_cold, 0.0, 1.0))


func _process(delta: float) -> void:
	if not enabled or camera == null or straps == null:
		if cursor != null:
			cursor.visible = false
		return
	_move_by_stick(delta)
	hands_cold = hub.get_hands_cold() if hub != null else hands_cold
	if not _taking.is_empty():
		_advance_take(delta)
		if cursor != null:
			cursor.progress = clampf(float(_taking.get("s", 0.0)) / maxf(float(_taking.get("need", 1.0)), 0.001), 0.0, 1.0) if not _taking.is_empty() else 0.0
			cursor.at = cursor_at + _tremor(delta)
		return
	hovered_slot = shelf.pick(camera.project_ray_origin(cursor_at), camera.project_ray_normal(cursor_at)) if shelf != null else -1
	hovered_hand = hovered_slot < 0 and shelf != null and shelf.pick_hand(camera.project_ray_origin(cursor_at), camera.project_ray_normal(cursor_at))
	hovered_item = -1
	hovered_shelf = container.pick(cursor_at, camera) if container != null and hovered_slot < 0 and not hovered_hand else -1
	## A strapped item wins over the card behind an item on the pack's outside.
	if not hovered_hand and hovered_shelf < 0 and (hovered_slot < 0 or shelf.slots[hovered_slot]["on_pack"]):
		var ray: Array = _pack_ray()
		hovered_item = straps.pick(ray[0], ray[0] + ray[1] * RAY_M)
		if hovered_item >= 0:
			hovered_slot = -1
	if not _carry.is_empty():
		_follow_carry()
	if shelf != null:
		shelf.focus_slot = hovered_slot
	_show_hover()
	if cursor != null:
		cursor.visible = true
		cursor.progress = 0.0
		cursor.at = cursor_at + _tremor(delta)
		cursor.shown = _carry.is_empty()
		cursor.hovering = hovered_item >= 0 or hovered_shelf >= 0 or (hovered_slot >= 0 and StringName(shelf.slots[hovered_slot]["item_id"]) != &"") \
			or (hovered_hand and shelf.hand_visual() != null)
		var target: Node3D = _hovered_visual() if cursor.hovering and _carry.is_empty() else null
		cursor.outline = _screen_outline(target) if target != null else PackedVector2Array()
		cursor.outline_key = target.get_instance_id() if target != null else 0
		cursor.hint = tr(&"INVENTORY_HINT_DROP") % ("Y" if _pad_used else "G")
		var verb: StringName = use_verb(_hovered_id()) if hovered_shelf < 0 else &""
		if verb != &"":
			cursor.hint = tr(verb) % ("X" if _pad_used else tr(&"KEY_RMB")) + "    " + cursor.hint
		var shown_id: StringName = _carry.get("id", _hovered_id())
		var in_pack: bool = hovered_item >= 0 and _carry.is_empty()
		cursor.info = ItemReadout.describe(shown_id, hub.inventory.get_count(shown_id) if in_pack and hub.inventory != null else 1) if shown_id != &"" else {}
		cursor.load_kg = hub.get_weight()
		cursor.load_max_kg = hub.get_max_weight()
		cursor.load_slows_at = hub.get_load_slows_at()
		cursor.load_item_kg = float(cursor.info.get("kg", 0.0))


## LMB pressed on something: the hand starts working it free (take_seconds); held long enough, it is taken.
func _begin_take() -> void:
	var need: float = take_seconds()
	if need <= 0.0:
		return
	_taking = {"hovered": [hovered_slot, hovered_item, hovered_shelf, hovered_hand], "s": 0.0, "need": need}
	_sound(RUSTLE)


## The take runs on while LMB is held; the hover it began on is kept, so the cursor may already move off.
func _advance_take(delta: float) -> void:
	_taking["s"] = float(_taking["s"]) + delta
	if float(_taking["s"]) < float(_taking["need"]):
		return
	var began: Array = _taking["hovered"]
	_taking = {}
	var now: Array = [hovered_slot, hovered_item, hovered_shelf, hovered_hand]
	hovered_slot = began[0]
	hovered_item = began[1]
	hovered_shelf = began[2]
	hovered_hand = began[3]
	_take()
	hovered_slot = now[0]
	hovered_item = now[1]
	hovered_shelf = now[2]
	hovered_hand = now[3]


## Cold hands' shake for the ring this frame: two sines off beat, scaled by the cold past TREMOR_FROM.
func _tremor(delta: float) -> Vector2:
	var shake: float = clampf((hands_cold - TREMOR_FROM) / (1.0 - TREMOR_FROM), 0.0, 1.0)
	if shake <= 0.0:
		return Vector2.ZERO
	_tremor_t += delta
	var phase: float = TAU * TREMOR_HZ * _tremor_t
	return Vector2(sin(phase) + 0.5 * sin(phase * 2.3), cos(phase * 1.3) + 0.5 * sin(phase * 3.1)) * TREMOR_PX * shake / 1.5


## The hand has it: it leaves its place and rides the cursor.
func _take() -> void:
	var id: StringName = &""
	if hovered_hand and shelf.selected >= 0 and shelf.hand_visual() != null:
		hovered_slot = shelf.selected  # the hand shows the pick's pocket: take from there
	if hovered_shelf >= 0:
		id = container.items[hovered_shelf]["id"]
		_carry = {"id": id, "from_shelf": hovered_shelf}
		(container.items[hovered_shelf]["pickup"] as Node3D).visible = false
	elif hovered_slot >= 0:
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
	_sound(RUSTLE)
	var visual: Node3D = SurvivalItemVisual.make(id)
	var box: AABB = BackpackModel._local_bounds(visual)
	var holder := Node3D.new()
	holder.add_child(visual)
	visual.position = -box.get_center()
	## True size: it hangs CARRY_DEPTH of the way to the pack, so it is scaled by that to look as big as beside it.
	holder.scale = Vector3.ONE * CARRY_DEPTH
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
	var from_shelf: int = carried.get("from_shelf", -1)
	var moved: bool = false
	var attempted: bool = false
	if from_shelf >= 0:
		attempted = hovered_slot >= 0 or _over_pack()
		moved = _release_from_shelf(from_shelf, id)
	elif container != null and (hovered_shelf >= 0 or _over_container()):
		attempted = true
		var full: StringName = container.refusal(id)
		if full != &"":
			show_refusal(full, null, false)
		elif from_slot >= 0:
			moved = hub.move_to_container(container, &"", shelf.slots[from_slot]["path"]) == &""
		else:
			moved = hub.move_to_container(container, id) == &""
	elif hovered_hand and from_slot >= 0:
		shelf.choose(from_slot)  # into the hand: it becomes the pick, staying in its pocket till the pack goes on
	elif hovered_slot >= 0 and hovered_slot != from_slot:
		attempted = true
		var why: StringName = shelf.refusal(hovered_slot, id)
		if why != &"":
			show_refusal(why, null, false)
		elif from_slot >= 0:
			moved = hub.move_between_zones(shelf.slots[from_slot]["path"], shelf.slots[hovered_slot]["path"]) == EquipmentComponent.Refusal.NONE
		else:
			moved = hub.move_to_zone(id, shelf.slots[hovered_slot]["path"]) == EquipmentComponent.Refusal.NONE
	elif from_slot >= 0 and _over_pack():
		attempted = true
		var why: StringName = straps.refusal(id)
		if why != &"":
			show_refusal(why, null, false)
		else:
			moved = hub.move_to_pack(shelf.slots[from_slot]["path"]) == &""
			if moved:
				hub.jolt_held_pack(float(ItemReadout.describe(id).get("kg", 0.0)))
	if attempted:
		hub.action_result.emit(moved)
	if moved:
		_sound(RUSTLE)
	if not moved and from_shelf >= 0 and from_shelf < container.items.size():
		(container.items[from_shelf]["pickup"] as Node3D).visible = true
	if not moved:
		if from_slot >= 0 and shelf.visual_of(from_slot) != null:
			shelf.visual_of(from_slot).visible = true
		if from_item >= 0:
			straps.set_lifted(from_item, false)
	shelf.refresh()


## Let go of something taken off the shelf: onto a card (that pocket) or over the pack (under the straps).
func _release_from_shelf(index: int, id: StringName) -> bool:
	if hovered_slot >= 0:
		var why: StringName = shelf.refusal(hovered_slot, id)
		if why != &"":
			show_refusal(why, null, false)
			return false
		return hub.move_from_container(container, index, shelf.slots[hovered_slot]["path"]) == &""
	if not _over_pack():
		return false
	var no_room: StringName = straps.refusal(id)
	if no_room != &"":
		show_refusal(no_room, null, false)
		return false
	var why: StringName = hub.move_from_container(container, index)
	if why != &"":
		show_refusal(&"PICKUP_REFUSED_TOO_HEAVY", null, false)
		return false
	hub.jolt_held_pack(float(ItemReadout.describe(id).get("kg", 0.0)))
	return true


## Whether the cursor's ray passes through the open container's shelves.
func _over_container() -> bool:
	if container == null:
		return false
	var to_shelves: Transform3D = container.global_transform.affine_inverse()
	var origin: Vector3 = to_shelves * camera.project_ray_origin(cursor_at)
	var direction: Vector3 = (to_shelves.basis * camera.project_ray_normal(cursor_at)).normalized()
	return container.shelves_box().intersects_ray(origin, direction) != null


## G over something: it goes down on the ground ahead of Henry.
func _drop_hovered() -> void:
	if hovered_slot >= 0:
		var id: StringName = shelf.slots[hovered_slot]["item_id"]
		if id != &"" and hub.drop_from_zone(shelf.slots[hovered_slot]["path"]):
			_sound(RUSTLE)
			shelf.refresh()
			hub.action_result.emit(true)
			dropped.emit(id)
	elif hovered_item >= 0:
		var id: StringName = straps.items[hovered_item]["id"]
		if hub.drop_from_pack(id):
			_sound(RUSTLE)
			hub.action_result.emit(true)
			dropped.emit(id)


## The carried item hangs on the cursor's ray between the camera and the pack.
func _follow_carry() -> void:
	var depth: float = camera.global_position.distance_to(straps.model.global_transform * PackStraps.room().get_center()) * CARRY_DEPTH
	var at: Vector3 = camera.project_ray_origin(cursor_at) + camera.project_ray_normal(cursor_at) * depth
	(_carry["visual"] as Node3D).global_position = at


## Card tints and rims: where a carried item would go pale, where it would not red. The hovered thing gets
## the ring's outline instead of a rim.
func _show_hover() -> void:
	var carried: StringName = _carry.get("id", &"")
	if carried == &"":
		var lit: int = hovered_slot if hovered_slot >= 0 and StringName(shelf.slots[hovered_slot]["item_id"]) != &"" else -1
		shelf.set_tint(lit, PackQuickShelf.ACTIVE)
	else:
		if hovered_slot >= 0 and hovered_slot != int(_carry.get("from_slot", -1)):
			shelf.set_tint(hovered_slot, PackQuickShelf.ACTIVE if shelf.refusal(hovered_slot, carried) == &"" else PackQuickShelf.REFUSE)
		else:
			shelf.set_tint(-1, Color.TRANSPARENT)
		var from_pack: bool = int(_carry.get("from_item", -1)) >= 0
		var into_shelf: bool = not _carry.has("from_shelf") and hovered_slot < 0 and (hovered_shelf >= 0 or _over_container())
		var into_pack: bool = not from_pack and not into_shelf and hovered_slot < 0 and _over_pack()
		var refused: bool = (into_pack and straps.refusal(carried) != &"") or (into_shelf and container.refusal(carried) != &"")
		var held: Node3D = (_carry["visual"] as Node3D).get_child(0)
		_rim(held, REFUSED_RIM if refused else HELD_RIM)


## Plays a cloth sound for the hands (flat: it is right before the camera).
func _sound(event: SoundEvent) -> void:
	var sound := get_node_or_null(^"/root/SoundSystem") as SoundSystemService
	if sound != null:
		sound.play(event)


## The pocket path of what the ring is over (a pocket or the hand's), or &"" for a strapped item or nothing.
func _hovered_path() -> StringName:
	if hovered_hand:
		return shelf.slots[shelf.selected]["path"] if shelf.selected >= 0 and shelf.selected < shelf.slots.size() else &""
	if hovered_item < 0 and hovered_slot >= 0:
		return shelf.slots[hovered_slot]["path"]
	return &""


## The id of what the ring is over (a strapped item, a pocket's item, the hand's), or &"".
func _hovered_id() -> StringName:
	if hovered_shelf >= 0:
		return container.items[hovered_shelf]["id"]
	if hovered_hand:
		return shelf.slots[shelf.selected]["item_id"] if shelf.selected >= 0 and shelf.selected < shelf.slots.size() else &""
	if hovered_item >= 0:
		return straps.items[hovered_item]["id"]
	if hovered_slot >= 0:
		return shelf.slots[hovered_slot]["item_id"]
	return &""


## What the ring is over: a strapped item's visual, a pocket's item (on the pack or on its card), or the hand's.
func _hovered_visual() -> Node3D:
	if hovered_shelf >= 0:
		return container.items[hovered_shelf]["pickup"]
	if hovered_hand:
		return shelf.hand_visual()
	if hovered_item >= 0:
		return straps.items[hovered_item]["visual"]
	if hovered_slot >= 0:
		return shelf.visual_of(hovered_slot)
	return null


## The outline of `visual` on screen (viewport pixels).
func _screen_outline(visual: Node3D) -> PackedVector2Array:
	return screen_outline(visual, camera)


## Forgets every traced outline (the view jumped: a hard cut).
static func clear_outline_cache() -> void:
	_outline_cache.clear()


## The silhouette of `visual` as `camera` sees it (viewport pixels): its triangles rasterised into a grid of
## OUTLINE_GRID cells across, the filled region's boundary traced (Moore neighbourhood). Cached while still.
static func screen_outline(visual: Node3D, camera: Camera3D) -> PackedVector2Array:
	var key: int = visual.get_instance_id()
	var pose: Array = [visual.global_transform, camera.global_transform, camera.fov]
	if _outline_cache.has(key) and _same_pose(_outline_cache[key][0], pose):
		return _outline_cache[key][1]
	var projected := PackedVector2Array()
	for node: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var at: Transform3D = mesh.global_transform
		var corners: PackedVector3Array = _sampled_triangles(mesh.mesh)
		for i: int in range(0, corners.size(), 3):
			var a: Vector3 = at * corners[i]
			var b: Vector3 = at * corners[i + 1]
			var c: Vector3 = at * corners[i + 2]
			if camera.is_position_behind(a) or camera.is_position_behind(b) or camera.is_position_behind(c):
				continue
			projected.append_array([camera.unproject_position(a), camera.unproject_position(b), camera.unproject_position(c)])
	var outline: PackedVector2Array = _trace_silhouette(projected)
	_outline_cache[key] = [pose, outline]
	return outline


static func _same_pose(a: Array, b: Array) -> bool:
	return (a[0] as Transform3D).is_equal_approx(b[0]) and (a[1] as Transform3D).is_equal_approx(b[1]) and is_equal_approx(a[2], b[2])


## Triangles (three points each) rasterised into a cell grid, and the outer boundary of the filled cells as a
## polygon of cell centres (viewport pixels).
static func _trace_silhouette(triangles: PackedVector2Array) -> PackedVector2Array:
	if triangles.size() < 3:
		return PackedVector2Array()
	var low: Vector2 = triangles[0]
	var high: Vector2 = triangles[0]
	for point: Vector2 in triangles:
		low = low.min(point)
		high = high.max(point)
	var cell: float = maxf(maxf(high.x - low.x, high.y - low.y) / OUTLINE_GRID, 1.0)
	var origin: Vector2 = low - Vector2.ONE * cell  # a one-cell empty border
	var width: int = int(ceil((high.x - low.x) / cell)) + 3
	var height: int = int(ceil((high.y - low.y) / cell)) + 3
	var filled := PackedByteArray()
	filled.resize(width * height)
	for i: int in range(0, triangles.size(), 3):
		var a: Vector2 = (triangles[i] - origin) / cell
		var b: Vector2 = (triangles[i + 1] - origin) / cell
		var c: Vector2 = (triangles[i + 2] - origin) / cell
		for corner: Vector2 in [a, b, c]:
			filled[int(corner.y) * width + int(corner.x)] = 1  # thin slivers still mark their corners
		var from := Vector2i(floori(minf(a.x, minf(b.x, c.x))), floori(minf(a.y, minf(b.y, c.y))))
		var to := Vector2i(floori(maxf(a.x, maxf(b.x, c.x))), floori(maxf(a.y, maxf(b.y, c.y))))
		for y: int in range(from.y, to.y + 1):
			for x: int in range(from.x, to.x + 1):
				if Geometry2D.point_is_inside_triangle(Vector2(x + 0.5, y + 0.5), a, b, c):
					filled[y * width + x] = 1
	## Moore neighbourhood tracing, clockwise on screen, from the first filled cell in reading order.
	var start: int = filled.find(1)
	if start < 0:
		return PackedVector2Array()
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	var first := Vector2i(start % width, start / width)
	var current: Vector2i = first
	var back: int = 4  # the cell to its west is empty (reading order)
	var outline := PackedVector2Array()
	for _guard: int in width * height * 4:
		outline.append(origin + (Vector2(current) + Vector2.ONE * 0.5) * cell)
		var moved: bool = false
		for turn: int in 8:
			var d: int = (back + 1 + turn) % 8
			var next: Vector2i = current + steps[d]
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height or filled[next.y * width + next.x] == 0:
				continue
			## Backtrack to the empty cell checked just before, as seen from the new cell.
			var empty: Vector2i = current + steps[(d + 7) % 8] - next
			back = steps.find(empty)
			current = next
			moved = true
			break
		if not moved or current == first:
			break
	return outline


## Up to OUTLINE_TRIANGLES of `mesh`'s triangles (three corners each), evenly picked, measured once per mesh.
static func _sampled_triangles(mesh: Mesh) -> PackedVector3Array:
	if _triangle_cache.has(mesh):
		return _triangle_cache[mesh]
	var faces: PackedVector3Array = mesh.get_faces()
	var count: int = faces.size() / 3
	var stride: int = maxi(count / OUTLINE_TRIANGLES, 1)
	var picked := PackedVector3Array()
	for t: int in range(0, count, stride):
		picked.append_array([faces[t * 3], faces[t * 3 + 1], faces[t * 3 + 2]])
	_triangle_cache[mesh] = picked
	return picked


func _move_by_stick(delta: float) -> void:
	var stick := Vector2(Input.get_axis(CURSOR_ACTIONS[0], CURSOR_ACTIONS[1]), Input.get_axis(CURSOR_ACTIONS[2], CURSOR_ACTIONS[3]))
	if stick.length() < SNAP_RELEASE:
		_snap_armed = true
		return
	_pad_used = true
	_snap_s -= delta
	if stick.length() >= SNAP_TILT and (_snap_armed or _snap_s <= 0.0):
		_snap_armed = false
		_snap_s = SNAP_REPEAT_S
		snap(stick)


## Jumps the ring to the nearest target along `direction` (screen space, y down); false when none lies that way.
func snap(direction: Vector2) -> bool:
	var way: Vector2 = direction.normalized()
	var best: Vector2 = cursor_at
	var best_score: float = INF
	var cone: float = cos(deg_to_rad(SNAP_CONE_DEG))
	for target: Vector2 in snap_targets():
		var offset: Vector2 = target - cursor_at
		if offset.length() < 12.0:
			continue
		var along: float = way.dot(offset.normalized())
		if along < cone:
			continue
		var score: float = offset.length() * (1.0 + SNAP_OFF_AXIS * (1.0 - along))
		if score < best_score:
			best_score = score
			best = target
	if best_score == INF:
		return false
	set_cursor(best)
	return true


## Where the ring can land (viewport pixels): every strapped item, every shown card, the hand card, the pack's
## room (to put a carried item in) and an open container's items and shelves.
func snap_targets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for item: Dictionary in straps.items:
		out.append(camera.unproject_position(straps.model.global_transform * (item["box"] as AABB).get_center()))
	out.append(camera.unproject_position(straps.model.global_transform * PackStraps.room().get_center()))
	if shelf != null:
		for k: int in shelf.slots.size():
			var card: Node3D = shelf.slots[k]["card"]
			if card != null and card.is_visible_in_tree():
				out.append(shelf.aim_point(k))
		if shelf.hand_card != null and shelf.hand_card.is_visible_in_tree():
			out.append(camera.unproject_position(shelf.hand_card.global_position))
	if container != null:
		for item: Dictionary in container.items:
			var pickup: Node3D = item["pickup"]
			if is_instance_valid(pickup) and pickup.is_visible_in_tree():
				out.append(camera.unproject_position(pickup.global_transform * BackpackModel._local_bounds(pickup).get_center()))
		out.append(camera.unproject_position(container.global_transform * container.shelves_box().get_center()))
	var screen: Rect2 = camera.get_viewport().get_visible_rect()
	var shown: Array[Vector2] = []
	for point: Vector2 in out:
		if screen.has_point(point):
			shown.append(point)
	return shown

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
	# The carried visual owns its rim. Hover updates change only its parameter;
	# allocating/replacing a material every frame churns renderer dependencies.
	var rim: ShaderMaterial = null
	if colour.a > 0.0:
		rim = visual.get_meta(&"pack_rim_material") as ShaderMaterial if visual.has_meta(&"pack_rim_material") else null
		if rim == null:
			rim = ShaderMaterial.new()
			rim.shader = OUTLINE_SHADER
			visual.set_meta(&"pack_rim_material", rim)
		if rim.get_shader_parameter(&"rim_colour") != colour:
			rim.set_shader_parameter(&"rim_colour", colour)
	for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			var overlay: Material = (mesh as MeshInstance3D).material_overlay
			if overlay != null and overlay.has_meta(&"focus_mask"):
				if overlay.next_pass != rim:
					overlay.next_pass = rim
			elif overlay != rim:
				(mesh as MeshInstance3D).material_overlay = rim

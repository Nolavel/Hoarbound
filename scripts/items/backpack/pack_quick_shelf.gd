class_name PackQuickShelf
extends Node3D

## Quick Access while Henry holds the pack open (3D inventory). Pockets whose item shows on the pack (side
## pockets, carabiners) have no card: the item there is hovered on its outline. Hidden pockets stand as cards on
## the Quick Access gradient (BG_frame.gdshader) with their 3D item, no text: the body's in a row at the bottom
## centre (trousers, the hand card, coat; the clothes panel is kept behind SHOW_BODY_PANEL), the lid's at the
## right. The hand card shows the Quick Access pick; a pocket's item let go on it becomes the pick.

const BG_FRAME: Shader = preload("res://assets/materials/Shaders/BG_frame.gdshader")
const BODY_FRONT: Texture2D = preload("res://assets/ui/inventory/body_front.png")
const BODY_POCKETS: JSON = preload("res://assets/ui/inventory/body_front.json")
const HAND_ICON: Texture2D = preload("res://assets/ui/hud/pickup_marker/hand_open.svg")
## The body panel: its height as a share of the frame's, its middle's x as a share of the half width (near the
## left edge), its tint; the cards on it show this share of their tint's alpha.
const BODY_SHARE: float = 0.54
const BODY_X_SHARE: float = 0.8
const BODY_TINT: Color = Color(0.62, 0.63, 0.66, 0.32)
const BODY_CARD_ALPHA: float = 0.55
## Cards on the panel are this share of the side cards' size, so the two on the coat stay apart.
const BODY_CARD_SCALE: float = 0.72
## The hand card stands beside the panel, at this height on it (0 top, 1 bottom, where the hands hang), with
## its icon this faint.
const HAND_V: float = 0.4
const HAND_ICON_TINT: Color = Color(1.0, 1.0, 1.0, 0.28)
## Off (owner's call), the clothes panel hides and the body's pockets stand in a row at the bottom centre:
## the trousers' left, the hand in the middle, the coat's right (BOTTOM_ROW order, "hand" the hand card).
const SHOW_BODY_PANEL: bool = false
const BOTTOM_ROW: Array[String] = ["thigh_left", "thigh_right", "hand", "coat_left", "coat_right"]
## The bottom row's middle height (share of the half height, down) and the extra gap between groups (cards).
const BOTTOM_SHARE: float = 0.8
const BOTTOM_GROUP_GAP: float = 0.35
## An item stands still on its card, turned this much so its shape reads (x, y radians).
const ITEM_TURN := Vector2(0.3, -0.55)
## A card's side in its own space, and how big its item stands on it (shares of that side).
const CARD_M: float = 0.1
const ITEM_FIT: float = 0.8
## Cards: depth ahead of the camera (metres), card height as a share of the frame height, column x as a share
## of the half width, the top row's y as a share of the half height, and the row pitch in card heights.
const DEPTH_M: float = 0.5
const CARD_SHARE: float = 0.115
const COLUMN_SHARE: float = 0.8
const TOP_SHARE: float = 0.78
const ROW_PITCH: float = 1.18
## A card behind an item on the pack: its margin around the item's screen outline, and how far behind the
## item's far side it stands, metres.
const BACKDROP_PAD_M: float = 0.015
const BACKDROP_BEHIND_M: float = 0.01
## The card of an empty pocket on the pack is this big around its spot, metres.
const EMPTY_SPOT_M: float = 0.07
## Card tints: hovered (pale), filled, empty, refusing.
const ACTIVE: Color = Color(0.92, 0.92, 0.9, 0.9)
const FILLED: Color = Color(0.42, 0.42, 0.42, 0.82)
const EMPTY: Color = Color(0.3, 0.3, 0.3, 0.38)
const REFUSE: Color = Color(1.0, 0.25, 0.2, 0.9)
const FULL: StringName = &"INVENTORY_POCKET_FULL"
const TOO_SMALL: StringName = &"INVENTORY_POCKET_TOO_SMALL"

## Per slot: {"path", "on_pack" (its item shows on the pack), "column" (0 left, 1 right), "row", "item_id",
## "card": MeshInstance3D, "visual": the card's own item (Node3D or null; none on the pack), "tint": Color}.
var slots: Array[Dictionary] = []
var camera: Camera3D
var hub: PlayerHubComponent
var pack: PackRig
## The selected slot (QuickAccessComponent's pick: what Henry takes in hand), or -1.
var selected: int = -1
var hand_card: MeshInstance3D
var _quick: QuickAccessComponent
var _body: MeshInstance3D
var _hand_visual: Node3D
## The gradient for the left column (fading toward the pack, rightward) and the right one (leftward).
var _frames: Array[SubViewport] = []


## Cards for `quick_hub`'s quick pockets at the sides of `view`'s frame.
func setup(quick_hub: PlayerHubComponent, view: Camera3D) -> void:
	hub = quick_hub
	camera = view
	pack = hub.pack
	_quick = hub.get_parent().get_node_or_null(^"QuickAccessComponent") as QuickAccessComponent if hub.get_parent() != null else null
	_frames = [_gradient_viewport(0), _gradient_viewport(1)]
	var rows: Array[int] = [0, 0]
	for zone: Dictionary in hub.get_quick_access_zones():
		var path: StringName = zone["path"]
		var parts: PackedStringArray = String(path).split(EquipmentComponent.POCKET_SEPARATOR)
		var on_pack: bool = pack != null and parts.size() == 2 and parts[0] == "pack" and PackRig.shows_pocket(StringName(parts[1]))
		var column: int = 1 if parts[0] == "pack" else 0
		slots.append({"path": path, "on_pack": on_pack, "column": column, "row": -1 if on_pack else rows[column],
			"item_id": zone["item_id"], "card": _card(_frames[0]), "visual": null, "tint": EMPTY})
		var anchor: Array = (BODY_POCKETS.data as Dictionary).get("pockets", {}).get(String(parts[parts.size() - 1]), [])
		slots[-1]["body_uv"] = Vector2(anchor[0], anchor[1]) if anchor.size() == 2 and column == 0 else Vector2(-1.0, -1.0)
		if on_pack:
			(slots[-1]["card"] as MeshInstance3D).visible = false
		elif (slots[-1]["body_uv"] as Vector2).x < 0.0:
			rows[column] += 1
	_body = _flat_quad(BODY_FRONT, BODY_TINT)
	_body.name = "BodyPanel"
	hand_card = _card(_frames[0])
	hand_card.name = "HandCard"
	var icon: MeshInstance3D = _flat_quad(HAND_ICON, HAND_ICON_TINT, hand_card)
	icon.scale = Vector3.ONE * 0.6 * CARD_M
	icon.position = Vector3(0.0, 0.0, 0.001)
	if hub.equipment != null:
		hub.equipment.slot_changed.connect(func(_path: StringName, _id: StringName) -> void: refresh())
	for k: int in slots.size():
		_refresh(k)


## Re-reads every pocket's item from the equipment.
func refresh() -> void:
	if hub == null:
		return
	var by_path: Dictionary = {}
	for zone: Dictionary in hub.get_quick_access_zones():
		by_path[zone["path"]] = zone["item_id"]
	for k: int in slots.size():
		var now: StringName = by_path.get(slots[k]["path"], &"")
		if now != StringName(slots[k]["item_id"]):
			slots[k]["item_id"] = now
			_refresh(k)


## Why slot k would not take `item_id` now (FULL, TOO_SMALL), or &"" when it would.
func refusal(k: int, item_id: StringName) -> StringName:
	if StringName(slots[k]["item_id"]) != &"":
		return FULL
	var parts: PackedStringArray = String(slots[k]["path"]).split(EquipmentComponent.POCKET_SEPARATOR)
	if hub.equipment == null or parts.size() != 2:
		return TOO_SMALL
	var why: EquipmentComponent.Refusal = hub.equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id)
	if why == EquipmentComponent.Refusal.NONE:
		return &""
	return FULL if why == EquipmentComponent.Refusal.SLOT_OCCUPIED else TOO_SMALL


## The slot whose card a world-space ray meets, or -1. An item on the pack is hit on its own outline on screen
## (the ring's), an empty pocket there on its unseen card; overlapping, the smallest wins.
func pick(origin: Vector3, direction: Vector3) -> int:
	var best: int = -1
	var best_area: float = INF
	var screen: Vector2 = camera.unproject_position(origin + direction)
	for k: int in slots.size():
		var visual: Node3D = visual_of(k) if slots[k]["on_pack"] else null
		if visual != null and visual.is_visible_in_tree():
			var outline: PackedVector2Array = PackHandling.screen_outline(visual, camera)
			if outline.size() >= 3 and Geometry2D.is_point_in_polygon(screen, outline):
				var box: Rect2 = Rect2(outline[0], Vector2.ZERO)
				for point: Vector2 in outline:
					box = box.expand(point)
				if box.get_area() * 1e-6 < best_area:
					best = k
					best_area = box.get_area() * 1e-6
			continue
		var card: MeshInstance3D = slots[k]["card"]
		var plane := Plane(card.global_basis.z.normalized(), card.global_position)
		var hit: Variant = plane.intersects_ray(origin, direction)
		if hit == null:
			continue
		var local: Vector3 = card.global_transform.affine_inverse() * (hit as Vector3)
		if absf(local.x) <= CARD_M * 0.5 and absf(local.y) <= CARD_M * 0.5:
			if not slots[k]["on_pack"]:
				return k
			var scale: Vector3 = card.global_basis.get_scale()
			if scale.x * scale.y < best_area:
				best = k
				best_area = scale.x * scale.y
	return best


## A screen point (viewport pixels) that hovers slot k: its card, or a point inside its item's outline on the
## pack that no other item's outline covers (for stands and captures).
func aim_point(k: int) -> Vector2:
	var visual: Node3D = visual_of(k) if slots[k]["on_pack"] else null
	if visual == null:
		return camera.unproject_position((slots[k]["card"] as Node3D).global_position)
	var outline: PackedVector2Array = PackHandling.screen_outline(visual, camera)
	var middle := Vector2.ZERO
	for point: Vector2 in outline:
		middle += point
	middle /= maxf(outline.size(), 1.0)
	for point: Vector2 in outline:
		var aim: Vector2 = point.lerp(middle, 0.35)
		if pick(camera.project_ray_origin(aim), camera.project_ray_normal(aim)) == k:
			return aim
	return middle


## Tints slot k's card ACTIVE or REFUSE; every other card (or all, with Color.TRANSPARENT) shows selected,
## filled or empty.
func set_tint(k: int, colour: Color) -> void:
	for i: int in slots.size():
		var want: Color = colour if i == k and colour.a > 0.0 else _rest_tint(i)
		if slots[i]["tint"] != want:
			slots[i]["tint"] = want
			var shown: Color = want
			if (slots[i]["body_uv"] as Vector2).x >= 0.0:
				shown.a *= BODY_CARD_ALPHA
			((slots[i]["card"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = shown


## What shows slot k's item: the real one on the pack, or the one standing on its card.
func visual_of(k: int) -> Node3D:
	if slots[k]["on_pack"]:
		return pack.get_pocket_visual(_pocket(k)) if is_instance_valid(pack) else null
	return slots[k]["visual"]


func _process(_delta: float) -> void:
	if camera == null:
		return
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_h: float = DEPTH_M * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w: float = half_h * view.x / maxf(view.y, 1.0)
	var size: float = half_h * 2.0 * CARD_SHARE
	var pick: int = _quick.get_selected_index() if _quick != null else -1
	if pick != selected:
		selected = pick
		set_tint(-1, Color.TRANSPARENT)
	_refresh_hand()
	## The clothes panel at the left; the coat's and the trousers' cards sit on it where their pockets are.
	var body_height: float = half_h * 2.0 * BODY_SHARE
	var body_size := Vector2(body_height * BODY_FRONT.get_width() / float(BODY_FRONT.get_height()), body_height)
	var body_at := Vector3(-half_w * BODY_X_SHARE, 0.0, -DEPTH_M - 0.002)
	_body.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(body_size.x, body_size.y, 1.0)), body_at)
	_body.visible = SHOW_BODY_PANEL
	var hand_at := body_at + Vector3(body_size.x * 0.5 + size * 0.75, (0.5 - HAND_V) * body_size.y, 0.002)
	if not SHOW_BODY_PANEL:
		hand_at = _bottom_spot("hand", half_h, size)
	hand_card.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size / CARD_M), hand_at)
	for k: int in slots.size():
		var slot: Dictionary = slots[k]
		if slot["on_pack"]:
			_place_backdrop(k)
			continue
		var side: float = -1.0 if int(slot["column"]) == 0 else 1.0
		var at := Vector3(side * half_w * COLUMN_SHARE, half_h * TOP_SHARE - float(slot["row"]) * size * ROW_PITCH, -DEPTH_M)
		var uv: Vector2 = slot["body_uv"]
		var side_m: float = size
		if uv.x >= 0.0 and SHOW_BODY_PANEL:
			at = body_at + Vector3((uv.x - 0.5) * body_size.x, (0.5 - uv.y) * body_size.y, 0.002)
			side_m = size * BODY_CARD_SCALE
		elif BOTTOM_ROW.has(String(_pocket(k))):
			at = _bottom_spot(String(_pocket(k)), half_h, size)
		(slot["card"] as Node3D).global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * side_m / CARD_M), at)


## Where `place` (a BOTTOM_ROW entry) stands in the bottom row, camera space: cards a pitch apart, the groups
## (trousers, hand, coat) a little further.
func _bottom_spot(place: String, half_h: float, size: float) -> Vector3:
	var index: int = BOTTOM_ROW.find(place)
	var middle: int = BOTTOM_ROW.find("hand")
	var x: float = float(index - middle) * size * ROW_PITCH
	if index != middle:
		x += signf(float(index - middle)) * size * BOTTOM_GROUP_GAP
	return Vector3(x, -half_h * BOTTOM_SHARE, -DEPTH_M)


## Slot k's unseen card stands square to the camera behind its item on the pack (or its empty spot), so the
## ring hovers it; it stops at the pack opening's edge.
func _place_backdrop(k: int) -> void:
	var to_view: Transform3D = camera.global_transform.affine_inverse()
	var visual: Node3D = visual_of(k)
	var corners: Array[Vector3] = []
	if visual != null and visual.is_visible_in_tree():
		var box: AABB = BackpackModel._local_bounds(visual)
		for i: int in 8:
			corners.append(to_view * (visual.global_transform * box.get_endpoint(i)))
	else:
		var box := AABB(pack.get_pocket_spot(_pocket(k)) - Vector3.ONE * EMPTY_SPOT_M * 0.5, Vector3.ONE * EMPTY_SPOT_M)
		for i: int in 8:
			corners.append(to_view * box.get_endpoint(i))
	## Every corner scaled onto the plane behind the far side; the card spans their outline.
	var depth: float = 0.0
	for corner: Vector3 in corners:
		depth = maxf(depth, -corner.z)
	depth += BACKDROP_BEHIND_M
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector3 in corners:
		var on_plane: Vector2 = Vector2(corner.x, corner.y) * depth / maxf(-corner.z, 0.01)
		low = low.min(on_plane)
		high = high.max(on_plane)
	low -= Vector2.ONE * BACKDROP_PAD_M
	high += Vector2.ONE * BACKDROP_PAD_M
	## It stops at the edge of the pack's opening on screen, so it never covers what the straps hold.
	var opening: Vector2 = _opening_span(to_view, depth)
	if (low.x + high.x) * 0.5 < (opening.x + opening.y) * 0.5:
		high.x = maxf(minf(high.x, opening.x), low.x + BACKDROP_PAD_M)
	else:
		low.x = minf(maxf(low.x, opening.y), high.x - BACKDROP_PAD_M)
	var middle: Vector2 = (low + high) * 0.5
	var span: Vector2 = high - low
	var card: MeshInstance3D = slots[k]["card"]
	card.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(span.x, span.y, 1.0) / CARD_M), Vector3(middle.x, middle.y, -depth))


## The pack opening's left and right x on the view plane at `depth` (camera space).
func _opening_span(to_view: Transform3D, depth: float) -> Vector2:
	var straps: PackStraps = pack.get_straps()
	var room: AABB = PackStraps.room()
	var span := Vector2(INF, -INF)
	for i: int in 8:
		var corner: Vector3 = to_view * (straps.model.global_transform * room.get_endpoint(i))
		var x: float = corner.x * depth / maxf(-corner.z, 0.01)
		span = Vector2(minf(span.x, x), maxf(span.y, x))
	return span


func _rest_tint(i: int) -> Color:
	return FILLED if StringName(slots[i]["item_id"]) != &"" else EMPTY


## Whether a world-space ray meets the hand card.
func pick_hand(origin: Vector3, direction: Vector3) -> bool:
	var hit: Variant = Plane(hand_card.global_basis.z.normalized(), hand_card.global_position).intersects_ray(origin, direction)
	if hit == null:
		return false
	var local: Vector3 = hand_card.global_transform.affine_inverse() * (hit as Vector3)
	return absf(local.x) <= CARD_M * 0.5 and absf(local.y) <= CARD_M * 0.5


## What stands on the hand card (the pick's item), or null.
func hand_visual() -> Node3D:
	return _hand_visual


## Makes slot k the pick: Henry takes its item in hand when the pack goes back on.
func choose(k: int) -> void:
	if _quick != null:
		_quick.select(k)


## The hand card shows the pick's item; it is refreshed when the pick or its pocket changes.
func _refresh_hand() -> void:
	var id: StringName = slots[selected]["item_id"] if selected >= 0 and selected < slots.size() else &""
	var shown: StringName = _hand_visual.get_meta(&"item_id", &"") if _hand_visual != null else &""
	if id == shown:
		return
	if _hand_visual != null:
		_hand_visual.queue_free()
		_hand_visual = null
	if id != &"":
		_hand_visual = _stand_on(hand_card, id)
		_hand_visual.set_meta(&"item_id", id)
	var tint: Color = FILLED if id != &"" else EMPTY
	tint.a *= BODY_CARD_ALPHA
	(hand_card.material_override as StandardMaterial3D).albedo_color = tint


## A quad of `texture` tinted `colour`, unlit and see-through, a child of `parent` (this shelf by default).
func _flat_quad(texture: Texture2D, colour: Color, parent: Node = null) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.albedo_color = colour
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.set_meta(&"flat_card", true)
	(parent if parent != null else self).add_child(quad)
	return quad


func _pocket(k: int) -> StringName:
	return StringName(String(slots[k]["path"]).get_slice(EquipmentComponent.POCKET_SEPARATOR, 1))


func _card(frame: SubViewport) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_M, CARD_M)
	card.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = frame.get_texture()
	material.albedo_color = EMPTY
	card.material_override = material
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.set_meta(&"flat_card", true)
	add_child(card)
	return card


## Slot k's item stands on its card, scaled to fit it.
func _refresh(k: int) -> void:
	var slot: Dictionary = slots[k]
	var old: Node3D = slot["visual"]
	if old != null:
		old.queue_free()
		slot["visual"] = null
	var id: StringName = slot["item_id"]
	if id != &"" and not slot["on_pack"]:
		slot["visual"] = _stand_on(slot["card"], id)
	slot["tint"] = Color.TRANSPARENT
	set_tint(-1, Color.TRANSPARENT)


## `id`'s 3D item standing on `card`, scaled to fit it.
func _stand_on(card: MeshInstance3D, id: StringName) -> Node3D:
	var holder := Node3D.new()
	var visual: Node3D = SurvivalItemVisual.make(id)
	var box: AABB = BackpackModel._local_bounds(visual)
	holder.add_child(visual)
	visual.position = -box.get_center()
	holder.scale = Vector3.ONE * (CARD_M * ITEM_FIT / maxf(box.size[box.size.max_axis_index()], 0.001))
	holder.rotation = Vector3(ITEM_TURN.x, ITEM_TURN.y, 0.0)
	card.add_child(holder)
	holder.position = Vector3(0.0, 0.0, CARD_M * 0.35)
	return holder


## The Quick Access gradient (BG_frame.gdshader) fading in `direction` (0 right, 1 left), drawn once in white;
## each card tints it.
func _gradient_viewport(direction: int) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(128, 128)
	var material := ShaderMaterial.new()
	material.shader = BG_FRAME
	material.set_shader_parameter(&"base_color", Color.WHITE)
	material.set_shader_parameter(&"fade_direction", direction)
	material.set_shader_parameter(&"reveal", 1.0)
	rect.material = material
	view.add_child(rect)
	add_child(view)
	return view

class_name PackRig
extends Node3D

## Henry's backpack on his back: a tray with four outer flaps over an inner
## attachment field. The top flap alone opens for a quick stow; all four open for the Hub.

signal openness_changed(state: Openness)

enum Openness { CLOSED, TOP_ONLY, FULL, AJAR }

## Hinge angles when open, in degrees; flaps swing out (-Z) first.
const TOP_OPEN_DEG: float = 150.0
const BOTTOM_OPEN_DEG: float = -120.0
const SIDE_OPEN_DEG: float = 150.0
## Share of the outer face each band covers, top to bottom.
const TOP_SHARE: float = 0.27
const BOTTOM_SHARE: float = 0.2
const FLAP_THICKNESS: float = 0.02
## Set down by the stove: in use, not spilled — top and sides lifted a little.
const AJAR_TOP_DEG: float = 40.0
const MAX_SWAY_DEG: float = 2.5
const AJAR_SIDE_DEG: float = 28.0
## The canvas pack's zip for the quick stow and for set down by the stove: how far each slider
## runs down its side past the top corner (m), and how far the freed top folds out (degrees).
const TOP_ONLY_ZIP_SIDE_M: float = 0.15
const TOP_ONLY_PANEL_DEG: float = 55.0
const AJAR_ZIP_SIDE_M: float = 0.22
const AJAR_PANEL_DEG: float = 24.0
## Longest step the sway spring takes in one frame, seconds: a hitch's long frame would blow it up.
const MAX_SPRING_STEP_S: float = 0.05

@export var size: Vector3 = Vector3(0.34, 0.44, 0.2)
@export var color: Color = Color(0.36, 0.33, 0.28)
@export var field_color: Color = Color(0.55, 0.5, 0.4)
## Seconds for the full book opening; the top-only opening takes half.
@export var open_time: float = 0.6
@export_flags_3d_render var render_layers: int = 1
## Draw the canvas backpack (#260) instead of the four-flap tray; the flaps still keep the state.
@export var use_canvas_model: bool = true
## The worn pack is strapped against the back and only rocks a little as Henry starts and stops:
## spring frequency empty and full (Hz), damping, and degrees per m/s^2, at most MAX_SWAY_DEG.
@export var sway_hz_empty: float = 3.6
@export var sway_hz_full: float = 2.8
@export_range(0.1, 1.0, 0.05) var sway_damping: float = 0.45
@export var sway_deg_per_mps2: float = 0.45
## Carried weight that fills the pack, kg.
@export var full_load_kg: float = 14.0

var _state: Openness = Openness.CLOSED
var _top: Node3D
var _bottom: Node3D
var _left: Node3D
var _right: Node3D
var _field: Node3D
var _tween: Tween
var _canvas: BackpackModel
var _sway: Node3D
var _sway_angle: Vector2 = Vector2.ZERO
var _sway_speed: Vector2 = Vector2.ZERO
var _last_position: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
## Side-pocket contents last shown (slot -> item id), and whether the first fill has happened.
var _side_items: Dictionary = {}
var _contents_shown: bool = false


func _init() -> void:
	name = "Backpack"


func _ready() -> void:
	if _top == null:
		build()


## Builds the tray, the field and the four hinged flaps. Idempotent.
func build() -> void:
	if _top != null:
		return
	var material: ShaderMaterial = _material(color)
	var outer_z: float = -size.z * 0.5
	var tray_depth: float = size.z - FLAP_THICKNESS
	_box("Tray", Vector3(size.x, size.y, tray_depth), Vector3(0.0, 0.0, FLAP_THICKNESS * 0.5), material, self)
	_field = _build_field(outer_z + FLAP_THICKNESS + 0.002)
	var top_h: float = size.y * TOP_SHARE
	var bottom_h: float = size.y * BOTTOM_SHARE
	var mid_h: float = size.y - top_h - bottom_h
	var mid_y: float = size.y * 0.5 - top_h - mid_h * 0.5
	var flap_z: float = outer_z + FLAP_THICKNESS * 0.5
	_top = _hinge("TopFlap", Vector3(0.0, size.y * 0.5, flap_z))
	_box("Panel", Vector3(size.x, top_h, FLAP_THICKNESS), Vector3(0.0, -top_h * 0.5, 0.0), material, _top)
	_bottom = _hinge("BottomFlap", Vector3(0.0, -size.y * 0.5, flap_z))
	_box("Panel", Vector3(size.x, bottom_h, FLAP_THICKNESS), Vector3(0.0, bottom_h * 0.5, 0.0), material, _bottom)
	var half_w: float = size.x * 0.5
	_left = _hinge("LeftFlap", Vector3(-half_w, mid_y, flap_z))
	_box("Panel", Vector3(half_w, mid_h, FLAP_THICKNESS), Vector3(half_w * 0.5, 0.0, 0.0), material, _left)
	_right = _hinge("RightFlap", Vector3(half_w, mid_y, flap_z))
	_box("Panel", Vector3(half_w, mid_h, FLAP_THICKNESS), Vector3(-half_w * 0.5, 0.0, 0.0), material, _right)
	if use_canvas_model:
		_build_canvas()


func get_openness() -> Openness:
	return _state


func is_open() -> bool:
	return _state != Openness.CLOSED


## The bottom flap's hinge, for things strapped to the outside (Kenny).
func get_bottom_flap() -> Node3D:
	build()
	return _bottom


## The canvas pack model, or null when the four-flap tray is drawn.
func get_canvas() -> BackpackModel:
	build()
	return _canvas


## A point on the canvas (BackpackModel space, outward normal n) in world space, as it sways.
func get_canvas_point(p: Vector3, n: Vector3) -> Vector3:
	build()
	if _canvas == null:
		return global_transform * p
	return _canvas.global_transform * _canvas.canvas_point(p, n)


## A point on the canvas (BackpackModel space, outward normal n) in world space, ignoring the
## sway: where a strap sewn there meets the pack while the pack rocks on its own.
func get_canvas_point_unswayed(p: Vector3, n: Vector3) -> Vector3:
	build()
	if _canvas == null:
		return global_transform * p
	return global_transform * Transform3D(Basis(), _sway.position) * _canvas.transform * _canvas.canvas_point(p, n)


## The inner attachment field, where slot visuals live.
func get_field() -> Node3D:
	build()
	return _field


## Opens or closes the flaps; instant skips the tween (tests, loading).
func set_openness(state: Openness, instant: bool = false) -> void:
	build()
	_state = state
	var full: bool = state == Openness.FULL
	var ajar: bool = state == Openness.AJAR
	var top_deg: float = AJAR_TOP_DEG if ajar else (TOP_OPEN_DEG if state != Openness.CLOSED else 0.0)
	var side_deg: float = AJAR_SIDE_DEG if ajar else (SIDE_OPEN_DEG if full else 0.0)
	var targets: Dictionary = {
		_top: Vector3(deg_to_rad(top_deg), 0.0, 0.0),
		_bottom: Vector3(deg_to_rad(BOTTOM_OPEN_DEG) if full else 0.0, 0.0, 0.0),
		_left: Vector3(0.0, deg_to_rad(side_deg), 0.0),
		_right: Vector3(0.0, -deg_to_rad(side_deg), 0.0),
	}
	if _tween != null:
		_tween.kill()
	if instant or not is_inside_tree():
		for flap: Node3D in targets:
			flap.rotation = targets[flap]
	else:
		var time: float = open_time if full or _left.rotation.y > 0.01 else open_time * 0.5
		_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		for flap: Node3D in targets:
			## The top leads; sides and bottom follow so the pack reads as unfolding.
			var delay: float = 0.0 if flap == _top else time * 0.25
			_tween.tween_property(flap, ^"rotation", targets[flap], time * 0.75).set_delay(delay)
	if _canvas != null:
		var corner: float = BackpackModel.BODY.x * 0.5
		var opening: Dictionary = {
			Openness.CLOSED: [0.0, 0.0],
			Openness.AJAR: [corner + AJAR_ZIP_SIDE_M, AJAR_PANEL_DEG],
			Openness.TOP_ONLY: [corner + TOP_ONLY_ZIP_SIDE_M, TOP_ONLY_PANEL_DEG],
			Openness.FULL: [BackpackModel.ZIP_FULL_M, BackpackModel.OPEN_DEG],
		}
		_canvas.set_opening(opening[state][0], opening[state][1])
	openness_changed.emit(state)


## Open amount of one flap, 0 closed to 1 fully open. Names: top, bottom, left, right.
func get_flap_open(flap_name: StringName) -> float:
	build()
	match flap_name:
		&"top":
			return _top.rotation.x / deg_to_rad(TOP_OPEN_DEG)
		&"bottom":
			return _bottom.rotation.x / deg_to_rad(BOTTOM_OPEN_DEG)
		&"left":
			return _left.rotation.y / deg_to_rad(SIDE_OPEN_DEG)
		&"right":
			return -_right.rotation.y / deg_to_rad(SIDE_OPEN_DEG)
	return 0.0


## The canvas pack in place of the tray: hung from a sway pivot at the top of its back, scaled to
## size, its front facing away from Henry. The tray, flaps and field stay as hidden state.
func _build_canvas() -> void:
	for child: Node in get_children():
		if child is Node3D and child.name != "Inspect":
			for mesh: Node in [child] + child.find_children("*", "MeshInstance3D", true, false):
				if mesh is MeshInstance3D:
					(mesh as MeshInstance3D).visible = false
	_sway = Node3D.new()
	_sway.name = "Sway"
	## It rocks about the middle of its back face, so that face stays against Henry's back.
	_sway.position = Vector3(0.0, 0.0, size.z * 0.5)
	add_child(_sway)
	_canvas = BackpackModel.new()
	_canvas.name = "Canvas"
	var fit := Vector3(size.x / BackpackModel.BODY.x, size.y / BackpackModel.BODY.y, size.z / BackpackModel.BODY.z)
	## Model space: origin at the bottom of the back face, +Z out; here -Z is away from Henry.
	_canvas.transform = Transform3D(Basis(Vector3.UP, PI).scaled(fit), Vector3(0.0, -size.y * 0.5, 0.0))
	_canvas.layers_for_contents = render_layers
	_sway.add_child(_canvas)
	_canvas.build()
	for mesh: Node in _canvas.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = render_layers


## Henry's acceleration swings the pack from its straps: a spring on pitch and roll that a fuller
## pack answers more slowly. Fill comes from what Henry carries.
func _process(delta: float) -> void:
	if _canvas == null or delta <= 0.0 or not is_inside_tree():
		return
	if _inventory == null:
		var walk: Node = get_parent()
		while walk != null and not (walk is CharacterBody3D):
			walk = walk.get_parent()
		_inventory = InventoryComponent.find_in(walk) if walk != null else null
	if _inventory != null:
		_canvas.load_fill = clampf(_inventory.get_total_weight() / full_load_kg, 0.0, 1.0)
	if _equipment == null and walk_owner() != null:
		_equipment = walk_owner().get_node_or_null(^"EquipmentComponent") as EquipmentComponent
		if _equipment != null:
			_equipment.slot_changed.connect(_on_slot_changed)
			_refresh_contents()
	var at: Vector3 = get_parent_node_3d().global_position if get_parent_node_3d() != null else global_position
	if not _has_last:
		_last_position = at
		_has_last = true
		return
	var velocity: Vector3 = (at - _last_position) / delta
	var accel: Vector3 = (velocity - _last_velocity) / delta
	_last_position = at
	_last_velocity = velocity
	## Teleports and frame hitches are not accelerations.
	if not accel.is_finite() or accel.length() > 60.0:
		accel = Vector3.ZERO
	var local: Vector3 = global_basis.orthonormalized().inverse() * accel
	var target := Vector2(local.z, -local.x) * deg_to_rad(sway_deg_per_mps2)
	target = target.limit_length(deg_to_rad(MAX_SWAY_DEG))
	var omega: float = TAU * lerpf(sway_hz_empty, sway_hz_full, _canvas.get_fill_target())
	var step: float = minf(delta, MAX_SPRING_STEP_S)
	_sway_speed += (target - _sway_angle) * omega * omega * step - _sway_speed * 2.0 * sway_damping * omega * step
	_sway_angle += _sway_speed * step
	if not _sway_angle.is_finite():
		_sway_angle = Vector2.ZERO
		_sway_speed = Vector2.ZERO
	## The spring overshoots its target on a jolt; the pack itself never rocks past the cap.
	if _sway_angle.length() > deg_to_rad(MAX_SWAY_DEG):
		_sway_angle = _sway_angle.limit_length(deg_to_rad(MAX_SWAY_DEG))
		_sway_speed = Vector2.ZERO
	_sway.rotation = Vector3(_sway_angle.x, 0.0, _sway_angle.y)


## The CharacterBody3D wearing this pack, or null.
func walk_owner() -> Node:
	var walk: Node = get_parent()
	while walk != null and not (walk is CharacterBody3D):
		walk = walk.get_parent()
	return walk


func _on_slot_changed(slot_path: StringName, _item_id: StringName) -> void:
	if String(slot_path).begins_with("pack/"):
		_refresh_contents()


## Shows what the pack's pockets hold: side pockets in the side pouches, the carabiner's item
## clipped on, everything else loose in the main body.
func _refresh_contents() -> void:
	if _canvas == null or _equipment == null:
		return
	_canvas.clear_items()
	var shown: Dictionary = {}
	for entry: Dictionary in _equipment.get_available_pockets():
		var held: StringName = entry["item_id"]
		if entry["body_slot"] != &"pack" or held == &"":
			continue
		match entry["pocket"]:
			&"pack_side_left", &"pack_side_right_front", &"pack_side_right_back":
				## Something new in a side pocket is pushed in; what was already there stays seated.
				var slot: StringName = StringName(String(entry["pocket"]).trim_prefix("pack_"))
				_canvas.add_item(held, slot, 0.0, _contents_shown and _side_items.get(slot, &"") != held)
				shown[slot] = held
			&"pack_carabiner":
				_canvas.hang_item(held, 1)
			_:
				_canvas.add_loose(held)
	_side_items = shown
	_contents_shown = true
	for mesh: Node in _canvas.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = render_layers


## A lighter board behind the flaps with a grid of strap loops.
func _build_field(z: float) -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	add_child(field)
	var inset: Vector2 = Vector2(size.x - 0.03, size.y - 0.03)
	_box("Board", Vector3(inset.x, inset.y, 0.004), Vector3(0.0, 0.0, z), _material(field_color), field)
	var loop_material: ShaderMaterial = _material(color.darkened(0.3))
	for row: int in range(4):
		for column: int in range(3):
			var at := Vector3((column - 1) * inset.x * 0.3, (1.5 - row) * inset.y * 0.22, z - 0.004)
			_box("Loop", Vector3(0.05, 0.012, 0.006), at, loop_material, field)
	return field


func _hinge(hinge_name: String, at: Vector3) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = hinge_name
	hinge.position = at
	add_child(hinge)
	return hinge


func _box(box_name: String, box_size: Vector3, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = mesh
	instance.position = at
	instance.layers = render_layers
	parent.add_child(instance)
	return instance


func _material(albedo: Color) -> ShaderMaterial:
	return StylizedEnvironmentMaterial.make_character(albedo, 0.9)

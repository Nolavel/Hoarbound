class_name PackHandling
extends Node

## Hands in the open pack (3D inventory, stage 1): the ring cursor picks an item by ray in the pack's own
## physics space, LMB (pad A) takes it and it follows the cursor on a plane facing the camera, the wheel (pad
## LB/RB) turns it, RMB (pad X) shoves the others aside, G (pad Y) throws the hovered or held item out. The
## mouse moves the cursor; the left stick does on a pad. Time keeps running: nothing here pauses the game.

signal dropped(item_id: StringName, state: Dictionary)

const GRAB_ACTION: StringName = &"pack_grab"
const SHOVE_ACTION: StringName = &"pack_shove"
const TURN_LEFT_ACTION: StringName = &"pack_turn_left"
const TURN_RIGHT_ACTION: StringName = &"pack_turn_right"
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
## A refusal shows this long, seconds.
const WARNING_S: float = 2.0

var interior: PackInterior
var camera: Camera3D
var cursor: PackCursor
## The ring's position in the camera's viewport, pixels.
var cursor_at: Vector2 = Vector2.ZERO
var hovered: int = -1
var enabled: bool = true
var _shoving: bool = false
## Where the shove's point was last step (pack space), to sweep along the cursor's motion.
var _shove_from: Vector3 = Vector3.INF
var _pad_used: bool = false
var _rims: Dictionary = {}


## Hands for `pack_interior` seen through `view`, drawing the ring on `ring` (any of them may change later).
func setup(pack_interior: PackInterior, view: Camera3D, ring: PackCursor) -> void:
	interior = pack_interior
	camera = view
	cursor = ring
	cursor_at = camera.get_viewport().get_visible_rect().size * 0.5
	interior.refused.connect(_on_refused)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or interior == null or not interior.is_open():
		return
	if event is InputEventMouseMotion:
		set_cursor((event as InputEventMouseMotion).position)
		_pad_used = false
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_used = true
	for action: StringName in [GRAB_ACTION, SHOVE_ACTION, TURN_LEFT_ACTION, TURN_RIGHT_ACTION, DROP_ACTION]:
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
			if pressed and interior.held() < 0 and hovered >= 0:
				var hit: Dictionary = _pick()
				if not hit.is_empty() and int(hit["index"]) == hovered:
					interior.hold(hovered, hit["point"])
			elif not pressed:
				interior.let_go()
		SHOVE_ACTION:
			_shoving = pressed and interior.held() < 0
			_shove_from = Vector3.INF
		TURN_LEFT_ACTION, TURN_RIGHT_ACTION:
			if pressed:
				interior.turn_held(1.0 if action == TURN_LEFT_ACTION else -1.0, _view_axis())
		DROP_ACTION:
			if pressed:
				var target: int = interior.held() if interior.held() >= 0 else hovered
				if target >= 0:
					_clear_rim(target)
					var out: Dictionary = interior.remove(target)
					hovered = -1
					_reindex_rims(target)
					if not out.is_empty():
						dropped.emit(out["id"], out["state"])


## Shows that `item_id` cannot go in: red rim on `visual` (if any) and the reason under the ring.
func show_refusal(reason: StringName, visual: Node3D = null) -> void:
	if cursor != null:
		cursor.warning = tr(reason)
		cursor.warning_s = WARNING_S
	if visual != null:
		_set_rim_on(visual, REFUSED_RIM)


func _physics_process(delta: float) -> void:
	if not enabled or interior == null or camera == null or not interior.is_open():
		if cursor != null:
			cursor.visible = false
		return
	_move_by_stick(delta)
	var held: int = interior.held()
	if held >= 0:
		## On the plane through the grab point that faces the camera.
		var plane := Plane(_to_pack_dir(-camera.global_basis.z), interior.held_point())
		var ray: Array = _ray()
		var target: Variant = plane.intersects_ray(ray[0], ray[1])
		if target != null:
			interior.move_held(target)
		hovered = held
	else:
		var hit: Dictionary = _pick()
		hovered = int(hit["index"]) if not hit.is_empty() else -1
		if _shoving and not hit.is_empty():
			## The hand sweeps across the heap at the depth the cursor meets it.
			var at: Vector3 = hit["point"]
			if _shove_from != Vector3.INF:
				var plane := Plane(_view_axis(), _shove_from)
				var ray: Array = _ray()
				var on_plane: Variant = plane.intersects_ray(ray[0], ray[1])
				if on_plane != null:
					at = on_plane
				interior.shove(at, (at - _shove_from) / delta)
			_shove_from = at
	_update_rims(held)
	if cursor != null:
		cursor.visible = true
		cursor.at = cursor_at
		cursor.shown = held < 0
		cursor.hovering = hovered >= 0
		cursor.hint = tr(&"INVENTORY_HINT_DROP") % ("Y" if _pad_used else "G")


func _move_by_stick(delta: float) -> void:
	var stick := Vector2(Input.get_axis(CURSOR_ACTIONS[0], CURSOR_ACTIONS[1]), Input.get_axis(CURSOR_ACTIONS[2], CURSOR_ACTIONS[3]))
	if stick.length() > 0.0:
		_pad_used = true
		var height: float = camera.get_viewport().get_visible_rect().size.y
		set_cursor(cursor_at + stick * STICK_SPEED * height * delta)


## The cursor's ray in pack space: [origin, direction].
func _ray() -> Array:
	var origin: Vector3 = camera.project_ray_origin(cursor_at)
	var direction: Vector3 = camera.project_ray_normal(cursor_at)
	var to_pack: Transform3D = interior.model.global_transform.affine_inverse()
	return [to_pack * origin, (to_pack.basis * direction).normalized()]


func _pick() -> Dictionary:
	var ray: Array = _ray()
	return interior.pick(ray[0], ray[0] + ray[1] * RAY_M)


func _to_pack_dir(world: Vector3) -> Vector3:
	return (interior.model.global_basis.orthonormalized().inverse() * world).normalized()


## The camera's line of sight in pack space: the wheel turns the held item about it.
func _view_axis() -> Vector3:
	return _to_pack_dir(-camera.global_basis.z)


func _update_rims(held: int) -> void:
	for i: int in interior.items.size():
		var colour: Color = HELD_RIM if i == held else (HOVER_RIM if i == hovered else Color.TRANSPARENT)
		if colour.a > 0.0:
			_set_rim(i, colour)
		else:
			_clear_rim(i)


func _set_rim(i: int, colour: Color) -> void:
	if _rims.get(i, Color.TRANSPARENT) == colour:
		return
	_rims[i] = colour
	_set_rim_on(interior.items[i]["visual"], colour)


func _clear_rim(i: int) -> void:
	if not _rims.has(i):
		return
	_rims.erase(i)
	if i < interior.items.size():
		for mesh: Node in (interior.items[i]["visual"] as Node3D).find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = null


static func _set_rim_on(visual: Node3D, colour: Color) -> void:
	var rim := ShaderMaterial.new()
	rim.shader = OUTLINE_SHADER
	rim.set_shader_parameter(&"rim_colour", colour)
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = rim


## After item `gone` left, the rims of the ones after it move down one index.
func _reindex_rims(gone: int) -> void:
	var moved: Dictionary = {}
	for i: int in _rims:
		if i != gone:
			moved[i - 1 if i > gone else i] = _rims[i]
	_rims = moved


func _on_refused(_item_id: StringName, reason: StringName) -> void:
	show_refusal(reason)

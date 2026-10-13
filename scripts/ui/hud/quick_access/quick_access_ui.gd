class_name QuickAccessUI
extends Control


# ============================================================================
# INPUT
# ============================================================================

const QUICK_NEXT: StringName = &"quick_next"
const QUICK_PREV: StringName = &"quick_prev"
const QUICK_USE: StringName = &"quick_use"


# ============================================================================
# SHADER PARAMETERS
# ============================================================================

const SHADER_REVEAL: StringName = &"reveal"
const SHADER_BASE_COLOR: StringName = &"base_color"


# ============================================================================
# HENRY / 3D ANCHORS
# ============================================================================

@export_group("Henry anchors")

@export var anchor_root: Node3D

@export var coat_left_anchor: Node3D
@export var coat_right_anchor: Node3D
@export var thigh_left_anchor: Node3D
@export var pack_lid_anchor: Node3D
@export var hands_anchor: Node3D


# ============================================================================
# GAMEPLAY
# ============================================================================

@export_group("Gameplay")

@export var quick_access_component: QuickAccessComponent


# ============================================================================
# UI FOLLOW
# ============================================================================

@export_group("UI")

@export_range(1.0, 40.0, 0.5)
var follow_speed: float = 18.0


# ============================================================================
# SHADER REVEAL
# ============================================================================

@export_group("Reveal")

@export_range(0.05, 1.0, 0.01)
var reveal_time: float = 0.24

@export_range(0.0, 0.15, 0.005)
var reveal_stagger: float = 0.025

@export_range(0.05, 1.0, 0.01)
var hide_time: float = 0.16


# ============================================================================
# FOCUS COLORS
# ============================================================================

@export_group("Focus colors")

@export var active_color: Color = Color(
	1.0,
	0.72,
	0.10,
	0.92
)

@export var inactive_color: Color = Color(
	0.36,
	0.36,
	0.36,
	0.72
)

@export_range(0.0, 0.5, 0.01)
var focus_transition_time: float = 0.10


# ============================================================================
# ORBIT
# ============================================================================

@export_group("Orbit")

@export_range(1.0, 40.0, 0.5)
var orbit_follow_speed: float = 12.0

@export var orbit_enabled: bool = true

@export_range(-180.0, 180.0, 1.0)
var orbit_yaw_offset_degrees: float = 0.0


# ============================================================================
# SCREEN OFFSETS
# ============================================================================

@export_group("Screen offsets")

@export var coat_left_offset: Vector2 = Vector2.ZERO
@export var coat_right_offset: Vector2 = Vector2.ZERO
@export var thigh_left_offset: Vector2 = Vector2.ZERO
@export var pack_lid_offset: Vector2 = Vector2.ZERO
@export var hands_offset: Vector2 = Vector2.ZERO


# ============================================================================
# UI NODES
# ============================================================================

@onready var coat_left: Control = $CoatLeft
@onready var coat_right: Control = $CoatRight
@onready var thigh_left: Control = $ThighLeft
@onready var pack_lid: Control = $PackLid
@onready var hands: Control = $Hands


@onready var coat_left_background: TextureRect = $CoatLeft/Background
@onready var coat_right_background: TextureRect = $CoatRight/Background
@onready var thigh_left_background: TextureRect = $ThighLeft/Background
@onready var pack_lid_background: TextureRect = $PackLid/Background
@onready var hands_background: TextureRect = $Hands/Background


# ============================================================================
# FOCUS
# ============================================================================

enum FocusSlot {
	HANDS,
	THIGH_LEFT,
	COAT_LEFT,
	COAT_RIGHT,
	PACK_LID,
}


var _focus_order: Array[int] = [
	FocusSlot.HANDS,
	FocusSlot.THIGH_LEFT,
	FocusSlot.COAT_LEFT,
	FocusSlot.COAT_RIGHT,
	FocusSlot.PACK_LID,
]


# ============================================================================
# MATERIALS
# ============================================================================

var _coat_left_material: ShaderMaterial
var _coat_right_material: ShaderMaterial
var _thigh_left_material: ShaderMaterial
var _pack_lid_material: ShaderMaterial
var _hands_material: ShaderMaterial


# ============================================================================
# STATE
# ============================================================================

var opened: bool = false
var _focus_index: int = 0

var _reveal_tween: Tween
var _focus_tween: Tween


# ============================================================================
# READY
# ============================================================================

func _ready() -> void:
	_make_mouse_transparent(self)

	_prepare_materials()

	_set_test_labels()

	opened = false
	_focus_index = 0

	_set_all_reveal(0.0)
	_refresh_focus_visuals(false)

	_set_visible_state(false)

	call_deferred("_initial_setup")


func _initial_setup() -> void:
	_snap_all()


# ============================================================================
# MATERIAL SETUP
# ============================================================================

func _prepare_materials() -> void:
	_coat_left_material = _duplicate_material(
		coat_left_background
	)

	_coat_right_material = _duplicate_material(
		coat_right_background
	)

	_thigh_left_material = _duplicate_material(
		thigh_left_background
	)

	_pack_lid_material = _duplicate_material(
		pack_lid_background
	)

	_hands_material = _duplicate_material(
		hands_background
	)


func _duplicate_material(
	background: TextureRect
) -> ShaderMaterial:
	if background == null:
		return null

	var source: ShaderMaterial = (
		background.material as ShaderMaterial
	)

	if source == null:
		push_error(
			"QuickAccessUI: Background has no ShaderMaterial: %s"
			% background.get_path()
		)

		return null

	var copy: ShaderMaterial = (
		source.duplicate() as ShaderMaterial
	)

	background.material = copy

	return copy


func _get_materials_in_reveal_order() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []

	# HANDS появляется первым.
	if _hands_material != null:
		result.append(_hands_material)

	if _thigh_left_material != null:
		result.append(_thigh_left_material)

	if _coat_left_material != null:
		result.append(_coat_left_material)

	if _coat_right_material != null:
		result.append(_coat_right_material)

	if _pack_lid_material != null:
		result.append(_pack_lid_material)

	return result


# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	if event.is_echo():
		return


	# ------------------------------------------------------------------------
	# CLOSED
	# ------------------------------------------------------------------------

	if not opened:
		if event.is_action_pressed(QUICK_NEXT):
			show_quick_access()

			get_viewport().set_input_as_handled()

			return


		if event.is_action_pressed(QUICK_PREV):
			show_quick_access()

			get_viewport().set_input_as_handled()

			return


		if event.is_action_pressed(QUICK_USE):
			show_quick_access()

			get_viewport().set_input_as_handled()

			return


		return


	# ------------------------------------------------------------------------
	# OPEN
	# ------------------------------------------------------------------------

	if not event is InputEventMouseButton:
		return


	var mouse_event := event as InputEventMouseButton


	# RMB = cancel.
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		hide_quick_access()

		get_viewport().set_input_as_handled()

		return


	# Wheel Up и Wheel Down делают одно и то же:
	# следующий элемент по часовой стрелке.
	if (
		mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
		or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	):
		_focus_next_clockwise()

		get_viewport().set_input_as_handled()

		return


	# LMB = confirm.
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_confirm_focus()

		get_viewport().set_input_as_handled()

		return


	# Middle Mouse при уже открытом selector ничего не делает.
	# Главное — не пропустить его в старый QuickAccessComponent.
	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		get_viewport().set_input_as_handled()

		return


# ============================================================================
# PROCESS
# ============================================================================

func _process(delta: float) -> void:
	if not opened:
		return


	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera == null:
		return


	if orbit_enabled:
		_update_anchor_orbit(
			camera,
			delta
		)


	_follow(
		coat_left,
		coat_left_anchor,
		coat_left_offset,
		camera,
		delta
	)

	_follow(
		coat_right,
		coat_right_anchor,
		coat_right_offset,
		camera,
		delta
	)

	_follow(
		thigh_left,
		thigh_left_anchor,
		thigh_left_offset,
		camera,
		delta
	)

	_follow(
		pack_lid,
		pack_lid_anchor,
		pack_lid_offset,
		camera,
		delta
	)

	_follow(
		hands,
		hands_anchor,
		hands_offset,
		camera,
		delta
	)


# ============================================================================
# SHOW
# ============================================================================

func show_quick_access() -> void:
	if opened:
		return


	opened = true


	# Каждое новое открытие начинается с HANDS.
	_focus_index = 0

	_refresh_focus_visuals(false)


	_set_visible_state(true)


	_snap_all()


	_animate_reveal_in()


# ============================================================================
# HIDE
# ============================================================================

func hide_quick_access() -> void:
	if not opened:
		return


	opened = false


	_animate_reveal_out()


func _finish_hide() -> void:
	if opened:
		return

	_set_visible_state(false)


# ============================================================================
# REVEAL ANIMATION
# ============================================================================

func _animate_reveal_in() -> void:
	if (
		_reveal_tween != null
		and _reveal_tween.is_valid()
	):
		_reveal_tween.kill()


	var materials := _get_materials_in_reveal_order()


	for material: ShaderMaterial in materials:
		material.set_shader_parameter(
			SHADER_REVEAL,
			0.0
		)


	_reveal_tween = create_tween()

	_reveal_tween.set_parallel(true)


	for i: int in range(materials.size()):
		var material: ShaderMaterial = materials[i]


		_reveal_tween.tween_method(
			_set_shader_reveal.bind(material),
			0.0,
			1.0,
			reveal_time
		).set_delay(
			float(i) * reveal_stagger
		)


func _animate_reveal_out() -> void:
	if (
		_reveal_tween != null
		and _reveal_tween.is_valid()
	):
		_reveal_tween.kill()


	var materials := _get_materials_in_reveal_order()


	_reveal_tween = create_tween()

	_reveal_tween.set_parallel(true)


	for material: ShaderMaterial in materials:
		var current: float = _get_shader_reveal(
			material
		)


		_reveal_tween.tween_method(
			_set_shader_reveal.bind(material),
			current,
			0.0,
			hide_time
		)


	_reveal_tween.finished.connect(
		_finish_hide
	)


func _set_shader_reveal(
	value: float,
	material: ShaderMaterial
) -> void:
	if material == null:
		return

	material.set_shader_parameter(
		SHADER_REVEAL,
		value
	)


func _get_shader_reveal(
	material: ShaderMaterial
) -> float:
	if material == null:
		return 0.0


	var value: Variant = material.get_shader_parameter(
		SHADER_REVEAL
	)


	if value is float:
		return value


	return 0.0


func _set_all_reveal(
	value: float
) -> void:
	for material: ShaderMaterial in _get_materials_in_reveal_order():
		material.set_shader_parameter(
			SHADER_REVEAL,
			value
		)


# ============================================================================
# FOCUS
# ============================================================================

func _focus_next_clockwise() -> void:
	_focus_index += 1


	if _focus_index >= _focus_order.size():
		_focus_index = 0


	_refresh_focus_visuals(true)


func _refresh_focus_visuals(
	animate: bool
) -> void:
	var focus: int = _focus_order[
		_focus_index
	]


	var hands_target: Color = (
		active_color
		if focus == FocusSlot.HANDS
		else inactive_color
	)

	var thigh_target: Color = (
		active_color
		if focus == FocusSlot.THIGH_LEFT
		else inactive_color
	)

	var coat_left_target: Color = (
		active_color
		if focus == FocusSlot.COAT_LEFT
		else inactive_color
	)

	var coat_right_target: Color = (
		active_color
		if focus == FocusSlot.COAT_RIGHT
		else inactive_color
	)

	var pack_target: Color = (
		active_color
		if focus == FocusSlot.PACK_LID
		else inactive_color
	)


	if not animate or focus_transition_time <= 0.0:
		_set_shader_color(
			hands_target,
			_hands_material
		)

		_set_shader_color(
			thigh_target,
			_thigh_left_material
		)

		_set_shader_color(
			coat_left_target,
			_coat_left_material
		)

		_set_shader_color(
			coat_right_target,
			_coat_right_material
		)

		_set_shader_color(
			pack_target,
			_pack_lid_material
		)

		return


	if (
		_focus_tween != null
		and _focus_tween.is_valid()
	):
		_focus_tween.kill()


	_focus_tween = create_tween()

	_focus_tween.set_parallel(true)


	_tween_shader_color(
		_focus_tween,
		_hands_material,
		hands_target
	)

	_tween_shader_color(
		_focus_tween,
		_thigh_left_material,
		thigh_target
	)

	_tween_shader_color(
		_focus_tween,
		_coat_left_material,
		coat_left_target
	)

	_tween_shader_color(
		_focus_tween,
		_coat_right_material,
		coat_right_target
	)

	_tween_shader_color(
		_focus_tween,
		_pack_lid_material,
		pack_target
	)


func _tween_shader_color(
	tween: Tween,
	material: ShaderMaterial,
	target: Color
) -> void:
	if material == null:
		return


	var current: Color = _get_shader_color(
		material
	)


	tween.tween_method(
		_set_shader_color.bind(material),
		current,
		target,
		focus_transition_time
	)


func _set_shader_color(
	value: Color,
	material: ShaderMaterial
) -> void:
	if material == null:
		return


	material.set_shader_parameter(
		SHADER_BASE_COLOR,
		value
	)


func _get_shader_color(
	material: ShaderMaterial
) -> Color:
	if material == null:
		return inactive_color


	var value: Variant = material.get_shader_parameter(
		SHADER_BASE_COLOR
	)


	if value is Color:
		return value


	return inactive_color


# ============================================================================
# CONFIRM
# ============================================================================

func _confirm_focus() -> void:
	var focus: int = _focus_order[
		_focus_index
	]


	# HANDS — оставить текущее состояние рук.
	if focus == FocusSlot.HANDS:
		hide_quick_access()

		return


	var pocket_index: int = _find_pocket_index(
		focus
	)


	if pocket_index < 0:
		hide_quick_access()

		return


	if quick_access_component == null:
		push_warning(
			"QuickAccessUI: QuickAccessComponent is not assigned."
		)

		hide_quick_access()

		return


	quick_access_component.select(
		pocket_index
	)


	quick_access_component.use_selected()


	hide_quick_access()


func _find_pocket_index(
	focus: int
) -> int:
	if quick_access_component == null:
		return -1


	if quick_access_component.hub == null:
		return -1


	var target_path: StringName


	match focus:
		FocusSlot.COAT_LEFT:
			target_path = &"torso_outer/coat_left"

		FocusSlot.COAT_RIGHT:
			target_path = &"torso_outer/coat_right"

		FocusSlot.THIGH_LEFT:
			target_path = &"legs_outer/thigh_left"

		FocusSlot.PACK_LID:
			target_path = &"pack/pack_lid"

		_:
			return -1


	var zones: Array[Dictionary] = (
		quick_access_component.hub.get_quick_access_zones()
	)


	for i: int in range(zones.size()):
		if StringName(zones[i]["path"]) == target_path:
			return i


	return -1


# ============================================================================
# ORBIT
# ============================================================================

func _update_anchor_orbit(
	camera: Camera3D,
	delta: float
) -> void:
	if anchor_root == null:
		return


	var direction: Vector3 = (
		camera.global_position
		- anchor_root.global_position
	)


	direction.y = 0.0


	if direction.length_squared() <= 0.000001:
		return


	direction = direction.normalized()


	var target_yaw: float = atan2(
		direction.x,
		direction.z
	)


	target_yaw += deg_to_rad(
		orbit_yaw_offset_degrees
	)


	var blend: float = (
		1.0
		- exp(
			-orbit_follow_speed * delta
		)
	)


	var rotation_now: Vector3 = (
		anchor_root.global_rotation
	)


	rotation_now.y = lerp_angle(
		rotation_now.y,
		target_yaw,
		blend
	)


	anchor_root.global_rotation = rotation_now


# ============================================================================
# FOLLOW
# ============================================================================

func _follow(
	slot: Control,
	anchor: Node3D,
	screen_offset: Vector2,
	camera: Camera3D,
	delta: float
) -> void:
	if anchor == null:
		slot.visible = false

		return


	if camera.is_position_behind(
		anchor.global_position
	):
		slot.visible = false

		return


	slot.visible = true


	var screen_position: Vector2 = (
		camera.unproject_position(
			anchor.global_position
		)
	)


	var target_position: Vector2 = (
		screen_position
		- slot.size * 0.5
		+ screen_offset
	)


	var blend: float = (
		1.0
		- exp(
			-follow_speed * delta
		)
	)


	slot.position = slot.position.lerp(
		target_position,
		blend
	)


# ============================================================================
# SNAP
# ============================================================================

func _snap_all() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()


	if camera == null:
		return


	if orbit_enabled:
		_snap_orbit(
			camera
		)


	_snap(
		coat_left,
		coat_left_anchor,
		coat_left_offset,
		camera
	)

	_snap(
		coat_right,
		coat_right_anchor,
		coat_right_offset,
		camera
	)

	_snap(
		thigh_left,
		thigh_left_anchor,
		thigh_left_offset,
		camera
	)

	_snap(
		pack_lid,
		pack_lid_anchor,
		pack_lid_offset,
		camera
	)

	_snap(
		hands,
		hands_anchor,
		hands_offset,
		camera
	)


func _snap_orbit(
	camera: Camera3D
) -> void:
	if anchor_root == null:
		return


	var direction: Vector3 = (
		camera.global_position
		- anchor_root.global_position
	)


	direction.y = 0.0


	if direction.length_squared() <= 0.000001:
		return


	direction = direction.normalized()


	var target_yaw: float = atan2(
		direction.x,
		direction.z
	)


	target_yaw += deg_to_rad(
		orbit_yaw_offset_degrees
	)


	var rotation_now: Vector3 = (
		anchor_root.global_rotation
	)


	rotation_now.y = target_yaw


	anchor_root.global_rotation = rotation_now


func _snap(
	slot: Control,
	anchor: Node3D,
	screen_offset: Vector2,
	camera: Camera3D
) -> void:
	if anchor == null:
		return


	if camera.is_position_behind(
		anchor.global_position
	):
		return


	var screen_position: Vector2 = (
		camera.unproject_position(
			anchor.global_position
		)
	)


	slot.position = (
		screen_position
		- slot.size * 0.5
		+ screen_offset
	)


# ============================================================================
# VISIBILITY
# ============================================================================

func _set_visible_state(
	value: bool
) -> void:
	coat_left.visible = value
	coat_right.visible = value
	thigh_left.visible = value
	pack_lid.visible = value
	hands.visible = value


# ============================================================================
# MOUSE
# ============================================================================

func _make_mouse_transparent(
	node: Node
) -> void:
	if node is Control:
		var control := node as Control

		control.mouse_filter = Control.MOUSE_FILTER_IGNORE


	for child: Node in node.get_children():
		_make_mouse_transparent(
			child
		)


# ============================================================================
# TEST LABELS
# ============================================================================

func _set_test_labels() -> void:
	$CoatLeft/Label.text = "COAT L"
	$CoatRight/Label.text = "COAT R"
	$ThighLeft/Label.text = "THIGH L"
	$PackLid/Label.text = "PACK"
	$Hands/Label.text = "HANDS"

class_name BackpackLoadBanner
extends Node3D

## World-owned diegetic carry-load readout. Its texture comes from a transparent
## SubViewport; the physical anchor remains on the backpack's deforming handle.
const SHOW_SECONDS: float = 2.8
const FOLLOW_SPEED: float = 9.0
const APPEAR_SPEED: float = 9.0
const LOAD_SPEED: float = 7.0
const MIN_CAMERA_DISTANCE: float = 0.95
const CLEARANCE_TOWARD_CAMERA: float = 0.30
const HEIGHT_ABOVE_HANDLE: float = 0.20
const SIDE_OFFSET: float = 0.25
const NORMAL_COLOR: Color = Color(0.72, 0.71, 0.63, 0.94)
const HEAVY_COLOR: Color = Color(0.87, 0.68, 0.38, 0.96)

@onready var _surface: Sprite3D = $Billboard
@onready var _viewport: SubViewport = $BannerViewport
@onready var _background: ColorRect = $BannerViewport/Card/Background
@onready var _fill: ColorRect = $BannerViewport/Card/Fill
@onready var _title: Label = $BannerViewport/Card/Title
@onready var _value: Label = $BannerViewport/Card/Value

var _player: Player
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _hub: PlayerHubComponent
var _quick: QuickAccessUI
var _visual: HenryUALAnimation
var _target_kg: float = 0.0
var _shown_kg: float = 0.0
var _maximum_kg: float = 0.0
var _visible_left: float = 0.0
var _appearance: float = 0.0
var _position_ready: bool = false
var _refresh_queued: bool = false
var _side: float = 1.0


func bind_player(player: Player, quick: QuickAccessUI) -> void:
	_player = player
	_quick = quick
	if player == null:
		return
	_visual = player.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation
	_inventory = player.get_node_or_null(^"InventoryComponent") as InventoryComponent
	_equipment = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	_hub = player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if _inventory == null:
		push_error("BackpackLoadBanner: InventoryComponent is missing.")
		return
	_target_kg = _inventory.get_total_weight()
	_shown_kg = _target_kg
	_maximum_kg = _inventory.max_carry_weight
	_inventory.weight_changed.connect(_queue_weight_refresh)
	if _equipment != null:
		_equipment.slot_changed.connect(_on_equipment_changed)


func _ready() -> void:
	_surface.texture = _viewport.get_texture()
	_surface.visible = false
	_title.text = tr("LOAD_BANNER_TITLE")
	_update_text_and_fill()
	set_process(true)


func _queue_weight_refresh(_total_kg: float, _maximum: float) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred(&"_refresh_weight")


func _on_equipment_changed(_slot: StringName, _item_id: StringName) -> void:
	_queue_weight_refresh(0.0, 0.0)


## Coalesce inventory transfers and equipment swaps after the final storage state.
func _refresh_weight() -> void:
	_refresh_queued = false
	if not is_instance_valid(_inventory):
		return
	var updated_kg: float = _inventory.get_total_weight()
	var updated_maximum: float = _inventory.max_carry_weight
	if absf(updated_kg - _target_kg) < 0.01 and is_equal_approx(updated_maximum, _maximum_kg):
		return
	_target_kg = updated_kg
	_maximum_kg = updated_maximum
	_visible_left = SHOW_SECONDS


func _process(delta: float) -> void:
	if _inventory == null or _visual == null:
		return
	var smooth_load: float = 1.0 - exp(-LOAD_SPEED * maxf(delta, 0.0))
	_shown_kg = lerpf(_shown_kg, _target_kg, smooth_load)
	_update_text_and_fill()
	_visible_left = maxf(0.0, _visible_left - delta)

	var camera := get_viewport().get_camera_3d()
	var anchor := _load_anchor()
	var can_show := _visible_left > 0.0 and camera != null and anchor != null
	can_show = can_show and (_hub == null or not _hub.is_open())
	can_show = can_show and (_quick == null or not _quick.is_open())
	var camera_factor: float = 1.0
	if can_show:
		var distance: float = camera.global_position.distance_to(anchor.global_position)
		if distance < MIN_CAMERA_DISTANCE:
			can_show = false
		if camera is TpsCamera:
			camera_factor = 1.0 - smoothstep(0.55, 0.85, (camera as TpsCamera).get_composition())
		if camera_factor < 0.05:
			can_show = false
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		var anchor_screen: Vector2 = camera.unproject_position(anchor.global_position)
		if camera.is_position_behind(anchor.global_position) or not Rect2(view_size * 0.08, view_size * 0.84).has_point(anchor_screen):
			can_show = false
		if can_show:
			if anchor_screen.x > view_size.x * 0.76:
				_side = -1.0
			elif anchor_screen.x < view_size.x * 0.56:
				_side = 1.0
			var direction: Vector3 = (camera.global_position - anchor.global_position).normalized()
			var destination: Vector3 = anchor.global_position + Vector3.UP * HEIGHT_ABOVE_HANDLE
			destination += camera.global_basis.x * (_side * SIDE_OFFSET) + direction * CLEARANCE_TOWARD_CAMERA
			if not _position_ready:
				global_position = destination
				_position_ready = true
			else:
				global_position = global_position.lerp(destination, 1.0 - exp(-FOLLOW_SPEED * maxf(delta, 0.0)))
	_appearance = lerpf(_appearance, 1.0 if can_show else 0.0, 1.0 - exp(-APPEAR_SPEED * maxf(delta, 0.0)))
	(_background.material as ShaderMaterial).set_shader_parameter(&"reveal", _appearance)
	_surface.modulate = Color(1.0, 1.0, 1.0, _appearance * camera_factor)
	_surface.visible = _surface.modulate.a > 0.015


func _load_anchor() -> Node3D:
	if _visual == null or _visual.is_pack_down():
		return null
	if _equipment != null and _equipment.get_equipped(&"pack") == &"":
		return null
	var rig: PackRig = _visual.get_pack_rig()
	if rig == null or not rig.is_visible_in_tree():
		return null
	var canvas: BackpackModel = rig.get_canvas()
	return canvas.get_load_anchor() if canvas != null else null


func _update_text_and_fill() -> void:
	if _fill == null:
		return
	_value.text = tr("LOAD_BANNER_VALUE") % [_shown_kg, _maximum_kg]
	var fraction: float = clampf(_shown_kg / _maximum_kg, 0.0, 1.0) if _maximum_kg > 0.0 else 0.0
	var material := _fill.material as ShaderMaterial
	material.set_shader_parameter(&"fill_fraction", fraction)
	var heavy: float = smoothstep(0.68, 0.97, fraction)
	material.set_shader_parameter(&"fill_color", NORMAL_COLOR.lerp(HEAVY_COLOR, heavy))

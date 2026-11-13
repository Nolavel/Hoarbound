class_name IceLabDirector
extends Node3D

## Isolated thin-ice lab: Henry walks out from a shore, the ice creaks, cracks and gives way.
## Owns only lab glue (water, climb-out, camera shake); the ice rules stay in IceField.

## Seconds of game-hour billing per real second while submerged; the lab has no clock.
const HOURS_PER_SECOND: float = 1.0 / 3600.0
## Henry's capsule clearance inside a hole, in metres.
const HOLE_CLEARANCE_M: float = 0.35
## How far beyond the hole's rim Henry is placed when he climbs out.
const CLIMB_OUT_MARGIN_M: float = 0.55

@export_group("Wiring")
@export var henry: CharacterBody3D
@export var camera: Camera3D
## Body carrying the ice collision; Henry ignores it while in the water.
@export var ice_body: StaticBody3D
@export var ice_field: IceField
@export var immersion: ColdWaterImmersion
@export var presenter: IceCrackPresenter
@export var spawn: Marker3D

@export_group("UI")
@export var stage_label: Label
@export var detail_label: Label
@export var hint_label: Label

@export_group("Shake")
## Peak camera offset in metres at full strength.
@export var shake_amplitude_m: float = 0.06

var _in_water: bool = false
## Henry's origin height above the surface he stands on, measured while he stands.
var _stand_height: float = 1.0
var _hole_tile: Vector2i = IceCrackPresenter.NO_TILE
var _hole_centre: Vector3 = Vector3.ZERO
var _shake_strength: float = 0.0
var _shake_left: float = 0.0
var _shake_time: float = 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	process_priority = 1000
	_noise.frequency = 3.0
	if spawn != null and henry != null:
		henry.global_transform = spawn.global_transform
	if immersion != null:
		immersion.immersion_started.connect(_on_immersion_started)
		immersion.climbed_out.connect(_on_climbed_out)
	if presenter != null:
		presenter.shake_requested.connect(_on_shake_requested)


func _physics_process(delta: float) -> void:
	if henry == null or immersion == null:
		return
	if _in_water:
		immersion.step(delta, delta * HOURS_PER_SECOND)
		_keep_inside_hole()
		if immersion.can_climb_out() and Input.is_action_just_pressed(&"interact"):
			climb_out()
		return
	if henry.is_on_floor():
		_stand_height = henry.global_position.y - ice_field.global_position.y
	if presenter != null and presenter.is_in_hole(henry.global_position):
		immersion.submerge(henry.global_position)


func _process(delta: float) -> void:
	_update_shake(delta)
	_update_labels()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		get_tree().reload_current_scene()


## Whether Henry is in the water right now.
func is_in_water() -> bool:
	return _in_water


## Pulls Henry out onto the rim on the side he is facing the hole from.
func climb_out() -> bool:
	var away := Vector3(henry.global_position.x - _hole_centre.x, 0.0, henry.global_position.z - _hole_centre.z)
	if away.length() < 0.05:
		away = -henry.global_basis.z
	away = away.normalized()
	var angle: float = atan2(away.z, away.x)
	var radius: float = IceHoleShape.radius_at(_hole_tile, angle) + CLIMB_OUT_MARGIN_M
	var rim: Vector3 = _hole_centre + away * radius
	rim.y = ice_field.global_position.y + _stand_height
	if not immersion.climb_out(rim):
		return false
	henry.global_position = rim
	henry.velocity = Vector3.ZERO
	return true


func _on_immersion_started(world_position: Vector3) -> void:
	_in_water = true
	if ice_body != null:
		henry.add_collision_exception_with(ice_body)
	_bind_hole.call_deferred(world_position)


## The presenter learns about a new hole after the immersion does, so look it up a frame later.
func _bind_hole(world_position: Vector3) -> void:
	_hole_tile = presenter.hole_at(world_position)
	if _hole_tile == IceCrackPresenter.NO_TILE:
		_hole_tile = ice_field.world_to_tile(world_position)
	_hole_centre = presenter.get_hole_centre(_hole_tile)


func _on_climbed_out(_world_position: Vector3) -> void:
	_in_water = false
	if ice_body != null:
		henry.remove_collision_exception_with(ice_body)


## Under the ice there is only the lake bed: Henry may not wade out beneath it.
func _keep_inside_hole() -> void:
	if _hole_tile == IceCrackPresenter.NO_TILE:
		return
	var offset := Vector3(henry.global_position.x - _hole_centre.x, 0.0, henry.global_position.z - _hole_centre.z)
	var limit: float = IceHoleShape.radius_at(_hole_tile, atan2(offset.z, offset.x)) - HOLE_CLEARANCE_M
	if offset.length() > limit and limit > 0.0:
		var clamped: Vector3 = _hole_centre + offset.normalized() * limit
		henry.global_position = Vector3(clamped.x, henry.global_position.y, clamped.z)


func _on_shake_requested(strength: float, seconds: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_left = maxf(_shake_left, seconds)


## Offsets only; TpsCamera rewrites h_offset each frame, so this runs after it.
func _update_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_left <= 0.0:
		_shake_strength = 0.0
		camera.v_offset = 0.0
		return
	_shake_left -= delta
	_shake_time += delta
	var amount: float = _shake_strength * shake_amplitude_m * clampf(_shake_left / 0.25, 0.0, 1.0)
	camera.h_offset = _noise.get_noise_1d(_shake_time * 40.0) * amount
	camera.v_offset = _noise.get_noise_1d(_shake_time * 40.0 + 100.0) * amount


func _update_labels() -> void:
	if ice_field == null or henry == null:
		return
	var tile: Vector2i = ice_field.world_to_tile(henry.global_position)
	var stage: IceField.Stage = ice_field.get_stage(tile)
	var base: float = maxf(0.0001, ice_field.get_base_thickness(tile))
	var shore_m: float = ice_field.distance_to_shore(Vector2(henry.global_position.x, henry.global_position.z))
	if stage_label != null:
		stage_label.text = tr(&"ICE_LAB_IN_WATER") if _in_water else tr(_stage_key(stage, shore_m))
	if detail_label != null:
		detail_label.text = "%s %.0f%%   %s %.1f m" % [
			tr(&"ICE_LAB_INTEGRITY"), ice_field.get_integrity(tile) / base * 100.0,
			tr(&"ICE_LAB_SHORE"), maxf(0.0, shore_m),
		]
	if hint_label != null:
		hint_label.visible = _in_water and immersion.can_climb_out()


func _stage_key(stage: IceField.Stage, shore_m: float) -> StringName:
	if shore_m < 0.0:
		return &"ICE_LAB_ON_SHORE"
	match stage:
		IceField.Stage.CREAKING:
			return &"ICE_STAGE_CREAKING"
		IceField.Stage.CRACKING:
			return &"ICE_STAGE_CRACKING"
		IceField.Stage.BROKEN:
			return &"ICE_STAGE_BROKEN"
		_:
			return &"ICE_STAGE_SOLID"

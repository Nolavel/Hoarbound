class_name LighterStrikeVFX
extends Node3D

## The authored lighter for the stove act: a strike jerk, sparks and a hold-controlled flame.
## Origin is the grip on the nozzle axis; the flame stands on the nozzle and always burns world-up.
## Nozzle above the grip origin, along the lighter's local +Y.
const NOZZLE := Vector3(0.0, 0.038, 0.0)

var _flame: LighterFlame
var _strike_tween: Tween
var _rest_rotation: Vector3
var _flame_on: bool = false


func _ready() -> void:
	var model: Node3D = SurvivalItemVisual.make(&"lighter")
	model.position = NOZZLE - SurvivalItemVisual.LIGHTER_NOZZLE
	add_child(model)
	_flame = LighterFlame.new()
	_flame.position = NOZZLE
	_flame.wheel = model.find_child("Lighter_v2_Wheel", true, false) as Node3D
	add_child(_flame)
	set_flame(_flame_on)


func strike(success: bool) -> void:
	if _strike_tween != null:
		_strike_tween.kill()
	else:
		_rest_rotation = rotation
	rotation = _rest_rotation
	_strike_tween = create_tween()
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation + Vector3(-0.16, 0.0, 0.10), 0.07)
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation, 0.13)
	_flame.strike()
	set_flame(success)


func set_flame(active: bool) -> void:
	_flame_on = active
	if _flame != null:
		_flame.set_lit(active)


func is_flame_visible() -> bool:
	return _flame_on and _flame != null and _flame.is_lit()


## World point of the nozzle, where the flame stands.
func get_flame_tip() -> Vector3:
	return to_global(NOZZLE)

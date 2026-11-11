class_name IceGaitBinder
extends Node

## Translates how Henry is moving into the load he puts on the ice. Reads the
## movement controller rather than editing it, so ownership stays clean.

## Emitted when the reported gait changes, for audio and animation to follow.
signal gait_changed(gait: IceField.Gait)

@export_group("Wiring")
@export var ice_field: IceField
## Body supplying the velocity; usually Henry's CharacterBody3D.
@export var character_body: CharacterBody3D
## Optional. When set, its sprint state wins over the speed threshold.
@export var movement_controller: MovementController

## Optional. Its fill adds load: a full pack is heavier on thin ice.
@export var inventory: InventoryComponent

@export_group("Carry")
## Extra ice load at a full pack, as a fraction of the gait's own load. Tuned
## so a loaded walk across the thinnest bay ice cracks it but holds.
@export var carry_load_factor: float = 0.6

@export_group("Thresholds")
## Horizontal speed below which Henry counts as standing still, in m/s.
@export var still_speed_mps: float = 0.35
## Horizontal speed at or above which he counts as sprinting, in m/s. Ignored
## when a movement controller is wired.
@export var sprint_speed_mps: float = 3.5

@export_group("Crouch")
## Legacy scene compatibility. Runtime crouch prefers MovementController.
@export var crouch_action: StringName = &"crouch"

var _gait: IceField.Gait = IceField.Gait.STILL


func on_world_ready(context: WorldContext) -> void:
	if character_body == null:
		character_body = context.player as CharacterBody3D
	_resolve_movement_controller()


func _resolve_movement_controller() -> void:
	if movement_controller != null or character_body == null:
		return
	movement_controller = character_body.get_node_or_null(^"MovementController") as MovementController


func _physics_process(_delta: float) -> void:
	if character_body == null:
		return
	apply(character_body.velocity)


## Classifies a velocity and pushes the result to the field.
func apply(velocity: Vector3) -> IceField.Gait:
	var gait: IceField.Gait = classify(velocity)
	if gait != _gait:
		_gait = gait
		gait_changed.emit(gait)
	if ice_field != null:
		ice_field.set_gait(gait)
		ice_field.set_load_multiplier(get_load_multiplier())
	return gait


## Ice load multiplier from what Henry carries, 1.0 with an empty pack.
func get_load_multiplier() -> float:
	if inventory == null and character_body != null and character_body.is_in_group(&"player"):
		inventory = InventoryComponent.find_in(character_body)
	if inventory == null:
		return 1.0
	return 1.0 + inventory.get_load_fraction() * carry_load_factor


## Gait for a velocity, without touching the field. Public so the HUD and the
## tests can ask the same question the binder answers.
func classify(velocity: Vector3) -> IceField.Gait:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed < still_speed_mps:
		return IceField.Gait.CROUCH if _is_crouching() else IceField.Gait.STILL
	if _is_crouching():
		return IceField.Gait.CROUCH
	if _is_sprinting(velocity, speed):
		return IceField.Gait.SPRINT
	return IceField.Gait.WALK


## Last gait reported to the field.
func get_gait() -> IceField.Gait:
	return _gait


func _is_sprinting(velocity: Vector3, speed: float) -> bool:
	_resolve_movement_controller()
	if movement_controller != null:
		return movement_controller.is_currently_sprinting(velocity)
	return speed >= sprint_speed_mps


func _is_crouching() -> bool:
	_resolve_movement_controller()
	if movement_controller != null:
		return movement_controller.is_crouching()
	var input_systems := get_node_or_null(^"/root/InputSystems") as InputSystemsService
	if input_systems != null:
		return input_systems.is_crouching()
	return false

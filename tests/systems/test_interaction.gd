extends SceneTree

## InteractComponent: picks the target before Henry with the camera turned away,
## acts at arm's length, walks to a farther one, ignores what is behind him even
## in the middle of the frame, and tells two close items apart by his turn.
## Run: godot --headless --script tests/systems/test_interaction.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
## A body with the walk contract; the walk arrives at once.
const WALKER_SOURCE: String = """extends CharacterBody3D
signal movement_stopped
func move_to_position(point: Vector3) -> void:
	global_position = point
func stop_moving() -> void:
	movement_stopped.emit()
"""

var _failures: int = 0
var _frame: int = 0
var _player: CharacterBody3D
var _component: InteractComponent
var _inventory: InventoryComponent
var _near: ItemPickup
var _far: ItemPickup
var _behind: ItemPickup
var _pair_left: ItemPickup
var _pair_right: ItemPickup
var _camera: Camera3D
var _target_seen_during_performed: InteractiveArea


## Stages step on physics frames: detection and the walk both run there.
func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		4:
			_check_near_without_camera_aim()
		7:
			_check_far_next()
		10:
			_check_after_walk()
			## Camera behind Henry: the item at his back sits between them, mid-frame.
			_player.global_position = Vector3.ZERO
			_camera.global_position = Vector3(0.0, 1.6, 3.5)
			_camera.look_at(Vector3(0.0, 0.0, -2.0), Vector3.UP)
		13:
			_check_behind_ignored()
			_face_pair(0.5)
		16:
			_check(_component.current_target == _pair_left, "turned left, Henry did not pick the left of two close items")
			_player.rotation.y = -0.5
		19:
			_check(_component.current_target == _pair_right, "turned right, Henry stayed on the left of two close items")
			_finish()
	return false


func _build() -> void:
	var walker := GDScript.new()
	walker.source_code = WALKER_SOURCE
	walker.reload()
	_player = CharacterBody3D.new()
	_player.set_script(walker)
	_player.add_to_group("player")
	var body_shape := CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	_player.add_child(body_shape)
	_inventory = InventoryComponent.new()
	_inventory.max_carry_weight = 60.0
	_player.add_child(_inventory)
	_component = InteractComponent.new()
	_player.add_child(_component)
	_component.interaction_performed.connect(func(_target: InteractiveArea) -> void:
		_target_seen_during_performed = _component.current_target)
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)
	_camera.look_at(Vector3(2.0, 0.0, -1.0), Vector3.UP)
	_near = _spawn(Vector3(0.0, 0.0, -0.6))
	_far = _spawn(Vector3(0.3, 0.0, -2.2))
	_behind = _spawn(Vector3(0.0, 0.0, 2.0))
	_pair_left = _spawn(Vector3(19.85, 0.0, -0.7))
	_pair_right = _spawn(Vector3(20.15, 0.0, -0.7))


func _spawn(at: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = &"firewood"
	pickup.position = at
	root.add_child(pickup)
	return pickup


## The camera looks off to the side; the item in front of Henry still wins.
func _check_near_without_camera_aim() -> void:
	_check(_component.current_target == _near, "the item at arm's length is not the target")
	_check(_near.prompt_shown, "the targeted item at arm's length shows no F prompt")
	_check(_component.is_target_in_reach(), "the item at 0.6 m is not in reach")
	_component.try_interact()
	_check(_inventory.get_count(&"firewood") == 1, "F did not pick up the near item")
	_check(_component.current_target == null, "picked-up item stayed as current target")
	_check(_target_seen_during_performed == null,
		"interaction_performed fired before consumed pickup focus was cleared")
	_check(not _near.prompt_shown, "picked-up item left the F prompt active")


func _check_far_next() -> void:
	_check(_component.current_target == _far, "the item 2.2 m ahead is not the next target")
	_check(not _component.is_target_in_reach(), "the item 2.2 m ahead counts as in reach")
	_component.try_interact()


func _check_after_walk() -> void:
	_check(_inventory.get_count(&"firewood") == 2, "Henry did not walk over and pick up the far item")


func _check_behind_ignored() -> void:
	_check(_component.current_target == null, "an item at Henry's back was targeted from mid-frame")
	_check(_inventory.get_count(&"firewood") == 2, "something else was picked up")


## Henry stands 0.7 m before two items 0.3 m apart; the camera looks between them.
func _face_pair(turn: float) -> void:
	_player.global_position = Vector3(20.0, 0.0, 0.0)
	_player.rotation.y = turn
	_camera.global_position = Vector3(20.0, 1.6, 3.5)
	_camera.look_at(Vector3(20.0, 0.0, -0.7), Vector3.UP)


func _finish() -> void:
	if _failures > 0:
		push_error("interaction: %d check(s) failed" % _failures)
		quit(1)
		return
	print("interaction: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("interaction: %s" % message)

extends SceneTree

## Interaction grammar: Henry's head attention picks the pickup, the player's view
## picks the world mechanism, and the world mechanism wins F.
## Run: godot --headless --script tests/systems/test_interaction.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
## A body whose head attention is set directly; its walk arrives at once.
const WALKER_SOURCE: String = """extends CharacterBody3D
signal movement_stopped
var attention_yaw: float = 0.0
func get_attention_origin() -> Vector3:
	return global_position + Vector3.UP * 0.62
func get_attention_direction() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, attention_yaw)
func move_to_position(point: Vector3) -> void:
	global_position = point
func stop_moving() -> void:
	movement_stopped.emit()
"""
## A world mechanism that counts its uses and can be switched off.
const MECHANISM_SOURCE: String = """extends InteractiveArea
var uses: int = 0
var enabled: bool = true
func can_interact() -> bool:
	return enabled and super()
func _on_interaction_performed() -> void:
	uses += 1
"""

var _failures: int = 0
var _player: CharacterBody3D
var _component: InteractComponent
var _inventory: InventoryComponent
var _camera: Camera3D
var _left: ItemPickup
var _middle: ItemPickup
var _right: ItemPickup
var _behind: ItemPickup
var _mechanism: InteractiveArea
var _target_seen_during_performed: InteractiveArea = null


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build()
	await _frames(2)
	await _check_head_attention_picks()
	await _check_noise_does_not_flicker()
	await _check_behind_never_offered()
	await _check_walking_keeps_head_attention()
	await _check_world_wins_f()
	await _check_disabled_world_not_authoritative()
	await _check_consumed_pickup_clears_at_once()
	await _check_far_pickup_walks_over()
	if _failures > 0:
		push_error("interaction: %d check(s) failed" % _failures)
		print("test_interaction: %d FAILED" % _failures)
		quit(1)
		return
	print("interaction: all checks passed")
	quit(0)


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
		_target_seen_during_performed = _component.get_pickup_target())
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)
	_camera.global_position = Vector3(0.0, 1.6, 3.0)
	_camera.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	## Three items 0.5 m apart on an arc 1.0 m before Henry, one behind him.
	_left = _spawn(_on_arc(deg_to_rad(30.0), 1.0))
	_middle = _spawn(_on_arc(0.0, 1.0))
	_right = _spawn(_on_arc(deg_to_rad(-30.0), 1.0))
	_behind = _spawn(Vector3(0.0, 0.0, 1.0))
	var mechanism_script := GDScript.new()
	mechanism_script.source_code = MECHANISM_SOURCE
	mechanism_script.reload()
	_mechanism = (load(AREA_SCENE) as PackedScene).instantiate() as InteractiveArea
	_mechanism.set_script(mechanism_script)
	_mechanism.position = Vector3(0.75, 0.9, -0.25)
	root.add_child(_mechanism)


func _on_arc(yaw: float, distance: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw) * distance


func _spawn(at: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = &"firewood"
	pickup.position = at
	root.add_child(pickup)
	return pickup


## Body fixed, only the head turns: the dominant pickup follows it A -> B -> C.
func _check_head_attention_picks() -> void:
	for step: Array in [[30.0, _left, "left"], [0.0, _middle, "middle"], [-30.0, _right, "right"]]:
		_player.set(&"attention_yaw", deg_to_rad(float(step[0])))
		await _frames(2)
		_check(_component.get_pickup_target() == step[1], "head at %s° did not pick the %s item" % [step[0], step[2]])
	_check(_player.rotation.y == 0.0, "the body turned during the head-attention check")
	_check(_component.get_world_target() == null, "a pickup became the world target")
	_check(not _middle.prompt_shown and not _left.prompt_shown, "a pickup raised the central world prompt")


## Small head noise around one item never swaps it for the neighbour.
func _check_noise_does_not_flicker() -> void:
	_player.set(&"attention_yaw", 0.0)
	await _frames(2)
	var switches: int = 0
	var last: InteractiveArea = _component.get_pickup_target()
	var rng := RandomNumberGenerator.new()
	rng.seed = 198
	## Halfway between two items is the hardest place: noise must not toggle them.
	for _i: int in range(40):
		_player.set(&"attention_yaw", deg_to_rad(15.0 + rng.randf_range(-2.0, 2.0)))
		await _frames(1)
		if _component.get_pickup_target() != last:
			switches += 1
			last = _component.get_pickup_target()
	_check(switches <= 1, "head noise of ±2° switched the dominant pickup %d times" % switches)


func _check_behind_never_offered() -> void:
	for yaw_deg: float in [0.0, 60.0, -60.0]:
		_player.set(&"attention_yaw", deg_to_rad(yaw_deg))
		await _frames(2)
		_check(_component.get_pickup_target() != _behind and not _component.get_pickup_candidates().has(_behind),
			"the item behind Henry's attention field was offered (head %d°)" % int(yaw_deg))


## Walking forward with the head turned left still picks by the head, not the torso.
func _check_walking_keeps_head_attention() -> void:
	_player.set(&"attention_yaw", deg_to_rad(30.0))
	_player.velocity = Vector3(0.0, 0.0, -2.0)
	await _frames(2)
	_check(_component.get_pickup_target() == _left, "walking replaced head attention with the torso facing")
	_player.velocity = Vector3.ZERO


## View on a mechanism, head on a pickup: F, the prompt and the active target go to the mechanism.
func _check_world_wins_f() -> void:
	_player.set(&"attention_yaw", 0.0)
	_aim_camera(_mechanism.get_focus_point(_player.global_position))
	await _frames(2)
	_check(_component.get_world_target() == _mechanism, "the mechanism under the view is not the world target")
	_check(_component.get_pickup_target() == _middle, "the view on a mechanism changed Henry's pickup attention")
	_check(_component.get_active_target() == _mechanism, "F does not belong to the world mechanism")
	_check(not _component.is_pickup_actionable(), "the pickup still promised F under a world interaction")
	_check(_mechanism.prompt_shown and not _middle.prompt_shown, "the central prompt did not come from the world target only")
	var count: int = _inventory.get_count(&"firewood")
	_component.try_interact()
	_check((_mechanism.get("uses") as int) == 1, "F did not act on the world mechanism")
	_check(_inventory.get_count(&"firewood") == count, "F took the pickup instead of the world mechanism")
	_aim_camera(Vector3(-3.0, 0.0, -3.0))
	await _frames(20)
	_check(_component.get_world_target() == null, "the world target outlived the view leaving it")
	_check(_component.is_pickup_actionable() and _component.get_active_target() == _middle,
		"the pickup did not take F back once the view left the mechanism")


func _check_disabled_world_not_authoritative() -> void:
	_aim_camera(_mechanism.get_focus_point(_player.global_position))
	await _frames(2)
	_mechanism.set(&"enabled", false)
	_check(_component.get_world_target() == null and _component.get_active_target() != _mechanism,
		"a disabled mechanism stayed authoritative")
	await _frames(1)
	_check(_component.world_target == null and not _mechanism.prompt_shown, "a disabled mechanism kept its prompt one frame later")
	_aim_camera(Vector3(-3.0, 0.0, -3.0))
	await _frames(2)


## A consumed pickup stops being authoritative before observers hear about it.
func _check_consumed_pickup_clears_at_once() -> void:
	_player.global_position = _middle.global_position + Vector3(0.0, 0.0, 0.6)
	_player.set(&"attention_yaw", 0.0)
	await _frames(2)
	_check(_component.get_pickup_target() == _middle, "the item at arm's length is not the dominant pickup")
	_check(_component.is_active_target_in_reach(), "the item at 0.6 m is not in reach")
	var count: int = _inventory.get_count(&"firewood")
	_component.try_interact()
	_check(_inventory.get_count(&"firewood") == count + 1, "F did not take the dominant pickup")
	_check(_component.get_pickup_target() == null and _component.get_active_target() == null,
		"the consumed pickup stayed authoritative")
	_check(_target_seen_during_performed == null, "interaction_performed fired before the consumed pickup was cleared")
	_player.global_position = Vector3.ZERO
	await _frames(1)


func _check_far_pickup_walks_over() -> void:
	var far: ItemPickup = _spawn(Vector3(0.3, 0.0, -2.2))
	_player.set(&"attention_yaw", 0.0)
	await _frames(2)
	_check(_component.get_pickup_target() == far, "the item 2.2 m ahead is not the dominant pickup")
	_check(not _component.is_active_target_in_reach(), "the item 2.2 m ahead counts as in reach")
	var count: int = _inventory.get_count(&"firewood")
	_component.try_interact()
	await _frames(3)
	_check(_inventory.get_count(&"firewood") == count + 1, "Henry did not walk over and take the far item")


func _aim_camera(point: Vector3) -> void:
	_camera.look_at(point, Vector3.UP)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("interaction: %s" % message)

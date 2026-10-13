extends SceneTree

## Proves a save participant can expose arbitrary Godot-visible method names
## through the shared capability layer without adding a Port node.

const TEST_SLOT: int = 5

var _failures: int = 0


class MappedSaveParticipant:
	extends Node

	var value: int = 0

	func stable_id() -> StringName:
		return &"mapped_capability"

	func snapshot() -> Dictionary:
		return {"value": value}

	func restore_snapshot(data: Dictionary) -> void:
		value = int(data.get("value", 0))


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var manager := SaveManager.new()
	root.add_child(manager)
	manager.delete_slot(TEST_SLOT)

	var participant := MappedSaveParticipant.new()
	root.add_child(participant)
	_check(
		SaveParticipantCapability.publish(
			participant,
			participant,
			&"stable_id",
			&"snapshot",
			&"restore_snapshot"
		),
		"explicit save capability mapping failed"
	)
	_check(
		CapabilityContract.has(participant, SaveParticipantCapability.ID),
		"published capability is not visible on the owner"
	)

	manager.register(participant)
	participant.value = 42
	_check(manager.save_to_slot(TEST_SLOT), "save through capability failed")
	participant.value = 1
	_check(manager.load_from_slot(TEST_SLOT), "load through capability failed")
	_check(participant.value == 42, "mapped provider did not restore its state")

	manager.delete_slot(TEST_SLOT)
	_dispose(participant)
	_dispose(manager)
	if _failures > 0:
		push_error("capability contract: %d check(s) failed" % _failures)
		quit(1)
		return
	print("capability contract: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("capability contract: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()

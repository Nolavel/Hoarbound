class_name SaveManager
extends Node

## Collects state from every participant and writes it atomically to a slot.
## Sleeping is the only thing that calls save() during play.
##
## Save participants are consumed through SaveParticipantCapability. Existing
## get_save_* nodes are adapted once at the contract boundary during migration.

## Emitted after a slot is written successfully.
signal save_completed(slot: int)
## Emitted when a save could not be written, with a human-readable reason.
signal save_failed(slot: int, reason: String)
## Emitted after a slot has been applied to every participant.
signal load_completed(slot: int)
## Emitted when a slot could not be loaded, with a human-readable reason.
signal load_failed(slot: int, reason: String)

## Nodes in this group are asked for their state when a save is written.
const SAVEABLE_GROUP: StringName = &"saveable"
const SAVE_DIR: String = "user://saves"
## Bumped whenever the payload layout changes; older files are migrated.
const SAVE_VERSION: int = 1
## Slot used by the autosave that sleeping performs.
const SLEEP_SLOT: int = 0

@export_group("Slots")
## Highest slot index the game offers, beyond the sleep autosave.
@export var max_slot: int = 5

var _last_error: String = ""
var _registered: Array[Node] = []

## Slot a menu asked for before the game scene existed, or -1 for a new game.
## Static because the menu and the world are different scenes.
static var pending_load_slot: int = -1


## The composition root's optional lifecycle hook. Everything this system
## needs is the already-built systems list.
func on_world_ready(context: WorldContext) -> void:
	for system: Node in context.systems:
		if system != self and implements_save_contract(system):
			register(system)
	## Inventory, equipment and the biomonitor live on the player, not in the
	## systems list, and a save without them is not Henry's save.
	_register_subtree(context.player)
	if pending_load_slot >= 0:
		## Deferred: systems later in the list adopt their scene state in their
		## own hook, and a load applied before that would be overwritten.
		_apply_pending_load.call_deferred()


func _register_subtree(node: Node) -> void:
	if node == null:
		return
	if node != self and implements_save_contract(node):
		register(node)
	for child: Node in node.get_children():
		_register_subtree(child)


## Applies and clears the slot the title menu asked for. Cleared first, so a
## failed load cannot loop the next time a world comes up.
func _apply_pending_load() -> void:
	var slot: int = pending_load_slot
	pending_load_slot = -1
	if not load_from_slot(slot):
		push_warning("SaveManager: could not continue from slot %d: %s" % [slot, _last_error])


## Registers a participant explicitly. Use this from _ready() when a system
## must be saved regardless of when the scene tree settles.
func register(node: Node) -> void:
	if node == null or _registered.has(node):
		return
	if not SaveParticipantCapability.ensure(node):
		push_warning("SaveManager: '%s' does not provide the save capability" % node.name)
		return
	_registered.append(node)


## Compatibility query for callers while save participants migrate to the
## capability layer. Reflection is contained inside SaveParticipantCapability.
static func implements_save_contract(node: Node) -> bool:
	return SaveParticipantCapability.ensure(node)


## Drops a participant; freed nodes are pruned automatically as well.
func unregister(node: Node) -> void:
	_registered.erase(node)


## Human-readable reason for the most recent failure, empty when none.
func get_last_error() -> String:
	return _last_error


## Writes every participant's state to the given slot. Returns true on success.
func save_to_slot(slot: int, metadata: Dictionary = {}) -> bool:
	if not _is_valid_slot(slot):
		return _fail_save(slot, "slot %d is out of range" % slot)

	var participants: Array[Node] = _get_participants()
	if participants.is_empty():
		return _fail_save(slot, "no save participants; refusing to write an empty save")

	var payload: Dictionary = {}
	for node: Node in participants:
		var id: String = _resolve_id(node)
		if payload.has(id):
			return _fail_save(slot, "duplicate save id '%s'" % id)
		var data: Variant = SaveParticipantCapability.capture(node)
		if typeof(data) != TYPE_DICTIONARY:
			return _fail_save(slot, "participant '%s' did not return a Dictionary" % id)
		payload[id] = data

	var document: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"metadata": metadata,
		"payload": payload,
	}
	if not _write_atomically(_slot_path(slot), JSON.stringify(document, "\t")):
		return _fail_save(slot, _last_error)

	_last_error = ""
	save_completed.emit(slot)
	return true


## Applies a slot to every participant. Returns true when the slot was applied.
func load_from_slot(slot: int) -> bool:
	var document: Dictionary = read_slot(slot)
	if document.is_empty():
		load_failed.emit(slot, _last_error)
		return false

	var payload: Dictionary = document.get("payload", {})
	for node: Node in _get_participants():
		var id: String = _resolve_id(node)
		if payload.has(id):
			SaveParticipantCapability.restore(node, payload[id])

	_last_error = ""
	load_completed.emit(slot)
	return true


## Reads and migrates a slot without applying it; empty means unreadable.
func read_slot(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		_last_error = "slot %d is out of range" % slot
		return {}
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		_last_error = "slot %d is empty" % slot
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_error = "cannot open slot %d (error %d)" % [slot, FileAccess.get_open_error()]
		return {}
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "slot %d is corrupt" % slot
		return {}
	return _migrate(parsed as Dictionary)


## True when the slot holds a readable save.
func has_slot(slot: int) -> bool:
	return _is_valid_slot(slot) and FileAccess.file_exists(_slot_path(slot))


## Deletes a slot. Returns true when the slot is gone afterwards.
func delete_slot(slot: int) -> bool:
	if not has_slot(slot):
		return true
	var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot_path(slot)))
	if error != OK:
		_last_error = "cannot delete slot %d (error %d)" % [slot, error]
		return false
	return true


## Metadata for every populated slot, for a load menu. Corrupt slots are
## reported with `corrupt = true` rather than hidden.
func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot: int in range(0, max_slot + 1):
		if not has_slot(slot):
			continue
		var document: Dictionary = read_slot(slot)
		if document.is_empty():
			slots.append({"slot": slot, "corrupt": true})
			continue
		slots.append({
			"slot": slot,
			"corrupt": false,
			"saved_at_unix": int(document.get("saved_at_unix", 0)),
			"metadata": document.get("metadata", {}),
		})
	return slots


## Every node that opted in, whether by group membership or explicit
## registration. Duplicates and freed nodes are dropped.
func _get_participants() -> Array[Node]:
	var participants: Array[Node] = []
	var live: Array[Node] = []
	for node: Node in _registered:
		if is_instance_valid(node):
			live.append(node)
			participants.append(node)
	if live.size() != _registered.size():
		_registered = live

	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
			if participants.has(node):
				continue
			if implements_save_contract(node):
				participants.append(node)
			else:
				push_warning(
					"SaveManager: '%s' is in the saveable group but does not "
					% node.name + "provide the save capability"
				)
	return participants


## A participant's own key. Stated explicitly by the system so renaming a
## script never orphans a save file.
func _resolve_id(node: Node) -> String:
	return String(SaveParticipantCapability.get_key(node))


## Writes via a temporary file and renames, so a crash cannot leave a half save.
func _write_atomically(path: String, text: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK and error != ERR_ALREADY_EXISTS:
		_last_error = "cannot create the save directory (error %d)" % error
		return false

	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_last_error = "cannot open the save file (error %d)" % FileAccess.get_open_error()
		return false
	file.store_string(text)
	file.close()

	var dir := DirAccess.open(absolute.get_base_dir())
	if dir == null:
		_last_error = "cannot open the save directory"
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	error = dir.rename(temporary.get_file(), path.get_file())
	if error != OK:
		_last_error = "cannot finalise the save file (error %d)" % error
		return false
	return true


## Upgrades an older document to the current layout, or refuses it.
##
## A version this build does not recognise is refused outright rather than
## half-applied: a save format without a version field is a migration problem
## that can never be fixed after the fact, so no partial apply is allowed.
func _migrate(document: Dictionary) -> Dictionary:
	if not document.has("version"):
		_last_error = "save has no version field"
		push_warning("SaveManager: %s; refusing it" % _last_error)
		return {}
	var version: int = int(document["version"])
	if version == SAVE_VERSION:
		return document
	if version > SAVE_VERSION:
		_last_error = "save was written by a newer build (v%d)" % version
		push_warning("SaveManager: %s; refusing it" % _last_error)
		return {}
	_last_error = "save version %d has no migration path" % version
	push_warning("SaveManager: %s; refusing it" % _last_error)
	return {}


func _slot_path(slot: int) -> String:
	return slot_path(slot)


## Where a slot lives on disk. Static so a title menu can ask before any
## SaveManager exists.
static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


## True when a sleep save is on disk, for the title menu's Continue button.
static func has_sleep_save() -> bool:
	return FileAccess.file_exists(slot_path(SLEEP_SLOT))


func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot <= max_slot


func _fail_save(slot: int, reason: String) -> bool:
	_last_error = reason
	push_warning("SaveManager: save to slot %d failed: %s" % [slot, reason])
	save_failed.emit(slot, reason)
	return false

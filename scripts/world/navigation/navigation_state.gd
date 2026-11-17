class_name NavigationState
extends RefCounted

## Sole owner of the discovered/visited/selected navigation state.
## Scenario and mental-map callers use the same validated target-id API.
## The HUD is a read-only view; no automatic discovery of Reality buildings.
var catalog: NavigationCatalog
var known: Dictionary = {}
var visited: Dictionary = {}
var active_target_id: String = ""


func discover_target(id: String) -> bool:
	if not _valid(id):
		return false
	known[id] = true
	return true


func select_target(id: String) -> bool:
	if not _valid(id) or not known.has(id):
		return false
	active_target_id = id
	return true


func clear_target() -> void:
	active_target_id = ""


func mark_arrived(id: String) -> bool:
	## Only a trusted world event may call this. Distance never counts as
	## arrival. Marking another known place must not clear the selected one.
	if not _valid(id):
		return false
	known[id] = true
	visited[id] = true
	if active_target_id == id:
		clear_target()
	return true


func reset() -> void:
	known.clear()
	visited.clear()
	clear_target()


func restore(data: Dictionary) -> void:
	reset()
	for raw_id: Variant in data.get("known", []):
		discover_target(String(raw_id))
	for raw_id: Variant in data.get("visited", []):
		mark_arrived(String(raw_id))
	var saved_target: String = String(data.get("active_target_id", ""))
	if not saved_target.is_empty():
		select_target(saved_target)


func known_targets() -> Array[NavigationTarget]:
	var result: Array[NavigationTarget] = []
	if catalog == null:
		return result
	var ids: Array = known.keys()
	ids.sort()
	for id: Variant in ids:
		var entry: NavigationTarget = catalog.get_target(String(id))
		if entry != null:
			result.append(entry)
	return result


func _valid(id: String) -> bool:
	return not id.is_empty() and catalog != null and catalog.get_target(id) != null

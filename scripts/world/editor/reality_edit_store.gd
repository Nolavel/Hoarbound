class_name RealityEditStore
extends RefCounted
## Reads and writes the Reality edit layer (tools/world/reality/edits.py reads the same files).
## One file per chunk; records are keyed by feature_id and tagged with a data layer.

const EDITS_DIR: String = "res://data/world/key_west/reality/overrides/edits"
const SCHEMA: String = "kw_reality.edits.v1"
## Layers offered in the dock; loot:<set> and story:<state> are typed in.
const LAYERS: PackedStringArray = ["base", "winter"]

## Where the per-chunk files live; tests point it at user://.
var edits_dir: String = EDITS_DIR

var _docs: Dictionary = {}  # chunk "x:z" -> {"schema", "chunk", "edits": Array}
var _layer_rule: RegEx = RegEx.create_from_string("^(base|winter|loot:[a-z0-9_]+|story:[a-z0-9_]+)$")


## Loads every edit file; returns the number of records.
func load_all() -> int:
	_docs.clear()
	var dir: DirAccess = DirAccess.open(edits_dir)
	if dir == null:
		return 0
	var count: int = 0
	for file_name: String in dir.get_files():
		if not (file_name.begins_with("edits_") and file_name.ends_with(".json")):
			continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(edits_dir.path_join(file_name)))
		if doc is Dictionary:
			var chunk: String = String(doc.get("chunk", file_name.trim_prefix("edits_").trim_suffix(".json").replace("_", ":")))
			_docs[chunk] = doc
			count += (doc.get("edits", []) as Array).size()
	return count


func is_valid_layer(layer: String) -> bool:
	return _layer_rule.search(layer) != null


## Records for one feature, oldest first.
func edits_for(feature_id: String) -> Array:
	var out: Array = []
	for doc: Dictionary in _docs.values():
		for e: Dictionary in doc.get("edits", []):
			if e.get("feature_id") == feature_id:
				out.append(e)
	return out


## Appends a record to its chunk file and writes it.
func add_edit(edit: Dictionary) -> Error:
	var chunk: String = String(edit["chunk"])
	var doc: Dictionary = _docs.get_or_add(chunk, {"schema": SCHEMA, "chunk": chunk, "edits": []})
	(doc["edits"] as Array).append(edit)
	return _write(chunk)


## Drops a record by id and rewrites its file; false when no record has that id.
func remove_edit(edit_id: String) -> bool:
	for chunk: String in _docs.keys():
		var list: Array = _docs[chunk]["edits"]
		for i: int in range(list.size()):
			if list[i].get("edit_id") == edit_id:
				list.remove_at(i)
				_write(chunk)
				return true
	return false


## A new record; feature_id and chunk come from the index, source_hash pins the source version.
static func new_edit(op: String, layer: String, feature_id: String, chunk: String, source_hash: String, params: Dictionary = {}) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var edit: Dictionary = {"edit_id": "e_%08x%08x" % [rng.randi(), rng.randi()], "op": op, "layer": layer,
		"feature_id": feature_id, "chunk": chunk, "source_geometry_hash": source_hash,
		"created": Time.get_datetime_string_from_system(true)}
	if not params.is_empty():
		edit["params"] = params
	return edit


func _write(chunk: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(edits_dir))
	var path: String = edits_dir.path_join("edits_%s.json" % chunk.replace(":", "_"))
	var doc: Dictionary = _docs[chunk]
	if (doc["edits"] as Array).is_empty():
		_docs.erase(chunk)
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, " ", false))
	return OK

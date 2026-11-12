@tool
extends EditorExportPlugin

## Ships the Key West Reality data the game reads at runtime. data/world/key_west/reality carries a .gdignore
## (494 MB of sources Godot must not import), so an export never sees it; the game reads these files raw.

const ROOT: String = "res://data/world/key_west/reality/"
## Folders shipped whole, and single files, relative to ROOT. Everything else there is source or editor data.
const FOLDERS: PackedStringArray = ["landmarks", "overrides", "routes"]
const FILES: PackedStringArray = ["editor/editor_index.json", "authoring/asset_manifest.json"]
## Only these extensions are read by the game.
const EXTENSIONS: PackedStringArray = ["json", "geojson"]


func _get_name() -> String:
	return "KeyWestRealityRuntimeData"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var count: int = 0
	for folder: String in FOLDERS:
		count += _add_folder(ROOT + folder)
	for file: String in FILES:
		count += int(_add(ROOT + file))
	print("Reality | export: shipped %d runtime data files from %s" % [count, ROOT])


func _add_folder(path: String) -> int:
	var count: int = 0
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() in EXTENSIONS:
			count += int(_add(path.path_join(file)))
	for sub: String in DirAccess.get_directories_at(path):
		count += _add_folder(path.path_join(sub))
	return count


func _add(path: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Reality export: cannot read %s; the game will miss it" % path)
		return false
	add_file(path, bytes, false)
	return true

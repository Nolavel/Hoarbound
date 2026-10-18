extends SceneTree

## Reserved render layers stay distinct: snow contact geometry must never be a
## dev map label, and neither may be drawn by the other's camera.
## Run: godot --headless --script tests/systems/test_render_layers.gd

const SNOW_SHELL: GDScript = preload("res://scripts/systems/world/snow/snow_shell.gd")
const DEV_MAP: GDScript = preload("res://scripts/ui/debug/dev_diorama_map.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_reserved_layers_do_not_overlap()
	_test_owners_use_the_reserved_masks()
	_test_layers_are_named()
	_test_no_magic_masks()
	if _failures > 0:
		push_error("render layers: %d check(s) failed" % _failures)
		quit(1)
		return
	print("render layers: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("render layers: %s" % message)


func _test_reserved_layers_do_not_overlap() -> void:
	_check(RenderLayers.SNOW_CONTACT & RenderLayers.DEV_MAP_LABEL == 0, "snow contact and dev map labels share a layer")
	## Layers 1-6 carry the world, Henry and gizmos.
	_check(RenderLayers.RESERVED & 0b111111 == 0, "a reserved layer overlaps the world layers")
	_check(RenderLayers.SNOW_TILE_EXPERIMENT & RenderLayers.SNOW_CONTACT == 0, "experimental witness conflicts with contact camera")
	_check(RenderLayers.SNOW_TILE_EXPERIMENT & RenderLayers.DEV_MAP_LABEL == 0, "experimental witness conflicts with dev map")


func _test_owners_use_the_reserved_masks() -> void:
	_check(SNOW_SHELL.CONTACT_LAYER == RenderLayers.SNOW_CONTACT, "SnowShell does not use the reserved contact layer")
	_check(DEV_MAP.MAP_LABEL_MASK == RenderLayers.DEV_MAP_LABEL, "the dev map does not use the reserved label layer")


func _test_layers_are_named() -> void:
	_check(String(ProjectSettings.get_setting("layer_names/3d_render/layer_19", "")) == "snow_contact", "layer 19 is not named snow_contact")
	_check(String(ProjectSettings.get_setting("layer_names/3d_render/layer_20", "")) == "dev_map_label", "layer 20 is not named dev_map_label")
	_check(String(ProjectSettings.get_setting("layer_names/3d_render/layer_21", "")) == "snow_tile_experiment", "layer 21 is not named snow_tile_experiment")


## Only RenderLayers may spell out the reserved bits.
func _test_no_magic_masks() -> void:
	var offenders: Array[String] = []
	_scan("res://scripts", offenders)
	_scan("res://world", offenders)
	_check(offenders.is_empty(), "raw 1 << 18 / 1 << 19 outside RenderLayers: %s" % str(offenders))


func _scan(directory: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_scan(directory.path_join(sub), offenders)
	for file_name: String in dir.get_files():
		var path: String = directory.path_join(file_name)
		if not file_name.ends_with(".gd") or path == "res://scripts/core/render_layers.gd":
			continue
		var text: String = FileAccess.get_file_as_string(path)
		if text.contains("1 << 18") or text.contains("1 << 19"):
			offenders.append(path)

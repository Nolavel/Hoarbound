class_name ShadowCasterPolicy
extends Node

## Keeps low-value generated geometry out of directional shadow passes while
## preserving shadows from authored/near buildings, roofs, utility poles and
## other large silhouettes. Generated city nodes use stable names, so the same
## policy also applies when streaming creates them later.

const SHADOW_OFF_NAMES: Dictionary = {
	&"PowerWires": true,
	&"Crossings": true,
	&"Curbs": true,
	&"Sidewalks": true,
	&"WhiteMarkings": true,
	&"YellowCenterlines": true,
	&"OneWayArrows": true,
	&"MappedSidewalks": true,
	&"CoastlineEdge": true,
	&"Runways": true,
	&"Taxiways": true,
	&"AirportWhiteMarkings": true,
	&"AirportYellowMarkings": true,
	&"WasteBaskets": true,
	&"FireHydrants": true,
	&"Bollards": true,
	&"PostBoxes": true,
	&"GolfTeeMarkers": true,
	&"Ring0Massing": true,
}

const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")
## Streamed chunk part whose palms and trees lose their shadows on LOW (GraphicsQuality vegetation_shadows).
const VEGETATION_NODE: StringName = &"Vegetation"

const SHADOW_OFF_PREFIXES: Array[String] = [
	"Ring0_",      # Island-wide far road ribbons.
	"Surface_",    # Streamed local road ribbons.
	"AirportArea_", # Flat runway/taxiway/apron polygons.
]


var _vegetation_shadows: bool = true


func _ready() -> void:
	add_to_group(&"graphics_quality_consumer")
	_vegetation_shadows = bool(GRAPHICS.current_profile().get("vegetation_shadows", true))
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred(&"_apply_existing")


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _apply_existing() -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	_apply_recursive(root)


func _apply_recursive(node: Node) -> void:
	_apply(node)
	for child: Node in node.get_children():
		_apply_recursive(child)


func _on_node_added(node: Node) -> void:
	_apply(node)


## GraphicsQuality.apply: LOW drops the vegetation's shadows, the other tiers restore them.
func apply_graphics_quality(_quality: StringName, profile: Dictionary) -> void:
	var wanted: bool = bool(profile.get("vegetation_shadows", true))
	if wanted == _vegetation_shadows:
		return
	_vegetation_shadows = wanted
	_apply_existing()


func _apply(node: Node) -> void:
	if not node is GeometryInstance3D:
		return
	var parent := node.get_parent()
	if parent != null and parent.name == VEGETATION_NODE:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _vegetation_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	if not _should_disable_shadow(node):
		return
	(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _should_disable_shadow(node: Node) -> bool:
	if SHADOW_OFF_NAMES.has(node.name):
		return true
	var node_name := String(node.name)
	for prefix: String in SHADOW_OFF_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	var parent := node.get_parent()
	return parent != null and parent.name == &"ChunkGrid"

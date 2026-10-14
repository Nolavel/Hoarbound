class_name KeyWestDevWaypoints
extends Node3D
## Debug-build navigation: F5 cycles a target through the First Exit route goals and listed addresses, shown as a
## tall beacon and a distance/bearing line; F6 teleports Henry to it. Freed in release builds.

const ROUTE_PATH: String = "res://data/world/key_west/reality/routes/first_exit_gate.json"
const BEACON_HEIGHT_M: float = 150.0
const BEACON_COLOUR: Color = Color(1.0, 0.35, 0.05, 0.55)
const TELEPORT_CLEARANCE_M: float = 1.0
const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Addresses resolved through the Reality editor index, after the route goals.
@export var addresses: PackedStringArray = PackedStringArray(["727 fort st", "907 whitehead st"])

var _player: Node3D
var _camera: Camera3D
var _ground: Node
var _targets: Array[Dictionary] = []  # {"name": String, "at": Vector3 (xz, y = top or 0)}
var _current: int = -1
var _beacon: MeshInstance3D
var _label: Label3D
var _hud: Label


func on_world_ready(context: WorldContext) -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_player = context.player
	_camera = context.camera
	_ground = get_parent().find_child("RealityGround", false, false)
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null or not input_systems.has_signal(&"dev_waypoint_next_pressed"):
		return
	input_systems.connect(&"dev_waypoint_next_pressed", next_target)
	input_systems.connect(&"dev_waypoint_teleport_pressed", teleport)
	set_process(false)


## Next target, or off after the last; the list is read on first use.
func next_target() -> void:
	if _targets.is_empty():
		_load_targets()
	_current = _current + 1 if _current + 1 < _targets.size() else -1
	_show()


## Moves Henry onto the ground at the current target.
func teleport() -> void:
	if _current < 0 or _player == null:
		return
	var at: Vector3 = _targets[_current]["at"]
	var y: float = float(_ground.call(&"get_height", at.x, at.z)) if _ground != null and _ground.has_method(&"get_height") else 0.0
	_player.global_position = Vector3(at.x, y + TELEPORT_CLEARANCE_M, at.z)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	if _camera is TpsCamera:
		(_camera as TpsCamera).snap_to_target()
	print("Dev waypoint: teleported to %s" % _targets[_current]["name"])


func current_target() -> Dictionary:
	return _targets[_current] if _current >= 0 else {}


func target_names() -> PackedStringArray:
	if _targets.is_empty():
		_load_targets()
	var out: PackedStringArray = PackedStringArray()
	for t: Dictionary in _targets:
		out.append(t["name"])
	return out


func _process(_delta: float) -> void:
	if _current < 0 or _player == null:
		return
	var at: Vector3 = _targets[_current]["at"]
	var d: Vector2 = Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z)
	## Local frame: x east, z south; compass 0 is north (-z).
	var sector: int = posmod(roundi(rad_to_deg(atan2(d.x, -d.y)) / 45.0), 8)
	_hud.text = "Dev target %d/%d: %s, %d m %s   [F5 next, F6 teleport]" % [_current + 1, _targets.size(), _targets[_current]["name"],
		roundi(d.length()), COMPASS[sector]]


func _load_targets() -> void:
	var seen: Dictionary = {}
	var route: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))
	if route is Dictionary:
		for goal: Dictionary in (route as Dictionary).get("goals", []):
			var xz: Array = goal["xz"]
			var key: String = "%.1f_%.1f" % [float(xz[0]), float(xz[1])]
			if seen.has(key):
				continue
			seen[key] = true
			_targets.append({"name": String(goal["name"]), "at": Vector3(float(xz[0]), 0.0, float(xz[1]))})
	var index: RealityIndex = RealityIndex.new()
	if not addresses.is_empty() and index.load_index():
		for query: String in addresses:
			var hits: Array = index.search(query, 1)
			if hits.is_empty():
				push_warning("KeyWestDevWaypoints: no building for '%s'" % query)
				continue
			var b: Dictionary = hits[0]
			_targets.append({"name": RealityIndex.label_of(b), "at": Vector3(float(b["c"][0]), 0.0, float(b["c"][1]))})


func _show() -> void:
	if _beacon == null:
		_build_markers()
	var on: bool = _current >= 0
	_beacon.visible = on
	_label.visible = on
	_hud.visible = on
	set_process(on)
	if not on:
		return
	var at: Vector3 = _targets[_current]["at"]
	var y: float = float(_ground.call(&"get_height", at.x, at.z)) if _ground != null and _ground.has_method(&"get_height") else 0.0
	_beacon.global_position = Vector3(at.x, y + BEACON_HEIGHT_M * 0.5, at.z)
	_label.global_position = Vector3(at.x, y + BEACON_HEIGHT_M + 4.0, at.z)
	_label.text = _targets[_current]["name"]
	_process(0.0)


func _build_markers() -> void:
	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	var column: CylinderMesh = CylinderMesh.new()
	column.top_radius = 0.8
	column.bottom_radius = 0.8
	column.height = BEACON_HEIGHT_M
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = BEACON_COLOUR
	mat.no_depth_test = true  # seen through buildings
	column.material = mat
	_beacon.mesh = column
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	add_child(_label)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24.0, 24.0)
	_hud.add_theme_font_size_override(&"font_size", 20)
	_hud.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_hud)

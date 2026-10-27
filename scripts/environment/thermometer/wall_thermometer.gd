class_name WallThermometer
extends Node3D

## An analog room thermometer on a wall: a dial with a needle, and the reading in 3D type
## on a grey plate that shows only when Henry is close. Presentation only; it reads its zone.

## Scale ends, °C; the needle sweeps SWEEP_DEG between them.
const SCALE_MIN_C: float = -40.0
const SCALE_MAX_C: float = 40.0
const SWEEP_DEG: float = 270.0
const DIAL_RADIUS: float = 0.09
const READING_FONT: Font = preload("res://assets/fonts/IM Fell English SC/IMFellEnglishSC-Regular.ttf")

## The room it hangs in; its air is outdoor air plus this zone's offset.
@export var zone: ThermalZone
## Henry closer than this sees the reading in full, m.
@export var reading_near_m: float = 2.5
## Beyond this the reading is gone, m.
@export var reading_far_m: float = 3.0
## How fast the needle and the figure follow the air, share of the gap per second.
@export var follow_rate: float = 1.5

var _thermal: ThermalManager
var _player: Node3D
var _shown_c: float = NAN
var _needle: Node3D
var _reading: Label3D
var _plate: MeshInstance3D
var _plate_material: StandardMaterial3D
var _search_left: float = 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if not _bind():
		_search_left -= delta
		return
	var air: float = get_air_c()
	_shown_c = air if is_nan(_shown_c) else lerpf(_shown_c, air, 1.0 - exp(-follow_rate * delta))
	_needle.rotation.z = -deg_to_rad(needle_angle_deg(_shown_c))
	_reading.text = tr(&"THERMOMETER_READING") % roundi(_shown_c)
	var near: float = 1.0
	if is_instance_valid(_player):
		near = 1.0 - smoothstep(reading_near_m, reading_far_m, _player.global_position.distance_to(global_position))
	_reading.modulate.a = near
	_reading.outline_modulate.a = near * 0.8
	_plate.visible = near > 0.001
	_plate_material.albedo_color.a = near
	_reading.visible = _plate.visible


## Room air where the thermometer hangs, °C: outdoor air plus its zone's warmth.
func get_air_c() -> float:
	if _thermal == null:
		return 0.0
	return _thermal.get_outdoor_air_c() + (zone.get_total_offset_c() if is_instance_valid(zone) else 0.0)


## Needle angle clockwise from straight up for a temperature, clamped to the scale.
static func needle_angle_deg(celsius: float) -> float:
	var t: float = inverse_lerp(SCALE_MIN_C, SCALE_MAX_C, clampf(celsius, SCALE_MIN_C, SCALE_MAX_C))
	return lerpf(-SWEEP_DEG * 0.5, SWEEP_DEG * 0.5, t)


func get_reading_alpha() -> float:
	return _reading.modulate.a


## Finds the thermal model and Henry; streamed shelters are not handed the world context.
func _bind() -> bool:
	if _thermal != null:
		return true
	if _search_left > 0.0 or not is_inside_tree():
		return false
	_search_left = 1.0
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	var found: Array[Node] = get_tree().root.find_children("*", "ThermalManager", true, false)
	_thermal = found[0] as ThermalManager if not found.is_empty() else null
	return _thermal != null


func _build() -> void:
	var iron := StylizedEnvironmentMaterial.make_static(Color(0.18, 0.18, 0.19), 0.6)
	var face := StylizedEnvironmentMaterial.make_static(Color(0.86, 0.84, 0.78), 0.9)
	var ink := StylizedEnvironmentMaterial.make_static(Color(0.08, 0.08, 0.08), 0.9)
	var red := StylizedEnvironmentMaterial.make_static(Color(0.62, 0.10, 0.08), 0.7)
	_disc(DIAL_RADIUS + 0.012, 0.03, 0.015, iron)
	_disc(DIAL_RADIUS, 0.004, 0.032, face)
	for i: int in range(17):
		var angle: float = deg_to_rad(lerpf(-SWEEP_DEG * 0.5, SWEEP_DEG * 0.5, float(i) / 16.0))
		var major: bool = i % 4 == 0
		var length: float = 0.018 if major else 0.01
		var tick := _box(Vector3(0.003 if major else 0.002, length, 0.002), ink)
		var radial := Vector3(sin(angle), cos(angle), 0.0)
		tick.position = radial * (DIAL_RADIUS - 0.006 - length * 0.5) + Vector3(0.0, 0.0, 0.035)
		tick.rotation.z = -angle
		if major:
			var label := Label3D.new()
			label.text = "%d" % roundi(lerpf(SCALE_MIN_C, SCALE_MAX_C, float(i) / 16.0))
			label.font = READING_FONT
			label.font_size = 32
			label.pixel_size = 0.0004
			label.modulate = Color(0.08, 0.08, 0.08)
			label.outline_size = 0
			label.position = radial * (DIAL_RADIUS - 0.04) + Vector3(0.0, 0.0, 0.035)
			add_child(label)
	_needle = Node3D.new()
	_needle.position = Vector3(0.0, 0.0, 0.037)
	add_child(_needle)
	var blade := _box(Vector3(0.004, DIAL_RADIUS * 0.85, 0.002), red, _needle)
	blade.position = Vector3(0.0, DIAL_RADIUS * 0.85 * 0.5 - 0.01, 0.0)
	var hub := _disc(0.008, 0.004, 0.002, iron, _needle)
	hub.position.z = 0.002
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.34, 0.34, 0.34, 0.0))
	gradient.set_color(1, Color(0.34, 0.34, 0.34, 0.0))
	gradient.add_point(0.5, Color(0.30, 0.30, 0.31, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 8
	_plate_material = StandardMaterial3D.new()
	_plate_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plate_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plate_material.albedo_texture = texture
	_plate = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.07)
	quad.material = _plate_material
	_plate.mesh = quad
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plate.position = Vector3(0.0, -DIAL_RADIUS - 0.07, 0.006)
	add_child(_plate)
	_reading = Label3D.new()
	_reading.font = READING_FONT
	_reading.font_size = 64
	_reading.pixel_size = 0.0007
	_reading.modulate = Color(0.95, 0.93, 0.88)
	_reading.outline_modulate = Color(0.1, 0.1, 0.1, 0.8)
	_reading.outline_size = 8
	_reading.position = _plate.position + Vector3(0.0, 0.0, 0.002)
	add_child(_reading)


func _disc(radius: float, depth: float, z: float, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 32
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.rotation.x = PI * 0.5
	node.position.z = z
	parent.add_child(node)
	return node


func _box(size: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	return node

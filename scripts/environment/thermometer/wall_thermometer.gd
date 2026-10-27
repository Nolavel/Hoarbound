class_name WallThermometer
extends Node3D

## An ordinary glass thermometer on a board, hung by a wire loop from a nail: a red column
## and, close up, the reading in 3D type on a grey plate. Presentation only; it reads its zone.

## Scale ends, °C; the column climbs from the bulb's top at SCALE_MIN_C to the tube's top.
const SCALE_MIN_C: float = -40.0
const SCALE_MAX_C: float = 40.0
## Board, m; the nail is the node origin and the board hangs BOARD_DROP below it.
const BOARD_SIZE: Vector3 = Vector3(0.09, 0.46, 0.01)
const BOARD_DROP: float = 0.08
const TUBE_LENGTH: float = 0.35
const TUBE_RADIUS: float = 0.006
const BULB_RADIUS: float = 0.012
const READING_FONT: Font = preload("res://assets/fonts/IM Fell English SC/IMFellEnglishSC-Regular.ttf")

## The room it hangs in; its air is outdoor air plus this zone's offset.
@export var zone: ThermalZone
## Henry closer than this sees the reading in full, m.
@export var reading_near_m: float = 2.5
## Beyond this the reading is gone, m.
@export var reading_far_m: float = 3.0
## How fast the column and the figure follow the air, share of the gap per second.
@export var follow_rate: float = 1.5

var _thermal: ThermalManager
var _player: Node3D
var _shown_c: float = NAN
var _column: MeshInstance3D
var _scale_bottom: Vector3
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
	var rise: float = maxf(column_fraction(_shown_c) * TUBE_LENGTH, 0.001)
	_column.scale.y = rise
	_column.position = _scale_bottom + Vector3(0.0, rise * 0.5, 0.0)
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


## Share of the tube the column fills for a temperature, clamped to the scale.
static func column_fraction(celsius: float) -> float:
	return inverse_lerp(SCALE_MIN_C, SCALE_MAX_C, clampf(celsius, SCALE_MIN_C, SCALE_MAX_C))


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
	var iron := StylizedEnvironmentMaterial.make_static(Color(0.20, 0.19, 0.18), 0.5)
	var board := StylizedEnvironmentMaterial.make_static(Color(0.90, 0.88, 0.80), 0.9)
	var ink := StylizedEnvironmentMaterial.make_static(Color(0.10, 0.10, 0.10), 0.9)
	var red := StylizedEnvironmentMaterial.make_static(Color(0.72, 0.08, 0.06), 0.6)
	var glass := StylizedEnvironmentMaterial.make_static(Color(0.97, 0.97, 0.95), 0.3)
	## The nail: a shank in the wall and a flat head standing off it.
	_rod(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.03), 0.0018, iron)
	_disc(0.0055, 0.002, 0.03, iron)
	## The wire loop from the nail to the board's top corners.
	var top_y: float = -BOARD_DROP
	var hx: float = BOARD_SIZE.x * 0.5 - 0.008
	for side: float in [-1.0, 1.0]:
		_rod(Vector3(0.0, -0.002, 0.024), Vector3(side * hx, top_y - 0.006, 0.01), 0.0016, iron)
	var plank := _box(BOARD_SIZE, board)
	plank.position = Vector3(0.0, top_y - BOARD_SIZE.y * 0.5, BOARD_SIZE.z * 0.5)
	var front: float = BOARD_SIZE.z + 0.001
	var bulb_y: float = top_y - BOARD_SIZE.y + 0.035
	_scale_bottom = Vector3(0.006, bulb_y + BULB_RADIUS * 0.6, front + TUBE_RADIUS)
	## The tube reads as a pale capillary strip behind the column: an opaque glass rod would hide it.
	var tube := _box(Vector3(TUBE_RADIUS * 2.0, TUBE_LENGTH + 0.012, 0.002), glass)
	tube.position = _scale_bottom + Vector3(0.0, (TUBE_LENGTH + 0.012) * 0.5, -TUBE_RADIUS + 0.001)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BULB_RADIUS
	sphere.height = BULB_RADIUS * 2.0
	sphere.material = red
	bulb.mesh = sphere
	bulb.position = Vector3(_scale_bottom.x, bulb_y, _scale_bottom.z)
	add_child(bulb)
	_column = _rod(Vector3.ZERO, Vector3.UP, TUBE_RADIUS * 0.6, red)
	_column.position = Vector3.ZERO
	var column_mesh := _column.mesh as CylinderMesh
	column_mesh.height = 1.0
	## Ticks to the left of the tube every 5 °C, figures every 10 °C.
	for i: int in range(17):
		var celsius: float = lerpf(SCALE_MIN_C, SCALE_MAX_C, float(i) / 16.0)
		var y: float = _scale_bottom.y + column_fraction(celsius) * TUBE_LENGTH
		var major: bool = i % 2 == 0
		var length: float = 0.014 if major else 0.008
		var tick := _box(Vector3(length, 0.0016 if major else 0.0011, 0.0006), ink)
		tick.position = Vector3(_scale_bottom.x - TUBE_RADIUS - 0.003 - length * 0.5, y, front)
		if major:
			var label := Label3D.new()
			label.text = "%d" % roundi(celsius)
			label.font = READING_FONT
			label.font_size = 48
			label.pixel_size = 0.00036
			label.modulate = Color(0.10, 0.10, 0.10)
			label.outline_size = 0
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.position = Vector3(_scale_bottom.x - TUBE_RADIUS - 0.02, y, front + 0.0005)
			add_child(label)
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
	quad.size = Vector2(0.30, 0.08)
	quad.material = _plate_material
	_plate.mesh = quad
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plate.position = Vector3(0.0, top_y - BOARD_SIZE.y - 0.06, 0.004)
	add_child(_plate)
	_reading = Label3D.new()
	_reading.font = READING_FONT
	_reading.font_size = 64
	_reading.pixel_size = 0.0009
	_reading.modulate = Color(0.95, 0.93, 0.88)
	_reading.outline_modulate = Color(0.1, 0.1, 0.1, 0.8)
	_reading.outline_size = 8
	_reading.position = _plate.position + Vector3(0.0, 0.0, 0.002)
	add_child(_reading)


## A thin cylinder from a to b.
func _rod(a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(a.distance_to(b), 0.0001)
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var axis: Vector3 = (b - a).normalized() if a.distance_to(b) > 0.0001 else Vector3.UP
	var side: Vector3 = Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x: Vector3 = axis.cross(side).normalized()
	node.transform = Transform3D(Basis(x, axis, x.cross(axis)), (a + b) * 0.5)
	add_child(node)
	return node


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

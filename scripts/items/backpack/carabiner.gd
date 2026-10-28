class_name Carabiner
extends Node3D

## A screw-gate carabiner hung from a strap loop (#260). It swings from its top like a pendulum
## under gravity and the motion of what it hangs from. `Hang` is where a mug or a bag clips on.
## Origin: the inside top of the ring, where it rests in its loop; it hangs down -Y.

const SHADER: Shader = preload("res://shaders/items/carabiner.gdshader")
## Outer height and width of the ring, and the radius of its rod, metres.
const HEIGHT_M: float = 0.095
const WIDTH_M: float = 0.056
const ROD_M: float = 0.0045
const RING_POINTS: int = 40
const TUBE_SIDES: int = 8
## The gate sleeve: where it sits along the ring (0..1 from the top, round the gate side), its size.
const SLEEVE_AT: float = 0.14
const SLEEVE_LENGTH_M: float = 0.024
const SLEEVE_RADIUS_M: float = 0.0078
## Pendulum spring: frequency (Hz), damping, and the widest swing from straight down, degrees.
const SWING_HZ: float = 1.9
const SWING_DAMPING: float = 0.18
const MAX_SWING_DEG: float = 55.0

## The plane the ring lies in, as a rotation about the hanging axis (radians).
@export var face_yaw: float = 0.0
@export_flags_3d_render var render_layers: int = 1

var _body: Node3D
var _hang: Node3D
var _dir: Vector3 = Vector3.DOWN
var _dir_speed: Vector3 = Vector3.ZERO
var _last_position: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _has_last: bool = false


func _ready() -> void:
	build()


## Builds the ring, the sleeve and the hang point. Safe to call once.
func build() -> void:
	if _body != null:
		return
	_body = Node3D.new()
	_body.name = "Body"
	_body.rotation.y = face_yaw
	add_child(_body)
	var path: PackedVector3Array = _ring_path()
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _tube(path)
	ring.material_override = _material(0.45, false)
	ring.layers = render_layers
	_body.add_child(ring)
	var i: int = int(SLEEVE_AT * RING_POINTS)
	var along: Vector3 = (path[i + 1] - path[i - 1]).normalized()
	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = SLEEVE_RADIUS_M
	cylinder.bottom_radius = SLEEVE_RADIUS_M
	cylinder.height = SLEEVE_LENGTH_M
	cylinder.radial_segments = 14
	cylinder.rings = 1
	sleeve.mesh = cylinder
	sleeve.material_override = _material(0.8, true)
	sleeve.layers = render_layers
	sleeve.transform = Transform3D(Basis(Quaternion(Vector3.UP, along)), path[i])
	_body.add_child(sleeve)
	_hang = Node3D.new()
	_hang.name = "Hang"
	_hang.position = Vector3(0.0, -HEIGHT_M + ROD_M * 4.0, 0.0)
	_body.add_child(_hang)


## Where something clipped on hangs from (inside the bottom of the ring).
func get_hang_point() -> Node3D:
	build()
	return _hang


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree() or get_parent_node_3d() == null:
		return
	var at: Vector3 = global_position
	if not _has_last:
		_last_position = at
		_has_last = true
		return
	var velocity: Vector3 = (at - _last_position) / delta
	var accel: Vector3 = (velocity - _last_velocity) / delta
	_last_position = at
	_last_velocity = velocity
	if accel.length() > 80.0:
		accel = Vector3.ZERO  # a teleport, not a swing
	## It hangs along gravity less the pivot's acceleration, in the parent's space.
	var pull: Vector3 = get_parent_node_3d().global_basis.orthonormalized().inverse() * (Vector3.DOWN * 9.8 - accel)
	var target: Vector3 = pull.normalized() if pull.length() > 0.5 else Vector3.DOWN
	var omega: float = TAU * SWING_HZ
	_dir_speed += ((target - _dir) * omega * omega - _dir_speed * 2.0 * SWING_DAMPING * omega) * delta
	_dir = (_dir + _dir_speed * delta).normalized()
	var limit: float = deg_to_rad(MAX_SWING_DEG)
	if _dir.angle_to(Vector3.DOWN) > limit:
		_dir = Vector3.DOWN.slerp(_dir, limit / _dir.angle_to(Vector3.DOWN)).normalized()
	basis = Basis(Quaternion(Vector3.DOWN, _dir))


## The ring's centreline: a pear, narrow at the top where it sits in the loop, wider at the bottom.
func _ring_path() -> PackedVector3Array:
	var points := PackedVector3Array()
	var half_h: float = HEIGHT_M * 0.5 - ROD_M
	var half_w: float = WIDTH_M * 0.5 - ROD_M
	for k: int in range(RING_POINTS + 2):
		## From the top, round the gate side (+X) first.
		var theta: float = PI * 0.5 - TAU * float(k) / RING_POINTS
		var y: float = sin(theta)
		var x: float = cos(theta) * (1.0 - 0.2 * y)
		points.append(Vector3(x * half_w, y * half_h - half_h + ROD_M, 0.0))
	return points


## A round tube swept along a closed path (the last two points repeat the first two).
func _tube(path: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for k: int in range(RING_POINTS + 1):
		var prev: Vector3 = path[k - 1] if k > 0 else path[RING_POINTS - 1]
		var along: Vector3 = (path[k + 1] - prev).normalized()
		var side: Vector3 = along.cross(Vector3.BACK).normalized()
		var up: Vector3 = side.cross(along).normalized()
		var ring: Array = []
		for j: int in range(TUBE_SIDES + 1):
			var a: float = TAU * float(j) / TUBE_SIDES
			var normal: Vector3 = side * cos(a) + up * sin(a)
			ring.append([path[k] + normal * ROD_M, normal, Vector2(float(k) / RING_POINTS, float(j) / TUBE_SIDES)])
		rings.append(ring)
	for k: int in range(RING_POINTS):
		for j: int in range(TUBE_SIDES):
			var quad: Array = [rings[k][j], rings[k + 1][j], rings[k + 1][j + 1], rings[k][j + 1]]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				var order: Array = tri
				var a: Vector3 = quad[tri[0]][0]
				var b: Vector3 = quad[tri[1]][0]
				var c: Vector3 = quad[tri[2]][0]
				if (c - a).cross(b - a).dot(quad[tri[0]][1]) < 0.0:
					order = [tri[0], tri[2], tri[1]]
				for v: int in order:
					st.set_normal(quad[v][1])
					st.set_uv(quad[v][2])
					st.add_vertex(quad[v][0])
	st.index()
	return st.commit()


func _material(paint_left: float, knurled: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"paint_left", paint_left)
	material.set_shader_parameter(&"knurled", knurled)
	return material

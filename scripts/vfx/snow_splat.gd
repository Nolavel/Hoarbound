class_name SnowSplat
extends Decal

## Where a snowball struck: a white splat that sticks to the surface (#257). In the cold it stays;
## inside a heated room it slides down a little and melts away in under a minute.

const POOL_GROUP: StringName = &"snow_splats"
const MAX_SPLATS: int = 32
const SIZE_M: float = 0.32
## Seconds a splat lasts in a heated room, and how far it slides down the wall meanwhile.
const WARM_LIFE_S: float = 45.0
const SLIDE_M: float = 0.12

static var _texture: ImageTexture

var _warm: bool = false
var _age_s: float = 0.0
var _start: Vector3


## Sticks a splat at point on the surface with normal; warm when the point is inside a heated room.
static func stick(parent: Node, point: Vector3, normal: Vector3) -> SnowSplat:
	var tree: SceneTree = parent.get_tree()
	var splats: Array[Node] = tree.get_nodes_in_group(POOL_GROUP)
	if splats.size() >= MAX_SPLATS:
		splats[0].queue_free()
	var splat := SnowSplat.new()
	parent.add_child(splat)
	var side: Vector3 = normal.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = normal.cross(Vector3.FORWARD)
	side = side.normalized()
	## A decal projects along its -Y: Y out of the surface, Z along the wall's down slope.
	var basis := Basis(side, normal, side.cross(normal)).rotated(normal, randf() * TAU)
	splat.global_transform = Transform3D(basis, point)
	splat._start = point
	splat._warm = is_warm_at(parent, point)
	return splat


## A puff of broken snow where a snowball burst, thrown back off the surface.
static func burst(parent: Node, point: Vector3, normal: Vector3) -> void:
	var puff := GPUParticles3D.new()
	puff.name = "SnowBurst"
	puff.one_shot = true
	puff.amount = 24
	puff.lifetime = 0.9
	puff.explosiveness = 0.95
	puff.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.4
	puff.process_material = process
	var flake := QuadMesh.new()
	flake.size = Vector2(0.035, 0.035)
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(0.95, 0.96, 0.98)
	material.roughness = 1.0
	flake.material = material
	puff.draw_pass_1 = flake
	parent.add_child(puff)
	var side: Vector3 = normal.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = normal.cross(Vector3.FORWARD)
	side = side.normalized()
	puff.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), point + normal * 0.03)
	puff.emitting = true
	puff.finished.connect(puff.queue_free)


## True inside an interior thermal zone that is warmer than freezing.
static func is_warm_at(parent: Node, point: Vector3) -> bool:
	return parent is Node3D and ThermalZone.is_warm_at((parent as Node3D).get_world_3d(), point)


func _init() -> void:
	name = "SnowSplat"
	add_to_group(POOL_GROUP)
	size = Vector3(SIZE_M, 0.25, SIZE_M)
	texture_albedo = _splat_texture()
	upper_fade = 0.2
	lower_fade = 0.2
	cull_mask = 0xFFFFF


func _process(delta: float) -> void:
	if not _warm:
		return
	_age_s += delta
	var t: float = clampf(_age_s / WARM_LIFE_S, 0.0, 1.0)
	global_position = _start + Vector3.DOWN * SLIDE_M * t
	modulate = Color(1.0, 1.0, 1.0, 1.0 - t * t)
	if t >= 1.0:
		queue_free()


## A lumpy white blob with short radial spatter, made once.
static func _splat_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var n: int = 64
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.12
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in range(n):
		for x: int in range(n):
			var d := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.5)
			var r: float = d.length()
			var angle: float = atan2(d.y, d.x)
			var lumps: float = 0.55 + 0.18 * noise.get_noise_2d(cos(angle) * 20.0, sin(angle) * 20.0)
			var spatter: float = 0.25 * maxf(sin(angle * 7.0 + 1.3), 0.0) * maxf(sin(angle * 3.0), 0.0)
			var a: float = 1.0 - smoothstep(lumps - 0.08, lumps + spatter, r)
			image.set_pixel(x, y, Color(0.95, 0.96, 0.98, clampf(a, 0.0, 1.0)))
	_texture = ImageTexture.create_from_image(image)
	return _texture

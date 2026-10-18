class_name WorldSnowTilePrototype
extends Node3D

## EXPERIMENT ONLY, instantiated by capture_snow_world_tiles.gd.
## Data belong to permanent 3.2m world tiles. Mesh instances may stream in/out,
## but their baked reference geometry + deformation image never recenter.
## No production scene references this class.
const TILE_M := 3.2
const GRID := 32 # 0.10m vertices, 33 samples incl. exact shared borders
const SIDE := GRID + 1
const RADIUS := 2 # prototype default; production config uses radius_tiles=6
const SURFACE_SHADER: Shader = preload("res://shaders/environment/snow/snow_world_tiles_experiment.gdshader")

var radius_tiles: int = RADIUS
var _top_at: Callable
var _data: Dictionary = {} # Vector2i -> Image, never mutated except stamping
var _surface: Dictionary = {} # Vector2i -> MeshInstance3D
var _meshes: Dictionary = {} # Vector2i -> ArrayMesh; persistent reference geometry
var _frozen: Dictionary = {} # Vector2i -> stable ImageTexture, streaming instance may drop
var _focus_cell: Vector2i = Vector2i(2147483647, 2147483647)
var mesh_builds := 0
var mesh_unloads := 0
var stamp_count := 0
var debug_height := false
var reference_y := 0.0


func configure(top_at: Callable, at: Vector2) -> void:
    _top_at = top_at
    focus(at)


static func cell_for(at: Vector2) -> Vector2i:
    return Vector2i(floori(at.x / TILE_M), floori(at.y / TILE_M))


static func key_origin(key: Vector2i) -> Vector2:
    return Vector2(key) * TILE_M


func focus(world_xz: Vector2) -> void:
    var at := cell_for(world_xz)
    if at == _focus_cell:
        return
    _focus_cell = at
    # Leave history and mesh vertex data untouched; only instances are culled.
    for old_key: Variant in _surface.keys():
        var key: Vector2i = old_key
        if maxi(absi(key.x - at.x), absi(key.y - at.y)) > radius_tiles:
            var old: MeshInstance3D = _surface[key]
            _surface.erase(key)
            old.queue_free()
            mesh_unloads += 1
    for z: int in range(at.y - radius_tiles, at.y + radius_tiles + 1):
        for x: int in range(at.x - radius_tiles, at.x + radius_tiles + 1):
            var key := Vector2i(x, z)
            if not _surface.has(key):
                _install(key)


func _install(key: Vector2i) -> void:
    if not _data.has(key):
        var img := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBAF)
        img.fill(Color(0.0, 0.0, 0.0, 0.0))
        _data[key] = img
    if not _frozen.has(key):
        _frozen[key] = ImageTexture.create_from_image(_data[key])
    if not _meshes.has(key):
        _meshes[key] = _build_baked_mesh(key)
        mesh_builds += 1
    var mat := ShaderMaterial.new()
    mat.shader = SURFACE_SHADER
    mat.set_shader_parameter("deformation", _frozen[key])
    mat.set_shader_parameter("tile_origin", key_origin(key))
    mat.set_shader_parameter("tile_m", TILE_M)
    mat.set_shader_parameter("debug_height", debug_height)
    mat.set_shader_parameter("reference_y", reference_y)
    var inst := MeshInstance3D.new()
    inst.name = "FixedSnow_%d_%d" % [key.x, key.y]
    inst.mesh = _meshes[key]
    inst.material_override = mat
    inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    inst.extra_cull_margin = 2.0
    inst.layers = 1 | RenderLayers.SNOW_TILE_EXPERIMENT # normal + isolated layer 21
    add_child(inst)
    _surface[key] = inst


func _build_baked_mesh(key: Vector2i) -> ArrayMesh:
    var origin := key_origin(key)
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    vertices.resize(SIDE * SIDE)
    indices.resize(GRID * GRID * 6)
    for z: int in range(SIDE):
        for x: int in range(SIDE):
            var at := origin + Vector2(float(x), float(z)) * TILE_M / float(GRID)
            vertices[z * SIDE + x] = Vector3(at.x, float(_top_at.call(at.x, at.y)), at.y)
    var k := 0
    for z: int in range(GRID):
        for x: int in range(GRID):
            var a: int = z * SIDE + x
            indices[k] = a
            indices[k + 1] = a + 1
            indices[k + 2] = a + SIDE
            indices[k + 3] = a + 1
            indices[k + 4] = a + SIDE + 1
            indices[k + 5] = a + SIDE
            k += 6
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


## Stamp persistent compression and displaced rim in world metres. A stamp
## touching a tile boundary updates BOTH matching endpoint samples, avoiding
## the half-texel discontinuity of a moving texture-window approach.
func stamp(at: Vector2, forward: Vector2, side: int, press_m: float = 0.12) -> void:
    var facing: Vector2 = forward.normalized()
    if facing.length_squared() < 0.5:
        return
    var right := Vector2(-facing.y, facing.x)
    var center: Vector2 = at if side < 0 else at + right * (0.13 if side == 0 else -0.13)
    var lo: Vector2i = cell_for(center - Vector2.ONE * 0.38)
    var hi: Vector2i = cell_for(center + Vector2.ONE * 0.38)
    for z: int in range(lo.y, hi.y + 1):
        for x: int in range(lo.x, hi.x + 1):
            var key := Vector2i(x, z)
            if not _data.has(key):
                continue
            var img: Image = _data[key]
            var base: Vector2 = key_origin(key)
            var dirty := false
            for iz: int in range(SIDE):
                for ix: int in range(SIDE):
                    var p: Vector2 = base + Vector2(float(ix), float(iz)) * (TILE_M / float(GRID))
                    var delta: Vector2 = p - center
                    var along: float = delta.dot(facing) / 0.205
                    var across: float = delta.dot(right) / 0.105
                    var d: float = sqrt(along * along + across * across)
                    if d >= 1.7:
                        continue
                    var c: Color = img.get_pixel(ix, iz)
                    var cut: float = press_m * pow(maxf(0.0, 1.0 - d * d), 0.8)
                    var rim: float = 0.040 * maxf(0.0, 1.0 - absf(d - 1.19) / 0.45)
                    if cut > c.r or rim > c.g:
                        c.r = maxf(c.r, cut)
                        c.g = maxf(c.g, rim)
                        img.set_pixel(ix, iz, c)
                        dirty = true
            if dirty and _frozen.has(key):
                (_frozen[key] as ImageTexture).update(img)
    stamp_count += 1


func set_height_debug(enabled: bool, reference: float) -> void:
    debug_height = enabled
    reference_y = reference
    for node: Variant in _surface.values():
        var mat := (node as MeshInstance3D).material_override as ShaderMaterial
        mat.set_shader_parameter("debug_height", enabled)
        mat.set_shader_parameter("reference_y", reference)


func deformation_fingerprint() -> int:
    # Stable, order-independent hash of NONEMPTY WORLD SAMPLES ONLY.
    # Streaming in an untouched tile must never count as a changed footprint.
    # The previous hash included blank texels and falsely failed all 16 snaps.
    var sum: int = 0
    for variant: Variant in _data.keys():
        var key: Vector2i = variant
        var img: Image = _data[key]
        for z: int in range(SIDE):
            for x: int in range(SIDE):
                var p: Color = img.get_pixel(x, z)
                var r: int = roundi(p.r * 100000.0)
                var g: int = roundi(p.g * 100000.0)
                if r == 0 and g == 0:
                    continue
                var site: int = posmod((key.x * GRID + x) * 73856093 + (key.y * GRID + z) * 19349663, 2147483629)
                sum = posmod(sum + posmod(site * (r + 7 * g), 2147483629), 2147483629)
    return sum


func witness(at: Vector2) -> Dictionary:
    var key := cell_for(at)
    if not _data.has(key):
        return {"exists": false}
    var local: Vector2 = (at - key_origin(key)) / TILE_M * float(GRID)
    var p := Vector2i(clampi(roundi(local.x), 0, GRID), clampi(roundi(local.y), 0, GRID))
    var state: Color = (_data[key] as Image).get_pixel(p.x, p.y)
    return {
        "exists": true,
        "compression_m": state.r,
        "displaced_m": state.g,
        "surface_y_m": float(_top_at.call(at.x, at.y)) + state.g - state.r,
        "resident": _surface.has(key),
        "tile": [key.x, key.y],
    }


func coverage() -> Dictionary:
    return {"resident_tiles": _surface.size(), "stored_tiles": _data.size(),
        "reference_meshes": _meshes.size(), "mesh_builds": mesh_builds,
        "mesh_unloads": mesh_unloads, "stamps": stamp_count}

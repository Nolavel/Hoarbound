extends SceneTree

const PROTOTYPE: GDScript = preload("res://scripts/systems/world/snow/world_snow_tile_prototype.gd")
var failures := 0


func _process(_delta: float) -> bool:
    _run()
    return true


func _flat(_x: float, _z: float) -> float:
    return 0.4


func _check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error("world snow tiles prototype: " + message)


func _run() -> void:
    var p := PROTOTYPE.new() as WorldSnowTilePrototype
    root.add_child(p)
    p.configure(Callable(self, "_flat"), Vector2(0.0, 0.0))
    var origin := WorldSnowTilePrototype.cell_for(Vector2(-0.01, 0.0))
    _check(origin.x == -1, "negative-world tile indexing breaks at zero")
    _check(p.coverage()["resident_tiles"] == 25, "prototype did not create 5x5 tile window")
    _check(p.coverage()["reference_meshes"] == 25, "baked world mesh count differs from instance count")

    # Cross X boundary; two tiles must sample the exact SAME world-space 33rd vertex.
    p.stamp(Vector2(3.2, 0.30), Vector2(0.0, 1.0), 0, 0.12)
    var a := Vector2i(0, 0)
    var b := Vector2i(1, 0)
    var ia: Image = p._data[a]
    var ib: Image = p._data[b]
    for z: int in range(WorldSnowTilePrototype.SIDE):
        var ca: Color = ia.get_pixel(WorldSnowTilePrototype.GRID, z)
        var cb: Color = ib.get_pixel(0, z)
        _check(is_equal_approx(ca.r, cb.r) and is_equal_approx(ca.g, cb.g),
            "adjacent permanent tiles have mismatched border samples at row %d" % z)

    var record_before := p.witness(Vector2(3.2, 0.30))
    var h := p.deformation_fingerprint()
    for x: int in [3, -3, 4, 0]:
        p.focus(Vector2(float(x) * WorldSnowTilePrototype.TILE_M, 0.0))
    _check(p.deformation_fingerprint() == h, "recenter mutated persistent packed/deformed data")
    var record_after := p.witness(Vector2(3.2, 0.30))
    _check(record_before["compression_m"] == record_after["compression_m"], "compression changed on unload/reload")
    _check(record_before["displaced_m"] == record_after["displaced_m"], "displaced rim changed on unload/reload")
    _check(p.coverage()["mesh_unloads"] > 0, "stress never unloaded any rendering meshes")
    _check(p.coverage()["stored_tiles"] > 25, "history disappears when leaving the resident window")

    # Two neighbouring fixed ground meshes share an actual position and altitude.
    var va: PackedVector3Array = (p._meshes[a] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var vb: PackedVector3Array = (p._meshes[b] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    for z: int in range(WorldSnowTilePrototype.SIDE):
        _check(va[z * WorldSnowTilePrototype.SIDE + WorldSnowTilePrototype.GRID]
            .distance_to(vb[z * WorldSnowTilePrototype.SIDE]) < 0.0005,
            "world baseline mesh border differs at row %d" % z)
    if failures == 0:
        print("world snow tiles prototype: all checks passed")
        quit(0)
    else:
        push_error("world snow tiles prototype: %d checks failed" % failures)
        quit(1)

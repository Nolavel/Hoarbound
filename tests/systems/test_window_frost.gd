extends SceneTree

## Window frost rule (owner): panes of a house with nothing inside are fully frosted; a house with content
## keeps 60-80 %; the panes of a room a stove has warmed clear down to 20 %.

## Duval St's chunk -7:2 is HLOD-built: its buildings live in 128 m cluster scenes (KeyWestChunkBuilder.cluster_id_of).
const CLUSTER_DIR: String = "res://scenes/world/key_west/generated/clusters"
const DUVAL_CHUNK: Vector2i = Vector2i(-7, 2)
const LANDMARK: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check_empty_houses()
	_check_landmark_glass()
	_check_warmth()
	if _failures > 0:
		push_error("window frost: %d check(s) failed" % _failures)
		quit(1)
		return
	print("window frost: all checks passed")
	quit(0)


func _check_empty_houses() -> void:
	var part := Node3D.new()
	for gx: int in range(DUVAL_CHUNK.x * 4, DUVAL_CHUNK.x * 4 + 4):
		for gz: int in range(DUVAL_CHUNK.y * 4, DUVAL_CHUNK.y * 4 + 4):
			var path: String = "%s/Cluster_c128_%d_%d.scn" % [CLUSTER_DIR, gx, gz]
			if ResourceLoader.exists(path):
				part.add_child((load(path) as PackedScene).instantiate())
	var panes: int = 0
	var houses: int = 0
	for node: Node in part.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s: int in range(mesh.get_surface_count()):
			if mesh.surface_get_name(s) != "windows":
				continue
			houses += 1
			var colors: PackedColorArray = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
			panes += colors.size() / 6
			for c: Color in colors:
				if not is_equal_approx(c.r, KeyWestChunkBuilder.EMPTY_HOUSE_FROST):
					_check(false, "%s has a pane at %.2f frost; empty houses are fully frosted" % [node.name, c.r])
					break
	_check(houses > 100 and panes > 1000, "too few generated windows: %d houses, %d panes" % [houses, panes])
	part.free()


func _check_landmark_glass() -> void:
	var house: Node = (load(LANDMARK) as PackedScene).instantiate()
	var glass := house.find_child("Glass", true, false) as MeshInstance3D
	_check(glass != null and glass.get_active_material(0) == KeyWest727Shelter.FROSTED_GLASS, "727 glass does not use the frosted glass material")
	if glass != null:
		var colors: PackedColorArray = glass.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var heated: int = 0
		for c: Color in colors:
			_check(c.r >= 0.6 - 0.001 and c.r <= 0.8 + 0.001, "727 pane frost %.3f is outside 60-80 %%" % c.r)
			heated += 1 if c.g > 0.5 else 0
		_check(heated == 4 * 36, "expected the 4 heated-room windows, found %d heated vertices" % heated)
	house.free()


func _check_warmth() -> void:
	var zone := ThermalZone.new()
	zone.max_heated_offset_c = 12.0
	_check(is_equal_approx(KeyWest727Shelter.frost_warmth(zone), 0.0), "a cold zone reads warm")
	zone._heated_offset_c = 12.0
	_check(is_equal_approx(KeyWest727Shelter.frost_warmth(zone), 1.0), "a fully warmed zone does not read 1")
	var mat: ShaderMaterial = KeyWest727Shelter.FROSTED_GLASS
	_check(is_equal_approx(float(mat.get_shader_parameter(&"warm_coverage")), 0.2), "a warmed room does not clear to 20 %")
	var unheated := ThermalZone.new()
	_check(is_equal_approx(KeyWest727Shelter.frost_warmth(unheated), 0.0), "an unheated zone reads warm")
	zone.free()
	unheated.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("window frost: " + message)

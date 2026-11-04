extends SceneTree

## The egg presentation is deterministic and stays within the pan's cooking floor.

var _failed: bool = false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var egg := EggCookingVisual.new()
	root.add_child(egg)
	egg.seek_seconds(0.0)
	_check((egg.get_node(^"UnbrokenShell") as MeshInstance3D).visible, "the whole egg is not visible")
	_check(not (egg.get_node(^"ShellLeft") as Node3D).visible, "the egg is already split")
	egg.seek_seconds(0.55)
	_check((egg.get_node(^"OpeningCrack") as MeshInstance3D).visible, "the first crack is absent")
	egg.seek_seconds(1.40)
	_check((egg.get_node(^"FallingAlbumen") as MeshInstance3D).visible, "albumen does not pour")
	egg.seek_seconds(2.5)
	_check(not (egg.get_node(^"FallingAlbumen") as MeshInstance3D).visible, "albumen keeps hanging after impact")
	_check((egg.get_node(^"Yolk") as MeshInstance3D).visible, "the yolk never lands")
	var white := egg.get_node(^"SpreadingWhite") as MeshInstance3D
	_check(white.visible, "the white does not spread")
	egg.seek_seconds(5.20)
	_check((egg.get_node(^"BrowningEdge") as MeshInstance3D).visible, "the hot edge never appears")
	var first: PackedVector3Array = white.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	egg.seek_seconds(5.35)
	var second: PackedVector3Array = white.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var outer_motion: float = 0.0
	var inside_motion: float = 0.0
	var furthest: float = 0.0
	for i: int in range(first.size()):
		var change: float = first[i].distance_to(second[i])
		if i >= first.size() - EggCookingVisual.WHITE_AROUND:
			outer_motion = maxf(outer_motion, change)
		else:
			inside_motion = maxf(inside_motion, change)
		furthest = maxf(furthest, Vector2(second[i].x, second[i].z).length())
	_check(outer_motion > 0.001 and outer_motion > inside_motion * 1.5,
		"frying does not move the mesh edge more than its centre")
	_check(outer_motion < 0.003, "frying edge moves like a rubber sheet")
	_check(furthest < 0.085, "fried white extends beyond the pan floor")
	print("test_egg_cooking_visual: %s (edge=%.4f m, floor_radius=%.4f m)" %
		["FAIL" if _failed else "PASS", outer_motion, furthest])
	quit(1 if _failed else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

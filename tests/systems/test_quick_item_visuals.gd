extends SceneTree

## Every item the game itself routes into a Quick Access pocket (prefer_quick_access) shows there as itself:
## SurvivalItemVisual draws it, and not as the plain parcel every unknown item gets (#42 record 02, item 8:
## the picked-up flare sat in the coat pocket drawn as a grey box, so the player found it nowhere).
## Run: godot --headless --script tests/systems/test_quick_item_visuals.gd

const PARCEL_SIZE: Vector3 = Vector3(0.12, 0.065, 0.085)

var _failures: int = 0


func _initialize() -> void:
	var checked: int = 0
	for item: ItemResource in ItemCatalog.shared().items:
		if not item.prefer_quick_access:
			continue
		checked += 1
		_check(SurvivalItemVisual.draws(item.id), "%s goes to a pocket by itself but is not drawn as itself" % item.id)
		var visual: Node3D = SurvivalItemVisual.make(item.id)
		_check(not _is_parcel(visual), "%s in a pocket is drawn as the plain parcel" % item.id)
		print("quick item visuals: %s drawn with %d meshes" % [item.id, visual.find_children("*", "MeshInstance3D", true, false).size()])
		visual.free()
	_check(checked > 0, "no item prefers Quick Access")
	if _failures > 0:
		push_error("quick item visuals: %d check(s) failed" % _failures)
		quit(1)
		return
	print("quick item visuals: all checks passed")
	quit(0)


static func _is_parcel(visual: Node3D) -> bool:
	var meshes: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		return false
	var box := (meshes[0] as MeshInstance3D).mesh as BoxMesh
	return box != null and box.size.is_equal_approx(PARCEL_SIZE)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("quick item visuals: " + message)

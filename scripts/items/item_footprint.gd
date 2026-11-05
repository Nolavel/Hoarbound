class_name ItemFootprint
extends RefCounted

## An item's real size from the model the game draws (SurvivalItemVisual), measured once per id, and whether it
## goes into a pocket of a given inner size. A pocket is open at the top: an item may stand out of it a little.

## How far past a pocket's depth an item may stand out of its mouth (a flask's neck, a knife's handle).
const STICK_OUT: float = 1.3

static var _cm: Dictionary = {}


## `item_id`'s size in centimetres, largest first (x >= y >= z).
static func size_cm(item_id: StringName) -> Vector3:
	if _cm.has(item_id):
		return _cm[item_id]
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = BackpackModel._local_bounds(visual) if visual != null else AABB()
	if visual != null:
		visual.free()
	var sides: Array[float] = [box.size.x * 100.0, box.size.y * 100.0, box.size.z * 100.0]
	sides.sort()
	_cm[item_id] = Vector3(sides[2], sides[1], sides[0])
	return _cm[item_id]


## Whether `item_id` goes into a pocket `inner_cm` inside (width, depth, thickness, cm): its two smaller sides
## through the mouth, its longest within the depth (or across), standing out up to STICK_OUT.
static func fits(item_id: StringName, inner_cm: Vector3) -> bool:
	var item: Vector3 = size_cm(item_id)
	var sides: Array[float] = [inner_cm.x, inner_cm.y, inner_cm.z]
	sides.sort()
	var pocket := Vector3(sides[2], sides[1], sides[0])
	return item.x <= pocket.x * STICK_OUT and item.y <= pocket.y and item.z <= pocket.z

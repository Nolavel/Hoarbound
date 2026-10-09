# =============================================================================
# item_resource.gd — one item, authored as a .tres in data/items/.
#
# Facet pattern: an optional sub-resource that is null means "not that kind of
# thing". `garment` null is an item you cannot wear; `consumable` null is one
# you cannot eat. A tin of food carries no empty garment fields.
#
# Ported from ADT, trimmed of what this game does not have: the ranged-weapon
# group, held-mesh ownership, throwing, and the Readability axis. HeldFit was
# restored from ADT so each Hoarbound item can own its hand pose.
# =============================================================================
class_name ItemResource
extends Resource

@export_group("Identity")
## Stable id, unique in the catalog. The file name matches it by convention.
@export var id: StringName = &""
## Player-facing name. A localisation key once items are named in game.
@export var display_name: String = "Item"

@export_group("Inventory")
## Kilograms. Gates what the inventory accepts; Kenny's weight is the point.
@export var weight: float = 1.0
## How many of these share one inventory entry. 1 means it never stacks.
@export var max_stack: int = 1

@export_group("Equipment")
## Which sockets will take it at all.
@export var size_class: ItemTraits.SizeClass = ItemTraits.SizeClass.POCKET
## Wearable facet. Null means this item cannot be worn.
@export var garment: GarmentData = null
## Tap-F pickup may move this item from the pack into the first fitting physical
## Quick Access pocket after the stow animation; the Hub (Tab) can re-place it.
@export var prefer_quick_access: bool = false

@export_group("Visuals")
## Mesh on Henry shown while this non-garment rides in a body slot, e.g. Kenny.
@export var attached_mesh_node_name: StringName = &""
## Carried in both hands, never stowed: while held, Henry walks with it in his
## arms, shown by the mesh named in attached_mesh_node_name.
@export var carried_in_hands: bool = false
## Maximum units that can be held as one visible two-hand load.
@export_range(1, 8, 1) var hand_carry_limit: int = 3
## Per-item transform for the ordinary one-hand prop. Null preserves the
## legacy socket fit until this item is authored in the Item Fitter dock.
@export var held_fit: HeldFit = null

@export_group("Survival")
## Edible facet. Null means this item cannot be consumed.
@export var consumable: ConsumableData = null
## What this becomes after warming on a stove top; empty means it does not warm.
@export var warms_into: StringName = &""
## Opening changes the catalog id without consuming food or the required tool.
@export var opens_into: StringName = &""

@export_group("Water")
## Authored fill states keep each physical container in the existing id-only save contract.
@export var water_capacity_ml: int = 0
@export var water_remaining_ml: int = 0


func get_status_text() -> String:
	if water_capacity_ml > 0:
		return tr("FLASK_STATUS") % [water_capacity_ml - water_remaining_ml, water_remaining_ml, water_capacity_ml]
	if consumable != null and consumable.required_tool_id != &"":
		return tr("PINEAPPLE_KNIFE_HINT")
	if id == &"tinned_pineapple_open":
		return tr("PINEAPPLE_OPEN_HINT")
	if id == &"knife":
		return tr("KNIFE_PURPOSE")
	return ""

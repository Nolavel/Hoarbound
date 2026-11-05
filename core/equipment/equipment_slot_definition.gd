# =============================================================================
# equipment_slot_definition.gd — one socket, described as data.
#
# The same class describes a BODY slot (what Henry has: head, torso, legs,
# feet, pack, the fixture Kenny rides on) and a POCKET (what a garment brings
# with it). They are the same thing — a place that holds exactly one item,
# with a limit on what may go there — so they are not two classes.
#
# A socket, not a grid. Fit is one comparison against max_size; there is no
# packing, no rotation and no cell layout.
#
# Ported from ADT. Its `refuses_threatening` flag went with the Readability
# axis; the role it played here is `excluded_from_auto_stow`.
# =============================================================================
class_name EquipmentSlotDefinition
extends Resource

## Stable authored identity, unique within its owner (a layout, or one
## garment). A garment names the body slot it occupies by this id, so a typo
## surfaces as "no such slot" rather than doing nothing quietly.
@export var id: StringName = &""

## Human-facing label, for debug output and a future inventory screen.
@export var display_name: String = ""

## Optional semantic clothing coordinates. Empty values mean this is an
## equipment/utility slot rather than a clothing layer.
@export var body_region: StringName = &""
@export var layer_id: StringName = &""

## The largest item this socket accepts. A coat pocket is POCKET, the pack
## slot is BULKY.
@export var max_size: ItemTraits.SizeClass = ItemTraits.SizeClass.POCKET

## Inside size of a pocket, cm: width, depth, thickness (ItemFootprint.fits against the item's model). Zero:
## the size class alone decides (the pack's main compartment, the carabiners).
@export var inner_cm: Vector3 = Vector3.ZERO

## May something that is NOT a garment go here. False wherever clothing is
## worn and on every pocket; true on the pack and on Kenny's fixture.
@export var accepts_non_garment: bool = false

## Skipped by stow_anywhere(). Kenny's fixture carries this: what rides there
## is a decision Henry makes, never a place the game drops spare weight.
@export var excluded_from_auto_stow: bool = false

## A pocket Henry reaches without opening anything: shown in Quick Access while its garment is worn.
## Inside a pack (its compartments) is reached through the Hub only.
@export var quick_access: bool = true

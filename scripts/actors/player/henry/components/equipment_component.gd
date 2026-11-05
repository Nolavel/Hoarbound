# =============================================================================
# equipment_component.gd — what Henry is wearing and what is in those pockets.
#
# Two levels, and the split is the whole point:
#   BODY SLOTS are fixed, described by an EquipmentLayout resource.
#   POCKETS are not. Each worn garment brings its own (GarmentData.pockets).
#   Take the coat off and its pockets — and their contents — go with it.
#
# Slots are addressed by a body slot id, or "<body_slot>/<pocket>".
#
# Stores item IDs (not ItemResource references) plus optional runtime pocket states.
# Both remain dictionaries/primitives in the established save contract.
#
# Ported from ADT, minus draw/holster (no weapons here), plus the axis ADT
# does not have: get_total_insulation_c(), which feeds ThermalManager.
# =============================================================================
class_name EquipmentComponent
extends Node

## Emitted whenever a slot's contents change. An empty id means emptied.
signal slot_changed(slot_path: StringName, item_id: StringName)
## Emitted when total insulation changes, so the thermal model can resample.
signal insulation_changed(total_c: float)
## Runtime state changed for one worn garment.
signal garment_state_changed(slot_id: StringName, state: Dictionary)

## Why a placement was refused. Never a bare bool: the caller has to be able
## to say what went wrong.
enum Refusal {
	NONE,
	NO_SUCH_SLOT,
	UNKNOWN_ITEM,
	SLOT_OCCUPIED,
	TOO_LARGE,
	WRONG_BODY_SLOT,
	POCKETS_NOT_EMPTY,
	HANDS_ONLY,
	STATEFUL_STACK,
}

const POCKET_SEPARATOR: String = "/"
const LEGACY_SLOT_MIGRATION: Dictionary = {
	&"head": &"head_outer",
	&"torso": &"torso_outer",
	&"legs": &"legs_outer",
	&"feet": &"feet_outer",
}

@export_group("Data")
## The body slots this character has. Without it nothing can be equipped.
@export var layout: EquipmentLayout
## Worn from the start, by item id.
@export var starter_garment_ids: Array[StringName] = []
## Starter items by body slot or worn-pocket path (body_slot/pocket).
@export var starter_slot_items: Dictionary[StringName, StringName] = {}

@export_group("Survival")
## Fraction of insulation retained by a fully soaked garment before condition.
@export_range(0.0, 1.0, 0.01) var soaked_insulation_retention: float = 0.25

@export_group("Debug")
@export var debug_log: bool = false

var _body: Dictionary = {}
var _pockets: Dictionary = {}
## Companion state keyed by physical pocket path; legacy id-only callers remain valid.
var _pocket_states: Dictionary = {}
var _garment_states: Dictionary = {}


func _ready() -> void:
	initialize()


## Wears the starter garments. Public and idempotent so headless tests can
## drive it without waiting for a frame.
func initialize() -> void:
	if not _body.is_empty():
		return
	for item_id: StringName in starter_garment_ids:
		var item: ItemResource = ItemCatalog.get_item(item_id)
		if item == null or item.garment == null:
			continue
		equip(item.garment.body_slot_id, item_id)
	for slot_id: StringName in starter_slot_items:
		var parts: PackedStringArray = String(slot_id).split(POCKET_SEPARATOR)
		if parts.size() == 2:
			stow(StringName(parts[0]), StringName(parts[1]), starter_slot_items[slot_id])
		else:
			equip(slot_id, starter_slot_items[slot_id])


## Kilograms of non-garments riding in body slots and pockets. Clothes are
## worn, not carried; Kenny and pocketed items count toward the load.
func get_carried_weight() -> float:
	var total: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item != null and item.garment == null:
			total += item.weight
	for path: StringName in _pockets:
		var pocketed: ItemResource = ItemCatalog.get_item(_pockets[path])
		if pocketed != null:
			total += pocketed.weight
	return total


## Item worn in a body slot, or empty.
func get_equipped(slot_id: StringName) -> StringName:
	return _body.get(_resolve_body_slot_id(slot_id), &"")


## Item in one pocket of one worn garment, or empty.
func get_pocket_item(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return _pockets.get(pocket_path(body_slot_id, pocket_id), &"")


## A copy of the state owned by a physical pocket item (not the ItemResource).
func get_pocket_instance_state(body_slot_id: StringName, pocket_id: StringName) -> Dictionary:
	var path: StringName = pocket_path(body_slot_id, pocket_id)
	return (_pocket_states.get(path, {}) as Dictionary).duplicate(true)


## Every pocket currently available, which means every pocket brought by
## something currently worn. Entries: body_slot, pocket, definition, item_id.
func get_available_pockets() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if layout == null:
		return available
	for body_slot: EquipmentSlotDefinition in layout.body_slots:
		if body_slot == null:
			continue
		var worn_id: StringName = get_equipped(body_slot.id)
		if worn_id == &"":
			continue
		var worn: ItemResource = ItemCatalog.get_item(worn_id)
		if worn == null or worn.garment == null:
			continue
		for pocket: EquipmentSlotDefinition in worn.garment.pockets:
			if pocket == null:
				continue
			available.append({
				"body_slot": body_slot.id,
				"pocket": pocket.id,
				"definition": pocket,
				"item_id": get_pocket_item(body_slot.id, pocket.id),
			})
	return available


## Degrees of insulation from everything worn on the body. What sits in a
## pocket does not keep anyone warm, so pockets are not counted.
func get_total_insulation_c() -> float:
	var total: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item != null and item.garment != null:
			total += item.garment.get_base_insulation_c()
	return total


## Effective protection is definition data × instance condition × instance wetness.
func get_effective_insulation_c() -> float:
	var total: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item == null or item.garment == null or item.garment.body_region == &"":
			continue
		var state: GarmentInstanceState = _ensure_garment_state(slot_id)
		var wet_factor: float = lerpf(1.0, soaked_insulation_retention, state.wetness)
		total += item.garment.get_base_insulation_c() * state.condition * wet_factor
	return total


## What covers one body region: effective insulation, best windproofing and the wettest layer.
func get_region_protection(region: StringName) -> Dictionary:
	var insulation: float = 0.0
	var windproof: float = 0.0
	var wetness: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item == null or item.garment == null or item.garment.body_region != region:
			continue
		var state: GarmentInstanceState = _ensure_garment_state(slot_id)
		insulation += item.garment.get_base_insulation_c() * state.condition * lerpf(1.0, soaked_insulation_retention, state.wetness)
		windproof = maxf(windproof, item.garment.windproof * state.condition)
		wetness = maxf(wetness, state.wetness)
	return {"insulation_c": insulation, "windproof": windproof, "wetness": wetness}


func get_wind_protection() -> float:
	return _aggregate_region_protection(&"windproof")


func get_water_protection() -> float:
	return _aggregate_region_protection(&"waterproof")


func get_average_wetness() -> float:
	var total: float = 0.0
	var count: int = 0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item == null or item.garment == null or item.garment.body_region == &"":
			continue
		total += _ensure_garment_state(slot_id).wetness
		count += 1
	return total / float(count) if count > 0 else 0.0


func has_wet_garments() -> bool:
	return get_average_wetness() > 0.001


func get_garment_state(slot_id: StringName) -> Dictionary:
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	if get_equipped(resolved) == &"":
		return {}
	var item: ItemResource = ItemCatalog.get_item(get_equipped(resolved))
	if item == null or item.garment == null:
		return {}
	return _ensure_garment_state(resolved).to_dict()


func set_garment_wetness(slot_id: StringName, wetness: float) -> bool:
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	var state: GarmentInstanceState = _ensure_existing_garment_state(resolved)
	if state == null:
		return false
	state.set_wetness(wetness)
	_emit_garment_state(resolved)
	return true


func damage_garment(slot_id: StringName, amount: float) -> bool:
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	var state: GarmentInstanceState = _ensure_existing_garment_state(resolved)
	if state == null:
		return false
	state.damage(amount)
	_emit_garment_state(resolved)
	return true


func repair_garment(slot_id: StringName, amount: float) -> bool:
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	var state: GarmentInstanceState = _ensure_existing_garment_state(resolved)
	if state == null:
		return false
	state.repair(amount)
	_emit_garment_state(resolved)
	return true


func add_wetness_all(amount: float) -> void:
	if amount <= 0.0:
		return
	for slot_id: StringName in _body:
		var state: GarmentInstanceState = _ensure_existing_garment_state(slot_id)
		if state == null:
			continue
		state.add_wetness(amount)
		_emit_garment_state(slot_id)


## Applies precipitation outside-in per body region, then dries every layer by
## its own authored rate. Outer waterproofing reduces penetration to inner layers.
func advance_garment_moisture(hours: float, exposure_rate_per_hour: float, drying_warmth: float) -> void:
	if hours <= 0.0:
		return
	var regions: Dictionary = {}
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item == null or item.garment == null or item.garment.body_region == &"":
			continue
		var region: StringName = item.garment.body_region
		if not regions.has(region):
			regions[region] = []
		(regions[region] as Array).append(slot_id)

	for region: StringName in regions:
		var slots: Array = regions[region]
		slots.sort_custom(func(a: StringName, b: StringName) -> bool:
			var ga: GarmentData = ItemCatalog.get_item(_body[a]).garment
			var gb: GarmentData = ItemCatalog.get_item(_body[b]).garment
			return int(ga.layer) > int(gb.layer)
		)
		var penetration: float = maxf(exposure_rate_per_hour, 0.0) * hours
		for slot_variant: Variant in slots:
			var slot_id := StringName(slot_variant)
			var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
			var garment: GarmentData = item.garment
			var state: GarmentInstanceState = _ensure_garment_state(slot_id)
			var before_wet: float = state.wetness
			if penetration > 0.0:
				var resistance: float = clampf(garment.waterproof * state.condition, 0.0, 1.0)
				penetration *= 1.0 - resistance
				state.add_wetness(penetration)
			state.dry(garment.drying_rate * clampf(drying_warmth, 0.0, 1.0) * hours)
			if not is_equal_approx(before_wet, state.wetness):
				_emit_garment_state(slot_id)


## Whether this item could go in this body slot right now.
func can_equip(slot_id: StringName, item_id: StringName) -> Refusal:
	slot_id = _resolve_body_slot_id(slot_id)
	var definition: EquipmentSlotDefinition = _find_body_slot(slot_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_equipped(slot_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.carried_in_hands:
		return Refusal.HANDS_ONLY
	if item.garment != null:
		if _resolve_body_slot_id(item.garment.body_slot_id) != slot_id:
			return Refusal.WRONG_BODY_SLOT
		if definition.body_region != &"" and item.garment.body_region != definition.body_region:
			return Refusal.WRONG_BODY_SLOT
		if definition.layer_id != &"" and item.garment.get_layer_id() != definition.layer_id:
			return Refusal.WRONG_BODY_SLOT
	elif not definition.accepts_non_garment:
		return Refusal.WRONG_BODY_SLOT
	return _check_fit(definition, item)


## Whether this item could go in this pocket right now.
func can_stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	var definition: EquipmentSlotDefinition = _find_pocket(body_slot_id, pocket_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_pocket_item(body_slot_id, pocket_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.carried_in_hands:
		return Refusal.HANDS_ONLY
	return _check_fit(definition, item)


## Wears an item. REFUSES an occupied slot rather than swapping: a component
## that knows nothing about the inventory could only drop what it displaced.
func equip(slot_id: StringName, item_id: StringName, garment_state: Dictionary = {}) -> Refusal:
	slot_id = _resolve_body_slot_id(slot_id)
	var refusal: Refusal = can_equip(slot_id, item_id)
	if refusal != Refusal.NONE:
		_log("equip refused", slot_id, item_id, refusal)
		return refusal
	_body[slot_id] = item_id
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item != null and item.garment != null:
		_garment_states[slot_id] = GarmentInstanceState.from_dict(garment_state)
	slot_changed.emit(slot_id, item_id)
	insulation_changed.emit(get_effective_insulation_c())
	return Refusal.NONE


## Takes a garment off and returns it. Refuses while its own pockets hold
## anything — emptying someone's coat for them is not this component's call.
func unequip(slot_id: StringName) -> StringName:
	var payload: Dictionary = take_off_instance(slot_id)
	return StringName(payload.get("id", ""))


## Stateful removal path for inventory transfers. The returned state belongs to
## this physical garment instance and must travel with it.
func take_off_instance(slot_id: StringName) -> Dictionary:
	slot_id = _resolve_body_slot_id(slot_id)
	var item_id: StringName = get_equipped(slot_id)
	if item_id == &"":
		return {}
	if not _pockets_empty_for(slot_id):
		_log("unequip refused", slot_id, item_id, Refusal.POCKETS_NOT_EMPTY)
		return {}
	var state: Dictionary = {}
	if _garment_states.has(slot_id):
		state = (_garment_states[slot_id] as GarmentInstanceState).to_dict()
	_body.erase(slot_id)
	_garment_states.erase(slot_id)
	slot_changed.emit(slot_id, &"")
	insulation_changed.emit(get_effective_insulation_c())
	return {"id": String(item_id), "garment_state": state}


## Moves a worn garment into Inventory while preserving per-instance state.
func unequip_to_inventory(slot_id: StringName, inventory: InventoryComponent) -> bool:
	if inventory == null:
		return false
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	var item_id: StringName = get_equipped(resolved)
	if item_id == &"" or not _pockets_empty_for(resolved):
		return false
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null or inventory.get_add_refusal(item) != &"":
		return false
	var payload: Dictionary = take_off_instance(resolved)
	if payload.is_empty():
		return false
	var state: Dictionary = payload.get("garment_state", {})
	if inventory.try_add_instance(item, state):
		return true
	# Defensive rollback: inventory refusal changed after preflight.
	equip(resolved, item_id, state)
	return false


## Equips one carried non-stackable garment instance, restoring its runtime state.
func equip_from_inventory(slot_id: StringName, item_id: StringName, inventory: InventoryComponent) -> Refusal:
	if inventory == null:
		return Refusal.UNKNOWN_ITEM
	var resolved: StringName = _resolve_body_slot_id(slot_id)
	var refusal: Refusal = can_equip(resolved, item_id)
	if refusal != Refusal.NONE:
		return refusal
	var payload: Dictionary = inventory.take_instance(item_id)
	if payload.is_empty():
		return Refusal.UNKNOWN_ITEM
	var state: Dictionary = payload.get("instance_state", {})
	refusal = equip(resolved, item_id, state)
	if refusal != Refusal.NONE:
		var item: ItemResource = payload.get("item") as ItemResource
		if item != null:
			inventory.try_add_instance(item, state)
	return refusal


## Legacy id-only path for ordinary stateless items.
func stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	return stow_instance(body_slot_id, pocket_id, item_id)


## Accepts a physical instance and its mutable state without changing the slot model.
func stow_instance(body_slot_id: StringName, pocket_id: StringName, item_id: StringName, instance_state: Dictionary = {}) -> Refusal:
	var refusal: Refusal = can_stow(body_slot_id, pocket_id, item_id)
	if refusal != Refusal.NONE:
		_log("stow refused", pocket_path(body_slot_id, pocket_id), item_id, refusal)
		return refusal
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item.max_stack > 1 and not instance_state.is_empty():
		return Refusal.STATEFUL_STACK
	var path: StringName = pocket_path(body_slot_id, pocket_id)
	_pockets[path] = item_id
	if not instance_state.is_empty():
		_pocket_states[path] = instance_state.duplicate(true)
	slot_changed.emit(path, item_id)
	return Refusal.NONE


## The state-aware counterpart to take_from_pocket(). Returns {} when empty.
func take_pocket_instance(body_slot_id: StringName, pocket_id: StringName) -> Dictionary:
	var path: StringName = pocket_path(body_slot_id, pocket_id)
	var item_id: StringName = _pockets.get(path, &"")
	if item_id == &"":
		return {}
	var state: Dictionary = get_pocket_instance_state(body_slot_id, pocket_id)
	_pockets.erase(path)
	_pocket_states.erase(path)
	slot_changed.emit(path, &"")
	return {"id": item_id, "instance_state": state}


## An id-only caller cannot safely remove a stateful item; refuse rather than
## quietly erase its condition/fuel/etc. Such callers must use take_pocket_instance.
func take_from_pocket(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	if not get_pocket_instance_state(body_slot_id, pocket_id).is_empty():
		push_warning("Equipment: stateful pocket item requires take_pocket_instance()")
		return &""
	return StringName(take_pocket_instance(body_slot_id, pocket_id).get("id", ""))


## Finds somewhere for an item: worn if it is a garment, then any empty
## pocket, then any body slot that takes non-garments. Slots marked
## excluded_from_auto_stow are skipped — Kenny's fixture is not a spare shelf.
## Returns the most informative refusal when nothing takes it.
func stow_anywhere(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.carried_in_hands:
		return Refusal.HANDS_ONLY
	if item.garment != null and equip(item.garment.body_slot_id, item_id) == Refusal.NONE:
		return Refusal.NONE

	var reason: Refusal = Refusal.NO_SUCH_SLOT
	for pocket: Dictionary in get_available_pockets():
		if pocket["item_id"] != &"":
			continue
		var refusal: Refusal = can_stow(pocket["body_slot"], pocket["pocket"], item_id)
		if refusal == Refusal.NONE:
			return stow(pocket["body_slot"], pocket["pocket"], item_id)
		reason = refusal

	if layout != null:
		for body_slot: EquipmentSlotDefinition in layout.body_slots:
			if body_slot == null or not body_slot.accepts_non_garment:
				continue
			if body_slot.excluded_from_auto_stow or get_equipped(body_slot.id) != &"":
				continue
			var refusal: Refusal = can_equip(body_slot.id, item_id)
			if refusal == Refusal.NONE:
				return equip(body_slot.id, item_id)
			reason = refusal
	return reason


## Address of one pocket, as stored and as reported by slot_changed.
func pocket_path(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	var resolved: StringName = _resolve_body_slot_id(body_slot_id)
	return StringName("%s%s%s" % [resolved, POCKET_SEPARATOR, pocket_id])


func get_save_key() -> StringName:
	return &"equipment"


func get_save_data() -> Dictionary:
	var states: Dictionary = {}
	for slot_id: StringName in _garment_states:
		states[String(slot_id)] = (_garment_states[slot_id] as GarmentInstanceState).to_dict()
	var pocket_states: Dictionary = {}
	for path: StringName in _pocket_states:
		pocket_states[String(path)] = (_pocket_states[path] as Dictionary).duplicate(true)
	return {
		"body": _to_string_keys(_body),
		"pockets": _to_string_keys(_pockets),
		"pocket_states": pocket_states,
		"garment_states": states,
	}


## Restores body slots BEFORE pockets: a pocket only exists while the garment
## that brings it is worn. Every id is re-validated against the layout and the
## catalog rather than trusted, so a stale save drops entries instead of
## resurrecting items that no longer exist.
func load_save_data(data: Dictionary) -> void:
	_body.clear()
	_pockets.clear()
	_pocket_states.clear()
	_garment_states.clear()

	var saved_body: Dictionary = data.get("body", {})
	for slot_key: Variant in saved_body:
		var slot_id := _resolve_body_slot_id(StringName(slot_key))
		var item_id := StringName(saved_body[slot_key])
		if _find_body_slot(slot_id) == null:
			push_warning("Equipment: save names body slot '%s', the layout does not" % slot_id)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_body[slot_id] = item_id
		var item: ItemResource = ItemCatalog.get_item(item_id)
		if item != null and item.garment != null:
			_garment_states[slot_id] = GarmentInstanceState.new()

	var saved_pockets: Dictionary = data.get("pockets", {})
	for path_key: Variant in saved_pockets:
		var parts: PackedStringArray = String(path_key).split(POCKET_SEPARATOR)
		if parts.size() != 2:
			push_warning("Equipment: malformed pocket path '%s' in save" % path_key)
			continue
		var item_id := StringName(saved_pockets[path_key])
		var migrated_slot: StringName = _resolve_body_slot_id(StringName(parts[0]))
		if _find_pocket(migrated_slot, StringName(parts[1])) == null:
			push_warning("Equipment: nothing worn provides pocket '%s'" % path_key)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_pockets[pocket_path(migrated_slot, StringName(parts[1]))] = item_id

	# Old saves have no pocket_states key. Preserve that id-only layout unchanged.
	var saved_pocket_states: Dictionary = data.get("pocket_states", {})
	for path_key: Variant in saved_pocket_states:
		var parts: PackedStringArray = String(path_key).split(POCKET_SEPARATOR)
		if parts.size() != 2:
			continue
		var path: StringName = pocket_path(StringName(parts[0]), StringName(parts[1]))
		if not _pockets.has(path):
			continue
		var state_data: Variant = saved_pocket_states[path_key]
		var item: ItemResource = ItemCatalog.get_item(_pockets[path])
		if item == null or item.max_stack != 1 or typeof(state_data) != TYPE_DICTIONARY:
			continue
		if not (state_data as Dictionary).is_empty():
			_pocket_states[path] = (state_data as Dictionary).duplicate(true)

	var saved_states: Dictionary = data.get("garment_states", {})
	for slot_key: Variant in saved_states:
		var slot_id: StringName = _resolve_body_slot_id(StringName(slot_key))
		if not _body.has(slot_id):
			push_warning("Equipment: garment state names empty slot '%s'" % slot_key)
			continue
		var state_data: Variant = saved_states[slot_key]
		if typeof(state_data) != TYPE_DICTIONARY:
			push_warning("Equipment: malformed garment state for '%s'" % slot_key)
			continue
		_garment_states[slot_id] = GarmentInstanceState.from_dict(state_data)

	insulation_changed.emit(get_effective_insulation_c())


## Too large by size class, or (a pocket with an inner size) by the item's real size; clothing squashes, so only
## the class counts for a garment.
func _check_fit(definition: EquipmentSlotDefinition, item: ItemResource) -> Refusal:
	if item.size_class > definition.max_size:
		return Refusal.TOO_LARGE
	if definition.inner_cm != Vector3.ZERO and item.garment == null and not ItemFootprint.fits(item.id, definition.inner_cm):
		return Refusal.TOO_LARGE
	return Refusal.NONE


func _find_body_slot(slot_id: StringName) -> EquipmentSlotDefinition:
	if layout == null:
		return null
	return layout.find_slot(_resolve_body_slot_id(slot_id))


func _resolve_body_slot_id(slot_id: StringName) -> StringName:
	if layout != null and layout.find_slot(slot_id) != null:
		return slot_id
	var migrated: StringName = LEGACY_SLOT_MIGRATION.get(slot_id, &"")
	if migrated != &"" and layout != null and layout.find_slot(migrated) != null:
		return migrated
	return slot_id


## A pocket exists only while the garment bringing it is worn in that slot.
func _find_pocket(body_slot_id: StringName, pocket_id: StringName) -> EquipmentSlotDefinition:
	var worn_id: StringName = get_equipped(body_slot_id)
	if worn_id == &"":
		return null
	var worn: ItemResource = ItemCatalog.get_item(worn_id)
	if worn == null or worn.garment == null:
		return null
	for pocket: EquipmentSlotDefinition in worn.garment.pockets:
		if pocket != null and pocket.id == pocket_id:
			return pocket
	return null


func _pockets_empty_for(body_slot_id: StringName) -> bool:
	body_slot_id = _resolve_body_slot_id(body_slot_id)
	var prefix: String = "%s%s" % [body_slot_id, POCKET_SEPARATOR]
	for path: StringName in _pockets:
		if String(path).begins_with(prefix) and _pockets[path] != &"":
			return false
	return true


func _ensure_existing_garment_state(slot_id: StringName) -> GarmentInstanceState:
	if not _body.has(slot_id):
		return null
	var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
	if item == null or item.garment == null:
		return null
	return _ensure_garment_state(slot_id)


func _ensure_garment_state(slot_id: StringName) -> GarmentInstanceState:
	if not _garment_states.has(slot_id):
		_garment_states[slot_id] = GarmentInstanceState.new()
	return _garment_states[slot_id] as GarmentInstanceState


func _emit_garment_state(slot_id: StringName) -> void:
	var state: GarmentInstanceState = _ensure_existing_garment_state(slot_id)
	if state == null:
		return
	garment_state_changed.emit(slot_id, state.to_dict())
	insulation_changed.emit(get_effective_insulation_c())


func _aggregate_region_protection(property_name: StringName) -> float:
	var by_region: Dictionary = {}
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item == null or item.garment == null or item.garment.body_region == &"":
			continue
		var garment: GarmentData = item.garment
		var state: GarmentInstanceState = _ensure_garment_state(slot_id)
		var authored: float = float(garment.get(property_name))
		var protection: float = clampf(authored * state.condition, 0.0, 1.0)
		var region: StringName = garment.body_region
		var previous_unblocked: float = 1.0 - float(by_region.get(region, 0.0))
		by_region[region] = 1.0 - previous_unblocked * (1.0 - protection)
	if by_region.is_empty():
		return 0.0
	var total: float = 0.0
	for region: StringName in by_region:
		total += float(by_region[region])
	return total / float(by_region.size())


## StringName keys do not survive JSON, so the save carries plain strings.
func _to_string_keys(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in source:
		out[String(key)] = String(source[key])
	return out


func _log(action: String, slot: StringName, item_id: StringName, refusal: Refusal) -> void:
	if debug_log:
		print("[Equipment] %s: %s / %s (%s)" % [action, slot, item_id, Refusal.keys()[refusal]])

# =============================================================================
# item_catalog.gd — every item in the game, resolvable by id.
#
# Loaded BY PATH, never by scanning the directory: an exported build converts
# .tres to binary behind a .remap, and a runtime DirAccess scan finds nothing.
# That is not a preference, it is the difference between working in the editor
# and working in a build.
#
# Not an autoload and not a Node — a static accessor, so anything can reach it
# without being wired to it.
#
# Ported from ADT unchanged.
# =============================================================================
class_name ItemCatalog
extends Resource

const CATALOG_PATH: String = "res://data/items/catalog.tres"

@export var items: Array[ItemResource] = []

static var _shared: ItemCatalog = null
static var _warned_missing: bool = false

var _index: Dictionary = {}
var _index_built: bool = false


## The one catalog, loaded on first use. Warns once when it is absent, because
## without it no item id resolves and every later warning would be noise.
static func shared() -> ItemCatalog:
	if _shared != null:
		return _shared
	_shared = load(CATALOG_PATH) as ItemCatalog
	if _shared == null and not _warned_missing:
		_warned_missing = true
		push_warning("ItemCatalog: no catalog at %s — no item id will resolve" % CATALOG_PATH)
	return _shared


## The item with this id, warning when it is unknown. Use this from gameplay,
## where an unresolvable id is a defect worth hearing about.
static func get_item(id: StringName) -> ItemResource:
	var catalog: ItemCatalog = shared()
	if catalog == null:
		return null
	var item: ItemResource = catalog.find(id)
	if item == null:
		push_warning("ItemCatalog: unknown item id '%s'" % id)
	return item


## Silent lookup, for callers that are asking whether an id exists at all.
func find(id: StringName) -> ItemResource:
	if not _index_built:
		_build_index()
	return _index.get(id) as ItemResource


## Drops the cached catalog, so a test can point at a different one.
static func reset_shared() -> void:
	_shared = null
	_warned_missing = false


## Pure authoring check: safe for tests and editor validation without printing errors.
## A repeated definition id is not a second physical item instance.
func validate_entries() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen: Dictionary = {}
	for item: ItemResource in items:
		if item == null:
			errors.append("ItemCatalog: null item resource")
			continue
		if item.id == &"":
			errors.append("ItemCatalog: an item has no id")
			continue
		if seen.has(item.id):
			errors.append("ItemCatalog: duplicate definition id '%s'" % item.id)
		else:
			seen[item.id] = true
	return errors


func _build_index() -> void:
	_index.clear()
	for item: ItemResource in items:
		if item == null:
			push_error("ItemCatalog: null item resource")
			continue
		if item.id == &"":
			push_error("ItemCatalog: an item has no id — it can never be resolved")
			continue
		if _index.has(item.id):
			# Never silently replace an existing definition because a save resolves by id.
			push_error("ItemCatalog: duplicate definition id '%s' — keeping the first" % item.id)
			continue
		_index[item.id] = item
	_index_built = true

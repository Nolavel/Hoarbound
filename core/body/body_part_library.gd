class_name BodyPartLibrary
extends Resource

## Every body part the cold model and the HUD silhouette know, loaded by path like ItemCatalog.
## A new part (ears, eyes) is a new BodyPartDefinition in the library, not new code.

const LIBRARY_PATH: String = "res://data/body/body_parts.tres"

@export var parts: Array[BodyPartDefinition] = []

static var _shared: BodyPartLibrary = null


## The one library, loaded on first use; an empty library when the file is missing.
static func shared() -> BodyPartLibrary:
	if _shared == null:
		_shared = load(LIBRARY_PATH) as BodyPartLibrary
		if _shared == null:
			push_warning("BodyPartLibrary: no library at %s" % LIBRARY_PATH)
			_shared = BodyPartLibrary.new()
	return _shared


## The part with this id, or null.
func find(id: StringName) -> BodyPartDefinition:
	for part: BodyPartDefinition in parts:
		if part != null and part.id == id:
			return part
	return null


## Ids in library order.
func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for part: BodyPartDefinition in parts:
		if part != null:
			ids.append(part.id)
	return ids

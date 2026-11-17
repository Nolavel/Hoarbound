class_name PassageProviderCapability
extends RefCounted

## Something that frames a narrow way through (a door's opening, a narrow passage): info() -> PassageInfo, or null
## while it offers none. Providers sit in PassageInfo.GROUP; the legacy get_passage_info name is adapted here.

const ID: StringName = &"passage_provider"
const INFO: StringName = &"info"
const LEGACY_INFO: StringName = &"get_passage_info"


static func publish(owner: Object, info_method: StringName) -> bool:
	return CapabilityContract.publish_self(owner, ID, {INFO: info_method})


static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(LEGACY_INFO):
		return false
	return publish(owner, LEGACY_INFO)


## Its passage now, or null (not a provider, or none offered).
static func info(owner: Object) -> PassageInfo:
	if not ensure(owner):
		return null
	return CapabilityContract.invoke(owner, ID, INFO) as PassageInfo

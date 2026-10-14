extends SceneTree

const EXPECTED_FROST_TRACE := "0,250,500,1000,0,500,1000"

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	for native_class: StringName in [&"HoarboundNativeProbe", &"HoarboundFrostModel", &"HoarboundFrostController"]:
		if not ClassDB.class_exists(native_class):
			fail("Native class was not registered: %s" % native_class)
			return

	var probe: Object = ClassDB.instantiate(&"HoarboundNativeProbe") as Object
	if probe == null or probe.call(&"ping") != "hoarbound-native-ok" or probe.call(&"build_contract") != "godot-4.8-dev6":
		fail("Native probe contract failed")
		return

	var frost: Object = ClassDB.instantiate(&"HoarboundFrostModel") as Object
	if frost == null or frost.call(&"reference_trace") != EXPECTED_FROST_TRACE:
		fail("Portable frost model trace failed")
		return
	frost.call(&"set_duration", 4.0)
	frost.call(&"restart")
	var quarter: float = frost.call(&"advance", 1.0)
	frost.call(&"set_frost_amount", 2.0)
	if not is_equal_approx(quarter, 0.25) or not is_equal_approx(frost.call(&"get_frost_amount"), 1.0):
		fail("GDExtension frost model contract failed")
		return

	var controller: Node = ClassDB.instantiate(&"HoarboundFrostController") as Node
	if controller == null:
		fail("Frost controller could not be instantiated")
		return
	controller.call(&"set_freeze_duration", 4.0)
	controller.call(&"restart_frost_demo")
	controller.call(&"set_frost_amount", 0.5)
	if not is_equal_approx(controller.call(&"get_frost_amount"), 0.5):
		fail("GDExtension frost controller contract failed")
		return
	controller.free()

	print("HOARBOUND_FROST_CORE_TRACE=", EXPECTED_FROST_TRACE)
	print("HOARBOUND_NATIVE_SMOKE_OK")
	quit(0)

#include "register_types.h"

#include "hoarbound_frost_controller.h"
#include "hoarbound_frost_model.h"
#include "hoarbound_native_probe.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_hoarbound_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(HoarboundFrostController);
	GDREGISTER_CLASS(HoarboundFrostModel);
	GDREGISTER_CLASS(HoarboundNativeProbe);
}

void uninitialize_hoarbound_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {

GDExtensionBool GDE_EXPORT hoarbound_native_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_object(p_get_proc_address, p_library, r_initialization);
	init_object.register_initializer(initialize_hoarbound_native);
	init_object.register_terminator(uninitialize_hoarbound_native);
	init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}

}

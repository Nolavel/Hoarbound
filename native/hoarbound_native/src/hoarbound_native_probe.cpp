#include "hoarbound_native_probe.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void HoarboundNativeProbe::_bind_methods() {
	ClassDB::bind_method(D_METHOD("ping"), &HoarboundNativeProbe::ping);
	ClassDB::bind_method(D_METHOD("build_contract"), &HoarboundNativeProbe::build_contract);
}

String HoarboundNativeProbe::ping() const {
	return "hoarbound-native-ok";
}

String HoarboundNativeProbe::build_contract() const {
	return "godot-4.8-dev6";
}

} // namespace godot


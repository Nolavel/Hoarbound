#include "hoarbound_frost_model.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void HoarboundFrostModel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_duration", "duration_seconds"), &HoarboundFrostModel::set_duration);
	ClassDB::bind_method(D_METHOD("get_duration"), &HoarboundFrostModel::get_duration);
	ClassDB::bind_method(D_METHOD("set_frost_amount", "amount"), &HoarboundFrostModel::set_frost_amount);
	ClassDB::bind_method(D_METHOD("get_frost_amount"), &HoarboundFrostModel::get_frost_amount);
	ClassDB::bind_method(D_METHOD("restart"), &HoarboundFrostModel::restart);
	ClassDB::bind_method(D_METHOD("advance", "delta_seconds"), &HoarboundFrostModel::advance);
	ClassDB::bind_method(D_METHOD("set_auto_playing", "enabled"), &HoarboundFrostModel::set_auto_playing);
	ClassDB::bind_method(D_METHOD("is_auto_playing"), &HoarboundFrostModel::is_auto_playing);
	ClassDB::bind_method(D_METHOD("reference_trace"), &HoarboundFrostModel::reference_trace);
}

void HoarboundFrostModel::set_duration(double duration_seconds) {
	progression_.set_duration(duration_seconds);
}

double HoarboundFrostModel::get_duration() const {
	return progression_.duration();
}

void HoarboundFrostModel::set_frost_amount(double amount) {
	progression_.set_amount(amount);
}

double HoarboundFrostModel::get_frost_amount() const {
	return progression_.amount();
}

void HoarboundFrostModel::restart() {
	progression_.restart();
}

double HoarboundFrostModel::advance(double delta_seconds) {
	return progression_.advance(delta_seconds);
}

void HoarboundFrostModel::set_auto_playing(bool enabled) {
	progression_.set_auto_playing(enabled);
}

bool HoarboundFrostModel::is_auto_playing() const {
	return progression_.is_auto_playing();
}

String HoarboundFrostModel::reference_trace() const {
	return String(hoarbound::frost::reference_trace().c_str());
}

} // namespace godot

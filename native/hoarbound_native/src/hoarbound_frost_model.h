#ifndef HOARBOUND_FROST_MODEL_H
#define HOARBOUND_FROST_MODEL_H

#include "frost_progression.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class HoarboundFrostModel : public RefCounted {
	GDCLASS(HoarboundFrostModel, RefCounted)

protected:
	static void _bind_methods();

public:
	void set_duration(double duration_seconds);
	double get_duration() const;
	void set_frost_amount(double amount);
	double get_frost_amount() const;
	void restart();
	double advance(double delta_seconds);
	void set_auto_playing(bool enabled);
	bool is_auto_playing() const;
	String reference_trace() const;

private:
	hoarbound::frost::FrostProgression progression_;
};

} // namespace godot

#endif // HOARBOUND_FROST_MODEL_H

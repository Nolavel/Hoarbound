#ifndef HOARBOUND_NATIVE_PROBE_H
#define HOARBOUND_NATIVE_PROBE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class HoarboundNativeProbe : public RefCounted {
	GDCLASS(HoarboundNativeProbe, RefCounted)

protected:
	static void _bind_methods();

public:
	String ping() const;
	String build_contract() const;
};

} // namespace godot

#endif // HOARBOUND_NATIVE_PROBE_H


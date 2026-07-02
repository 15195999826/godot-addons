#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

// Presence/diagnostics probe for the sim-nav-map native backend.
//
// GDScript must reach every SimNavNative* class through ClassDB indirection
// (class_exists + instantiate), never by direct identifier: platforms without
// a built library must still parse all addon scripts.
class SimNavNativeSupport : public godot::RefCounted {
	GDCLASS(SimNavNativeSupport, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	godot::String version() const;
	godot::Dictionary build_info() const;
};

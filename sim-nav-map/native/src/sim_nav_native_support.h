#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
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
	// Float-primitive parity probes (test support): each applies the same
	// operation the motion solver uses so a GDScript sweep can compare against
	// the engine's own results bit-for-bit and pinpoint CRT/codegen ULP drift.
	godot::PackedVector2Array probe_from_angle(const godot::PackedFloat64Array &p_angles) const;
	godot::PackedVector2Array probe_from_angle_via_double(const godot::PackedFloat64Array &p_angles) const;
	godot::PackedFloat64Array probe_vec_angle(const godot::PackedVector2Array &p_vectors) const;
	godot::PackedVector2Array probe_normalized(const godot::PackedVector2Array &p_vectors) const;
	godot::PackedFloat64Array probe_length(const godot::PackedVector2Array &p_vectors) const;
	godot::PackedFloat64Array probe_distance(const godot::PackedVector2Array &p_pairs) const;
	godot::PackedFloat64Array probe_dot(const godot::PackedVector2Array &p_pairs) const;
	godot::PackedVector2Array probe_rotated(const godot::PackedVector2Array &p_vectors, const godot::PackedFloat64Array &p_angles) const;
};

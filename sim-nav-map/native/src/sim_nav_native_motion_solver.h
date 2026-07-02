#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "core/sim_nav_motion_solver.h"

// GDExtension boundary for simnav::MotionSolver: ONE call per tick moves the
// whole Phase A/B hot path across as SoA packed arrays (unit truth stays on
// the GDScript Dota2LabUnit objects; Phase C reads the written-back values).
// PackedFloat64Array carries GDScript doubles losslessly; positions cross as
// float32 Vector2s, which is their storage width on both sides.
class SimNavNativeMotionSolver : public godot::RefCounted {
	GDCLASS(SimNavNativeMotionSolver, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	godot::Dictionary step(
			const godot::PackedVector2Array &p_positions,
			const godot::PackedFloat64Array &p_facing,
			const godot::PackedFloat64Array &p_radius,
			const godot::PackedFloat64Array &p_speed,
			const godot::PackedFloat64Array &p_turn_rate,
			const godot::PackedByteArray &p_moving,
			const godot::PackedByteArray &p_mobile,
			const godot::PackedByteArray &p_has_path,
			const godot::PackedVector2Array &p_track,
			const godot::PackedFloat64Array &p_steer_side,
			const godot::PackedInt32Array &p_id_rank,
			const godot::PackedVector2Array &p_static_centers,
			const godot::PackedFloat64Array &p_static_dims,
			const godot::Dictionary &p_params);

private:
	simnav::MotionSolver solver;
};

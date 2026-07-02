#include "sim_nav_native_motion_solver.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void SimNavNativeMotionSolver::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("step", "positions", "facing", "radius", "speed", "turn_rate", "moving", "mobile", "has_path", "track", "steer_side", "id_rank", "static_centers", "static_dims", "params"),
			&SimNavNativeMotionSolver::step);
}

Dictionary SimNavNativeMotionSolver::step(
		const PackedVector2Array &p_positions,
		const PackedFloat64Array &p_facing,
		const PackedFloat64Array &p_radius,
		const PackedFloat64Array &p_speed,
		const PackedFloat64Array &p_turn_rate,
		const PackedByteArray &p_moving,
		const PackedByteArray &p_mobile,
		const PackedByteArray &p_has_path,
		const PackedVector2Array &p_track,
		const PackedFloat64Array &p_steer_side,
		const PackedInt32Array &p_id_rank,
		const PackedVector2Array &p_static_centers,
		const PackedFloat64Array &p_static_dims,
		const Dictionary &p_params) {
	Dictionary out;
	int64_t count = p_positions.size();
	ERR_FAIL_COND_V_MSG(
			p_facing.size() != count || p_radius.size() != count || p_speed.size() != count ||
					p_turn_rate.size() != count || p_moving.size() != count || p_mobile.size() != count ||
					p_has_path.size() != count || p_track.size() != count || p_steer_side.size() != count ||
					p_id_rank.size() != count,
			out, "unit array sizes disagree");
	ERR_FAIL_COND_V_MSG(p_static_dims.size() != p_static_centers.size() * 3, out, "static_dims must hold (width, height, rotation) triplets");

	simnav::MotionState state;
	if (count > 0) {
		state.position.assign(p_positions.ptr(), p_positions.ptr() + count);
		state.facing_angle_rad.assign(p_facing.ptr(), p_facing.ptr() + count);
		state.radius.assign(p_radius.ptr(), p_radius.ptr() + count);
		state.speed.assign(p_speed.ptr(), p_speed.ptr() + count);
		state.turn_rate_rad_per_sec.assign(p_turn_rate.ptr(), p_turn_rate.ptr() + count);
		state.moving.assign(p_moving.ptr(), p_moving.ptr() + count);
		state.mobile.assign(p_mobile.ptr(), p_mobile.ptr() + count);
		state.has_path.assign(p_has_path.ptr(), p_has_path.ptr() + count);
		state.track_point.assign(p_track.ptr(), p_track.ptr() + count);
		state.steer_side.assign(p_steer_side.ptr(), p_steer_side.ptr() + count);
		state.id_rank.assign(p_id_rank.ptr(), p_id_rank.ptr() + count);
	}
	state.last_speed_factor.assign((size_t)count, 0.0);
	state.last_turn_delta_rad.assign((size_t)count, 0.0);

	simnav::MotionStatics statics;
	int64_t static_count = p_static_centers.size();
	if (static_count > 0) {
		statics.center.assign(p_static_centers.ptr(), p_static_centers.ptr() + static_count);
	}
	statics.width.resize((size_t)static_count);
	statics.height.resize((size_t)static_count);
	statics.rotation_rad.resize((size_t)static_count);
	for (int64_t s = 0; s < static_count; s++) {
		statics.width[(size_t)s] = p_static_dims[s * 3];
		statics.height[(size_t)s] = p_static_dims[s * 3 + 1];
		statics.rotation_rad[(size_t)s] = p_static_dims[s * 3 + 2];
	}

	simnav::MotionParams params;
	params.delta = (double)p_params.get("delta", 0.0);
	params.pushability_moving = (double)p_params.get("pushability_moving", 0.35);
	params.pushability_idle = (double)p_params.get("pushability_idle", 1.0);
	params.contact_steering_enabled = (bool)p_params.get("contact_steering_enabled", true);
	params.separation_brute_force_max = (int)(int64_t)p_params.get("separation_brute_force_max", 16);
	params.map_size = (Vector2)p_params.get("map_size", Vector2());

	simnav::MotionStats stats = solver.step(state, statics, params);

	PackedVector2Array out_positions;
	out_positions.resize(count);
	PackedFloat64Array out_facing;
	out_facing.resize(count);
	PackedFloat64Array out_steer;
	out_steer.resize(count);
	PackedFloat64Array out_factor;
	out_factor.resize(count);
	PackedFloat64Array out_turn_delta;
	out_turn_delta.resize(count);
	if (count > 0) {
		Vector2 *pw = out_positions.ptrw();
		double *fw = out_facing.ptrw();
		double *sw = out_steer.ptrw();
		double *cw = out_factor.ptrw();
		double *tw = out_turn_delta.ptrw();
		for (int64_t i = 0; i < count; i++) {
			pw[i] = state.position[(size_t)i];
			fw[i] = state.facing_angle_rad[(size_t)i];
			sw[i] = state.steer_side[(size_t)i];
			cw[i] = state.last_speed_factor[(size_t)i];
			tw[i] = state.last_turn_delta_rad[(size_t)i];
		}
	}
	out["positions"] = out_positions;
	out["facing"] = out_facing;
	out["steer_side"] = out_steer;
	out["last_speed_factor"] = out_factor;
	out["last_turn_delta_rad"] = out_turn_delta;
	out["separation_rounds"] = stats.separation_rounds;
	out["max_residual_overlap"] = stats.max_residual_overlap;
	return out;
}

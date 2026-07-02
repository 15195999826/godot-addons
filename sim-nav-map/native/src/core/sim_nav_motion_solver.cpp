#include "sim_nav_motion_solver.h"

#include <algorithm>
#include <cmath>

namespace simnav {

using godot::real_t;

static constexpr double MATH_TAU = 6.2831853071795864769252867666;
static constexpr double MATH_PI = 3.1415926535897932384626433833;

// ── Godot builtin twins ──────────────────────────────────────────────────────

double MotionSolver::_angle_difference(double p_from, double p_to) {
	// Twin: core/math/math_funcs.h angle_difference (double variant — the
	// GDScript global function).
	double difference = std::fmod(p_to - p_from, MATH_TAU);
	return std::fmod(2.0 * difference, MATH_TAU) - difference;
}

double MotionSolver::_rotate_toward(double p_from, double p_to, double p_delta) {
	// Twin: core/math/math_funcs.h rotate_toward.
	double difference = _angle_difference(p_from, p_to);
	double abs_difference = std::abs(difference);
	return p_from + std::clamp(p_delta, abs_difference - MATH_PI, abs_difference) * (difference >= 0.0 ? 1.0 : -1.0);
}

Vector2 MotionSolver::_from_angle(double p_angle) {
	// Twin: Vector2::from_angle(real_t) — angle narrowed to float. The float
	// trig itself is computed in double and narrowed: the engine binary's
	// sinf/cosf are correctly-rounded on the probed range (200k-sample zero
	// mismatch, see smoke_dota2_lab_native_motion_ab history), while this
	// extension's CRT sinf/cosf drift by 1 ULP on ~0.26% of inputs.
	float angle = (float)p_angle;
	return Vector2((float)std::cos((double)angle), (float)std::sin((double)angle));
}

double MotionSolver::_vec_angle(const Vector2 &p_v) {
	// Twin: Vector2::angle() — float atan2 (real_t components), result
	// promoted to GDScript double.
	return (double)std::atan2((float)p_v.y, (float)p_v.x);
}

Vector2 MotionSolver::_rotated(const Vector2 &p_v, double p_by) {
	// Twin: Vector2::rotated(real_t) — float math; float trig via
	// double-then-narrow (see _from_angle note).
	float by = (float)p_by;
	float sine = (float)std::sin((double)by);
	float cosine = (float)std::cos((double)by);
	return Vector2(p_v.x * cosine - p_v.y * sine, p_v.x * sine + p_v.y * cosine);
}

// ── Step pipeline ────────────────────────────────────────────────────────────

MotionStats MotionSolver::step(MotionState &p_state, const MotionStatics &p_statics, const MotionParams &p_params) {
	int count = (int)p_state.size();

	// Phase A: intent step. Above the brute threshold the steering scan uses
	// position buckets built from tick-start positions (same as the GDScript
	// engine — built once, before any unit moves).
	SteerBuckets buckets;
	if (p_params.contact_steering_enabled && count > p_params.separation_brute_force_max) {
		buckets.cell_size = _steering_hash_cell_size(p_state, p_params.delta);
		_build_position_buckets(p_state, buckets.cell_size, buckets.buckets);
	}
	for (int i = 0; i < count; i++) {
		// prev_tick_position bookkeeping stays GDScript-side (tick-start
		// positions are captured before this call).
		if (p_state.moving[(size_t)i]) {
			_advance_unit(p_state, i, p_params, buckets);
		}
	}

	// Phase B: separation solve.
	// Conservative axis-aligned reach bounds per static (twin:
	// _static_reach_bounds) — stored flat as [min_x, min_y, max_x, max_y].
	double max_radius = 0.0;
	for (int i = 0; i < count; i++) {
		max_radius = std::max(max_radius, p_state.radius[(size_t)i]);
	}
	std::vector<float> bounds;
	bounds.reserve(p_statics.center.size() * 4);
	for (size_t s = 0; s < p_statics.center.size(); s++) {
		double half_x = p_statics.width[s] * 0.5;
		double half_y = p_statics.height[s] * 0.5;
		if (p_statics.rotation_rad[s] != 0.0) {
			double cos_abs = std::abs(std::cos(p_statics.rotation_rad[s]));
			double sin_abs = std::abs(std::sin(p_statics.rotation_rad[s]));
			double rotated_x = cos_abs * p_statics.width[s] * 0.5 + sin_abs * p_statics.height[s] * 0.5;
			double rotated_y = sin_abs * p_statics.width[s] * 0.5 + cos_abs * p_statics.height[s] * 0.5;
			half_x = rotated_x;
			half_y = rotated_y;
		}
		double reach_x = half_x + max_radius + 1.0;
		double reach_y = half_y + max_radius + 1.0;
		// Twin: Rect2(center - reach, reach * 2) — float32 position/size
		// storage; the max edge is summed in double at compare time, exactly
		// like the GDScript `bounds.position.x + bounds.size.x` expression.
		bounds.push_back((float)((double)p_statics.center[s].x - reach_x));
		bounds.push_back((float)((double)p_statics.center[s].y - reach_y));
		bounds.push_back((float)(reach_x * 2.0));
		bounds.push_back((float)(reach_y * 2.0));
	}

	MotionStats stats;
	bool use_hash = count > p_params.separation_brute_force_max;
	double hash_cell = use_hash ? _separation_hash_cell_size(p_state) : 0.0;
	for (int iteration = 0; iteration < SEPARATION_ITERATIONS; iteration++) {
		stats.separation_rounds = iteration + 1;
		bool moved_any = false;
		if (use_hash) {
			moved_any = _separate_pairs_hashed(p_state, hash_cell, p_params);
		} else {
			for (int i = 0; i < count; i++) {
				for (int j = i + 1; j < count; j++) {
					if (_separate_pair(p_state, i, j, p_params)) {
						moved_any = true;
					}
				}
			}
		}
		for (int i = 0; i < count; i++) {
			if (p_state.mobile[(size_t)i] && _project_out_of_world(p_state, i, p_statics, bounds, p_params)) {
				moved_any = true;
			}
		}
		if (!moved_any) {
			break;
		}
	}
	stats.max_residual_overlap = max_overlap_depth(p_state, p_params.separation_brute_force_max);
	return stats;
}

// ── Phase A ──────────────────────────────────────────────────────────────────

void MotionSolver::_advance_unit(MotionState &p_state, int p_i, const MotionParams &p_params, const SteerBuckets &p_buckets) {
	// Path shortcutting and waypoint-reach pops run in the GDScript pre-pass
	// (they touch only the unit's own path and static line checks); this is
	// the turn/step body from the track point on.
	size_t i = (size_t)p_i;
	Vector2 track = p_state.track_point[i];
	Vector2 to_track = track - p_state.position[i];
	double distance = (double)to_track.length();
	if (distance < 0.01) {
		p_state.last_speed_factor[i] = 0.0;
		p_state.last_turn_delta_rad[i] = 0.0;
		return;
	}

	double desired = _vec_angle(to_track);
	if (p_params.contact_steering_enabled) {
		desired = _contact_steered_heading(p_state, p_i, to_track / (real_t)distance, p_params, p_buckets);
	}
	p_state.last_turn_delta_rad[i] = _angle_difference(p_state.facing_angle_rad[i], desired);
	p_state.facing_angle_rad[i] = _rotate_toward(
			p_state.facing_angle_rad[i], desired, p_state.turn_rate_rad_per_sec[i] * p_params.delta);
	double remaining_error = std::abs(_angle_difference(p_state.facing_angle_rad[i], desired));
	double factor = _alignment_factor(remaining_error);
	p_state.last_speed_factor[i] = factor;
	if (factor <= 0.0) {
		return;
	}
	double step_length = p_state.speed[i] * p_params.delta * factor;
	if (!p_state.has_path[i]) {
		step_length = std::min(step_length, distance);
	}
	p_state.position[i] += _from_angle(p_state.facing_angle_rad[i]) * (real_t)step_length;
}

double MotionSolver::_contact_steered_heading(MotionState &p_state, int p_i, const Vector2 &p_toward_track, const MotionParams &p_params, const SteerBuckets &p_buckets) {
	size_t i = (size_t)p_i;
	double my_push = _pushability(p_state, p_i, p_params);
	Vector2 steered = p_toward_track;
	bool any_contact = false;
	double locked_side = p_state.steer_side[i];
	if (p_buckets.cell_size <= 0.0) {
		for (int other = 0; other < (int)p_state.size(); other++) {
			Vector2 bias;
			double used_side = locked_side;
			if (_steer_contribution(p_state, p_i, other, p_toward_track, my_push, p_params, locked_side, used_side, bias)) {
				any_contact = true;
				locked_side = used_side;
				steered += bias;
			}
		}
	} else {
		// Same others in the same (sorted-index) order as the GDScript hashed
		// loop; the accumulation is float-order-sensitive.
		int32_t base_x = (int32_t)std::floor((double)p_state.position[i].x / p_buckets.cell_size);
		int32_t base_y = (int32_t)std::floor((double)p_state.position[i].y / p_buckets.cell_size);
		grid_candidates.clear();
		for (int32_t oy = -1; oy <= 1; oy++) {
			for (int32_t ox = -1; ox <= 1; ox++) {
				auto found = p_buckets.buckets.find(_bucket_key(base_x + ox, base_y + oy));
				if (found == p_buckets.buckets.end()) {
					continue;
				}
				for (int32_t candidate : found->second) {
					grid_candidates.push_back(candidate);
				}
			}
		}
		std::sort(grid_candidates.begin(), grid_candidates.end());
		for (int32_t candidate : grid_candidates) {
			Vector2 bias;
			double used_side = locked_side;
			if (_steer_contribution(p_state, p_i, candidate, p_toward_track, my_push, p_params, locked_side, used_side, bias)) {
				any_contact = true;
				locked_side = used_side;
				steered += bias;
			}
		}
	}
	p_state.steer_side[i] = any_contact ? locked_side : 0.0;
	return _vec_angle(steered);
}

bool MotionSolver::_steer_contribution(const MotionState &p_state, int p_i, int p_other, const Vector2 &p_toward_track, double p_my_push, const MotionParams &p_params, double p_locked_side, double &r_used_side, Vector2 &r_bias) const {
	r_bias = Vector2();
	r_used_side = p_locked_side;
	if (p_other == p_i) {
		return false;
	}
	size_t i = (size_t)p_i;
	size_t o = (size_t)p_other;
	// Only steer around bodies that will not yield to this unit.
	if (p_state.mobile[o] && _pushability(p_state, p_other, p_params) > p_my_push + 0.001) {
		return false;
	}
	Vector2 offset = p_state.position[o] - p_state.position[i];
	double gap = (double)offset.length() - (p_state.radius[i] + p_state.radius[o]);
	if (gap > CONTACT_STEER_GAP_RANGE) {
		return false;
	}
	Vector2 to_other = offset.normalized();
	double frontness_dot = (double)p_toward_track.dot(to_other);
	if (frontness_dot < CONTACT_STEER_FRONT_DOT_MIN) {
		return false;
	}
	if (r_used_side == 0.0) {
		r_used_side = _pick_steer_side(to_other, p_toward_track);
	}
	double proximity = std::clamp(1.0 - gap / CONTACT_STEER_GAP_RANGE, 0.0, 1.0);
	double frontness = (frontness_dot - CONTACT_STEER_FRONT_DOT_MIN) / (1.0 - CONTACT_STEER_FRONT_DOT_MIN);
	Vector2 around = Vector2(-to_other.y, to_other.x) * (real_t)r_used_side;
	r_bias = around * (real_t)(proximity * frontness * CONTACT_STEER_WEIGHT);
	return true;
}

double MotionSolver::_pick_steer_side(const Vector2 &p_to_other, const Vector2 &p_intent_dir) {
	double lean = (double)p_to_other.cross(p_intent_dir);
	if (std::abs(lean) <= CONTACT_STEER_SIDE_DEADZONE) {
		return -1.0;
	}
	// Twin: signf — lean == 0 is caught by the deadzone above.
	return lean > 0.0 ? 1.0 : -1.0;
}

double MotionSolver::_alignment_factor(double p_heading_error) {
	if (p_heading_error <= TURN_ALIGN_FULL_RAD) {
		return 1.0;
	}
	if (p_heading_error >= TURN_ALIGN_ZERO_RAD) {
		return 0.0;
	}
	return 1.0 - (p_heading_error - TURN_ALIGN_FULL_RAD) / (TURN_ALIGN_ZERO_RAD - TURN_ALIGN_FULL_RAD);
}

double MotionSolver::_pushability(const MotionState &p_state, int p_i, const MotionParams &p_params) const {
	size_t i = (size_t)p_i;
	if (!p_state.mobile[i]) {
		return 0.0;
	}
	if (p_state.moving[i]) {
		return p_params.pushability_moving;
	}
	return p_params.pushability_idle;
}

// ── Phase B ──────────────────────────────────────────────────────────────────

bool MotionSolver::_separate_pair(MotionState &p_state, int p_a, int p_b, const MotionParams &p_params) {
	size_t a = (size_t)p_a;
	size_t b = (size_t)p_b;
	double min_distance = p_state.radius[a] + p_state.radius[b];
	Vector2 offset = p_state.position[b] - p_state.position[a];
	double distance = (double)offset.length();
	if (distance >= min_distance - SEPARATION_SLACK) {
		return false;
	}
	double weight_a = _separation_weight_a(p_state, p_a, p_b, p_params);
	if (weight_a < 0.0) {
		return false;
	}
	Vector2 direction;
	if (distance > 0.001) {
		direction = offset / (real_t)distance;
	} else {
		// Perfectly coincident centers: deterministic split by id order.
		direction = p_state.id_rank[a] < p_state.id_rank[b] ? Vector2(1, 0) : Vector2(-1, 0);
	}
	direction = _head_on_biased(p_state, p_a, p_b, direction);
	double overlap = min_distance - distance;
	p_state.position[a] -= direction * (real_t)overlap * (real_t)weight_a;
	p_state.position[b] += direction * (real_t)overlap * (real_t)(1.0 - weight_a);
	return true;
}

double MotionSolver::_separation_weight_a(const MotionState &p_state, int p_a, int p_b, const MotionParams &p_params) const {
	size_t a = (size_t)p_a;
	size_t b = (size_t)p_b;
	if (!p_state.mobile[a] && !p_state.mobile[b]) {
		return -1.0;
	}
	if (!p_state.mobile[a]) {
		return 0.0;
	}
	if (!p_state.mobile[b]) {
		return 1.0;
	}
	double push_a = _pushability(p_state, p_a, p_params);
	double push_b = _pushability(p_state, p_b, p_params);
	double total = push_a + push_b;
	if (total <= 0.0) {
		return 0.5;
	}
	return push_a / total;
}

Vector2 MotionSolver::_head_on_biased(const MotionState &p_state, int p_a, int p_b, const Vector2 &p_direction) const {
	size_t a = (size_t)p_a;
	size_t b = (size_t)p_b;
	int steer_unit = -1;
	if (p_state.moving[a] && std::abs((double)_from_angle(p_state.facing_angle_rad[a]).dot(p_direction)) > HEAD_ON_ALIGN_DOT) {
		steer_unit = p_a;
	} else if (p_state.moving[b] && std::abs((double)_from_angle(p_state.facing_angle_rad[b]).dot(p_direction)) > HEAD_ON_ALIGN_DOT) {
		steer_unit = p_b;
	}
	if (steer_unit == -1) {
		return p_direction;
	}
	double side = p_state.steer_side[(size_t)steer_unit];
	if (side == 0.0) {
		Vector2 to_other = steer_unit == p_a ? p_direction : -p_direction;
		side = _pick_steer_side(to_other, _from_angle(p_state.facing_angle_rad[(size_t)steer_unit]));
	}
	Vector2 lateral = Vector2(p_direction.y, -p_direction.x) * (real_t)side;
	return (p_direction + lateral * (real_t)HEAD_ON_LATERAL_BIAS).normalized();
}

bool MotionSolver::_separate_pairs_hashed(MotionState &p_state, double p_cell_size, const MotionParams &p_params) {
	int count = (int)p_state.size();
	if (count == 0) {
		return false;
	}
	double min_x = (double)p_state.position[0].x;
	double min_y = (double)p_state.position[0].y;
	double max_x = min_x;
	double max_y = min_y;
	for (int i = 0; i < count; i++) {
		min_x = std::min(min_x, (double)p_state.position[(size_t)i].x);
		min_y = std::min(min_y, (double)p_state.position[(size_t)i].y);
		max_x = std::max(max_x, (double)p_state.position[(size_t)i].x);
		max_y = std::max(max_y, (double)p_state.position[(size_t)i].y);
	}
	int grid_w = (int)((max_x - min_x) / p_cell_size) + 1;
	int grid_h = (int)((max_y - min_y) / p_cell_size) + 1;
	if ((int)grid_heads.size() < grid_w * grid_h) {
		grid_heads.resize((size_t)grid_w * grid_h);
	}
	for (int cell = 0; cell < grid_w * grid_h; cell++) {
		grid_heads[(size_t)cell] = -1;
	}
	if ((int)grid_next.size() < count) {
		grid_next.resize((size_t)count);
	}
	if ((int)grid_candidates.size() < count) {
		grid_candidates.resize((size_t)count);
	}
	for (int rev = 0; rev < count; rev++) {
		int insert_index = count - 1 - rev;
		const Vector2 &insert_pos = p_state.position[(size_t)insert_index];
		int cell = (int)(((double)insert_pos.y - min_y) / p_cell_size) * grid_w +
				(int)(((double)insert_pos.x - min_x) / p_cell_size);
		grid_next[(size_t)insert_index] = grid_heads[(size_t)cell];
		grid_heads[(size_t)cell] = insert_index;
	}
	bool moved_any = false;
	for (int i = 0; i < count; i++) {
		int cx = (int)(((double)p_state.position[(size_t)i].x - min_x) / p_cell_size);
		int cy = (int)(((double)p_state.position[(size_t)i].y - min_y) / p_cell_size);
		int candidate_count = 0;
		for (int oy = std::max(cy - 1, 0); oy < std::min(cy + 2, grid_h); oy++) {
			int row = oy * grid_w;
			for (int ox = std::max(cx - 1, 0); ox < std::min(cx + 2, grid_w); ox++) {
				int j = grid_heads[(size_t)(row + ox)];
				while (j != -1) {
					if (j > i) {
						int insert_at = candidate_count;
						while (insert_at > 0 && grid_candidates[(size_t)(insert_at - 1)] > j) {
							grid_candidates[(size_t)insert_at] = grid_candidates[(size_t)(insert_at - 1)];
							insert_at -= 1;
						}
						grid_candidates[(size_t)insert_at] = j;
						candidate_count += 1;
					}
					j = grid_next[(size_t)j];
				}
			}
		}
		for (int k = 0; k < candidate_count; k++) {
			int other = grid_candidates[(size_t)k];
			// Squared-distance pre-reject at the raw radius sum (strictly
			// looser than _separate_pair's slack-adjusted reject).
			double reach = p_state.radius[(size_t)i] + p_state.radius[(size_t)other];
			if ((double)p_state.position[(size_t)i].distance_squared_to(p_state.position[(size_t)other]) >= reach * reach) {
				continue;
			}
			if (_separate_pair(p_state, i, other, p_params)) {
				moved_any = true;
			}
		}
	}
	return moved_any;
}

double MotionSolver::_separation_hash_cell_size(const MotionState &p_state) {
	double max_radius = 0.0;
	for (size_t i = 0; i < p_state.size(); i++) {
		max_radius = std::max(max_radius, p_state.radius[i]);
	}
	return std::max(1.0, max_radius * 2.0 + 1.0);
}

double MotionSolver::_steering_hash_cell_size(const MotionState &p_state, double p_delta) {
	double max_radius = 0.0;
	double max_speed = 0.0;
	for (size_t i = 0; i < p_state.size(); i++) {
		max_radius = std::max(max_radius, p_state.radius[i]);
		max_speed = std::max(max_speed, p_state.speed[i]);
	}
	return std::max(1.0, max_radius * 2.0 + CONTACT_STEER_GAP_RANGE + max_speed * p_delta + 1.0);
}

void MotionSolver::_build_position_buckets(const MotionState &p_state, double p_cell_size, std::unordered_map<int64_t, std::vector<int32_t>> &r_buckets) {
	r_buckets.clear();
	for (int i = 0; i < (int)p_state.size(); i++) {
		int32_t key_x = (int32_t)std::floor((double)p_state.position[(size_t)i].x / p_cell_size);
		int32_t key_y = (int32_t)std::floor((double)p_state.position[(size_t)i].y / p_cell_size);
		r_buckets[_bucket_key(key_x, key_y)].push_back(i);
	}
}

bool MotionSolver::_project_out_of_world(MotionState &p_state, int p_i, const MotionStatics &p_statics, const std::vector<float> &p_bounds, const MotionParams &p_params) const {
	size_t i = (size_t)p_i;
	bool moved = false;
	Vector2 pos = p_state.position[i];
	for (int shape_index = 0; shape_index < (int)p_statics.center.size(); shape_index++) {
		const float *bounds = &p_bounds[(size_t)shape_index * 4];
		// [pos_x, pos_y, size_x, size_y] — max edges summed in double (twin
		// of the GDScript inline reject).
		if (pos.x < bounds[0] || pos.y < bounds[1] ||
				(double)pos.x >= (double)bounds[0] + (double)bounds[2] ||
				(double)pos.y >= (double)bounds[1] + (double)bounds[3]) {
			continue;
		}
		if (_project_out_of_shape(p_state, p_i, p_statics, shape_index)) {
			moved = true;
			pos = p_state.position[i];
		}
	}
	// Inline twin of clamp_to_playable.
	Vector2 clamped(
			(real_t)std::clamp((double)pos.x, p_state.radius[i], (double)p_params.map_size.x - p_state.radius[i]),
			(real_t)std::clamp((double)pos.y, p_state.radius[i], (double)p_params.map_size.y - p_state.radius[i]));
	if (clamped != p_state.position[i]) {
		p_state.position[i] = clamped;
		moved = true;
	}
	return moved;
}

bool MotionSolver::_project_out_of_shape(MotionState &p_state, int p_i, const MotionStatics &p_statics, int p_shape) const {
	size_t i = (size_t)p_i;
	size_t s = (size_t)p_shape;
	Vector2 local = p_state.position[i] - p_statics.center[s];
	if (p_statics.rotation_rad[s] != 0.0) {
		local = _rotated(local, -p_statics.rotation_rad[s]);
	}
	Vector2 half = Vector2((real_t)p_statics.width[s], (real_t)p_statics.height[s]) * (real_t)0.5;
	Vector2 clamped(
			(real_t)std::clamp((double)local.x, (double)-half.x, (double)half.x),
			(real_t)std::clamp((double)local.y, (double)-half.y, (double)half.y));
	Vector2 delta = local - clamped;
	double distance = (double)delta.length();
	if (clamped == local) {
		// Center inside the rectangle: exit through the shallowest face.
		double exit_x = (double)half.x - std::abs((double)local.x);
		double exit_y = (double)half.y - std::abs((double)local.y);
		if (exit_x <= exit_y) {
			double sign_x = (double)local.x >= 0.0 ? 1.0 : -1.0;
			local = Vector2((real_t)(((double)half.x + p_state.radius[i]) * sign_x), local.y);
		} else {
			double sign_y = (double)local.y >= 0.0 ? 1.0 : -1.0;
			local = Vector2(local.x, (real_t)(((double)half.y + p_state.radius[i]) * sign_y));
		}
	} else if (distance < p_state.radius[i]) {
		local = clamped + delta / (real_t)distance * (real_t)p_state.radius[i];
	} else {
		return false;
	}
	if (p_statics.rotation_rad[s] != 0.0) {
		local = _rotated(local, p_statics.rotation_rad[s]);
	}
	p_state.position[i] = p_statics.center[s] + local;
	return true;
}

// ── Overlap stat ─────────────────────────────────────────────────────────────

double MotionSolver::max_overlap_depth(const MotionState &p_state, int p_brute_force_max) {
	int count = (int)p_state.size();
	if (count > p_brute_force_max) {
		return _max_overlap_depth_hashed(p_state);
	}
	double deepest = 0.0;
	for (int i = 0; i < count; i++) {
		for (int j = i + 1; j < count; j++) {
			size_t a = (size_t)i;
			size_t b = (size_t)j;
			if (!p_state.mobile[a] && !p_state.mobile[b]) {
				continue;
			}
			double depth = (p_state.radius[a] + p_state.radius[b]) - (double)p_state.position[a].distance_to(p_state.position[b]);
			deepest = std::max(deepest, depth);
		}
	}
	return deepest;
}

double MotionSolver::_max_overlap_depth_hashed(const MotionState &p_state) {
	double cell_size = _separation_hash_cell_size(p_state);
	std::unordered_map<int64_t, std::vector<int32_t>> buckets;
	_build_position_buckets(p_state, cell_size, buckets);
	double deepest = 0.0;
	for (int i = 0; i < (int)p_state.size(); i++) {
		size_t a = (size_t)i;
		int32_t base_x = (int32_t)std::floor((double)p_state.position[a].x / cell_size);
		int32_t base_y = (int32_t)std::floor((double)p_state.position[a].y / cell_size);
		for (int32_t oy = -1; oy <= 1; oy++) {
			for (int32_t ox = -1; ox <= 1; ox++) {
				auto found = buckets.find(_bucket_key(base_x + ox, base_y + oy));
				if (found == buckets.end()) {
					continue;
				}
				for (int32_t j : found->second) {
					if (j <= i) {
						continue;
					}
					size_t b = (size_t)j;
					if (!p_state.mobile[a] && !p_state.mobile[b]) {
						continue;
					}
					double depth = (p_state.radius[a] + p_state.radius[b]) - (double)p_state.position[a].distance_to(p_state.position[b]);
					deepest = std::max(deepest, depth);
				}
			}
		}
	}
	return deepest;
}

} // namespace simnav
